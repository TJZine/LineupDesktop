import type { PlayerTrackId } from '../../contracts/player.js';
import type { PlaybackTrackMap } from '../plex/streamTrackMapping.js';

export interface NativeHelperPlaybackSetup {
  playbackMode: 'direct-play' | 'direct-stream' | 'transcode';
  mediaPath: string;
  variantId: string;
  partPath: string;
  selectedTrackIds: {
    video: PlayerTrackId | null;
    audio: PlayerTrackId | null;
    subtitle: PlayerTrackId | null;
  };
  selectedPrivateTrackIds: {
    video: string | null;
    audio: string | null;
    subtitle: string | null;
  };
  trackMap: PlaybackTrackMap;
}

