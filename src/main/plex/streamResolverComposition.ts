import { PlexStreamResolver } from './streamResolver.js';
import type { DesktopPlexRuntime } from './desktopPlexRuntime.js';
import type { PlexConnection } from './discovery/types.js';
import type {
  PlexStreamResolverSelectedConnectionPort,
  PlexStreamResolverActiveCredentialPort,
  PlexStreamResolverAuthHeader,
} from './streamResolver.js';
import { PlaybackMediaDetailPort } from './playbackMediaDetailPort.js';
import { PmsPlaybackSessionPort } from './pmsPlaybackSessionPort.js';

export class PlaybackSelectedConnectionPort implements PlexStreamResolverSelectedConnectionPort {
  readonly #runtime: DesktopPlexRuntime;

  constructor(runtime: DesktopPlexRuntime) {
    this.#runtime = runtime;
  }

  async getSelectedConnection(): Promise<PlexConnection | null> {
    return this.#runtime.getActiveConnectionAndToken().connection;
  }
}

export class PlaybackActiveCredentialPort implements PlexStreamResolverActiveCredentialPort {
  readonly #runtime: DesktopPlexRuntime;

  constructor(runtime: DesktopPlexRuntime) {
    this.#runtime = runtime;
  }

  async getActiveAuthHeader(): Promise<PlexStreamResolverAuthHeader | null> {
    const { token } = this.#runtime.getActiveConnectionAndToken();
    if (!token) {
      return null;
    }
    return {
      name: 'X-Plex-Token',
      value: token,
    };
  }
}

export interface LiveStreamResolverComposition {
  resolver: PlexStreamResolver;
  pmsSessionPort: PmsPlaybackSessionPort;
}

export function createLivePlexStreamResolverComposition(
  runtime: DesktopPlexRuntime,
): LiveStreamResolverComposition {
  const pmsSessionPort = new PmsPlaybackSessionPort(runtime);
  const selectedConnection = new PlaybackSelectedConnectionPort(runtime);
  const activeCredential = new PlaybackActiveCredentialPort(runtime);
  const mediaDetail = new PlaybackMediaDetailPort(runtime);

  const resolver = new PlexStreamResolver({
    selectedConnection,
    activeCredential,
    mediaDetail,
    pmsSession: pmsSessionPort,
  });

  return {
    resolver,
    pmsSessionPort,
  };
}
