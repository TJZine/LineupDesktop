import type {
  PlexIpcResult,
  PlexSelectServerValue,
  PlexSwitchHomeUserValue,
} from '../../contracts/plex.js';
import type { DesktopPlexRuntime } from '../plex/desktopPlexRuntime.js';
import type { PlexPlaybackRuntime } from './plexPlaybackRuntime.js';

export type PlaybackCleanupPlexRuntime = Pick<DesktopPlexRuntime, 'switchHomeUser' | 'selectServer'>;
export type PlaybackCleanupRuntime = Pick<PlexPlaybackRuntime, 'cleanup'>;

const PLAYBACK_CLEANUP_WIRED = Symbol('lineup.plexPlaybackCleanupWired');

type WireablePlaybackCleanupPlexRuntime = PlaybackCleanupPlexRuntime & {
  [PLAYBACK_CLEANUP_WIRED]?: true;
};

export interface PlaybackCleanupWiringOptions {
  plexRuntime: PlaybackCleanupPlexRuntime;
  getPlaybackRuntime: () => PlaybackCleanupRuntime | null;
  reportDiagnostic: (message: string, error: unknown) => void;
}

export function wirePlexPlaybackCleanup(options: PlaybackCleanupWiringOptions): void {
  const { getPlaybackRuntime, reportDiagnostic } = options;
  const plexRuntime = options.plexRuntime as WireablePlaybackCleanupPlexRuntime;
  if (plexRuntime[PLAYBACK_CLEANUP_WIRED]) {
    return;
  }

  const originalSwitchHomeUser = plexRuntime.switchHomeUser.bind(plexRuntime);
  const switchHomeUserWithPlaybackCleanup = async (
    requestId: string,
    input: Parameters<PlaybackCleanupPlexRuntime['switchHomeUser']>[1],
  ): Promise<PlexIpcResult<PlexSwitchHomeUserValue>> => {
    const result = await originalSwitchHomeUser(requestId, input);
    if (result.ok) {
      await cleanupPlaybackRuntime(
        getPlaybackRuntime(),
        'profile-change',
        'Playback cleanup on profile-change failed',
        reportDiagnostic,
      );
    }
    return result;
  };

  const originalSelectServer = plexRuntime.selectServer.bind(plexRuntime);
  const selectServerWithPlaybackCleanup = async (
    requestId: string,
    serverId: Parameters<PlaybackCleanupPlexRuntime['selectServer']>[1],
  ): Promise<PlexIpcResult<PlexSelectServerValue>> => {
    const result = await originalSelectServer(requestId, serverId);
    if (result.ok) {
      await cleanupPlaybackRuntime(
        getPlaybackRuntime(),
        'server-change',
        'Playback cleanup on server-change failed',
        reportDiagnostic,
      );
    }
    return result;
  };

  Object.defineProperty(plexRuntime, PLAYBACK_CLEANUP_WIRED, {
    value: true,
    enumerable: false,
    configurable: false,
  });
  plexRuntime.switchHomeUser = switchHomeUserWithPlaybackCleanup;
  plexRuntime.selectServer = selectServerWithPlaybackCleanup;
}

async function cleanupPlaybackRuntime(
  playbackRuntime: PlaybackCleanupRuntime | null,
  reason: 'profile-change' | 'server-change',
  failureMessage: string,
  reportDiagnostic: (message: string, error: unknown) => void,
): Promise<void> {
  if (playbackRuntime === null) {
    return;
  }
  try {
    await playbackRuntime.cleanup({ reason });
  } catch (error: unknown) {
    reportDiagnostic(failureMessage, error);
  }
}
