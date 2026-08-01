import type { PlayerRequestId } from '../../contracts/player.js';
import type { IChannelScheduler, ScheduledProgram } from '../../domain/scheduler/index.js';
import type { PlexStreamResolverInput, PlexStreamResolverResult } from '../plex/streamResolver.js';
import type { DesktopStreamCapabilityProfile } from './streamPolicy/types.js';
import type {
  DesktopPlaybackSettingsPreferences,
} from '../settings/desktopSettingsPolicy.js';
import type { DesktopSettingsCapabilityProjection } from '../../contracts/settings.js';
import type { ResolvedAudioOutput } from '../settings/settingsAudioOutputOwner.js';
import {
  PlexPlaybackRuntimeCandidateResolutionError,
  isSamePlexPlaybackScheduleSelection,
  projectPlexPlaybackScheduleSelection,
  type PlexPlaybackRuntimeCandidate,
  type PlexPlaybackRuntimeChannelPort,
  type PlexPlaybackRuntimeSchedulerPort,
  type PlexPlaybackScheduleSelection,
} from './plexPlaybackRuntime.js';

export interface PlexPlaybackBridgeResolverPort {
  resolve(input: PlexStreamResolverInput): Promise<PlexStreamResolverResult>;
}

export interface PlexPlaybackBridgeOptions {
  scheduler: Pick<IChannelScheduler, 'getCurrentProgram' | 'getState'>;
  resolver: PlexPlaybackBridgeResolverPort;
  capabilityProfile:
    | DesktopStreamCapabilityProfile
    | (() => DesktopStreamCapabilityProfile | Promise<DesktopStreamCapabilityProfile>);
  createRequestId?: (prefix: string) => PlayerRequestId;
  autoplay?: boolean;
  settingsPreferences?: () => DesktopPlaybackSettingsPreferences | Promise<DesktopPlaybackSettingsPreferences>;
  settingsCapabilities?: () => DesktopSettingsCapabilityProjection;
  resolveAudioOutput?: (
    selectedId: DesktopPlaybackSettingsPreferences['audioOutputDeviceId'],
  ) => Promise<ResolvedAudioOutput>;
}

export class PlexPlaybackBridge implements PlexPlaybackRuntimeSchedulerPort, PlexPlaybackRuntimeChannelPort {
  readonly #scheduler: Pick<IChannelScheduler, 'getCurrentProgram' | 'getState'>;
  readonly #resolver: PlexPlaybackBridgeResolverPort;
  readonly #capabilityProfile:
    | DesktopStreamCapabilityProfile
    | (() => DesktopStreamCapabilityProfile | Promise<DesktopStreamCapabilityProfile>);
  readonly #createRequestId: (prefix: string) => PlayerRequestId;
  readonly #autoplay: boolean;
  readonly #settingsPreferences?: PlexPlaybackBridgeOptions['settingsPreferences'];
  readonly #settingsCapabilities?: PlexPlaybackBridgeOptions['settingsCapabilities'];
  readonly #resolveAudioOutput?: PlexPlaybackBridgeOptions['resolveAudioOutput'];
  #requestCounter = 0;

  constructor(options: PlexPlaybackBridgeOptions) {
    this.#scheduler = options.scheduler;
    this.#resolver = options.resolver;
    this.#capabilityProfile = options.capabilityProfile;
    this.#createRequestId =
      options.createRequestId ??
      ((prefix) => {
        this.#requestCounter += 1;
        return `${prefix}-bridge-${this.#requestCounter}`;
      });
    this.#autoplay = options.autoplay ?? true;
    this.#settingsPreferences = options.settingsPreferences;
    this.#settingsCapabilities = options.settingsCapabilities;
    this.#resolveAudioOutput = options.resolveAudioOutput;
  }

  async getCurrentPlayback(_input?: {
    nowMs: number;
    reason: 'startup' | 'schedule-tick' | 'manual-switch';
  }): Promise<PlexPlaybackScheduleSelection | null> {
    const program = this.#readCurrentProgram();
    if (program === null || !program.isCurrent) {
      return null;
    }

    const channelId = this.#readChannelId();
    if (channelId === null) {
      return null;
    }

    return projectPlexPlaybackScheduleSelection({
      channelId,
      ratingKey: program.item.ratingKey,
      scheduledStartTime: program.scheduledStartTime,
      scheduledEndTime: program.scheduledEndTime,
    });
  }

