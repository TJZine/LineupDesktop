import { PlexStreamResolver } from './streamResolver.js';
import type { DesktopPlexRuntime } from './desktopPlexRuntime.js';
import type {
  PlexStreamResolverSelectedConnectionPort,
  PlexStreamResolverActiveCredentialPort,
  PlexStreamResolverAuthHeader,
} from './streamResolver.js';
import { PlaybackMediaDetailPort } from './playbackMediaDetailPort.js';
import { PmsPlaybackSessionPort } from './pmsPlaybackSessionPort.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';

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
  const selectedConnection: PlexStreamResolverSelectedConnectionPort = {
    getSelectedConnection: async () => runtime.getSelectedConnectionForMain(),
  };
  const activeCredential = new PlaybackActiveCredentialPort(runtime);
  const mediaDetail = new PlaybackMediaDetailPort(runtime, {
    diagnosticEventStore: options.diagnosticEventStore,
  });

  const resolver = new PlexStreamResolver({
    selectedConnection,
    activeCredential,
    mediaDetail,
    pmsSession: pmsSessionPort,
    subtitleDiagnostics: options.diagnosticEventStore,
  });

  return {
    resolver,
    pmsSessionPort,
  };
}
