import type { PlayerCommand, PlayerEvent, PlayerRequestId } from '../../contracts/player.js';
import type { PlayerRendererIntentEnvelope } from '../../contracts/ipc.js';
import type { IChannelScheduler } from '../../domain/scheduler/index.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import type { PlexStreamResolverInput, PlexStreamResolverResult } from '../plex/streamResolver.js';
import { PlexPlaybackBridge } from './plexPlaybackBridge.js';
import { PlexPlaybackRuntime, type PlexPlaybackRuntimeClockPort, type PlexPlaybackRuntimePlayerPort, type PlexPlaybackRuntimePmsPort } from './plexPlaybackRuntime.js';
import type { DesktopStreamCapabilityProfile } from './streamPolicy/types.js';

type DesktopPlayerAdapterRuntimePort = {
  dispatchRendererIntent(envelope: PlayerRendererIntentEnvelope): Promise<{
    accepted: boolean;
    events: readonly PlayerEvent[];
  }>;
  cleanup(): Promise<{
    accepted: boolean;
    events: readonly PlayerEvent[];
  }>;
};

export interface PlexPlaybackCompositionResolverPort {
  resolve(input: PlexStreamResolverInput): Promise<PlexStreamResolverResult>;
}

export interface CreatePlexPlaybackRuntimeCompositionOptions {
  scheduler: Pick<IChannelScheduler, 'getCurrentProgram' | 'getState'>;
  resolver: PlexPlaybackCompositionResolverPort;
  player: PlexPlaybackRuntimePlayerPort;
  pms: PlexPlaybackRuntimePmsPort;
  capabilityProfile:
    | DesktopStreamCapabilityProfile
    | (() => DesktopStreamCapabilityProfile | Promise<DesktopStreamCapabilityProfile>);
  createRequestId?: (prefix: string) => PlayerRequestId;
  clock?: PlexPlaybackRuntimeClockPort;
  autoplay?: boolean;
  onEvents?: (events: readonly PlayerEvent[]) => void;
  diagnosticEventStore?: DiagnosticEventStore;
}

export interface PlexPlaybackRuntimeComposition {
  bridge: PlexPlaybackBridge;
  runtime: PlexPlaybackRuntime;
}

export function createPlexPlaybackRuntimeComposition(
  options: CreatePlexPlaybackRuntimeCompositionOptions,
): PlexPlaybackRuntimeComposition {
  const bridge = new PlexPlaybackBridge({
    scheduler: options.scheduler,
    resolver: options.resolver,
    capabilityProfile: options.capabilityProfile,
    createRequestId: options.createRequestId,
    autoplay: options.autoplay,
  });

  return {
    bridge,
    runtime: new PlexPlaybackRuntime({
      scheduler: bridge,
      channel: bridge,
      player: options.player,
      pms: options.pms,
      createRequestId: options.createRequestId,
      clock: options.clock,
      onEvents: options.onEvents,
      diagnosticEventStore: options.diagnosticEventStore,
    }),
  };
}

export function createDesktopPlayerAdapterRuntimePort(
  adapter: DesktopPlayerAdapterRuntimePort,
): PlexPlaybackRuntimePlayerPort {
  return {
    async dispatch(command) {
      const result = await adapter.dispatchRendererIntent(toRendererIntentEnvelope(command));
      return { ok: result.accepted, events: result.events };
    },
    async cleanup(_requestId) {
      const result = await adapter.cleanup();
      if (!result.accepted) {
        throw new Error('Desktop player adapter cleanup failed.');
      }
    },
  };
}

function toRendererIntentEnvelope(command: PlayerCommand): PlayerRendererIntentEnvelope {
  switch (command.command) {
    case 'load':
      return {
        intent: 'player.load',
        requestId: command.requestId,
        payload: command.payload,
      };
    case 'play':
      return emptyPayloadIntent('player.play', command.requestId);
    case 'pause':
      return emptyPayloadIntent('player.pause', command.requestId);
    case 'stop':
      return emptyPayloadIntent('player.stop', command.requestId);
    case 'seek.absolute':
      return {
        intent: 'player.seekAbsolute',
        requestId: command.requestId,
        payload: command.payload,
      };
    case 'seek.relative':
      return {
        intent: 'player.seekRelative',
        requestId: command.requestId,
        payload: command.payload,
      };
    case 'volume.set':
      return {
        intent: 'player.setVolume',
        requestId: command.requestId,
        payload: command.payload,
      };
    case 'mute.set':
      return {
        intent: 'player.setMute',
        requestId: command.requestId,
        payload: command.payload,
      };
    case 'track.audio.select':
      return {
        intent: 'player.selectAudio',
        requestId: command.requestId,
        payload: command.payload,
      };
    case 'track.subtitle.select':
      return {
        intent: 'player.selectSubtitle',
        requestId: command.requestId,
        payload: command.payload,
      };
  }
}

function emptyPayloadIntent(
  intent: PlayerRendererIntentEnvelope['intent'],
  requestId: PlayerRequestId,
): PlayerRendererIntentEnvelope {
  return { intent, requestId, payload: {} };
}
