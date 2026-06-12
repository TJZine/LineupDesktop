import type {
  PlayerSnapshot,
  PlayerTrackId,
  PlayerTrackKind,
  PlayerTrackSummary,
} from '../../contracts/player.js';
import { sanitizePlayerError } from './playerAdapterErrors.js';

export function applyTrackSnapshot(
  snapshot: PlayerSnapshot,
  requestId: string,
  tracks: readonly PlayerTrackSummary[],
): PlayerSnapshot {
  return {
    ...snapshot,
    requestId,
    tracks,
    selectedAudioTrackId: findSelectedTrackId(tracks, 'audio'),
    selectedSubtitleTrackId: findSelectedTrackId(tracks, 'subtitle'),
    selectedVideoTrackId: findSelectedTrackId(tracks, 'video'),
  };
}

export function createInitialSnapshot(): PlayerSnapshot {
  return {
    requestId: null,
    status: 'idle',
    media: null,
    capabilityProfileId: null,
    positionMs: 0,
    durationMs: null,
    bufferedRanges: [],
    playing: false,
    volume: 1,
    muted: false,
    playbackRate: 1,
    selectedAudioTrackId: null,
    selectedSubtitleTrackId: null,
    selectedVideoTrackId: null,
    tracks: [],
    quality: { mode: 'unknown', sourceDynamicRange: 'unknown', outputDynamicRangeStatus: 'unknown' },
    lastError: null,
  };
}

export function cloneSnapshot(snapshot: PlayerSnapshot): PlayerSnapshot {
  return {
    ...snapshot,
    media: snapshot.media === null ? null : { ...snapshot.media },
    bufferedRanges: snapshot.bufferedRanges.map((range) => ({ ...range })),
    tracks: snapshot.tracks.map((track) => ({ ...track })),
    lastError: snapshot.lastError === null ? null : sanitizePlayerError(snapshot.lastError, 'PLAYER_ERROR'),
  };
}

function findSelectedTrackId(
  tracks: readonly PlayerTrackSummary[],
  kind: PlayerTrackKind,
): PlayerTrackId | null {
  return tracks.find((track) => track.kind === kind && track.selected)?.id ?? null;
}
