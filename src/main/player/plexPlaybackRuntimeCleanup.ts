import type { PlayerEvent, PlayerMediaSummary, PlayerRequestId } from '../../contracts/player.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import type {
  PlexPlaybackPmsSessionLease,
  PlexPlaybackRuntimeCleanupReason,
  PlexPlaybackRuntimePlayerPort,
  PlexPlaybackRuntimePmsPort,
} from './plexPlaybackRuntime.js';
import {
  createRuntimeCleanupFailure,
  createRuntimeUnscopedCleanupFailure,
  recordRuntimeCleanupDiagnostic,
} from './plexPlaybackRuntimeDiagnostics.js';

export interface PlexPlaybackActiveSession {
  epoch: number;
  requestId: PlayerRequestId;
  media: PlayerMediaSummary;
  pmsSession: PlexPlaybackPmsSessionLease | null;
}

export class PlexPlaybackRuntimeCleanupCoordinator {
  readonly #player: PlexPlaybackRuntimePlayerPort;
  readonly #pms: PlexPlaybackRuntimePmsPort;
  readonly #diagnosticEventStore?: DiagnosticEventStore;

  constructor(options: {
    player: PlexPlaybackRuntimePlayerPort;
    pms: PlexPlaybackRuntimePmsPort;
    diagnosticEventStore?: DiagnosticEventStore;
  }) {
    this.#player = options.player;
    this.#pms = options.pms;
    this.#diagnosticEventStore = options.diagnosticEventStore;
  }

  async cleanupActive(
    active: PlexPlaybackActiveSession | null,
    reason: PlexPlaybackRuntimeCleanupReason,
  ): Promise<readonly PlayerEvent[]> {
    if (active === null) {
      return [];
    }

    const events: PlayerEvent[] = [];
    if (active.pmsSession !== null) {
      try {
        await this.#pms.releaseSession(active.pmsSession, {
          reason,
          requestId: active.requestId,
        });
      } catch {
        recordRuntimeCleanupDiagnostic(
          this.#diagnosticEventStore,
          active.requestId,
          reason,
          'PLAYER_PLAYBACK_PMS_CLEANUP_FAILED',
        );
        events.push(createRuntimeCleanupFailure(active.requestId, reason, 'pms session release failed'));
      }
    }

    try {
      await this.#player.cleanup(active.requestId);
    } catch {
      recordRuntimeCleanupDiagnostic(
        this.#diagnosticEventStore,
        active.requestId,
        reason,
        'PLAYER_PLAYBACK_PLAYER_CLEANUP_FAILED',
      );
      events.push(createRuntimeCleanupFailure(active.requestId, reason, 'player cleanup failed'));
    }

    return events;
  }

  async releaseOrphanSession(
    active: PlexPlaybackActiveSession,
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
      return [createRuntimeCleanupFailure(active.requestId, 'stale', 'stale pms session release failed')];
    }
  }

  async releaseRejectedSession(
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
      return [createRuntimeCleanupFailure(requestId, 'stale', 'rejected pms session release failed')];
    }
  }

  async releaseUnsafeCandidateSession(
    session: PlexPlaybackPmsSessionLease,
  ): Promise<readonly PlayerEvent[]> {
    try {
      await this.#pms.releaseSession(session, {
        reason: 'stale',
        requestId: 'unsafe-candidate',
      });
      return [];
    } catch {
      return [createRuntimeUnscopedCleanupFailure('rejected unsafe pms session release failed')];
    }
  }
}
