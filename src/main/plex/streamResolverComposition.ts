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
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';

export class PlaybackSelectedConnectionPort implements PlexStreamResolverSelectedConnectionPort {
  readonly #runtime: DesktopPlexRuntime;

  constructor(runtime: DesktopPlexRuntime) {
    this.#runtime = runtime;
  }

  async getSelectedConnection(): Promise<PlexConnection | null> {
    return this.#runtime.getSelectedConnectionForMain();
  }
}

export class PlaybackActiveCredentialPort implements PlexStreamResolverActiveCredentialPort {
  readonly #runtime: DesktopPlexRuntime;

  constructor(runtime: DesktopPlexRuntime) {
    this.#runtime = runtime;
  }

  async getActiveAuthHeader(): Promise<PlexStreamResolverAuthHeader | null> {
    try {
      return await this.#runtime.withActivePlexToken('getMetadata', async (token) => ({
        name: 'X-Plex-Token',
        value: token,
      }));
    } catch {
      return null;
    }
  }
}

export interface LiveStreamResolverComposition {
  resolver: PlexStreamResolver;
  pmsSessionPort: PmsPlaybackSessionPort;
}

export function createLivePlexStreamResolverComposition(
  runtime: DesktopPlexRuntime,
  options: { diagnosticEventStore?: DiagnosticEventStore } = {},
): LiveStreamResolverComposition {
  const pmsSessionPort = new PmsPlaybackSessionPort(runtime);
  const selectedConnection = new PlaybackSelectedConnectionPort(runtime);
  const activeCredential = new PlaybackActiveCredentialPort(runtime);
  const mediaDetail = new PlaybackMediaDetailPort(runtime, {
    diagnosticEventStore: options.diagnosticEventStore,
  });

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
