import {
  PLAYER_ERROR_CATEGORIES,
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  type PlayerCommand,
  type PlayerCommandName,
  type PlayerError,
  type PlayerErrorCategory,
  type PlayerEvent,
  type PlayerLoadCommandPayload,
  type PlayerMediaSummary,
  type PlayerRendererSafeDiagnostic,
  type PlayerRequestId,
  type PlayerSnapshot,
  type PlayerTimeRange,
  type PlayerTrackDeliveryType,
  type PlayerTrackId,
  type PlayerTrackKind,
  type PlayerTrackSummary,
} from '../../contracts/player.js';
import type { PlayerRendererIntent, RendererIntentEnvelope } from '../../contracts/ipc.js';
import type {
  NativePlayerHostEvent,
  NativePlayerHostFailure,
  NativePlayerHostPort,
  NativePlayerHostStatus,
} from './nativePlayerHostPort.js';

type UnknownRecord = Record<string, unknown>;

interface CommandMappingResult {
  command: PlayerCommand;
}

interface ValidationFailure {
  error: PlayerError;
}

export interface DesktopPlayerAdapterDispatchResult {
  accepted: boolean;
  command: PlayerCommand | null;
  events: readonly PlayerEvent[];
  snapshot: PlayerSnapshot;
}

const EMPTY_PAYLOAD: Record<string, never> = {};

const PLAYER_INTENT_TO_COMMAND = {
  'player.load': 'load',
  'player.play': 'play',
  'player.pause': 'pause',
  'player.stop': 'stop',
  'player.seekAbsolute': 'seek.absolute',
  'player.seekRelative': 'seek.relative',
  'player.setVolume': 'volume.set',
  'player.setMute': 'mute.set',
  'player.selectAudio': 'track.audio.select',
  'player.selectSubtitle': 'track.subtitle.select',
} as const satisfies Record<PlayerRendererIntent, PlayerCommandName>;

const HOST_PLAYBACK_STATUSES = [
  'ready',
  'buffering',
  'playing',
  'paused',
  'seeking',
  'stalled',
] as const satisfies readonly NativePlayerHostStatus[];

const PLAYER_TRACK_KINDS = ['audio', 'subtitle', 'video'] as const satisfies readonly PlayerTrackKind[];

const PLAYER_TRACK_DELIVERY_TYPES = [
  'embedded',
  'sidecar',
  'external',
  'burned-in',
  'unknown',
] as const satisfies readonly PlayerTrackDeliveryType[];

export class DesktopPlayerAdapter {
  readonly #host: NativePlayerHostPort;
  #snapshot: PlayerSnapshot = createInitialSnapshot();
  #pendingCommands = new Map<PlayerRequestId, PlayerCommandName>();

  constructor(host: NativePlayerHostPort) {
    this.#host = host;
  }

