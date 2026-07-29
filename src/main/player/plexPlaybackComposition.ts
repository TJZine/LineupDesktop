import type { PlayerCommand, PlayerEvent, PlayerRequestId } from '../../contracts/player.js';
import type { PlayerRendererIntentEnvelope } from '../../contracts/ipc.js';
import type { IChannelScheduler } from '../../domain/scheduler/index.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import type { PlexStreamResolverInput, PlexStreamResolverResult } from '../plex/streamResolver.js';
import { PlexPlaybackBridge } from './plexPlaybackBridge.js';
import { PlexPlaybackRuntime, type PlexPlaybackRuntimeClockPort, type PlexPlaybackRuntimePlayerPort, type PlexPlaybackRuntimePmsPort } from './plexPlaybackRuntime.js';
import type { DesktopStreamCapabilityProfile } from './streamPolicy/types.js';
import type { PrivilegedPlaybackDispatchContext } from './privilegedPlaybackDispatchContext.js';
import type { PlexPlaybackRecoveryTimerPort } from './plexPlaybackRecoveryOwner.js';

type DesktopPlayerAdapterRuntimePort = {
  dispatchRendererIntent(envelope: PlayerRendererIntentEnvelope): Promise<{
    accepted: boolean;
    events: readonly PlayerEvent[];
  }>;
  dispatchRuntimeCommand(
    command: PlayerCommand,
    context?: PrivilegedPlaybackDispatchContext | null,
  ): Promise<{
    accepted: boolean;
    events: readonly PlayerEvent[];
  }>;
  cleanup(requestId?: PlayerRequestId | null): Promise<{
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
  recoveryTimer?: PlexPlaybackRecoveryTimerPort;
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
      recoveryTimer: options.recoveryTimer,
      diagnosticEventStore: options.diagnosticEventStore,
    }),
  };
}

export function createDesktopPlayerAdapterRuntimePort(
  adapter: DesktopPlayerAdapterRuntimePort,
): PlexPlaybackRuntimePlayerPort {
  return {
    async dispatch(command, context) {
      const result = await adapter.dispatchRuntimeCommand(command, context);
      const settlements = result.events.filter(
        (event): event is Extract<PlayerEvent, { event: 'command.settled' }> => (
          event.event === 'command.settled'
        ),
      );
      const settlement = settlements[0];
      return {
        ok:
          result.accepted &&
          settlements.length === 1 &&
          settlement?.requestId === command.requestId &&
          settlement.command === command.command &&
          settlement.ok,
        events: result.events,
      };
    },
    async cleanup(requestId) {
      const result = await adapter.cleanup(requestId);
      if (!result.accepted) {
        throw new Error('Desktop player adapter cleanup failed.');
      }
    },
  };
}
