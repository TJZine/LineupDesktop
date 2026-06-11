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
      token: string;
    }
  >();

  constructor(runtime: DesktopPlexRuntime) {
    this.#runtime = runtime;
  }

  async startSession(
    input: PlexStreamResolverPmsSessionStartInput,
  ): Promise<PlexStreamResolverPmsSessionLease | null> {
    const resolvedConnection = input.connection;
    if (!isValidPlexConnection(resolvedConnection)) {
      return null;
    }
    let token: string;
    try {
      token = await this.#runtime.withActivePlexToken('startPlayback', async (activeToken) => activeToken);
    } catch {
      return null;
    }

    if (this.#activeSessions.has(input.requestId)) {
      // Session request IDs are release keys; reusing one would orphan the previous PMS session.
      throw new Error(`Playback session already active for request ID: ${input.requestId}`);
    }

    this.#activeSessions.set(input.requestId, {
      connection: resolvedConnection,
      decisionKind: input.decisionKind,
      token,
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

    const { connection, decisionKind, token } = sessionDetails;
    if (decisionKind === 'transcode' || decisionKind === 'direct-stream') {
      await this.#runtime.getLibraryTransport().stopTranscodeSession({
        connection,
        token,
        sessionId: session.id,
      }).catch(() => {
        // Safe no-op on failure
      });
    }
  }
}

function isValidPlexConnection(connection: PlexConnection): boolean {
  return (
    (connection.protocol === 'http' || connection.protocol === 'https') &&
    connection.address.trim().length > 0 &&
    Number.isInteger(connection.port) &&
    connection.port > 0 &&
    connection.port <= 65_535 &&
    connection.uri.trim().length > 0
  );
}