  getSnapshot(): PlayerSnapshot {
    return cloneSnapshot(this.#snapshot);
  }

  getPendingRequestCount(): number {
    return this.#pendingCommands.size;
  }

  async dispatchRendererIntent(
    envelope: RendererIntentEnvelope<unknown>,
  ): Promise<DesktopPlayerAdapterDispatchResult> {
    const commandResult = mapRendererIntentToCommand(envelope);
    if ('error' in commandResult) {
      const events = this.#emitBoundaryError(commandResult.error);
      return this.#result(false, null, events);
    }

    const { command } = commandResult;
    this.#pendingCommands.set(command.requestId, command.command);
    const events: PlayerEvent[] = [];

    if (command.command === 'load') {
      this.#snapshot = {
        ...this.#snapshot,
        requestId: command.requestId,
        status: 'loading',
        media: command.payload.media,
        capabilityProfileId: command.payload.capabilityProfileId ?? null,
        positionMs: command.payload.policy.startPositionMs ?? 0,
        durationMs: command.payload.media.durationMs ?? null,
        selectedAudioTrackId: command.payload.policy.preferredAudioTrackId ?? null,
        selectedSubtitleTrackId: command.payload.policy.preferredSubtitleTrackId ?? null,
        selectedVideoTrackId: null,
        tracks: [],
        lastError: null,
      };
      events.push(this.#stateChanged());
    }

    try {
      const hostResult = await this.#host.execute(command);
      if (hostResult.ok) {
        for (const hostEvent of hostResult.events ?? []) {
          events.push(...this.handleHostEvent(hostEvent));
        }
        events.push({
          event: 'command.settled',
          requestId: command.requestId,
          command: command.command,
          ok: true,
        });
        return this.#result(true, command, events);
      }

      const error = hostFailureToError(command.requestId, hostResult.error);
      events.push(...this.#recordError(error));
      events.push({
        event: 'command.settled',
        requestId: command.requestId,
        command: command.command,
        ok: false,
        error,
      });
      return this.#result(true, command, events);
    } catch {
      const error = createPlayerError({
        code: 'PLAYER_HELPER_COMMAND_FAILED',
        category: 'helper-failure',
        message: 'The player helper failed while handling the command.',
        requestId: command.requestId,
        diagnostic: {
          component: 'desktop-player-adapter',
          operation: command.command,
          status: 'failed',
          reason: 'helper command rejected',
        },
      });
      events.push(...this.#recordError(error));
      events.push({
        event: 'command.settled',
        requestId: command.requestId,
        command: command.command,
        ok: false,
        error,
      });
      return this.#result(true, command, events);
    } finally {
      this.#pendingCommands.delete(command.requestId);
    }
  }

  handleHostEvent(event: unknown): readonly PlayerEvent[] {
    const validation = validateHostEvent(event);
    if ('error' in validation) {
      return this.#emitBoundaryError(validation.error);
    }

    const hostEvent = validation.event;
    const hostRequestId = hostEvent.requestId;
    if (
      this.#snapshot.requestId === null &&
      (hostRequestId === null || !this.#pendingCommands.has(hostRequestId))
    ) {
      return [
        {
          event: 'warning',
          requestId: null,
          warning: createPlayerError({
            code: 'PLAYER_STALE_HOST_EVENT',
            category: 'stale-request',
            message: 'A stale player event was ignored.',
            requestId: hostRequestId ?? undefined,
            diagnostic: {
              component: 'desktop-player-adapter',
              operation: hostEvent.type,
              status: 'ignored',
              reason: 'no active player request',
            },
          }),
        },
      ];
    }

    if (hostEvent.requestId !== null && this.#isStale(hostEvent.requestId)) {
      return [
        {
          event: 'warning',
          requestId: this.#snapshot.requestId,
          warning: createPlayerError({
            code: 'PLAYER_STALE_HOST_EVENT',
            category: 'stale-request',
            message: 'A stale player event was ignored.',
            requestId: hostEvent.requestId,
            diagnostic: {
              component: 'desktop-player-adapter',
              operation: hostEvent.type,
              status: 'ignored',
              reason: 'request id did not match current playback state',
            },
          }),
        },
      ];
    }

    switch (hostEvent.type) {
      case 'media.loaded':
        this.#snapshot = {
          ...this.#snapshot,
          requestId: hostEvent.requestId,
          status: 'ready',
          media: hostEvent.media,
          durationMs: hostEvent.durationMs,
          tracks: hostEvent.tracks ?? this.#snapshot.tracks,
          lastError: null,
        };
        return [
          {
            event: 'media.loaded',
            requestId: hostEvent.requestId,
            media: hostEvent.media,
            durationMs: hostEvent.durationMs,
          },
          this.#stateChanged(),
        ];
      case 'playback.state':
        this.#snapshot = {
          ...this.#snapshot,
          requestId: hostEvent.requestId,
          status: hostEvent.status,
          playing: hostEvent.playing,
        };
        return [this.#stateChanged()];
      case 'time.updated':
        this.#snapshot = {
          ...this.#snapshot,
          requestId: hostEvent.requestId,
          positionMs: hostEvent.positionMs,
          durationMs: hostEvent.durationMs,
        };
        return [
          {
            event: 'time.updated',
            requestId: hostEvent.requestId,
            positionMs: hostEvent.positionMs,
            durationMs: hostEvent.durationMs,
          },
        ];
      case 'buffer.updated':
        this.#snapshot = {
          ...this.#snapshot,
          requestId: hostEvent.requestId,
          bufferedRanges: hostEvent.bufferedRanges,
        };
        return [
          {
            event: 'buffer.updated',
            requestId: hostEvent.requestId,
            bufferedRanges: hostEvent.bufferedRanges,
          },
        ];
      case 'tracks.changed':
        this.#snapshot = applyTrackSnapshot(this.#snapshot, hostEvent.requestId, hostEvent.tracks);
        return [
          {
            event: 'tracks.changed',
            requestId: hostEvent.requestId,
            tracks: hostEvent.tracks,
          },
          this.#stateChanged(),
        ];
      case 'track.selection.changed':
        this.#snapshot = {
          ...this.#snapshot,
          requestId: hostEvent.requestId,
          selectedAudioTrackId: hostEvent.audioTrackId,
          selectedSubtitleTrackId: hostEvent.subtitleTrackId,
          selectedVideoTrackId: hostEvent.videoTrackId,
        };
        return [
          {
            event: 'track.selection.changed',
            requestId: hostEvent.requestId,
            audioTrackId: hostEvent.audioTrackId,
            subtitleTrackId: hostEvent.subtitleTrackId,
            videoTrackId: hostEvent.videoTrackId,
          },
          this.#stateChanged(),
        ];
      case 'ended':
        this.#snapshot = {
          ...this.#snapshot,
          requestId: hostEvent.requestId,
          status: 'ended',
          playing: false,
        };
        return [{ event: 'ended', requestId: hostEvent.requestId }, this.#stateChanged()];
      case 'error':
        return this.#recordError(hostEvent.error);
    }
  }

