import {
  type PlayerCommand,
  type PlayerError,
  type PlayerEvent,
  type PlayerRequestId,
  type PlayerSnapshot,
} from '../../contracts/player.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import type {
  NativePlayerHostEvent,
  NativePlayerHostLifecycleFailure,
  NativePlayerHostPort,
} from './nativePlayerHostPort.js';
import {
  type PrivilegedPlaybackDispatchContext,
  validatePrivilegedPlaybackDescriptor,
} from './privilegedPlaybackDispatchContext.js';
import { validateHostEvent } from './hostEventProjection.js';
import {
  createPlayerError,
  duplicateRequestError,
  hostFailureToError,
  hostLifecycleFailureToError,
  sanitizePlayerError,
} from './playerAdapterErrors.js';
import { PlayerAdapterRequestCustody } from './playerAdapterRequestCustody.js';
import {
  applyTrackSnapshot,
  cloneSnapshot,
  createInitialSnapshot,
} from './playerAdapterSnapshot.js';
import { mapRendererIntentToCommand } from './rendererIntentMapping.js';

export interface DesktopPlayerAdapterDispatchResult {
  accepted: boolean;
  command: PlayerCommand | null;
  events: readonly PlayerEvent[];
  snapshot: PlayerSnapshot;
}
export interface DesktopPlayerAdapterOptions {
  onEvents?: (events: readonly PlayerEvent[]) => void;
  diagnosticEventStore?: DiagnosticEventStore;
  rejectRendererLoad?: boolean;
}

/**
 * Maps renderer intents into closed host commands, validates host event
 * semantics, quarantines stale request ids, and normalizes helper failures.
 */
