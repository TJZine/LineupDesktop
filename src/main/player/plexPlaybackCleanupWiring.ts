import type {
  PlexIpcResult,
  PlexSelectServerValue,
  PlexSwitchHomeUserValue,
} from '../../contracts/plex.js';
import type { DesktopPlexRuntime } from '../plex/desktopPlexRuntime.js';
import type { PlexPlaybackRuntime } from './plexPlaybackRuntime.js';

export type PlaybackCleanupPlexRuntime = Pick<DesktopPlexRuntime, 'switchHomeUser' | 'selectServer'>;
export type PlaybackCleanupRuntime = Pick<PlexPlaybackRuntime, 'cleanup'>;

export interface PlaybackCleanupWiringOptions {
  plexRuntime: PlaybackCleanupPlexRuntime;
  getPlaybackRuntime: () => PlaybackCleanupRuntime | null;
  reportDiagnostic: (message: string, error: unknown) => void;
}

export function wirePlexPlaybackCleanup(options: PlaybackCleanupWiringOptions): void {
  const { plexRuntime, getPlaybackRuntime, reportDiagnostic } = options;
  const originalSwitchHomeUser = plexRuntime.switchHomeUser.bind(plexRuntime);
  plexRuntime.switchHomeUser = async (requestId, input): Promise<PlexIpcResult<PlexSwitchHomeUserValue>> => {
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
  plexRuntime.selectServer = async (requestId, serverId): Promise<PlexIpcResult<PlexSelectServerValue>> => {
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
