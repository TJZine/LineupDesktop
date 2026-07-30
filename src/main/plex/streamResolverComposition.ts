import { PlexStreamResolver } from './streamResolver.js';
import type { DesktopPlexRuntime } from './desktopPlexRuntime.js';
import type {
  PlexStreamResolverSelectedConnectionPort,
  PlexStreamResolverActiveCredentialPort,
} from './streamResolver.js';
import { PlaybackMediaDetailPort } from './playbackMediaDetailPort.js';
import { PmsPlaybackSessionPort } from './pmsPlaybackSessionPort.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';

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
  const activeCredential: PlexStreamResolverActiveCredentialPort = {
    getActiveAuthHeader: async () => {
      try {
        return await runtime.withActivePlexToken('getMetadata', async (token) => ({
          name: 'X-Plex-Token',
          value: token,
        }));
      } catch {
        return null;
      }
    },
  };
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