export class DesktopPlayerAdapter {
  readonly #host: NativePlayerHostPort;
  readonly #onEvents?: (events: readonly PlayerEvent[]) => void;
  readonly #diagnosticEventStore?: DiagnosticEventStore;
  readonly #rejectRendererLoad: boolean;
  #snapshot: PlayerSnapshot = createInitialSnapshot();
  readonly #requestCustody = new PlayerAdapterRequestCustody();
  constructor(host: NativePlayerHostPort, options: DesktopPlayerAdapterOptions = {}) {
    this.#host = host;
    this.#onEvents = options.onEvents;
    this.#diagnosticEventStore = options.diagnosticEventStore;
    this.#rejectRendererLoad = options.rejectRendererLoad ?? false;
    host.onLifecycleFailure?.((failure) => {
      const events = this.handleHostLifecycleFailure(failure);
      if (events.length > 0) {
        this.#onEvents?.(events);
      }
    });
  }
  getSnapshot(): PlayerSnapshot {
    return cloneSnapshot(this.#snapshot);
  }
  getPendingRequestCount(): number {
    return this.#requestCustody.getPendingRequestCount();
  }
  async dispatchRendererIntent(envelope: unknown): Promise<DesktopPlayerAdapterDispatchResult> {
    const commandResult = mapRendererIntentToCommand(envelope);
    if ('error' in commandResult) {
      const events = this.#emitBoundaryError(commandResult.error);
      return this.#result(false, null, events);
    }
    const { command } = commandResult;
    if (this.#requestCustody.has(command.requestId)) {
      const events = this.#emitBoundaryError(duplicateRequestError(command.requestId));
      return this.#result(false, command, events);
    }
    if (command.command === 'load' && this.#rejectRendererLoad) {
      const error = createPlayerError({
        code: 'PLAYER_UNSUPPORTED_CAPABILITY',
        category: 'unsupported-capability',
        message: 'Renderer-originated load commands are not supported in production native mode.',
        requestId: command.requestId,
        diagnostic: {
          component: 'desktop-player-adapter',
          operation: 'load',
          status: 'rejected',
          reason: 'renderer load command blocked',
        },
      });
      const events = this.#emitBoundaryError(error);
      return this.#result(false, command, events);
    }
    this.#requestCustody.begin(command);
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
      this.#recordHelperDiagnostic(command.requestId, 'host.command', 'failed', error.code);
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
      this.#recordHelperDiagnostic(command.requestId, 'host.command', 'failed', 'PLAYER_HELPER_COMMAND_FAILED');
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
      this.#requestCustody.settle(command.requestId);
    }
  }
  async dispatchRuntimeCommand(
    command: PlayerCommand,
    context?: PrivilegedPlaybackDispatchContext | null,
  ): Promise<DesktopPlayerAdapterDispatchResult> {
    if (this.#requestCustody.has(command.requestId)) {
      const events = this.#emitBoundaryError(duplicateRequestError(command.requestId));
      return this.#result(false, command, events);
    }
    if (command.command === 'load') {
      if (!context || !context.privatePlayback) {
        const error = createPlayerError({
          code: 'PLAYER_VALIDATION_FAILED',
          category: 'validation-failure',
          message: 'Privileged playback context is missing.',
          requestId: command.requestId,
          diagnostic: {
            component: 'desktop-player-adapter',
            operation: 'load',
            status: 'rejected',
            reason: 'missing private playback descriptor',
          },
        });
        const events = this.#emitBoundaryError(error);
        return this.#result(false, command, events);
      }
      const validation = validatePrivilegedPlaybackDescriptor(context.privatePlayback, command.requestId);
      if (!validation.ok) {
        const events = this.#emitBoundaryError(validation.error);
        return this.#result(false, command, events);
      }
    }
    this.#requestCustody.begin(command);
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
      const hostResult = await this.#host.execute(command, context);
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
      this.#recordHelperDiagnostic(command.requestId, 'host.command', 'failed', error.code);
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
      this.#recordHelperDiagnostic(command.requestId, 'host.command', 'failed', 'PLAYER_HELPER_COMMAND_FAILED');
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
      this.#requestCustody.settle(command.requestId);
    }
  }
  handleHostEvent(event: unknown): readonly PlayerEvent[] {
    const validation = validateHostEvent(event);
    if ('error' in validation) {
      return this.#emitBoundaryError(validation.error);
    }
    const hostEvent = validation.event;
    const hostRequestId = hostEvent.requestId;
    if (this.#snapshot.requestId === null) {
      return this.#staleHostEventWarning(hostEvent, hostRequestId, 'no active player request');
    }
    if (hostRequestId !== null && hostRequestId !== this.#snapshot.requestId) {
      return this.#staleHostEventWarning(
        hostEvent,
        hostRequestId,
        'request id did not match current playback state',
      );
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
    this.#requestCustody.clear();
    this.#recordHelperDiagnostic(requestId ?? null, 'helper.lifecycle', 'failed', 'PLAYER_HELPER_CRASHED');
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
  handleHostLifecycleFailure(failure: NativePlayerHostLifecycleFailure): readonly PlayerEvent[] {
    const requestId = failure.requestId ?? this.#snapshot.requestId;
    this.#requestCustody.clear();
    this.#recordHelperDiagnostic(failure.requestId, 'helper.lifecycle', 'failed', failure.error.code);
    return this.#recordError(hostLifecycleFailureToError(requestId, failure.error));
  }
  async cleanup(): Promise<DesktopPlayerAdapterDispatchResult> {
    const requestId = this.#snapshot.requestId;
    try {
      await this.#host.cleanup(requestId);
      this.#requestCustody.clear();
      this.#snapshot = createInitialSnapshot();
      return this.#result(true, null, [this.#stateChanged()]);
    } catch {
      this.#diagnosticEventStore?.record({
        surface: 'desktop-player-adapter',
        category: 'cleanup',
        severity: 'error',
        status: 'failed',
        operation: 'cleanup',
        message: 'Player adapter cleanup failed.',
        requestId: requestId ?? undefined,
        result: 'failure',
        context: { code: 'PLAYER_CLEANUP_FAILED' },
      });
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
  #staleHostEventWarning(
    hostEvent: NativePlayerHostEvent,
    requestId: PlayerRequestId | null,
    reason: string,
  ): readonly PlayerEvent[] {
    return [
      {
        event: 'warning',
        requestId: this.#snapshot.requestId,
        warning: createPlayerError({
          code: 'PLAYER_STALE_HOST_EVENT',
          category: 'stale-request',
          message: 'A stale player event was ignored.',
          requestId: requestId ?? undefined,
          diagnostic: {
            component: 'desktop-player-adapter',
            operation: hostEvent.type,
            status: 'ignored',
            reason,
          },
        }),
      },
    ];
  }
  #recordHelperDiagnostic(
    requestId: PlayerRequestId | null,
    operation: string,
    status: 'failed' | 'observed',
    code: string,
  ): void {
    this.#diagnosticEventStore?.record({
      surface: 'desktop-player-adapter',
      category: 'helper-crash',
      severity: status === 'failed' ? 'error' : 'warning',
      status,
      operation,
      message: 'Player helper failure was normalized by the adapter.',
      requestId: requestId ?? undefined,
      result: status === 'failed' ? 'failure' : 'ignored',
      context: { code },
    });
  }
}