  handleHelperCrash(requestId: PlayerRequestId | null = this.#snapshot.requestId): readonly PlayerEvent[] {
    return this.#recordError(
      createPlayerError({
        code: 'PLAYER_HELPER_CRASHED',
        category: 'helper-failure',
        message: 'The player helper stopped unexpectedly.',
        requestId: requestId ?? undefined,
        diagnostic: {
          component: 'desktop-player-adapter',
          operation: 'helper.lifecycle',
          status: 'crashed',
          reason: 'helper terminated',
        },
      }),
    );
  }

  async cleanup(): Promise<DesktopPlayerAdapterDispatchResult> {
    const requestId = this.#snapshot.requestId;
    try {
      await this.#host.cleanup(requestId);
      this.#pendingCommands.clear();
      this.#snapshot = createInitialSnapshot();
      return this.#result(true, null, [this.#stateChanged()]);
    } catch {
      const error = createPlayerError({
        code: 'PLAYER_CLEANUP_FAILED',
        category: 'cleanup-failure',
        message: 'The player helper could not be cleaned up safely.',
        requestId: requestId ?? undefined,
        diagnostic: {
          component: 'desktop-player-adapter',
          operation: 'cleanup',
          status: 'failed',
          reason: 'helper cleanup rejected',
        },
      });
      return this.#result(false, null, this.#recordError(error));
    }
  }

  #emitBoundaryError(error: PlayerError): readonly PlayerEvent[] {
    const safeError = sanitizePlayerError(error, 'PLAYER_VALIDATION_FAILED');
    return [
      {
        event: 'error',
        requestId: safeError.requestId ?? null,
        error: safeError,
      },
    ];
  }

  #recordError(error: PlayerError): readonly PlayerEvent[] {
    const safeError = sanitizePlayerError(error, 'PLAYER_UNKNOWN_ERROR');
    this.#snapshot = {
      ...this.#snapshot,
      status: 'error',
      playing: false,
      lastError: safeError,
    };
    return [
      {
        event: 'error',
        requestId: safeError.requestId ?? null,
        error: safeError,
      },
      this.#stateChanged(),
    ];
  }

  #stateChanged(): PlayerEvent {
    return {
      event: 'state.changed',
      requestId: this.#snapshot.requestId,
      snapshot: cloneSnapshot(this.#snapshot),
    };
  }

  #result(
    accepted: boolean,
    command: PlayerCommand | null,
    events: readonly PlayerEvent[],
  ): DesktopPlayerAdapterDispatchResult {
    return {
      accepted,
      command,
      events,
      snapshot: cloneSnapshot(this.#snapshot),
    };
  }

  #isStale(requestId: PlayerRequestId): boolean {
    return requestId !== this.#snapshot.requestId && !this.#pendingCommands.has(requestId);
  }
}

function mapRendererIntentToCommand(
  envelope: RendererIntentEnvelope<unknown>,
): CommandMappingResult | ValidationFailure {
  if (!isRecord(envelope)) {
    return validationFailure(undefined, 'renderer envelope must be an object');
  }

  if (hasForbiddenPrivilegedField(envelope)) {
    return validationFailure(readRequestId(envelope), 'renderer envelope contained privileged fields');
  }

  const requestId = envelope.requestId;
  if (!isNonEmptyString(requestId)) {
    return validationFailure(undefined, 'renderer envelope request id must be a non-empty string');
  }

  if (!isPlayerRendererIntent(envelope.intent)) {
    return validationFailure(requestId, 'renderer envelope intent is not a player intent');
  }

  const commandName = PLAYER_INTENT_TO_COMMAND[envelope.intent];

  switch (commandName) {
    case 'load': {
      const payload = validateLoadPayload(envelope.payload);
      if ('error' in payload) {
        return validationFailure(requestId, payload.error);
      }
      return { command: { command: 'load', requestId, payload: payload.value } };
    }
    case 'play':
    case 'pause':
    case 'stop':
      if (!isEmptyPayload(envelope.payload)) {
        return validationFailure(requestId, `${commandName} payload must be empty`);
      }
      return { command: { command: commandName, requestId, payload: EMPTY_PAYLOAD } };
    case 'seek.absolute': {
      const payload = validateObjectPayload(envelope.payload, ['positionMs']);
      if ('error' in payload || !isFiniteNonNegativeNumber(payload.value.positionMs)) {
        return validationFailure(requestId, 'seek absolute payload must include positionMs');
      }
      return {
        command: { command: 'seek.absolute', requestId, payload: { positionMs: payload.value.positionMs } },
      };
    }
    case 'seek.relative': {
      const payload = validateObjectPayload(envelope.payload, ['deltaMs']);
      if ('error' in payload || !isFiniteNumber(payload.value.deltaMs)) {
        return validationFailure(requestId, 'seek relative payload must include deltaMs');
      }
      return {
        command: { command: 'seek.relative', requestId, payload: { deltaMs: payload.value.deltaMs } },
      };
    }
    case 'volume.set': {
      const payload = validateObjectPayload(envelope.payload, ['volume']);
      if ('error' in payload || !isFiniteRangeNumber(payload.value.volume, 0, 1)) {
        return validationFailure(requestId, 'volume payload must include volume from 0 to 1');
      }
      return { command: { command: 'volume.set', requestId, payload: { volume: payload.value.volume } } };
    }
    case 'mute.set': {
      const payload = validateObjectPayload(envelope.payload, ['muted']);
      if ('error' in payload || typeof payload.value.muted !== 'boolean') {
        return validationFailure(requestId, 'mute payload must include muted boolean');
      }
      return { command: { command: 'mute.set', requestId, payload: { muted: payload.value.muted } } };
    }
    case 'track.audio.select': {
      const payload = validateObjectPayload(envelope.payload, ['trackId']);
      if ('error' in payload || !isNonEmptyString(payload.value.trackId)) {
        return validationFailure(requestId, 'audio track payload must include opaque trackId');
      }
      return {
        command: {
          command: 'track.audio.select',
          requestId,
          payload: { trackId: payload.value.trackId },
        },
      };
    }
    case 'track.subtitle.select': {
      const payload = validateObjectPayload(envelope.payload, ['trackId']);
      if (
        'error' in payload ||
        !(payload.value.trackId === null || isNonEmptyString(payload.value.trackId))
      ) {
        return validationFailure(requestId, 'subtitle track payload must include opaque trackId or null');
      }
      return {
        command: {
          command: 'track.subtitle.select',
          requestId,
          payload: { trackId: payload.value.trackId },
        },
      };
    }
  }
}

