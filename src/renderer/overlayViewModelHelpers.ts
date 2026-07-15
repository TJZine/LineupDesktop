import type { PlayerSnapshot, PlayerStatus, PlayerTrackSummary } from '../contracts/player.js';

export function formatDuration(valueMs: number): string {
  const totalSeconds = Math.floor(Math.max(0, valueMs) / 1000);
  return `${Math.floor(totalSeconds / 60)}:${String(totalSeconds % 60).padStart(2, '0')}`;
}

export function statusLabel(status: PlayerStatus): string {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

export function selectedTrackLabel(
  snapshot: PlayerSnapshot,
  kind: 'audio' | 'subtitle',
): string | undefined {
  const id = kind === 'audio' ? snapshot.selectedAudioTrackId : snapshot.selectedSubtitleTrackId;
  if (kind === 'subtitle' && id === null) return 'Off';
  return snapshot.tracks.find((track) => track.kind === kind && track.id === id)?.label;
}

export function trackMeta(track: PlayerTrackSummary): string | undefined {
  if (track.kind === 'audio') {
    const values = [track.codec?.toUpperCase(), track.channelCount === undefined ? undefined : `${track.channelCount}ch`];
    const value = values.filter((part): part is string => part !== undefined).join(' ');
    return value.length === 0 ? undefined : value;
  }
  if (track.forced) return 'Forced';
  if (track.deliveryType === 'burned-in') return 'Burn-in';
  return track.format?.toUpperCase();
}
