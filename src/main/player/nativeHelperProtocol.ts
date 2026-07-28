import type { PlayerCommandName, PlayerRequestId } from '../../contracts/player.js';
import type { NativeHelperPlaybackSetup } from './nativeHelperPlaybackSetup.js';

export const MAX_HELPER_MESSAGE_SIZE = 1024 * 1024; // 1MB

export interface NativeHelperCommandMessage {
  type: 'command';
  requestId: PlayerRequestId;
  command: PlayerCommandName;
  payload: unknown;
  setup?: NativeHelperPlaybackSetup | null;
  playbackUrl?: string | null;
  credentialHeader?: { name: string; value: string } | null;
}

export interface NativeHelperCleanupMessage {
  type: 'cleanup';
  requestId: PlayerRequestId | null;
}

export type NativeHelperInputMessage =
  | NativeHelperCommandMessage
  | NativeHelperCleanupMessage;

export type NativeHelperOutputMessage =
  | {
      type: 'result';
      requestId: PlayerRequestId;
      ok: true;
      events?: unknown;
    }
  | {
      type: 'result';
      requestId: PlayerRequestId;
      ok: false;
      error?: {
        code: string;
        message: string;
        category?: string;
        recoverable?: boolean;
        retryable?: boolean;
      };
    }
  | {
      type: 'event';
      event: unknown;
    };

export function validateHelperMessageSize(messageStr: string): void {
  if (messageStr.length > MAX_HELPER_MESSAGE_SIZE) {
    throw new Error(`Message size ${messageStr.length} exceeds maximum limit of ${MAX_HELPER_MESSAGE_SIZE} characters.`);
  }
}
