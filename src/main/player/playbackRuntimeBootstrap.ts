import type { IChannelScheduler } from '../../domain/scheduler/index.js';
import type { ShellMode } from '../../contracts/shell.js';
import type { PlayerEvent } from '../../contracts/player.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import {
  createPlexPlaybackRuntimeComposition,
  createDesktopPlayerAdapterRuntimePort,
  type PlexPlaybackCompositionResolverPort,
} from './plexPlaybackComposition.js';
import type { PlexPlaybackRuntime, PlexPlaybackRuntimePmsPort } from './plexPlaybackRuntime.js';
import type { DesktopPlayerAdapter } from './desktopPlayerAdapter.js';
import type { DesktopStreamCapabilityProfile } from './streamPolicy/types.js';
import type { PlexStreamResolverInput, PlexStreamResolverResult } from '../plex/streamResolver.js';
import type { DesktopPlexRuntime } from '../plex/desktopPlexRuntime.js';
import { createLivePlexStreamResolverComposition } from '../plex/streamResolverComposition.js';

export interface PlaybackRuntimeBootstrapOptions {
  shellMode: ShellMode;
  scheduler: Pick<IChannelScheduler, 'getCurrentProgram' | 'getState'>;
  adapter: DesktopPlayerAdapter | null;
  createRequestId: (prefix: string) => string;
  diagnosticEventStore?: DiagnosticEventStore;
  plexRuntime?: DesktopPlexRuntime;
}

export interface PlaybackRuntimeBootstrapResult {
  runtime: PlexPlaybackRuntime;
}

export function bootstrapPlaybackRuntime(
  options: PlaybackRuntimeBootstrapOptions,
): PlaybackRuntimeBootstrapResult {
  const { shellMode, scheduler, adapter, createRequestId, diagnosticEventStore, plexRuntime } = options;

  if (shellMode === 'development' || shellMode === 'smoke') {
    // Development / Smoke: Use fake resolver and capability profile
    const fakePlaybackResolver = createFakeResolver();
    const fakePmsPort = {
      async releaseSession() {
        // No-op
      },
    };
    const capabilityProfile = getDevelopmentCapabilityProfile();

    const playerPort = adapter
      ? createDesktopPlayerAdapterRuntimePort(adapter)
      : {
          dispatch: async () => ({ ok: true, events: [] }),
          cleanup: async () => {},
        };

    const composition = createPlexPlaybackRuntimeComposition({
      scheduler,
      resolver: fakePlaybackResolver,
      player: playerPort,
      pms: fakePmsPort,
      capabilityProfile,
      createRequestId,
      diagnosticEventStore,
    });

    return {
      runtime: composition.runtime,
    };
  }

  // Production:
  let resolver: PlexPlaybackCompositionResolverPort;
  let pmsPort: PlexPlaybackRuntimePmsPort;

  if (plexRuntime) {
    const liveResolverComposition = createLivePlexStreamResolverComposition(plexRuntime);
    resolver = liveResolverComposition.resolver;
    pmsPort = liveResolverComposition.pmsSessionPort;
  } else {
    resolver = {
      async resolve(input: PlexStreamResolverInput): Promise<PlexStreamResolverResult> {
        return {
          ok: false,
          error: {
            code: 'PLAYER_UNSUPPORTED_CAPABILITY',
            category: 'unsupported-capability',
            message: 'Desktop player playback is not available in production without Plex runtime.',
            retryable: false,
            recoverable: false,
            requestId: input.requestId,
          },
          diagnostics: [
            {
              component: 'playback-bootstrap',
              operation: 'resolve',
              status: 'unsupported',
              reason: 'Plex runtime is not registered',
            },
          ],
        };
      },
    };
    pmsPort = {
      async releaseSession() {
        // No-op
      },
    };
  }

  const capabilityProfile = getDevelopmentCapabilityProfile();

  const playerPort = adapter
    ? createDesktopPlayerAdapterRuntimePort(adapter)
    : {
        dispatch: async () => {
          return {
            ok: false as const,
            events: [
              {
                event: 'error',
                requestId: null,
                error: {
                  code: 'PLAYER_UNSUPPORTED_CAPABILITY',
                  category: 'unsupported-capability',
                  message: 'Desktop player playback is not available in this configuration.',
                  recoverable: false,
                  retryable: false,
                  diagnostic: {
                    component: 'playback-bootstrap',
                    operation: 'dispatch',
                    status: 'unsupported',
                    reason: 'production native helper unavailable',
                  },
                },
              },
            ] as readonly PlayerEvent[],
          };
        },
        cleanup: async () => {},
      };

  const composition = createPlexPlaybackRuntimeComposition({
    scheduler,
    resolver,
    player: playerPort,
    pms: pmsPort,
    capabilityProfile,
    createRequestId,
    diagnosticEventStore,
  });

  return {
    runtime: composition.runtime,
  };
}