function validateHostEvent(
  event: unknown,
): { event: NativePlayerHostEvent } | ValidationFailure {
  if (!isRecord(event)) {
    return validationFailure(undefined, 'host event must be an object');
  }

  if (hasForbiddenPrivilegedField(event)) {
    return validationFailure(readRequestId(event), 'host event contained privileged fields');
  }

  const type = event.type;
  if (typeof type !== 'string') {
    return validationFailure(readRequestId(event), 'host event type must be a string');
  }

  switch (type) {
    case 'media.loaded': {
      const requestId = event.requestId;
      const media = validateMediaSummary(event.media);
      const tracks = event.tracks === undefined ? undefined : validateTracks(event.tracks);
      if (
        !isNonEmptyString(requestId) ||
        'error' in media ||
        !isNullableFiniteNonNegativeNumber(event.durationMs) ||
        (tracks !== undefined && 'error' in tracks)
      ) {
        return validationFailure(readRequestId(event), 'media loaded host event was invalid');
      }
      return {
        event: {
          type,
          requestId,
          media: media.value,
          durationMs: event.durationMs,
          tracks: tracks?.value,
        },
      };
    }
    case 'playback.state': {
      const requestId = event.requestId;
      if (
        !isNonEmptyString(requestId) ||
        !isStringInSet(event.status, HOST_PLAYBACK_STATUSES) ||
        typeof event.playing !== 'boolean'
      ) {
        return validationFailure(readRequestId(event), 'playback state host event was invalid');
      }
      return { event: { type, requestId, status: event.status, playing: event.playing } };
    }
    case 'time.updated': {
      const requestId = event.requestId;
      if (
        !isNonEmptyString(requestId) ||
        !isFiniteNonNegativeNumber(event.positionMs) ||
        !isNullableFiniteNonNegativeNumber(event.durationMs)
      ) {
        return validationFailure(readRequestId(event), 'time host event was invalid');
      }
      return {
        event: {
          type,
          requestId,
          positionMs: event.positionMs,
          durationMs: event.durationMs,
        },
      };
    }
    case 'buffer.updated': {
      const requestId = event.requestId;
      const bufferedRanges = validateTimeRanges(event.bufferedRanges);
      if (!isNonEmptyString(requestId) || 'error' in bufferedRanges) {
        return validationFailure(readRequestId(event), 'buffer host event was invalid');
      }
      return { event: { type, requestId, bufferedRanges: bufferedRanges.value } };
    }
    case 'tracks.changed': {
      const requestId = event.requestId;
      const tracks = validateTracks(event.tracks);
      if (!isNonEmptyString(requestId) || 'error' in tracks) {
        return validationFailure(readRequestId(event), 'tracks host event was invalid');
      }
      return { event: { type, requestId, tracks: tracks.value } };
    }
    case 'track.selection.changed': {
      const requestId = event.requestId;
      if (
        !isNonEmptyString(requestId) ||
        !isNullableString(event.audioTrackId) ||
        !isNullableString(event.subtitleTrackId) ||
        !isNullableString(event.videoTrackId)
      ) {
        return validationFailure(readRequestId(event), 'track selection host event was invalid');
      }
      return {
        event: {
          type,
          requestId,
          audioTrackId: event.audioTrackId,
          subtitleTrackId: event.subtitleTrackId,
          videoTrackId: event.videoTrackId,
        },
      };
    }
    case 'ended': {
      const requestId = event.requestId;
      if (!isNonEmptyString(requestId)) {
        return validationFailure(readRequestId(event), 'ended host event was invalid');
      }
      return { event: { type, requestId } };
    }
    case 'error': {
      if (!(event.requestId === null || isNonEmptyString(event.requestId))) {
        return validationFailure(undefined, 'error host event request id was invalid');
      }
      const error = normalizeHostErrorPayload(event.error, event.requestId);
      if ('error' in error) {
        return error;
      }
      return { event: { type, requestId: event.requestId, error } };
    }
    default:
      return validationFailure(readRequestId(event), 'host event type is unsupported');
  }
}

