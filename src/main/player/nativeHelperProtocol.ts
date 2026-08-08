import type { PlayerCommandName, PlayerRequestId } from '../../contracts/player.js';
import type { NativeHelperPlaybackSetup } from './nativeHelperPlaybackSetup.js';

export const MAX_HELPER_MESSAGE_SIZE = 1024 * 1024; // 1MB
export const MAX_PRESENTATION_MESSAGE_SIZE = 4096;

export type NativePresentationMode =
  | 'hidden'
  | 'player-full'
  | 'guide-overlay-full'
  | 'guide-classic-pip';

export interface NativeHelperPresentationUpdateMessage {
  type: 'presentation.update';
  version: 1;
  operationId: PlayerRequestId;
  documentEpoch: number;
  revision: number;
  parentHwnd: string;
  parentPid: number;
  loadedRequestId: PlayerRequestId | null;
  mode: NativePresentationMode;
  bounds: { x: number; y: number; width: number; height: number } | null;
}

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

export interface NativeHelperAudioOutputQueryMessage {
  type: 'audio-output.query';
  requestId: PlayerRequestId;
}

export type NativeHelperInputMessage =
  | NativeHelperCommandMessage
  | NativeHelperCleanupMessage
  | NativeHelperAudioOutputQueryMessage
  | NativeHelperPresentationUpdateMessage;

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
      error: {
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
    }
  | {
      type: 'audio-output.result';
      requestId: PlayerRequestId;
      ok: true;
      outputs: { nativeKey: string; label: string }[];
    }
  | {
      type: 'audio-output.result';
      requestId: PlayerRequestId;
      ok: false;
      error: unknown;
    }
  | {
      type: 'presentation.result';
      version: 1;
      operationId: PlayerRequestId;
      documentEpoch: number;
      revision: number;
      status: 'applied' | 'hidden' | 'stale' | 'rejected';
    };

export function validateHelperMessageSize(messageStr: string): void {
  if (messageStr.length > MAX_HELPER_MESSAGE_SIZE) {
    throw new Error(`Message size ${messageStr.length} exceeds maximum limit of ${MAX_HELPER_MESSAGE_SIZE} characters.`);
  }
}
