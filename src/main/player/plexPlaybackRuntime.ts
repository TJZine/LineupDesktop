import {
  hasPlayerForbiddenPrivilegedField,
  type PlayerError,
  type PlayerCommand,
  type PlayerEvent,
  type PlayerLoadCommandPayload,
  type PlayerMediaSummary,
  type PlayerRendererSafeDiagnostic,
  type PlayerRequestId,
} from '../../contracts/player.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
export type PlexPlaybackRuntimeCleanupReason =
  | 'stop'
  | 'switch'
  | 'error'
  | 'helper-crash'
  | 'logout'
  | 'server-change'
  | 'profile-change'
  | 'teardown';
export interface PlexPlaybackScheduleSelection {
  channelId: string;
  programId: string;
  startedAtMs: number;
  endsAtMs?: number | null;
}
export interface PlexPlaybackRuntimeSchedulerPort {
  getCurrentPlayback(input: {
    nowMs: number;
    reason: 'startup' | 'schedule-tick' | 'manual-switch';
  }): Promise<PlexPlaybackScheduleSelection | null>;
}
export interface PlexPlaybackPmsSessionLease {
  id: string;
  requestId: PlayerRequestId;
}
export interface PlexPlaybackRuntimeCandidate {
  requestId?: PlayerRequestId;
  load: PlayerLoadCommandPayload;
  pmsSession?: PlexPlaybackPmsSessionLease | null;
}
export interface PlexPlaybackRuntimeChannelPort {
  resolvePlaybackCandidate(
    selection: PlexPlaybackScheduleSelection,
  ): Promise<PlexPlaybackRuntimeCandidate>;
}
export type PlexPlaybackRuntimePlayerDispatchResult =
  | {
      ok: true;
      events?: readonly PlayerEvent[];
    }
  | {
      ok: false;
      events?: readonly PlayerEvent[];
    };
