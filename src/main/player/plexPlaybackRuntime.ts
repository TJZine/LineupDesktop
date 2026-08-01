import { clearTimeout, setTimeout } from 'node:timers';

import {
  hasPlayerForbiddenPrivilegedField,
  type PlayerError,
  type PlayerCommand,
  type PlayerEvent,
  type PlayerLoadCommandPayload,
  type PlayerMediaSummary,
  type PlayerRequestId,
} from '../../contracts/player.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import type { PlexPrivilegedPlaybackDescriptor } from '../plex/streamResolver.js';
import {
  type PrivilegedPlaybackDispatchContext,
  validatePrivilegedPlaybackDescriptor,
} from './privilegedPlaybackDispatchContext.js';
import {
  type PlexPlaybackActiveSession,
  PlexPlaybackRuntimeCleanupCoordinator,
} from './plexPlaybackRuntimeCleanup.js';
import {
  createRuntimeBoundaryError,
  createRuntimeLoadFailedError,
  createRuntimeSchedulerSelectionError,
  createRuntimeSourceError,
  createRuntimeWarning,
  recordRuntimeHelperCrashDiagnostic,
} from './plexPlaybackRuntimeDiagnostics.js';
import {
  PlexPlaybackRuntimeStaleCustody,
  readEventRequestId,
} from './plexPlaybackRuntimeStaleCustody.js';
import {
  PlexPlaybackRecoveryOwner,
  type PlexPlaybackRecoveryIdentity,
  type PlexPlaybackRecoveryTimerPort,
} from './plexPlaybackRecoveryOwner.js';
export type PlexPlaybackRuntimeCleanupReason = 'stop'
  | 'switch'
  | 'stale'
  | 'error'
  | 'helper-crash'
  | 'logout'
  | 'server-change'
  | 'profile-change'
  | 'teardown';