function validateLoadPayload(
  value: unknown,
): { value: PlayerLoadCommandPayload } | { error: string } {
  const payload = validateObjectPayload(value, ['media', 'policy'], ['capabilityProfileId']);
  if ('error' in payload) {
    return payload;
  }

  const media = validateMediaSummary(payload.value.media);
  const policy = validateLoadPolicy(payload.value.policy);
  if ('error' in media || 'error' in policy) {
    return { error: 'load payload must include safe media and policy' };
  }

  if (
    payload.value.capabilityProfileId !== undefined &&
    !isNonEmptyString(payload.value.capabilityProfileId)
  ) {
    return { error: 'load payload capabilityProfileId must be a string when present' };
  }

  return {
    value: {
      media: media.value,
      policy: policy.value,
      capabilityProfileId: payload.value.capabilityProfileId,
    },
  };
}

function validateLoadPolicy(
  value: unknown,
): { value: PlayerLoadCommandPayload['policy'] } | { error: string } {
  const payload = validateObjectPayload(
    value,
    ['autoplay'],
    ['startPositionMs', 'preferredAudioTrackId', 'preferredSubtitleTrackId'],
  );
  if ('error' in payload || typeof payload.value.autoplay !== 'boolean') {
    return { error: 'load policy must include autoplay' };
  }
  if (
    payload.value.startPositionMs !== undefined &&
    !isFiniteNonNegativeNumber(payload.value.startPositionMs)
  ) {
    return { error: 'load policy startPositionMs must be non-negative' };
  }
  if (
    payload.value.preferredAudioTrackId !== undefined &&
    !isNullableString(payload.value.preferredAudioTrackId)
  ) {
    return { error: 'load policy preferredAudioTrackId must be opaque or null' };
  }
  if (
    payload.value.preferredSubtitleTrackId !== undefined &&
    !isNullableString(payload.value.preferredSubtitleTrackId)
  ) {
    return { error: 'load policy preferredSubtitleTrackId must be opaque or null' };
  }
  return {
    value: {
      autoplay: payload.value.autoplay,
      startPositionMs: payload.value.startPositionMs,
      preferredAudioTrackId: payload.value.preferredAudioTrackId,
      preferredSubtitleTrackId: payload.value.preferredSubtitleTrackId,
    },
  };
}

function validateMediaSummary(value: unknown): { value: PlayerMediaSummary } | { error: string } {
  const payload = validateObjectPayload(value, ['id', 'title'], ['subtitle', 'durationMs', 'container']);
  if ('error' in payload || !isNonEmptyString(payload.value.id) || !isNonEmptyString(payload.value.title)) {
    return { error: 'media summary must include id and title' };
  }
  if (payload.value.subtitle !== undefined && typeof payload.value.subtitle !== 'string') {
    return { error: 'media summary subtitle must be a string' };
  }
  if (
    payload.value.durationMs !== undefined &&
    !isNullableFiniteNonNegativeNumber(payload.value.durationMs)
  ) {
    return { error: 'media summary durationMs must be non-negative or null' };
  }
  if (payload.value.container !== undefined && typeof payload.value.container !== 'string') {
    return { error: 'media summary container must be a string' };
  }
  return {
    value: {
      id: payload.value.id,
      title: payload.value.title,
      subtitle: payload.value.subtitle,
      durationMs: payload.value.durationMs,
      container: payload.value.container,
    },
  };
}

function validateTracks(value: unknown): { value: readonly PlayerTrackSummary[] } | { error: string } {
  if (!Array.isArray(value)) {
    return { error: 'tracks must be an array' };
  }

  const tracks: PlayerTrackSummary[] = [];
  for (const item of value) {
    const track = validateTrack(item);
    if ('error' in track) {
      return track;
    }
    tracks.push(track.value);
  }
  return { value: tracks };
}

