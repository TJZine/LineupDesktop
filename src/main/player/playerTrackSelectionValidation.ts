import {
  type PlayerCommand,
  type PlayerSnapshot,
  type PlayerError,
} from '../../contracts/player.js';
import { createPlayerError } from './playerAdapterErrors.js';

export function validateTrackSelectionCommand(
  command: PlayerCommand,
  snapshot: PlayerSnapshot,
): PlayerError | null {
  if (
    (command.command === 'track.audio.select' || command.command === 'track.subtitle.select') &&
    command.payload.snapshotRequestId !== snapshot.requestId
  ) {
    return createPlayerError({
      code: 'PLAYER_VALIDATION_FAILED',
      category: 'stale-request',
      message: 'Track selection targeted a stale player snapshot.',
      requestId: command.requestId,
      diagnostic: {
        component: 'player-track-validation',
        operation: command.command,
        status: 'rejected',
        reason: 'snapshot request mismatch',
      },
    });
  }

  if (command.command === 'track.audio.select') {
    const { trackId } = command.payload;
    if (trackId === null) {
      return createPlayerError({
        code: 'PLAYER_VALIDATION_FAILED',
        category: 'validation-failure',
        message: 'Audio track selection cannot be null.',
        requestId: command.requestId,
        diagnostic: {
          component: 'player-track-validation',
          operation: 'track.audio.select',
          status: 'rejected',
          reason: 'null audio track id',
        },
      });
    }

    const track = snapshot.tracks.find((t) => t.id === trackId);
    if (!track) {
      return createPlayerError({
        code: 'PLAYER_VALIDATION_FAILED',
        category: 'validation-failure',
        message: 'The requested audio track does not exist.',
        requestId: command.requestId,
        diagnostic: {
          component: 'player-track-validation',
          operation: 'track.audio.select',
          status: 'rejected',
          reason: 'track not found',
        },
      });
    }

    if (track.kind !== 'audio') {
      return createPlayerError({
        code: 'PLAYER_VALIDATION_FAILED',
        category: 'validation-failure',
        message: 'The requested track is not an audio track.',
        requestId: command.requestId,
        diagnostic: {
          component: 'player-track-validation',
          operation: 'track.audio.select',
          status: 'rejected',
          reason: 'wrong track kind',
        },
      });
    }

    if (!track.available) {
      return createPlayerError({
        code: 'PLAYER_VALIDATION_FAILED',
        category: 'validation-failure',
        message: 'The requested audio track is not available.',
        requestId: command.requestId,
        diagnostic: {
          component: 'player-track-validation',
          operation: 'track.audio.select',
          status: 'rejected',
          reason: 'track unavailable',
        },
      });
    }
  }

  if (command.command === 'track.subtitle.select') {
    const { trackId } = command.payload;
    if (trackId !== null) {
      const track = snapshot.tracks.find((t) => t.id === trackId);
      if (!track) {
        return createPlayerError({
          code: 'PLAYER_VALIDATION_FAILED',
          category: 'validation-failure',
          message: 'The requested subtitle track does not exist.',
          requestId: command.requestId,
          diagnostic: {
            component: 'player-track-validation',
            operation: 'track.subtitle.select',
            status: 'rejected',
            reason: 'track not found',
          },
        });
      }

      if (track.kind !== 'subtitle') {
        return createPlayerError({
          code: 'PLAYER_VALIDATION_FAILED',
          category: 'validation-failure',
          message: 'The requested track is not a subtitle track.',
          requestId: command.requestId,
          diagnostic: {
            component: 'player-track-validation',
            operation: 'track.subtitle.select',
            status: 'rejected',
            reason: 'wrong track kind',
          },
        });
      }

      if (!track.available) {
        return createPlayerError({
          code: 'PLAYER_VALIDATION_FAILED',
          category: 'validation-failure',
          message: 'The requested subtitle track is not available.',
          requestId: command.requestId,
          diagnostic: {
            component: 'player-track-validation',
            operation: 'track.subtitle.select',
            status: 'rejected',
            reason: 'track unavailable',
          },
        });
      }
    }
  }

  return null;
}