export interface PlexPlaybackRuntimePlayerPort {
  dispatch(command: PlayerCommand): Promise<PlexPlaybackRuntimePlayerDispatchResult>;
  cleanup(requestId: PlayerRequestId | null): Promise<void>;
}
export interface PlexPlaybackRuntimePmsPort {
  releaseSession(
    session: PlexPlaybackPmsSessionLease,
    input: {
      reason: PlexPlaybackRuntimeCleanupReason | 'stale';
      requestId: PlayerRequestId;
    },
  ): Promise<void>;
}
export interface PlexPlaybackRuntimeClockPort {
  now(): number;
}
export interface PlexPlaybackRuntimeOptions {
  scheduler: PlexPlaybackRuntimeSchedulerPort;
  channel: PlexPlaybackRuntimeChannelPort;
  player: PlexPlaybackRuntimePlayerPort;
  pms: PlexPlaybackRuntimePmsPort;
  clock?: PlexPlaybackRuntimeClockPort;
  createRequestId?: (prefix: string) => PlayerRequestId;
  onEvents?: (events: readonly PlayerEvent[]) => void;
  diagnosticEventStore?: DiagnosticEventStore;
}
export interface PlexPlaybackRuntimeStartResult {
  accepted: boolean;
  epoch: number;
  requestId: PlayerRequestId | null;
  events: readonly PlayerEvent[];
}
export class PlexPlaybackRuntimeCandidateResolutionError extends Error {
  readonly playerError: PlayerError;
  constructor(playerError: PlayerError) {
    super('Plex playback candidate resolution failed.');
    this.name = 'PlexPlaybackRuntimeCandidateResolutionError';
    this.playerError = playerError;
  }
}
interface ActivePlaybackSession {
  epoch: number;
  requestId: PlayerRequestId;
  media: PlayerMediaSummary;
  pmsSession: PlexPlaybackPmsSessionLease | null;
}
const EMPTY_PAYLOAD: Record<string, never> = {};
export class PlexPlaybackRuntime {
  readonly #scheduler: PlexPlaybackRuntimeSchedulerPort;
  readonly #channel: PlexPlaybackRuntimeChannelPort;
  readonly #player: PlexPlaybackRuntimePlayerPort;
  readonly #pms: PlexPlaybackRuntimePmsPort;
  readonly #clock: PlexPlaybackRuntimeClockPort;
  readonly #createRequestId: (prefix: string) => PlayerRequestId;
  readonly #onEvents?: (events: readonly PlayerEvent[]) => void;
  readonly #diagnosticEventStore?: DiagnosticEventStore;
  #epoch = 0;
  #active: ActivePlaybackSession | null = null;
  #requestCounter = 0;
  constructor(options: PlexPlaybackRuntimeOptions) {
    this.#scheduler = options.scheduler;
    this.#channel = options.channel;
    this.#player = options.player;
    this.#pms = options.pms;
    this.#clock = options.clock ?? { now: () => Date.now() };
    this.#createRequestId =
      options.createRequestId ??
      ((prefix) => {
        this.#requestCounter += 1;
        return `${prefix}-${this.#requestCounter}`;
      });
    this.#onEvents = options.onEvents;
    this.#diagnosticEventStore = options.diagnosticEventStore;
  }
  getCurrentEpoch(): number {
    return this.#epoch;
  }
  getActiveRequestId(): PlayerRequestId | null {
    return this.#active?.requestId ?? null;
  }
  async startCurrentPlayback(
    reason: 'startup' | 'schedule-tick' | 'manual-switch' = 'schedule-tick',
  ): Promise<PlexPlaybackRuntimeStartResult> {
    const epoch = this.#nextEpoch();
    const events: PlayerEvent[] = [];
    events.push(...(await this.#cleanupActive('switch', { invalidateEpoch: false })));
    let selection: PlexPlaybackScheduleSelection | null;
    try {
      selection = await this.#scheduler.getCurrentPlayback({
        nowMs: this.#clock.now(),
        reason,
      });
    } catch {
      if (!this.#isCurrentEpoch(epoch)) {
        return this.#staleStartResult(epoch, null, events, 'scheduler failure arrived after cleanup');
      }
      events.push(this.#schedulerSelectionError());
      this.#emit(events);
      return { accepted: false, epoch, requestId: null, events };
    }
    if (!this.#isCurrentEpoch(epoch)) {
      return this.#staleStartResult(epoch, null, events, 'scheduler result arrived after cleanup');
    }
    if (selection === null) {
      events.push(this.#warning(null, 'PLAYER_PLAYBACK_NO_SELECTION', 'No scheduled playback is active.', {
        operation: 'schedule.resolve',
        status: 'ignored',
        reason: 'no scheduled playback',
      }));
      this.#emit(events);
      return { accepted: false, epoch, requestId: null, events };
    }
    if (!isSafeScheduleSelection(selection)) {
      events.push(this.#boundaryError(undefined, 'schedule selection was not renderer-safe'));
      this.#emit(events);
      return { accepted: false, epoch, requestId: null, events };
    }
    let candidate: PlexPlaybackRuntimeCandidate;
    try {
      candidate = await this.#channel.resolvePlaybackCandidate(selection);
    } catch (error) {
      events.push(this.#candidateResolutionError(error));
      this.#emit(events);
      return { accepted: false, epoch, requestId: null, events };
    }
    if (!isSafeRuntimeCandidate(candidate)) {
      const rejectedSession = readReleasablePmsSession(candidate);
      if (rejectedSession !== null) {
        events.push(...(await this.#releaseUnsafeCandidateSession(rejectedSession)));
      }
      events.push(this.#boundaryError(undefined, 'channel playback candidate was not renderer-safe'));
      this.#emit(events);
      return { accepted: false, epoch, requestId: null, events };
    }
    const requestId = candidate.requestId ?? this.#createRequestId('plex-playback');
    if (!isPmsSessionForRequest(candidate.pmsSession ?? null, requestId)) {
      events.push(...(await this.#releaseRejectedSession(candidate.pmsSession ?? null, requestId)));
      events.push(this.#boundaryError(requestId, 'pms session request id did not match playback request'));
      this.#emit(events);
      return { accepted: false, epoch, requestId, events };
    }
    const active: ActivePlaybackSession = {
      epoch,
      requestId,
      media: candidate.load.media,
      pmsSession: candidate.pmsSession ?? null,
    };
    if (!this.#isCurrentEpoch(epoch)) {
      events.push(...(await this.#releaseOrphanSession(active, 'stale')));
      return this.#staleStartResult(epoch, requestId, events, 'candidate arrived after cleanup');
    }
    this.#active = active;
    const command: PlayerCommand = {
      command: 'load',
      requestId,
      payload: candidate.load,
    };
    let playerResult: PlexPlaybackRuntimePlayerDispatchResult;
    try {
      playerResult = await this.#player.dispatch(command);
    } catch {
      playerResult = { ok: false };
    }
    if (!this.#isCurrentEpoch(epoch) || this.#active?.requestId !== requestId) {
      events.push(...this.#quarantineEvents(epoch, playerResult.events ?? [], 'player load settled late'));
      return this.#staleStartResult(epoch, requestId, events, 'player load settled after cleanup');
    }
    for (const event of playerResult.events ?? []) {
      events.push(...this.handlePlayerEvent(epoch, event));
    }
    if (!playerResult.ok) {
      events.push(this.#loadFailedError(requestId, active.media));
      events.push(...(await this.#cleanupActive('error', { invalidateEpoch: false })));
      this.#nextEpoch();
      this.#emit(events);
      return { accepted: false, epoch, requestId, events };
    }
    this.#emit(events);
    return { accepted: true, epoch, requestId, events };
  }
  async cleanup(input: {
    reason: PlexPlaybackRuntimeCleanupReason;
  }): Promise<readonly PlayerEvent[]> {
    const events = await this.#cleanupActive(input.reason, { invalidateEpoch: true });
    this.#emit(events);
    return events;
  }
  async stop(): Promise<readonly PlayerEvent[]> {
    const active = this.#active;
    if (active !== null) {
      try {
        await this.#player.dispatch({
          command: 'stop',
          requestId: active.requestId,
          payload: EMPTY_PAYLOAD,
        });
      } catch {
        // Stop is best-effort; scoped cleanup below owns renderer-safe failure reporting.
      }
    }
    return this.cleanup({ reason: 'stop' });
  }
  async teardown(): Promise<readonly PlayerEvent[]> {
    return this.cleanup({ reason: 'teardown' });
  }
  handlePlayerEvent(epoch: number, event: PlayerEvent): readonly PlayerEvent[] {
    if (hasPlayerForbiddenPrivilegedField(event)) {
      return [this.#boundaryError(readEventRequestId(event) ?? undefined, 'player event contained privileged fields')];
    }
    const eventRequestId = readEventRequestId(event);
    if (
      epoch !== this.#epoch ||
      this.#active === null ||
      (eventRequestId !== null && eventRequestId !== this.#active.requestId)
    ) {
      return [
        this.#warning(eventRequestId, 'PLAYER_STALE_PLAYBACK_EVENT', 'A stale playback event was ignored.', {
          operation: event.event,
          status: 'ignored',
          reason: 'event epoch did not match current playback state',
        }),
      ];
    }
    return [event];
  }
  async handleHelperCrash(): Promise<readonly PlayerEvent[]> {
    this.#diagnosticEventStore?.record({
      surface: 'plex-playback-runtime',
      category: 'helper-crash',
      severity: 'error',
      status: 'observed',
      operation: 'helper-crash.cleanup',
      message: 'Playback runtime received a helper crash cleanup request.',
      requestId: this.#active?.requestId,
      result: 'ignored',
      context: { code: 'PLAYER_HELPER_CRASHED' },
    });
    return this.cleanup({ reason: 'helper-crash' });
  }
  #nextEpoch(): number {
    this.#epoch = this.#epoch >= Number.MAX_SAFE_INTEGER ? 1 : this.#epoch + 1;
    return this.#epoch;
  }
  #isCurrentEpoch(epoch: number): boolean {
    return epoch === this.#epoch;
  }
  async #cleanupActive(
    reason: PlexPlaybackRuntimeCleanupReason,
    options: { invalidateEpoch: boolean },
  ): Promise<readonly PlayerEvent[]> {
    if (options.invalidateEpoch) {
      this.#nextEpoch();
    }
    const active = this.#active;
    if (active === null) {
      return [];
    }
    this.#active = null;
    const events: PlayerEvent[] = [];
    if (active.pmsSession !== null) {
      try {
        await this.#pms.releaseSession(active.pmsSession, {
          reason,
          requestId: active.requestId,
        });
      } catch {
        this.#recordCleanupDiagnostic(active.requestId, reason, 'PLAYER_PLAYBACK_PMS_CLEANUP_FAILED');
        events.push(this.#cleanupFailure(active.requestId, reason, 'pms session release failed'));
      }
    }
    try {
      await this.#player.cleanup(active.requestId);
    } catch {
      this.#recordCleanupDiagnostic(active.requestId, reason, 'PLAYER_PLAYBACK_PLAYER_CLEANUP_FAILED');
      events.push(this.#cleanupFailure(active.requestId, reason, 'player cleanup failed'));
    }
    return events;
  }
  async #releaseOrphanSession(
    active: ActivePlaybackSession,
    reason: 'stale',
  ): Promise<readonly PlayerEvent[]> {
    if (active.pmsSession === null) {
      return [];
    }
    try {
      await this.#pms.releaseSession(active.pmsSession, {
        reason,
        requestId: active.requestId,
      });
      return [];
    } catch {
      return [this.#cleanupFailure(active.requestId, 'switch', 'stale pms session release failed')];
    }
  }
  async #releaseRejectedSession(
    session: PlexPlaybackPmsSessionLease | null,
    requestId: PlayerRequestId,
  ): Promise<readonly PlayerEvent[]> {
    if (session === null) {
      return [];
    }
    try {
      await this.#pms.releaseSession(session, {
        reason: 'stale',
        requestId,
      });
      return [];
    } catch {
      return [this.#cleanupFailure(requestId, 'switch', 'rejected pms session release failed')];
    }
  }
  async #releaseUnsafeCandidateSession(
    session: PlexPlaybackPmsSessionLease,
  ): Promise<readonly PlayerEvent[]> {
    try {
      await this.#pms.releaseSession(session, {
        reason: 'stale',
        requestId: 'unsafe-candidate',
      });
      return [];
    } catch {
      return [this.#unscopedCleanupFailure('rejected unsafe pms session release failed')];
    }
  }
  #quarantineEvents(
    epoch: number,
    events: readonly PlayerEvent[],
    reason: string,
  ): readonly PlayerEvent[] {
    if (events.length === 0) {
      return [];
    }
    return [
      this.#warning(readEventRequestId(events[0]) ?? null, 'PLAYER_STALE_PLAYBACK_EVENT', 'A stale playback event was ignored.', {
        operation: 'player.dispatch',
        status: 'ignored',
        reason: epoch === this.#epoch ? reason : 'event epoch did not match current playback state',
        counts: { ignoredEvents: events.length },
      }),
    ];
  }
  #staleStartResult(
    epoch: number,
    requestId: PlayerRequestId | null,
    events: readonly PlayerEvent[],
    reason: string,
  ): PlexPlaybackRuntimeStartResult {
    const nextEvents = [
      ...events,
      this.#warning(requestId, 'PLAYER_STALE_PLAYBACK_REQUEST', 'A stale playback request was ignored.', {
        operation: 'runtime.start',
        status: 'ignored',
        reason,
      }),
    ];
    this.#emit(nextEvents);
    return { accepted: false, epoch, requestId, events: nextEvents };
  }
  #warning(
    requestId: PlayerRequestId | null,
    code: string,
    message: string,
    diagnostic: Omit<PlayerRendererSafeDiagnostic, 'component'>,
  ): PlayerEvent {
    const warning: PlayerError = {
      code,
      category: 'stale-request',
      message,
      recoverable: true,
      retryable: false,
      requestId: requestId ?? undefined,
      diagnostic: { component: 'plex-playback-runtime', ...diagnostic },
    };
    return {
      event: 'warning',
      requestId: warning.requestId ?? null,
      warning,
    };
  }
  #error(
    requestId: PlayerRequestId | undefined,
    code: string,
    message: string,
    diagnostic: Omit<PlayerRendererSafeDiagnostic, 'component'>,
  ): PlayerEvent {
    return {
      event: 'error',
      requestId: requestId ?? null,
      error: {
        code,
        category: 'source',
        message,
        recoverable: true,
        retryable: true,
        requestId,
        diagnostic: { component: 'plex-playback-runtime', ...diagnostic },
      },
    };
  }
  #loadFailedError(requestId: PlayerRequestId, media: PlayerMediaSummary): PlayerEvent {
    return this.#error(requestId, 'PLAYER_PLAYBACK_LOAD_FAILED', 'The player could not load the scheduled media.', {
      operation: 'player.load',
      status: 'failed',
      reason: 'player load failed',
      media: projectDiagnosticMedia(media),
    });
  }
  #schedulerSelectionError(): PlayerEvent {
    return this.#error(
      undefined,
      'PLAYER_PLAYBACK_SELECTION_UNAVAILABLE',
      'The playback runtime could not resolve the scheduled playback.',
      {
        operation: 'schedule.resolve',
        status: 'failed',
        reason: 'scheduler selection failed',
      },
    );
  }
  #boundaryError(requestId: PlayerRequestId | undefined, reason: string): PlayerEvent {
    return {
      event: 'error',
      requestId: requestId ?? null,
      error: {
        code: 'PLAYER_RUNTIME_VALIDATION_FAILED',
        category: 'validation-failure',
        message: 'The playback runtime rejected an unsafe playback payload.',
        recoverable: false,
        retryable: false,
        requestId,
        diagnostic: {
          component: 'plex-playback-runtime',
          operation: 'validation',
          status: 'rejected',
          reason,
        },
      },
    };
  }
  #candidateResolutionError(error: unknown): PlayerEvent {
    if (
      error instanceof PlexPlaybackRuntimeCandidateResolutionError &&
      isSafePlayerError(error.playerError)
    ) {
      return {
        event: 'error',
        requestId: error.playerError.requestId ?? null,
        error: error.playerError,
      };
    }
    return this.#error(
      undefined,
      'PLAYER_PLAYBACK_CANDIDATE_UNAVAILABLE',
      'The playback runtime could not resolve the scheduled media.',
      {
        operation: 'channel.resolve',
        status: 'failed',
        reason: 'playback candidate resolution failed',
      },
    );
  }
  #cleanupFailure(
    requestId: PlayerRequestId,
    reason: PlexPlaybackRuntimeCleanupReason,
    failureReason: string,
  ): PlayerEvent {
    return {
      event: 'error',
      requestId,
      error: {
        code: 'PLAYER_PLAYBACK_CLEANUP_FAILED',
        category: 'cleanup-failure',
        message: 'Playback cleanup did not complete safely.',
        recoverable: true,
        retryable: true,
        requestId,
        diagnostic: {
          component: 'plex-playback-runtime',
          operation: 'cleanup',
          status: 'failed',
          reason: failureReason,
          counts: { [reason]: 1 },
        },
      },
    };
  }
  #unscopedCleanupFailure(failureReason: string): PlayerEvent {
    return {
      event: 'error',
      requestId: null,
      error: {
        code: 'PLAYER_PLAYBACK_CLEANUP_FAILED',
        category: 'cleanup-failure',
        message: 'Playback cleanup did not complete safely.',
        recoverable: true,
        retryable: true,
        diagnostic: {
          component: 'plex-playback-runtime',
          operation: 'cleanup',
          status: 'failed',
          reason: failureReason,
        },
      },
    };
  }
  #emit(events: readonly PlayerEvent[]): void {
    if (events.length > 0) {
      this.#onEvents?.(events);
    }
  }
  #recordCleanupDiagnostic(
    requestId: PlayerRequestId,
    reason: PlexPlaybackRuntimeCleanupReason,
    code: string,
  ): void {
    this.#diagnosticEventStore?.record({
      surface: 'plex-playback-runtime',
      category: 'cleanup',
      severity: 'error',
      status: 'failed',
      operation: 'cleanup',
      message: 'Playback runtime cleanup failed.',
      requestId,
      result: 'failure',
      context: { code, reason },
    });
  }
}
function isSafeScheduleSelection(value: unknown): value is PlexPlaybackScheduleSelection {
  if (!isRecord(value) || hasPlayerForbiddenPrivilegedField(value)) {
    return false;
  }
  return (
    hasOnlyKeys(value, ['channelId', 'programId', 'startedAtMs'], ['endsAtMs']) &&
    isNonEmptyString(value.channelId) &&
    isNonEmptyString(value.programId) &&
    isFiniteNonNegativeNumber(value.startedAtMs) &&
    (value.endsAtMs === undefined || value.endsAtMs === null || isFiniteNonNegativeNumber(value.endsAtMs))
  );
}
function isSafeRuntimeCandidate(value: unknown): value is PlexPlaybackRuntimeCandidate {
  if (!isRecord(value) || hasPlayerForbiddenPrivilegedField(value)) {
    return false;
  }
  return (
    hasOnlyKeys(value, ['load'], ['requestId', 'pmsSession']) &&
    (value.requestId === undefined || isNonEmptyString(value.requestId)) &&
    isSafeLoadPayload(value.load) &&
    (value.pmsSession === undefined ||
      value.pmsSession === null ||
      isSafePmsSession(value.pmsSession))
  );
}
function isSafePmsSession(value: unknown): value is PlexPlaybackPmsSessionLease {
  return (
    isRecord(value) &&
    !hasPlayerForbiddenPrivilegedField(value) &&
    hasOnlyKeys(value, ['id', 'requestId']) &&
    isNonEmptyString(value.id) &&
    isNonEmptyString(value.requestId)
  );
}
function readReleasablePmsSession(value: unknown): PlexPlaybackPmsSessionLease | null {
  if (!isRecord(value) || !('pmsSession' in value)) {
    return null;
  }
  return isSafePmsSession(value.pmsSession) ? value.pmsSession : null;
}
function isPmsSessionForRequest(
  session: PlexPlaybackPmsSessionLease | null,
  requestId: PlayerRequestId,
): boolean {
  return session === null || session.requestId === requestId;
}
function isSafeLoadPayload(value: unknown): value is PlayerLoadCommandPayload {
  if (!isRecord(value) || hasPlayerForbiddenPrivilegedField(value)) {
    return false;
  }
  return (
    hasOnlyKeys(value, ['media', 'policy'], ['capabilityProfileId']) &&
    isSafeMediaSummary(value.media) &&
    isSafeLoadPolicy(value.policy) &&
    (value.capabilityProfileId === undefined || isNonEmptyString(value.capabilityProfileId))
  );
}
function isSafeMediaSummary(value: unknown): value is PlayerMediaSummary {
  return (
    isRecord(value) &&
    !hasPlayerForbiddenPrivilegedField(value) &&
    hasOnlyKeys(value, ['id', 'title'], ['subtitle', 'durationMs', 'container']) &&
    isNonEmptyString(value.id) &&
    isNonEmptyString(value.title) &&
    (value.subtitle === undefined || typeof value.subtitle === 'string') &&
    (value.durationMs === undefined || value.durationMs === null || isFiniteNonNegativeNumber(value.durationMs)) &&
    (value.container === undefined || typeof value.container === 'string')
  );
}
function isSafeLoadPolicy(value: unknown): value is PlayerLoadCommandPayload['policy'] {
  return (
    isRecord(value) &&
    !hasPlayerForbiddenPrivilegedField(value) &&
    hasOnlyKeys(
      value,
      ['autoplay'],
      ['startPositionMs', 'preferredAudioTrackId', 'preferredSubtitleTrackId'],
    ) &&
    typeof value.autoplay === 'boolean' &&
    (value.startPositionMs === undefined || isFiniteNonNegativeNumber(value.startPositionMs)) &&
    (value.preferredAudioTrackId === undefined ||
      value.preferredAudioTrackId === null ||
      isNonEmptyString(value.preferredAudioTrackId)) &&
    (value.preferredSubtitleTrackId === undefined ||
      value.preferredSubtitleTrackId === null ||
      isNonEmptyString(value.preferredSubtitleTrackId))
  );
}
function isSafePlayerError(value: unknown): value is PlayerError {
  if (!isRecord(value) || hasPlayerForbiddenPrivilegedField(value)) {
    return false;
  }
  return (
    hasOnlyKeys(value, ['code', 'category', 'message', 'recoverable', 'retryable'], ['requestId', 'diagnostic']) &&
    isNonEmptyString(value.code) &&
    typeof value.category === 'string' &&
    isNonEmptyString(value.message) &&
    typeof value.recoverable === 'boolean' &&
    typeof value.retryable === 'boolean' &&
    (value.requestId === undefined || isNonEmptyString(value.requestId)) &&
    (value.diagnostic === undefined || isSafeDiagnostic(value.diagnostic))
  );
}
function isSafeDiagnostic(value: unknown): value is PlayerError['diagnostic'] {
  if (!isRecord(value) || hasPlayerForbiddenPrivilegedField(value)) {
    return false;
  }
  return (
    hasOnlyKeys(
      value,
      ['component', 'operation'],
      ['status', 'reason', 'counts', 'capabilityProfileId', 'trackIds', 'media', 'timestampMs'],
    ) &&
    isNonEmptyString(value.component) &&
    isNonEmptyString(value.operation) &&
    (value.status === undefined || typeof value.status === 'string') &&
    (value.reason === undefined || typeof value.reason === 'string') &&
    (value.counts === undefined || isSafeCounts(value.counts)) &&
    (value.capabilityProfileId === undefined || isNonEmptyString(value.capabilityProfileId)) &&
    (value.trackIds === undefined ||
      (Array.isArray(value.trackIds) && value.trackIds.every(isNonEmptyString))) &&
    (value.media === undefined || isSafeDiagnosticMedia(value.media)) &&
    (value.timestampMs === undefined || isFiniteNonNegativeNumber(value.timestampMs))
  );
}
function isSafeCounts(value: unknown): value is Readonly<Record<string, number>> {
  return (
    isRecord(value) &&
    Object.entries(value).every(([key, count]) => isNonEmptyString(key) && isFiniteNonNegativeNumber(count))
  );
}
function isSafeDiagnosticMedia(value: unknown): value is NonNullable<PlayerError['diagnostic']>['media'] {
  return (
    isRecord(value) &&
    hasOnlyKeys(value, ['id', 'title']) &&
    isNonEmptyString(value.id) &&
    isNonEmptyString(value.title)
  );
}
function projectDiagnosticMedia(media: PlayerMediaSummary): Pick<PlayerMediaSummary, 'id' | 'title'> {
  return { id: media.id, title: media.title };
}
function readEventRequestId(event: PlayerEvent): PlayerRequestId | null {
  return 'requestId' in event ? event.requestId : null;
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function hasOnlyKeys(
  value: Record<string, unknown>,
  requiredKeys: readonly string[],
  optionalKeys: readonly string[] = [],
): boolean {
  const allowed = new Set([...requiredKeys, ...optionalKeys]);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      return false;
    }
  }
  return requiredKeys.every((key) => Object.hasOwn(value, key));
}
function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}
function isFiniteNonNegativeNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}