function validateTrack(value: unknown): { value: PlayerTrackSummary } | { error: string } {
  const payload = validateObjectPayload(
    value,
    ['id', 'kind', 'label', 'selected', 'available'],
    ['language', 'codec', 'format', 'channelCount', 'deliveryType', 'forced', 'default'],
  );
  if (
    'error' in payload ||
    !isNonEmptyString(payload.value.id) ||
    !isStringInSet(payload.value.kind, PLAYER_TRACK_KINDS) ||
    !isNonEmptyString(payload.value.label) ||
    typeof payload.value.selected !== 'boolean' ||
    typeof payload.value.available !== 'boolean'
  ) {
    return { error: 'track summary must include safe opaque fields' };
  }
  if (payload.value.language !== undefined && typeof payload.value.language !== 'string') {
    return { error: 'track language must be a string' };
  }
  if (payload.value.codec !== undefined && typeof payload.value.codec !== 'string') {
    return { error: 'track codec must be a string' };
  }
  if (payload.value.format !== undefined && typeof payload.value.format !== 'string') {
    return { error: 'track format must be a string' };
  }
  if (
    payload.value.channelCount !== undefined &&
    !isFiniteRangeNumber(payload.value.channelCount, 1, 64)
  ) {
    return { error: 'track channel count must be in range' };
  }
  if (
    payload.value.deliveryType !== undefined &&
    !isStringInSet(payload.value.deliveryType, PLAYER_TRACK_DELIVERY_TYPES)
  ) {
    return { error: 'track delivery type is unsupported' };
  }
  if (payload.value.forced !== undefined && typeof payload.value.forced !== 'boolean') {
    return { error: 'track forced flag must be boolean' };
  }
  if (payload.value.default !== undefined && typeof payload.value.default !== 'boolean') {
    return { error: 'track default flag must be boolean' };
  }

  return {
    value: {
      id: payload.value.id,
      kind: payload.value.kind,
      label: payload.value.label,
      language: payload.value.language,
      codec: payload.value.codec,
      format: payload.value.format,
      channelCount: payload.value.channelCount,
      deliveryType: payload.value.deliveryType,
      forced: payload.value.forced,
      default: payload.value.default,
      selected: payload.value.selected,
      available: payload.value.available,
    },
  };
}

function validateTimeRanges(value: unknown): { value: readonly PlayerTimeRange[] } | { error: string } {
  if (!Array.isArray(value)) {
    return { error: 'buffered ranges must be an array' };
  }

  const ranges: PlayerTimeRange[] = [];
  for (const item of value) {
    const payload = validateObjectPayload(item, ['startMs', 'endMs']);
    if (
      'error' in payload ||
      !isFiniteNonNegativeNumber(payload.value.startMs) ||
      !isFiniteNonNegativeNumber(payload.value.endMs) ||
      payload.value.endMs < payload.value.startMs
    ) {
      return { error: 'buffered range must include startMs and endMs' };
    }
    ranges.push({ startMs: payload.value.startMs, endMs: payload.value.endMs });
  }
  return { value: ranges };
}

function validateObjectPayload(
  value: unknown,
  requiredKeys: readonly string[],
  optionalKeys: readonly string[] = [],
): { value: UnknownRecord } | { error: string } {
  if (!isRecord(value)) {
    return { error: 'payload must be an object' };
  }
  if (hasForbiddenPrivilegedField(value)) {
    return { error: 'payload contained privileged fields' };
  }

  const allowed = new Set([...requiredKeys, ...optionalKeys]);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      return { error: 'payload contained unsupported fields' };
    }
  }
  for (const key of requiredKeys) {
    if (!Object.hasOwn(value, key)) {
      return { error: `payload missing required field ${key}` };
    }
  }
  return { value };
}

function isEmptyPayload(value: unknown): boolean {
  return isRecord(value) && Object.keys(value).length === 0 && !hasForbiddenPrivilegedField(value);
}

function applyTrackSnapshot(
  snapshot: PlayerSnapshot,
  requestId: PlayerRequestId,
  tracks: readonly PlayerTrackSummary[],
): PlayerSnapshot {
  return {
    ...snapshot,
    requestId,
    tracks,
    selectedAudioTrackId: findSelectedTrackId(tracks, 'audio'),
    selectedSubtitleTrackId: findSelectedTrackId(tracks, 'subtitle'),
    selectedVideoTrackId: findSelectedTrackId(tracks, 'video'),
  };
}

function findSelectedTrackId(
  tracks: readonly PlayerTrackSummary[],
  kind: PlayerTrackKind,
): PlayerTrackId | null {
  return tracks.find((track) => track.kind === kind && track.selected)?.id ?? null;
}

function validationFailure(requestId: PlayerRequestId | undefined, reason: string): ValidationFailure {
  return {
    error: createPlayerError({
      code: 'PLAYER_VALIDATION_FAILED',
      category: 'validation-failure',
      message: 'The player request was rejected because it was not valid.',
      requestId,
      diagnostic: {
        component: 'desktop-player-adapter',
        operation: 'validation',
        status: 'rejected',
        reason,
      },
    }),
  };
}

function hostFailureToError(requestId: PlayerRequestId, failure: NativePlayerHostFailure): PlayerError {
  const hostFailure: UnknownRecord =
    isRecord(failure) && !hasForbiddenPrivilegedField(failure) ? failure : {};
  const category = isPlayerErrorCategory(hostFailure.category) ? hostFailure.category : 'unknown';
  return createPlayerError({
    code: hostFailureCode(category),
    category,
    message: hostFailureMessage(category),
    recoverable: typeof hostFailure.recoverable === 'boolean' ? hostFailure.recoverable : false,
    retryable: typeof hostFailure.retryable === 'boolean' ? hostFailure.retryable : false,
    requestId,
    diagnostic: {
      component: 'desktop-player-adapter',
      operation: 'host.command',
      status: 'failed',
      reason: 'host reported command failure',
    },
  });
}