type PlexPlaybackRetryOwner = 'manual' | 'recovery';
type PlexPlaybackRetryResult = 'started' | 'failed' | 'stale';
export interface PlexPlaybackScheduleSelection {
  channelId: string;
  programId: string;
  startedAtMs: number;
  endsAtMs?: number | null;
}
export function projectPlexPlaybackScheduleSelection(input: {
  channelId: string;
  ratingKey: string;
  scheduledStartTime: number;
  scheduledEndTime: number;
}): PlexPlaybackScheduleSelection {
  const channelId = input.channelId.trim();
  return {
    channelId,
    programId: [
      'program',
      safeScheduleIdPart(channelId),
      safeScheduleIdPart(input.ratingKey),
      String(input.scheduledStartTime),
      String(input.scheduledEndTime),
    ].join('-'),
    startedAtMs: input.scheduledStartTime,
    endsAtMs: input.scheduledEndTime,
  };
}
export function isSamePlexPlaybackScheduleSelection(
  left: PlexPlaybackScheduleSelection | null,
  right: PlexPlaybackScheduleSelection,
): boolean {
  return (
    left !== null &&
    left.channelId === right.channelId &&
    left.programId === right.programId &&
    left.startedAtMs === right.startedAtMs &&
    (left.endsAtMs ?? null) === (right.endsAtMs ?? null)
  );
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
  privatePlayback?: PlexPrivilegedPlaybackDescriptor | null;
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
  dispatch(command: PlayerCommand, context?: PrivilegedPlaybackDispatchContext | null): Promise<PlexPlaybackRuntimePlayerDispatchResult>;
  cleanup(requestId: PlayerRequestId | null): Promise<void>;
}
export interface PlexPlaybackRuntimePmsPort {
  releaseSession(
    session: PlexPlaybackPmsSessionLease,
    input: {
      reason: PlexPlaybackRuntimeCleanupReason;
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
  recoveryTimer?: PlexPlaybackRecoveryTimerPort;
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
const EMPTY_PAYLOAD: Record<string, never> = {};
export class PlexPlaybackRuntime {
  readonly #scheduler: PlexPlaybackRuntimeSchedulerPort;
  readonly #channel: PlexPlaybackRuntimeChannelPort;
  readonly #player: PlexPlaybackRuntimePlayerPort;
  readonly #clock: PlexPlaybackRuntimeClockPort;
  readonly #createRequestId: (prefix: string) => PlayerRequestId;
  readonly #onEvents?: (events: readonly PlayerEvent[]) => void;
  readonly #diagnosticEventStore?: DiagnosticEventStore;
  readonly #cleanupCoordinator: PlexPlaybackRuntimeCleanupCoordinator;
  readonly #staleCustody = new PlexPlaybackRuntimeStaleCustody();
  readonly #recovery: PlexPlaybackRecoveryOwner;
  #epoch = 0;
  #active: PlexPlaybackActiveSession | null = null;
  #activeSelection: PlexPlaybackScheduleSelection | null = null;
  #cleanupHoldCount = 0;
  #requestCounter = 0;
  constructor(options: PlexPlaybackRuntimeOptions) {
    this.#scheduler = options.scheduler;
    this.#channel = options.channel;
    this.#player = options.player;
    this.#clock = options.clock ?? { now: () => Date.now() };
    this.#createRequestId =
      options.createRequestId ??
      ((prefix) => {
        this.#requestCounter += 1;
        return `${prefix}-${this.#requestCounter}`;
      });
    this.#onEvents = options.onEvents;
    this.#diagnosticEventStore = options.diagnosticEventStore;
    this.#cleanupCoordinator = new PlexPlaybackRuntimeCleanupCoordinator({
      player: options.player,
      pms: options.pms,
      diagnosticEventStore: options.diagnosticEventStore,
    });
    this.#recovery = new PlexPlaybackRecoveryOwner({
      timer: options.recoveryTimer ?? createDefaultRecoveryTimer(),
      retry: (identity) => this.#retrySelection(identity),
    });
  }
  getCurrentEpoch(): number {
    return this.#epoch;
  }
  getActiveRequestId(): PlayerRequestId | null {
    return this.#active?.requestId ?? null;
  }
  async retryCurrentPlayback(
    expectedSelection: PlexPlaybackScheduleSelection,
  ): Promise<boolean> {
    return (
      await this.#restartSelectionForRetry(expectedSelection, 'manual')
    ) === 'started';
  }
  async startCurrentPlayback(
    reason: 'startup' | 'schedule-tick' | 'manual-switch' = 'schedule-tick',
  ): Promise<PlexPlaybackRuntimeStartResult> {
    if (this.#cleanupHoldCount > 0) {
      return {
        accepted: false,
        epoch: this.#epoch,
        requestId: null,
        events: [],
      };
    }
    this.#recovery.cancel();
    this.#activeSelection = null;
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
      events.push(createRuntimeSchedulerSelectionError());
      this.#emit(events);
      return { accepted: false, epoch, requestId: null, events };
    }
    if (!this.#isCurrentEpoch(epoch)) {
      return this.#staleStartResult(epoch, null, events, 'scheduler result arrived after cleanup');
    }
    if (selection === null) {
      events.push(createRuntimeWarning(null, 'PLAYER_PLAYBACK_NO_SELECTION', 'No scheduled playback is active.', {
        operation: 'schedule.resolve',
        status: 'ignored',
        reason: 'no scheduled playback',
      }));
      this.#emit(events);
      return { accepted: false, epoch, requestId: null, events };
    }
    if (!isSafeScheduleSelection(selection)) {
      events.push(createRuntimeBoundaryError(undefined, 'schedule selection was not renderer-safe'));
      this.#emit(events);
      return { accepted: false, epoch, requestId: null, events };
    }
    return this.#startSelection(epoch, events, selection);
  }
  async #startSelection(
    epoch: number,
    events: PlayerEvent[],
    selection: PlexPlaybackScheduleSelection,
  ): Promise<PlexPlaybackRuntimeStartResult> {
    this.#activeSelection = { ...selection };
    this.#recovery.activate(selection);
    let candidate: PlexPlaybackRuntimeCandidate;
    try {
      candidate = await this.#channel.resolvePlaybackCandidate(selection);
    } catch (error) {
      if (!this.#isCurrentEpoch(epoch)) {
        return this.#staleStartResult(epoch, null, events, 'candidate failure arrived after cleanup');
      }
      events.push(this.#candidateResolutionError(error));
      this.#emit(events);
      return { accepted: false, epoch, requestId: null, events };
    }
    const publicCandidate = { ...candidate };
    delete (publicCandidate as { privatePlayback?: unknown }).privatePlayback;
    if (!isSafeRuntimeCandidate(publicCandidate)) {
      const rejectedSession = readReleasablePmsSession(candidate);
      if (rejectedSession !== null) {
        events.push(...(await this.#cleanupCoordinator.releaseUnsafeCandidateSession(rejectedSession)));
      }
      if (!this.#isCurrentEpoch(epoch)) {
        return this.#staleStartResult(epoch, null, events, 'candidate rejection settled after cleanup');
      }
      events.push(createRuntimeBoundaryError(undefined, 'channel playback candidate was not renderer-safe'));
      this.#emit(events);
      return { accepted: false, epoch, requestId: null, events };
    }
    const requestId = candidate.requestId ?? this.#createRequestId('plex-playback');
    if (!isPmsSessionForRequest(candidate.pmsSession ?? null, requestId)) {
      events.push(...(await this.#cleanupCoordinator.releaseRejectedSession(candidate.pmsSession ?? null, requestId)));
      if (!this.#isCurrentEpoch(epoch)) {
        return this.#staleStartResult(epoch, requestId, events, 'candidate rejection settled after cleanup');
      }
      events.push(createRuntimeBoundaryError(requestId, 'pms session request id did not match playback request'));
      this.#emit(events);
      return { accepted: false, epoch, requestId, events };
    }
    if (candidate.privatePlayback) {
      const validation = validatePrivilegedPlaybackDescriptor(candidate.privatePlayback, requestId);
      if (!validation.ok) {
        events.push(...(await this.#cleanupCoordinator.releaseRejectedSession(candidate.pmsSession ?? null, requestId)));
        if (!this.#isCurrentEpoch(epoch)) {
          return this.#staleStartResult(epoch, requestId, events, 'candidate rejection settled after cleanup');
        }
        events.push({
          event: 'error',
          requestId,
          error: validation.error,
        });
        this.#emit(events);
        return { accepted: false, epoch, requestId, events };
      }
    }
    const active: PlexPlaybackActiveSession = {
      epoch,
      requestId,
      media: candidate.load.media,
      pmsSession: candidate.pmsSession ?? null,
    };
    if (!this.#isCurrentEpoch(epoch)) {
      events.push(...(await this.#cleanupCoordinator.releaseOrphanSession(active, 'stale')));
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
      const context = candidate.privatePlayback ? { privatePlayback: candidate.privatePlayback } : null;
      playerResult = await this.#player.dispatch(command, context);
    } catch {
      playerResult = { ok: false };
    }
    if (!this.#isCurrentEpoch(epoch) || this.#active?.requestId !== requestId) {
      events.push(...this.#staleCustody.quarantineEvents({
        currentEpoch: this.#epoch,
        eventEpoch: epoch,
        events: playerResult.events ?? [],
        reason: 'player load settled late',
      }));
      return this.#staleStartResult(epoch, requestId, events, 'player load settled after cleanup');
    }
    for (const event of playerResult.events ?? []) {
      const accepted = this.handlePlayerEvent(epoch, event);
      this.#observeAcceptedEvents(accepted);
      events.push(...accepted);
    }
    if (!playerResult.ok) {
      events.push(createRuntimeLoadFailedError(requestId, active.media));
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
    const releaseCleanupHold = this.#acquireCleanupHold();
    try {
      this.#recovery.cancel();
      this.#activeSelection = null;
      const events = await this.#cleanupActive(input.reason, { invalidateEpoch: true });
      this.#emit(events);
      return events;
    } finally {
      releaseCleanupHold();
    }
  }
  async stop(): Promise<readonly PlayerEvent[]> {
    const releaseCleanupHold = this.#acquireCleanupHold();
    try {
      this.#recovery.cancel();
      this.#activeSelection = null;
      this.#nextEpoch();
      const active = this.#active;
      this.#active = null;
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
      const events = await this.#cleanupCoordinator.cleanupActive(active, 'stop');
      this.#emit(events);
      return events;
    } finally {
      releaseCleanupHold();
    }
  }
  async teardown(): Promise<readonly PlayerEvent[]> {
    return this.cleanup({ reason: 'teardown' });
  }
  handlePlayerEvent(epoch: number, event: PlayerEvent): readonly PlayerEvent[] {
    if (hasPlayerForbiddenPrivilegedField(event)) {
      return [createRuntimeBoundaryError(readEventRequestId(event) ?? undefined, 'player event contained privileged fields')];
    }
    const eventRequestId = readEventRequestId(event);
    if (
      epoch !== this.#epoch ||
      this.#active === null ||
      (eventRequestId !== null && eventRequestId !== this.#active.requestId)
    ) {
      return [
        createRuntimeWarning(eventRequestId, 'PLAYER_STALE_PLAYBACK_EVENT', 'A stale playback event was ignored.', {
          operation: event.event,
          status: 'ignored',
          reason: 'event epoch did not match current playback state',
        }),
      ];
    }
    return [event];
  }
  ingestPlayerEvents(events: readonly PlayerEvent[]): readonly PlayerEvent[] {
    const accepted: PlayerEvent[] = [];
    const epoch = this.#epoch;
    for (const event of events) {
      accepted.push(...this.handlePlayerEvent(epoch, event));
    }
    this.#observeAcceptedEvents(accepted);
    this.#emit(accepted);
    return accepted;
  }
  async handleHelperCrash(): Promise<readonly PlayerEvent[]> {
    recordRuntimeHelperCrashDiagnostic(this.#diagnosticEventStore, this.#active?.requestId);
    return this.cleanup({ reason: 'helper-crash' });
  }
  #nextEpoch(): number {
    this.#epoch = this.#epoch >= Number.MAX_SAFE_INTEGER ? 1 : this.#epoch + 1;
    return this.#epoch;
  }
  #isCurrentEpoch(epoch: number): boolean {
    return epoch === this.#epoch;
  }
  async #retrySelection(
    identity: PlexPlaybackRecoveryIdentity,
  ): Promise<PlexPlaybackRetryResult> {
    return this.#restartSelectionForRetry(identity, 'recovery');
  }
  async #restartSelectionForRetry(
    identity: PlexPlaybackRecoveryIdentity,
    owner: PlexPlaybackRetryOwner,
  ): Promise<PlexPlaybackRetryResult> {
    if (
      this.#cleanupHoldCount > 0 ||
      !isSafeScheduleSelection(identity) ||
      identity.endsAtMs === undefined ||
      identity.endsAtMs === null ||
      (
        owner === 'recovery' &&
        !isSamePlexPlaybackScheduleSelection(this.#activeSelection, identity)
      )
    ) {
      return 'stale';
    }
    const initialEpoch = this.#epoch;
    let selection: PlexPlaybackScheduleSelection | null;
    try {
      selection = await this.#scheduler.getCurrentPlayback({
        nowMs: this.#clock.now(),
        reason: 'schedule-tick',
      });
    } catch {
      return (
        owner === 'recovery' &&
        isSamePlexPlaybackScheduleSelection(this.#activeSelection, identity)
      )
        ? 'failed'
        : 'stale';
    }
    if (
      this.#cleanupHoldCount > 0 ||
      !isSafeScheduleSelection(selection) ||
      !isSamePlexPlaybackScheduleSelection(selection, identity) ||
      (
        owner === 'manual'
          ? !this.#isCurrentEpoch(initialEpoch)
          : !isSamePlexPlaybackScheduleSelection(this.#activeSelection, identity)
      )
    ) {
      return 'stale';
    }
    if (owner === 'manual') {
      this.#recovery.cancel();
    }
    const epoch = this.#nextEpoch();
    const events: PlayerEvent[] = [
      ...(await this.#cleanupActive('switch', { invalidateEpoch: false })),
    ];
    if (
      !this.#isCurrentEpoch(epoch) ||
      (
        owner === 'recovery' &&
        !isSamePlexPlaybackScheduleSelection(this.#activeSelection, identity)
      )
    ) {
      return 'stale';
    }
    const result = await this.#startSelection(epoch, events, selection);
    if (!isSamePlexPlaybackScheduleSelection(this.#activeSelection, identity)) {
      return 'stale';
    }
    if (!result.accepted) {
      return 'failed';
    }
    return this.#isCurrentEpoch(epoch) ? 'started' : 'stale';
  }
  #acquireCleanupHold(): () => void {
    this.#cleanupHoldCount += 1;
    let released = false;
    return () => {
      if (released) {
        return;
      }
      released = true;
      this.#cleanupHoldCount -= 1;
    };
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
    return this.#cleanupCoordinator.cleanupActive(active, reason);
  }
  #staleStartResult(
    epoch: number,
    requestId: PlayerRequestId | null,
    events: readonly PlayerEvent[],
    reason: string,
  ): PlexPlaybackRuntimeStartResult {
    const result = this.#staleCustody.createStaleStartResult({
      epoch,
      requestId,
      events,
      reason,
    });
    this.#emit(result.events);
    return result;
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
    return createRuntimeSourceError(
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
  #observeAcceptedEvents(events: readonly PlayerEvent[]): void {
    const identity = this.#activeSelection;
    const requestId = this.#active?.requestId;
    if (identity === null || requestId === undefined) {
      return;
    }
    for (const event of events) {
      if (readEventRequestId(event) !== requestId) {
        continue;
      }
      this.#recovery.observeAcceptedEvent(identity, event);
      if (event.event === 'ended') {
        this.#recovery.cancel();
        this.#activeSelection = null;
      }
    }
  }
  #emit(events: readonly PlayerEvent[]): void {
    if (events.length > 0) {
      this.#onEvents?.(events);
    }
  }
}
function createDefaultRecoveryTimer(): PlexPlaybackRecoveryTimerPort {
  return {
    set(delayMs, callback) {
      return setTimeout(callback, delayMs);
    },
    clear(handle) {
      clearTimeout(handle as ReturnType<typeof setTimeout>);
    },
  };
}
function safeScheduleIdPart(value: string): string {
  const normalized = value.trim().replace(/[^a-zA-Z0-9._-]+/gu, '-');
  return normalized === '' ? 'unknown' : normalized;
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
    hasOnlyKeys(value, ['media', 'policy', 'seekSupport'], ['capabilityProfileId']) &&
    isSafeMediaSummary(value.media) &&
    isSafeLoadPolicy(value.policy) &&
    (value.capabilityProfileId === undefined || isNonEmptyString(value.capabilityProfileId)) &&
    isPlayerCapabilitySupport(value.seekSupport)
  );
}
function isPlayerCapabilitySupport(value: unknown): value is PlayerLoadCommandPayload['seekSupport'] {
  return value === 'supported' || value === 'unsupported' || value === 'unknown' || value === 'unproven';
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
