import type {
  PlayerCommand,
  PlayerCommandName,
} from '../../contracts/player.js';
import type { PlayerRendererIntent } from '../../contracts/ipc.js';
import { validationFailure, type ValidationFailure } from './playerAdapterErrors.js';
import {
  hasForbiddenPrivilegedField,
  isEmptyPayload,
  isFiniteNonNegativeNumber,
  isFiniteNumber,
  isFiniteRangeNumber,
  isNonEmptyString,
  isPlayerRendererIntent,
  isRecord,
  readRequestId,
  validateLoadPayload,
  validateObjectPayload,
} from './playerAdapterValidation.js';

interface CommandMappingResult {
  command: PlayerCommand;
}

const EMPTY_PAYLOAD: Record<string, never> = {};
const PLAYER_INTENT_TO_COMMAND = {
  'player.load': 'load',
  'player.play': 'play',
  'player.pause': 'pause',
  'player.stop': 'stop',
  'player.seekAbsolute': 'seek.absolute',
  'player.seekRelative': 'seek.relative',
  'player.setVolume': 'volume.set',
  'player.setMute': 'mute.set',
  'player.selectAudio': 'track.audio.select',
  'player.selectSubtitle': 'track.subtitle.select',
} as const satisfies Record<PlayerRendererIntent, PlayerCommandName>;

export function mapRendererIntentToCommand(envelope: unknown): CommandMappingResult | ValidationFailure {
  if (!isRecord(envelope)) {
    return validationFailure(undefined, 'renderer envelope must be an object');
  }
  if (hasForbiddenPrivilegedField(envelope)) {
    return validationFailure(readRequestId(envelope), 'renderer envelope contained privileged fields');
  }
  const requestId = envelope.requestId;
  if (!isNonEmptyString(requestId)) {
    return validationFailure(undefined, 'renderer envelope request id must be a non-empty string');
  }
  if (!isPlayerRendererIntent(envelope.intent, PLAYER_INTENT_TO_COMMAND)) {
    return validationFailure(requestId, 'renderer envelope intent is not a player intent');
  }
  const commandName = PLAYER_INTENT_TO_COMMAND[envelope.intent];
  switch (commandName) {
    case 'load': {
      const payload = validateLoadPayload(envelope.payload);
      if ('error' in payload) {
        return validationFailure(requestId, payload.error);
      }
      return { command: { command: 'load', requestId, payload: payload.value } };
    }
    case 'play':
    case 'pause':
    case 'stop':
      if (!isEmptyPayload(envelope.payload)) {
        return validationFailure(requestId, `${commandName} payload must be empty`);
      }
      return { command: { command: commandName, requestId, payload: EMPTY_PAYLOAD } };
    case 'seek.absolute': {
      const payload = validateObjectPayload(envelope.payload, ['positionMs']);
      if ('error' in payload || !isFiniteNonNegativeNumber(payload.value.positionMs)) {
        return validationFailure(requestId, 'seek absolute payload must include positionMs');
      }
      return {
        command: { command: 'seek.absolute', requestId, payload: { positionMs: payload.value.positionMs } },
      };
    }
    case 'seek.relative': {
      const payload = validateObjectPayload(envelope.payload, ['deltaMs']);
      if ('error' in payload || !isFiniteNumber(payload.value.deltaMs)) {
        return validationFailure(requestId, 'seek relative payload must include deltaMs');
      }
      return {
        command: { command: 'seek.relative', requestId, payload: { deltaMs: payload.value.deltaMs } },
      };
    }
    case 'volume.set': {
      const payload = validateObjectPayload(envelope.payload, ['volume']);
      if ('error' in payload || !isFiniteRangeNumber(payload.value.volume, 0, 1)) {
        return validationFailure(requestId, 'volume payload must include volume from 0 to 1');
      }
      return { command: { command: 'volume.set', requestId, payload: { volume: payload.value.volume } } };
    }
    case 'mute.set': {
      const payload = validateObjectPayload(envelope.payload, ['muted']);
      if ('error' in payload || typeof payload.value.muted !== 'boolean') {
        return validationFailure(requestId, 'mute payload must include muted boolean');
      }
      return { command: { command: 'mute.set', requestId, payload: { muted: payload.value.muted } } };
    }
    case 'track.audio.select': {
      const payload = validateObjectPayload(envelope.payload, ['trackId']);
      if ('error' in payload || !isNonEmptyString(payload.value.trackId)) {
        return validationFailure(requestId, 'audio track payload must include opaque trackId');
      }
      return {
        command: {
          command: 'track.audio.select',
          requestId,
          payload: { trackId: payload.value.trackId },
        },
      };
    }
    case 'track.subtitle.select': {
      const payload = validateObjectPayload(envelope.payload, ['trackId']);
      if (
        'error' in payload ||
        !(payload.value.trackId === null || isNonEmptyString(payload.value.trackId))
      ) {
        return validationFailure(requestId, 'subtitle track payload must include opaque trackId or null');
      }
      return {
        command: {
          command: 'track.subtitle.select',
          requestId,
          payload: { trackId: payload.value.trackId },
        },
      };
    }
  }
}