function normalizeHostErrorPayload(
  value: unknown,
  requestId: PlayerRequestId | null,
): { error: ValidationFailure['error'] } | PlayerError {
  if (!isRecord(value) || hasForbiddenPrivilegedField(value)) {
    return validationFailure(requestId ?? undefined, 'host error payload was invalid');
  }

  const category = isPlayerErrorCategory(value.category) ? value.category : 'unknown';
  return createPlayerError({
    code: hostFailureCode(category),
    category,
    message: hostFailureMessage(category),
    recoverable: typeof value.recoverable === 'boolean' ? value.recoverable : false,
    retryable: typeof value.retryable === 'boolean' ? value.retryable : false,
    requestId: requestId ?? undefined,
    diagnostic: {
      component: 'desktop-player-adapter',
      operation: 'host.error',
      status: 'failed',
      reason: 'host reported playback failure',
    },
  });
}

function hostFailureCode(category: PlayerErrorCategory): string {
  switch (category) {
    case 'source':
      return 'PLAYER_HOST_SOURCE_FAILURE';
    case 'authentication':
      return 'PLAYER_HOST_AUTHENTICATION_FAILURE';
    case 'authorization':
      return 'PLAYER_HOST_AUTHORIZATION_FAILURE';
    case 'network':
      return 'PLAYER_HOST_NETWORK_FAILURE';
    case 'unsupported-media':
      return 'PLAYER_HOST_UNSUPPORTED_MEDIA';
    case 'unsupported-capability':
      return 'PLAYER_HOST_UNSUPPORTED_CAPABILITY';
    case 'timeout':
      return 'PLAYER_HOST_TIMEOUT';
    case 'aborted':
      return 'PLAYER_HOST_ABORTED';
    case 'engine-failure':
      return 'PLAYER_HOST_ENGINE_FAILURE';
    case 'helper-failure':
      return 'PLAYER_HOST_HELPER_FAILURE';
    case 'render-failure':
      return 'PLAYER_HOST_RENDER_FAILURE';
    case 'track-failure':
      return 'PLAYER_HOST_TRACK_FAILURE';
    case 'cleanup-failure':
      return 'PLAYER_HOST_CLEANUP_FAILURE';
    case 'stale-request':
      return 'PLAYER_HOST_STALE_REQUEST';
    case 'validation-failure':
      return 'PLAYER_HOST_VALIDATION_FAILURE';
    case 'unknown':
      return 'PLAYER_HOST_FAILURE';
    default:
      return assertNever(category);
  }
}

function hostFailureMessage(category: PlayerErrorCategory): string {
  switch (category) {
    case 'source':
      return 'The player helper could not load the selected media.';
    case 'authentication':
    case 'authorization':
      return 'The player helper was not allowed to load the selected media.';
    case 'network':
      return 'The player helper could not reach the media source.';
    case 'unsupported-media':
      return 'The selected media is not supported by the player helper.';
    case 'unsupported-capability':
      return 'The requested player capability is not supported.';
    case 'timeout':
      return 'The player helper timed out.';
    case 'aborted':
      return 'The player helper operation was aborted.';
    case 'engine-failure':
      return 'The player engine failed.';
    case 'helper-failure':
      return 'The player helper failed.';
    case 'render-failure':
      return 'The player renderer surface failed.';
    case 'track-failure':
      return 'The player helper could not apply the requested track change.';
    case 'cleanup-failure':
      return 'The player helper could not clean up safely.';
    case 'stale-request':
      return 'The player helper reported a stale playback request.';
    case 'validation-failure':
      return 'The player helper returned an invalid playback payload.';
    case 'unknown':
      return 'The player helper reported a playback failure.';
    default:
      return assertNever(category);
  }
}

function sanitizePlayerError(value: unknown, fallbackCode: string): PlayerError {
  if (!isRecord(value) || hasForbiddenPrivilegedField(value)) {
    return createPlayerError({
      code: fallbackCode,
      category: 'validation-failure',
      message: 'The player helper returned an invalid error payload.',
      diagnostic: {
        component: 'desktop-player-adapter',
        operation: 'host.error',
        status: 'rejected',
        reason: 'invalid host error payload',
      },
    });
  }

  return createPlayerError({
    code: isNonEmptyString(value.code) ? value.code : fallbackCode,
    category: isPlayerErrorCategory(value.category) ? value.category : 'unknown',
    message: isNonEmptyString(value.message) ? value.message : 'The player helper reported an error.',
    recoverable: typeof value.recoverable === 'boolean' ? value.recoverable : false,
    retryable: typeof value.retryable === 'boolean' ? value.retryable : false,
    requestId: isNonEmptyString(value.requestId) ? value.requestId : undefined,
    diagnostic: sanitizeDiagnostic(value.diagnostic),
  });
}