  async resolvePlaybackCandidate(
    selection: PlexPlaybackScheduleSelection,
  ): Promise<PlexPlaybackRuntimeCandidate> {
    const program = this.#getProgramForSelection(selection);
    if (program === null) {
      throw new PlexPlaybackRuntimeCandidateResolutionError(createBridgeError({
        code: 'PLEX_PLAYBACK_PROGRAM_STALE',
        requestId: undefined,
        category: 'stale-request',
        reason: 'scheduled program is no longer current',
        retryable: false,
      }));
    }

    const requestId = this.#createRequestId('plex-playback');
    const settingsPreferences = await this.#readSettingsPreferences(requestId);
    const resolveAudioOutput = this.#resolveAudioOutput;
    const privateAudioSetup =
      settingsPreferences !== undefined && resolveAudioOutput !== undefined
        ? await this.#resolvePrivateAudioSetup(
          requestId,
          settingsPreferences,
          resolveAudioOutput,
        )
        : undefined;
    const resolverInput: PlexStreamResolverInput = {
      requestId,
      mediaId: program.item.ratingKey,
      capabilityProfile: await this.#resolveCapabilityProfile(),
      autoplay: this.#autoplay,
      startPositionMs: program.elapsedMs,
      ...(settingsPreferences !== undefined ? { settingsPreferences } : {}),
    };

    const result = await this.#resolver.resolve(resolverInput);
    if (!result.ok) {
      throw new PlexPlaybackRuntimeCandidateResolutionError(result.error);
    }

    let privatePlayback = result.privatePlayback;
    if (settingsPreferences !== undefined && privateAudioSetup !== undefined) {
      privatePlayback = {
        ...privatePlayback,
        setup: {
          ...privatePlayback.setup,
          audioOutputNativeKey: privateAudioSetup.resolvedOutput.audioOutputNativeKey,
          dtsPassthroughEnabled:
            settingsPreferences.dtsPassthroughEnabled && privateAudioSetup.dtsSupported,
        },
      };
    }

    return {
      requestId,
      load: result.load,
      pmsSession: result.pmsSession,
      privatePlayback,
    };
  }

  #readCurrentProgram(): ScheduledProgram | null {
    try {
      return this.#scheduler.getCurrentProgram();
    } catch {
      return null;
    }
  }

  #readChannelId(): string | null {
    try {
      const state = this.#scheduler.getState();
      const channelId = state.channelId.trim();
      return state.isActive && channelId !== '' ? channelId : null;
    } catch {
      return null;
    }
  }

  #getProgramForSelection(selection: PlexPlaybackScheduleSelection): ScheduledProgram | null {
    const current = this.#readCurrentProgram();
    if (current === null || !current.isCurrent) {
      return null;
    }
    const channelId = this.#readChannelId();
    if (channelId === null) {
      return null;
    }
    const currentSelection = projectPlexPlaybackScheduleSelection({
      channelId,
      ratingKey: current.item.ratingKey,
      scheduledStartTime: current.scheduledStartTime,
      scheduledEndTime: current.scheduledEndTime,
    });
    if (!isSamePlexPlaybackScheduleSelection(currentSelection, selection)) {
      return null;
    }
    return current;
  }

  async #resolveCapabilityProfile(): Promise<DesktopStreamCapabilityProfile> {
    if (typeof this.#capabilityProfile === 'function') {
      return this.#capabilityProfile();
    }
    return this.#capabilityProfile;
  }

  async #readSettingsPreferences(
    requestId: PlayerRequestId,
  ): Promise<DesktopPlaybackSettingsPreferences | undefined> {
    try {
      return await this.#settingsPreferences?.();
    } catch {
      throw new PlexPlaybackRuntimeCandidateResolutionError(createBridgeError({
        code: 'PLEX_PLAYBACK_SETTINGS_UNAVAILABLE',
        requestId,
        category: 'source',
        operation: 'settings.read',
        reason: 'settings preferences unavailable',
        retryable: true,
      }));
    }
  }

  async #resolvePrivateAudioSetup(
    requestId: PlayerRequestId,
    settingsPreferences: DesktopPlaybackSettingsPreferences,
    resolveAudioOutput: NonNullable<PlexPlaybackBridgeOptions['resolveAudioOutput']>,
  ): Promise<{ resolvedOutput: ResolvedAudioOutput; dtsSupported: boolean }> {
    try {
      const resolvedOutput = await resolveAudioOutput(
        settingsPreferences.audioOutputDeviceId,
      );
      const dtsSupported =
        this.#settingsCapabilities?.().dtsPassthrough.status === 'supported';
      return { resolvedOutput, dtsSupported };
    } catch {
      throw new PlexPlaybackRuntimeCandidateResolutionError(createBridgeError({
        code: 'PLEX_PLAYBACK_AUDIO_SETUP_UNAVAILABLE',
        requestId,
        category: 'source',
        operation: 'settings.audio.resolve',
        reason: 'private audio setup unavailable',
        retryable: true,
      }));
    }
  }
}

function createBridgeError(input: {
  code: string;
  requestId: PlayerRequestId | undefined;
  category: 'stale-request' | 'source';
  operation?: 'schedule.map' | 'settings.read' | 'settings.audio.resolve';
  reason: string;
  retryable: boolean;
}) {
  return {
    code: input.code,
    category: input.category,
    message: 'The scheduled Plex program could not be prepared for playback.',
    recoverable: true,
    retryable: input.retryable,
    ...(input.requestId !== undefined ? { requestId: input.requestId } : {}),
    diagnostic: {
      component: 'plex-playback-bridge',
      operation: input.operation ?? 'schedule.map',
      status: 'ignored',
      reason: input.reason,
    },
  };
}
