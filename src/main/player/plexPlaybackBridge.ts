import type { PlayerRequestId } from '../../contracts/player.js';
import type { IChannelScheduler, ScheduledProgram } from '../../domain/scheduler/index.js';
import type { PlexStreamResolverInput, PlexStreamResolverResult } from '../plex/streamResolver.js';
import type { DesktopStreamCapabilityProfile } from './streamPolicy/types.js';
import {
  PlexPlaybackRuntimeCandidateResolutionError,
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
}

export class PlexPlaybackBridge implements PlexPlaybackRuntimeSchedulerPort, PlexPlaybackRuntimeChannelPort {
  readonly #scheduler: Pick<IChannelScheduler, 'getCurrentProgram' | 'getState'>;
  readonly #resolver: PlexPlaybackBridgeResolverPort;
  readonly #capabilityProfile:
    | DesktopStreamCapabilityProfile
    | (() => DesktopStreamCapabilityProfile | Promise<DesktopStreamCapabilityProfile>);
  readonly #createRequestId: (prefix: string) => PlayerRequestId;
  readonly #autoplay: boolean;
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

    return projectScheduleSelection(channelId, program);
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
    const resolverInput: PlexStreamResolverInput = {
      requestId,
      mediaId: program.item.ratingKey,
      capabilityProfile: await this.#resolveCapabilityProfile(),
      autoplay: this.#autoplay,
      startPositionMs: program.elapsedMs,
    };

    const result = await this.#resolver.resolve(resolverInput);
    if (!result.ok) {
      throw new PlexPlaybackRuntimeCandidateResolutionError(result.error);
    }

    return {
      requestId,
      load: result.load,
      pmsSession: result.pmsSession,
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
      return state.isActive && state.channelId.trim() !== '' ? state.channelId : null;
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
    const currentSelection = projectScheduleSelection(channelId, current);
    if (!isSameSelection(currentSelection, selection)) {
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
}

function projectScheduleSelection(
  channelId: string,
  program: ScheduledProgram,
): PlexPlaybackScheduleSelection {
  return {
    channelId,
    programId: toProgramId(channelId, program),
    startedAtMs: program.scheduledStartTime,
    endsAtMs: program.scheduledEndTime,
  };
}

function toProgramId(channelId: string, program: ScheduledProgram): string {
  return [
    'program',
    safeIdPart(channelId),
    safeIdPart(program.item.ratingKey),
    String(program.scheduledStartTime),
    String(program.scheduledEndTime),
  ].join('-');
}

function safeIdPart(value: string): string {
  const normalized = value.trim().replace(/[^a-zA-Z0-9._-]+/gu, '-');
  return normalized === '' ? 'unknown' : normalized;
}

function isSameSelection(
  left: PlexPlaybackScheduleSelection,
  right: PlexPlaybackScheduleSelection,
): boolean {
  return (
    left.channelId === right.channelId &&
    left.programId === right.programId &&
    left.startedAtMs === right.startedAtMs &&
    (left.endsAtMs ?? null) === (right.endsAtMs ?? null)
  );
}

function createBridgeError(input: {
  code: string;
  requestId: PlayerRequestId | undefined;
  category: 'stale-request' | 'source';
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
      operation: 'schedule.map',
      status: 'ignored',
      reason: input.reason,
    },
  };
}