function createPlayerError(input: {
  code: string;
  category: PlayerErrorCategory;
  message: string;
  recoverable?: boolean;
  retryable?: boolean;
  requestId?: PlayerRequestId;
  diagnostic?: PlayerRendererSafeDiagnostic;
}): PlayerError {
  return {
    code: input.code,
    category: input.category,
    message: input.message,
    recoverable: input.recoverable ?? false,
    retryable: input.retryable ?? false,
    requestId: input.requestId,
    diagnostic: sanitizeDiagnostic(input.diagnostic),
  };
}

function sanitizeDiagnostic(value: unknown): PlayerRendererSafeDiagnostic | undefined {
  if (!isRecord(value) || hasForbiddenPrivilegedField(value)) {
    return undefined;
  }

  const counts = isRecord(value.counts) ? sanitizeCounts(value.counts) : undefined;
  const media = validateMediaDiagnostic(value.media);
  const trackIds = validateTrackIds(value.trackIds);
  return {
    component: isNonEmptyString(value.component) ? value.component : 'desktop-player-adapter',
    operation: isNonEmptyString(value.operation) ? value.operation : 'unknown',
    status: typeof value.status === 'string' ? value.status : undefined,
    reason: typeof value.reason === 'string' ? value.reason : undefined,
    counts,
    capabilityProfileId: isNonEmptyString(value.capabilityProfileId)
      ? value.capabilityProfileId
      : undefined,
    trackIds,
    media,
    timestampMs: isFiniteNonNegativeNumber(value.timestampMs) ? value.timestampMs : undefined,
  };
}

function sanitizeCounts(value: UnknownRecord): Readonly<Record<string, number>> | undefined {
  const counts: Record<string, number> = {};
  for (const [key, count] of Object.entries(value)) {
    if (isNonEmptyString(key) && isFiniteNonNegativeNumber(count)) {
      counts[key] = count;
    }
  }
  return Object.keys(counts).length === 0 ? undefined : counts;
}

function validateTrackIds(value: unknown): readonly PlayerTrackId[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }

  const ids: PlayerTrackId[] = [];
  for (const item of value) {
    if (!isNonEmptyString(item)) {
      return undefined;
    }
    ids.push(item);
  }
  return ids;
}

function validateMediaDiagnostic(value: unknown): PlayerRendererSafeDiagnostic['media'] | undefined {
  if (!isRecord(value) || !isNonEmptyString(value.id) || !isNonEmptyString(value.title)) {
    return undefined;
  }
  return { id: value.id, title: value.title };
}

function createInitialSnapshot(): PlayerSnapshot {
  return {
    requestId: null,
    status: 'idle',
    media: null,
    capabilityProfileId: null,
    positionMs: 0,
    durationMs: null,
    bufferedRanges: [],
    playing: false,
    volume: 1,
    muted: false,
    playbackRate: 1,
    selectedAudioTrackId: null,
    selectedSubtitleTrackId: null,
    selectedVideoTrackId: null,
    tracks: [],
    lastError: null,
  };
}

function cloneSnapshot(snapshot: PlayerSnapshot): PlayerSnapshot {
  return {
    ...snapshot,
    media: snapshot.media === null ? null : { ...snapshot.media },
    bufferedRanges: snapshot.bufferedRanges.map((range) => ({ ...range })),
    tracks: snapshot.tracks.map((track) => ({ ...track })),
    lastError: snapshot.lastError === null ? null : sanitizePlayerError(snapshot.lastError, 'PLAYER_ERROR'),
  };
}

function isRecord(value: unknown): value is UnknownRecord {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isNullableString(value: unknown): value is string | null {
  return value === null || isNonEmptyString(value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function isFiniteNonNegativeNumber(value: unknown): value is number {
  return isFiniteNumber(value) && value >= 0;
}

function isFiniteRangeNumber(value: unknown, min: number, max: number): value is number {
  return isFiniteNumber(value) && value >= min && value <= max;
}

function isNullableFiniteNonNegativeNumber(value: unknown): value is number | null {
  return value === null || isFiniteNonNegativeNumber(value);
}

function isStringInSet<TValue extends string>(
  value: unknown,
  allowed: readonly TValue[],
): value is TValue {
  return typeof value === 'string' && allowed.includes(value as TValue);
}

function isPlayerErrorCategory(value: unknown): value is PlayerErrorCategory {
  return isStringInSet(value, PLAYER_ERROR_CATEGORIES);
}

function isPlayerRendererIntent(value: RendererIntentEnvelope<unknown>['intent']): value is PlayerRendererIntent {
  return Object.hasOwn(PLAYER_INTENT_TO_COMMAND, value);
}

function assertNever(value: never): never {
  throw new Error(`Unhandled player error category: ${String(value)}`);
}

function hasForbiddenPrivilegedField(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some((item) => hasForbiddenPrivilegedField(item));
  }
  if (!isRecord(value)) {
    return false;
  }

  for (const [key, child] of Object.entries(value)) {
    if (
      PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS.includes(
        key as (typeof PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS)[number],
      ) ||
      hasForbiddenPrivilegedField(child)
    ) {
      return true;
    }
  }
  return false;
}

function readRequestId(value: UnknownRecord): PlayerRequestId | undefined {
  return isNonEmptyString(value.requestId) ? value.requestId : undefined;
}
