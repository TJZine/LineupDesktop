import type { PlayerRequestId } from '../../contracts/player.js';
import type {
  PlexStreamResolverPmsSessionPort,
  PlexStreamResolverPmsSessionStartInput,
  PlexStreamResolverPmsSessionLease,
} from './streamResolver.js';
import type {
  PlexPlaybackRuntimePmsPort,
  PlexPlaybackRuntimeCleanupReason,
  PlexPlaybackPmsSessionLease,
} from '../player/plexPlaybackRuntime.js';
import type { DesktopPlexRuntime } from './desktopPlexRuntime.js';
import type { PlexConnection } from './discovery/types.js';

export class PmsPlaybackSessionPort
  implements PlexStreamResolverPmsSessionPort, PlexPlaybackRuntimePmsPort
{
  readonly #runtime: DesktopPlexRuntime;
  readonly #activeSessions = new Map<
    string,
    {
      connection: PlexConnection;
      decisionKind: string;
    }
  >();

  constructor(runtime: DesktopPlexRuntime) {
    this.#runtime = runtime;
  }

  async startSession(
    input: PlexStreamResolverPmsSessionStartInput,
  ): Promise<PlexStreamResolverPmsSessionLease | null> {
    const connection = this.#runtime.getSelectedConnectionForMain();
    if (!connection) {
      return null;
    }
    try {
      await this.#runtime.withActivePlexToken('getMetadata', async () => undefined);
    } catch {
      return null;
    }

    this.#activeSessions.set(input.requestId, {
      connection,
      decisionKind: input.decisionKind,
    });

    return {
      id: input.requestId,
      requestId: input.requestId,
    };
  }

  async releaseSession(
    session: PlexPlaybackPmsSessionLease,
    _input: {
      reason: PlexPlaybackRuntimeCleanupReason | 'stale';
      requestId: PlayerRequestId;
    },
  ): Promise<void> {
    const sessionDetails = this.#activeSessions.get(session.id);
    if (!sessionDetails) {
      return;
    }

    this.#activeSessions.delete(session.id);

    const { connection, decisionKind } = sessionDetails;
    if (decisionKind === 'transcode' || decisionKind === 'direct-stream') {
      await this.#runtime.withActivePlexToken('getMetadata', async (token) => {
        await this.#runtime.getLibraryTransport().stopTranscodeSession({
          connection,
          token,
          sessionId: session.id,
        });
      }).catch(() => {
        // Safe no-op on failure
      });
    }
  }
}
