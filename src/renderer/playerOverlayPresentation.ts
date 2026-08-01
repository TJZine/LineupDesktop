import type { PlayerSnapshot, PlayerTrackSummary } from '../contracts/player.js';
import type { ChannelSetupSummary } from '../contracts/channel.js';
import type { EpgPresentationSource, EpgProgramViewModel } from './epg.js';

export interface OverlayProgramViewModel {
  id: string;
  title: string;
  subtitle?: string;
  startsAtMs: number;
  endsAtMs: number;
}

export interface OverlayChannelViewModel {
  id: string;
  number: string;
  name: string;
  currentProgram?: OverlayProgramViewModel;
  nextProgram?: OverlayProgramViewModel;
  progressPercent?: number;
}

export interface PlayerOverlayPresentationSource {
  channels: readonly OverlayChannelViewModel[];
  currentChannelId: string | null;
  playerSnapshot: PlayerSnapshot;
  nowMs: number;
}

export interface PlayerOverlayPresentationInput {
  playerSnapshot: PlayerSnapshot;
  channelSummary: ChannelSetupSummary | null;
  guidePresentation: EpgPresentationSource | null;
  nowMs?: number;
}

export function createEmptyPlayerSnapshot(): PlayerSnapshot {
  return {
    requestId: null,
    status: 'idle',
    media: null,
    capabilityProfileId: null,
    seekSupport: 'unknown',
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
    quality: {
      mode: 'unknown',
      sourceDynamicRange: 'unknown',
      outputDynamicRangeStatus: 'unknown',
    },
    lastError: null,
  };
}

export function createPlayerOverlayPresentation(
  input: PlayerOverlayPresentationInput,
): PlayerOverlayPresentationSource {
  const nowMs = input.nowMs ?? input.guidePresentation?.nowMs ?? Date.now();
  const guideById = new Map(
    (input.guidePresentation?.channels ?? []).map((channel) => [channel.id, channel]),
  );
  const channels = (input.channelSummary?.channels ?? []).map((channel) => {
    const programs = guideById.get(channel.id)?.programs ?? [];
    const currentIndex = programs.findIndex(
      (program) => program.startsAtMs <= nowMs && nowMs < program.endsAtMs,
    );
    const current = currentIndex < 0 ? undefined : programs[currentIndex];
    const next = currentIndex < 0
      ? programs.find((program) => program.startsAtMs >= nowMs)
      : programs[currentIndex + 1];
    return {
      id: channel.id,
      number: String(channel.number),
      name: channel.name,
      ...(current === undefined ? {} : {
        currentProgram: projectProgram(current),
        progressPercent: progress(current, nowMs),
      }),
      ...(next === undefined ? {} : { nextProgram: projectProgram(next) }),
    };
  });

  const currentChannelId = input.channelSummary?.currentChannelId ?? null;
  return {
    channels,
    currentChannelId: channels.some((channel) => channel.id === currentChannelId)
      ? currentChannelId
      : null,
    playerSnapshot: input.playerSnapshot,
    nowMs,
  };
}

export function availableTracks(
  snapshot: PlayerSnapshot,
  kind: 'audio' | 'subtitle',
): readonly PlayerTrackSummary[] {
  return snapshot.tracks.filter((track) => track.kind === kind && track.available);
}

export function isAudioControlEligible(snapshot: PlayerSnapshot): boolean {
  return availableTracks(snapshot, 'audio').some(
    (track) => track.id !== snapshot.selectedAudioTrackId,
  );
}

export function isSubtitleControlEligible(snapshot: PlayerSnapshot): boolean {
  return snapshot.selectedSubtitleTrackId !== null || availableTracks(snapshot, 'subtitle').length > 0;
}

export function resolveRetryChannelId(
  presentation: PlayerOverlayPresentationSource,
  lastTuneChannelId: string | null,
): string | null {
  const candidates = [presentation.currentChannelId, lastTuneChannelId];
  return candidates.find((candidate) =>
    candidate !== null && presentation.channels.some((channel) => channel.id === candidate)) ?? null;
}

function projectProgram(program: EpgProgramViewModel): OverlayProgramViewModel {
  return {
    id: program.id,
    title: program.title,
    ...(program.subtitle.trim().length === 0 ? {} : { subtitle: program.subtitle }),
    startsAtMs: program.startsAtMs,
    endsAtMs: program.endsAtMs,
  };
}

function progress(program: EpgProgramViewModel, nowMs: number): number {
  const duration = program.endsAtMs - program.startsAtMs;
  if (duration <= 0) return 0;
  return Math.max(0, Math.min(100, Math.round(((nowMs - program.startsAtMs) / duration) * 100)));
}