function createFakeResolver() {
  return {
    async resolve(input: PlexStreamResolverInput): Promise<PlexStreamResolverResult> {
      const fakeMediaId = `plex-media-${input.mediaId}`;
      const fakeMediaTitle = `Live Program ${input.mediaId}`;
      const fakeMediaDurationMs = 1_200_000;
      if (input.mediaId.length === 0) {
        return {
          ok: false,
          error: {
            code: 'resource-missing',
            category: 'source',
            message: 'Missing media id',
            retryable: false,
            recoverable: false,
          },
          diagnostics: [],
        };
      }
      const payload = {
        media: {
          id: fakeMediaId,
          title: fakeMediaTitle,
          durationMs: fakeMediaDurationMs,
          container: 'mp4',
        },
        policy: {
          autoplay: input.autoplay ?? true,
          startPositionMs: input.startPositionMs ?? 0,
          preferredAudioTrackId: null,
          preferredSubtitleTrackId: null,
        },
        capabilityProfileId: input.capabilityProfile?.id || 'desktop-default-profile',
      };
      return {
        ok: true,
        load: payload,
        privatePlayback: {
          requestId: input.requestId,
          decisionKind: 'direct-play',
          playbackUrl: 'https://mock.plex.invalid/file.mp4',
          credentialHeader: { name: 'X-Plex-Token', value: 'mock-token' },
          selectedConnection: {
            protocol: 'https',
            address: 'mock.plex.invalid',
            port: 443,
            local: true,
            relay: false,
          },
          media: { id: payload.media.id, title: payload.media.title },
          setup: {
            playbackMode: 'direct-play',
            mediaPath: '/library/metadata/mock',
            variantId: 'mock-variant',
            partPath: '/library/parts/mock/file.mp4',
            selectedTrackIds: { video: null, audio: null, subtitle: null },
            selectedPrivateTrackIds: { video: null, audio: null, subtitle: null },
          },
        },
        decision: {
          kind: 'direct-play',
          candidateId: 'mock-candidate',
          selectedTrackIds: { video: null, audio: null, subtitle: null },
          summary: {
            media: {
              id: fakeMediaId,
              title: fakeMediaTitle,
            },
            container: 'mp4',
            videoCodec: 'h264',
            audioCodec: 'aac',
            audioLanguage: null,
            subtitleDelivery: null,
            subtitleLanguage: null,
            dynamicRange: 'sdr',
            action: 'direct-play',
          },
          reasonCodes: ['direct-play-supported'],
          unknowns: [],
        },
        pmsSession: null,
        diagnostics: [],
      };
    },
  };
}

function getDevelopmentCapabilityProfile(): DesktopStreamCapabilityProfile {
  return {
    id: 'desktop-default-profile',
    directPlayContainers: ['mp4'],
    directPlayVideoCodecs: ['h264'],
    directPlayAudioCodecs: ['aac'],
    subtitleDeliveryModes: ['embedded', 'sidecar', 'none'],
    headerAuthSetup: 'supported',
    audioTrackSwitching: 'supported',
    subtitleTrackSwitching: 'supported',
    hdr: 'supported',
    dolbyVision: 'unsupported',
    directStream: {
      containerRemux: 'supported',
      audioTranscode: 'supported',
      subtitleConversion: 'supported',
    },
    transcode: {
      video: 'supported',
      audio: 'supported',
      subtitles: 'supported',
      hdr: 'supported',
    },
  };
}
