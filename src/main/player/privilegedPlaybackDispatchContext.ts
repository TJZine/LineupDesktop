import type { PlayerError, PlayerRequestId } from '../../contracts/player.js';
import type { PlexPrivilegedPlaybackDescriptor } from '../plex/streamResolver.js';

export interface PrivilegedPlaybackDispatchContext {
  privatePlayback: PlexPrivilegedPlaybackDescriptor;
}

export type PrivilegedPlaybackDescriptorValidationResult =
  | { ok: true }
  | { ok: false; error: PlayerError };

export function validatePrivilegedPlaybackDescriptor(
  descriptor: PlexPrivilegedPlaybackDescriptor,
  commandRequestId: PlayerRequestId,
): PrivilegedPlaybackDescriptorValidationResult {
  if (descriptor.requestId !== commandRequestId) {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      'request-id-mismatch',
      'Privileged playback descriptor request ID does not match command request ID.',
    );
  }

  const kind = descriptor.decisionKind;
  if (kind !== 'direct-play' && kind !== 'direct-stream' && kind !== 'transcode') {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      'unsupported-decision-kind',
      'Unsupported privileged playback decision kind.',
    );
  }

  const mode = descriptor.setup.playbackMode;
  if (mode !== 'direct-play' && mode !== 'direct-stream' && mode !== 'transcode') {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      'unsupported-playback-mode',
      'Unsupported privileged playback mode.',
    );
  }

  if (!descriptor.playbackUrl || descriptor.playbackUrl.trim().length === 0) {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      'empty-playback-url',
      'Privileged playback URL is empty.',
    );
  }

  if (!descriptor.credentialHeader || !descriptor.credentialHeader.name || !descriptor.credentialHeader.value) {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      'missing-credential-header',
      'Privileged credential header is missing required fields.',
    );
  }

  return { ok: true };
}

function invalidPrivilegedPlaybackDescriptor(
  commandRequestId: PlayerRequestId,
  reason: string,
  message: string,
): PrivilegedPlaybackDescriptorValidationResult {
  return {
    ok: false,
    error: {
      code: 'PLAYER_PRIVILEGED_DESCRIPTOR_INVALID',
      category: 'validation-failure',
      message,
      recoverable: false,
      retryable: false,
      requestId: commandRequestId,
      diagnostic: {
        component: 'privileged-playback-dispatch-context',
        operation: 'validate',
        status: 'rejected',
        reason,
      },
    },
  };
}
