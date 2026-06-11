import type { PlexPrivilegedPlaybackDescriptor } from '../plex/streamResolver.js';

export interface PrivilegedPlaybackDispatchContext {
  privatePlayback: PlexPrivilegedPlaybackDescriptor;
}

export function validatePrivilegedPlaybackDescriptor(
  descriptor: PlexPrivilegedPlaybackDescriptor,
  commandRequestId: string,
): void {
  if (descriptor.requestId !== commandRequestId) {
    throw new Error('Privileged playback descriptor request ID does not match command request ID.');
  }
  
  const kind = descriptor.decisionKind;
  if (kind !== 'direct-play' && kind !== 'direct-stream' && kind !== 'transcode') {
    throw new Error(`Unsupported privileged playback decision kind: ${kind}`);
  }
  
  const mode = descriptor.setup.playbackMode;
  if (mode !== 'direct-play' && mode !== 'direct-stream' && mode !== 'transcode') {
    throw new Error(`Unsupported privileged playback mode: ${mode}`);
  }

  if (!descriptor.playbackUrl || descriptor.playbackUrl.trim().length === 0) {
    throw new Error('Privileged playback URL is empty.');
  }

  if (!descriptor.credentialHeader || !descriptor.credentialHeader.name || !descriptor.credentialHeader.value) {
    throw new Error('Privileged credential header is missing name or value.');
  }
}
