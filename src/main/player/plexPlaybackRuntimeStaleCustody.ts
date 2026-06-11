import type { PlayerEvent, PlayerRequestId } from '../../contracts/player.js';
import type { PlexPlaybackRuntimeStartResult } from './plexPlaybackRuntime.js';
import { createRuntimeWarning } from './plexPlaybackRuntimeDiagnostics.js';

export class PlexPlaybackRuntimeStaleCustody {
  quarantineEvents(input: {
    currentEpoch: number;
    eventEpoch: number;
    events: readonly PlayerEvent[];
    reason: string;
  }): readonly PlayerEvent[] {
    if (input.events.length === 0) {
      return [];
    }

    return [
      createRuntimeWarning(
        readEventRequestId(input.events[0]) ?? null,
        'PLAYER_STALE_PLAYBACK_EVENT',
        'A stale playback event was ignored.',
        {
          operation: 'player.dispatch',
          status: 'ignored',
          reason: input.eventEpoch === input.currentEpoch
            ? input.reason
            : 'event epoch did not match current playback state',
          counts: { ignoredEvents: input.events.length },
        },
      ),
    ];
  }

  createStaleStartResult(input: {
    epoch: number;
    requestId: PlayerRequestId | null;
    events: readonly PlayerEvent[];
    reason: string;
  }): PlexPlaybackRuntimeStartResult {
    const nextEvents = [
      ...input.events,
      createRuntimeWarning(
        input.requestId,
        'PLAYER_STALE_PLAYBACK_REQUEST',
        'A stale playback request was ignored.',
        {
          operation: 'runtime.start',
          status: 'ignored',
          reason: input.reason,
        },
      ),
    ];
    return {
      accepted: false,
      epoch: input.epoch,
      requestId: input.requestId,
      events: nextEvents,
    };
  }
}

export function readEventRequestId(event: PlayerEvent): PlayerRequestId | null {
  return 'requestId' in event ? event.requestId : null;
}
