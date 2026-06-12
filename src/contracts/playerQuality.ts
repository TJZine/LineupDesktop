import { PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS, type PlayerForbiddenPrivilegedFieldKey } from './player.js';

export type PlayerPlaybackMode = 'direct-play' | 'direct-stream' | 'transcode' | 'unknown';
export type PlayerDynamicRange = 'sdr' | 'hdr10' | 'dolby-vision' | 'unknown';
export type PlayerOutputDynamicRange =
  | 'sdr'
  | 'hdr10'
  | 'dolby-vision'
  | 'tone-mapped'
  | 'unknown'
  | 'unproven';

export interface PlayerPlaybackQualitySummary {
  mode: PlayerPlaybackMode;
  videoCodec?: string;
  audioCodec?: string;
  sourceDynamicRange: PlayerDynamicRange;
  outputDynamicRangeStatus: PlayerOutputDynamicRange;
  fallbackReason?: string;
}

export const PLAYER_PLAYBACK_MODE_VALUES = [
  'direct-play',
  'direct-stream',
  'transcode',
  'unknown',
] as const;

export const PLAYER_DYNAMIC_RANGE_VALUES = [
  'sdr',
  'hdr10',
  'dolby-vision',
  'unknown',
] as const;

export const PLAYER_OUTPUT_DYNAMIC_RANGE_VALUES = [
  'sdr',
  'hdr10',
  'dolby-vision',
  'tone-mapped',
  'unknown',
  'unproven',
] as const;

export function isRendererSafePlayerPlaybackQualitySummary(
  value: unknown,
): value is PlayerPlaybackQualitySummary {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return false;
  }

  if (hasForbiddenField(value)) {
    return false;
  }

  const keys = Object.keys(value);
  const allowed = new Set([
    'mode',
    'videoCodec',
    'audioCodec',
    'sourceDynamicRange',
    'outputDynamicRangeStatus',
    'fallbackReason',
  ]);

  for (const key of keys) {
    if (!allowed.has(key)) {
      return false;
    }
  }

  const val = value as Record<string, unknown>;

  if (!isStringInSet(val.mode, PLAYER_PLAYBACK_MODE_VALUES)) {
    return false;
  }
  if (!isStringInSet(val.sourceDynamicRange, PLAYER_DYNAMIC_RANGE_VALUES)) {
    return false;
  }
  if (!isStringInSet(val.outputDynamicRangeStatus, PLAYER_OUTPUT_DYNAMIC_RANGE_VALUES)) {
    return false;
  }
  if (val.videoCodec !== undefined && typeof val.videoCodec !== 'string') {
    return false;
  }
  if (val.audioCodec !== undefined && typeof val.audioCodec !== 'string') {
    return false;
  }
  if (val.fallbackReason !== undefined && typeof val.fallbackReason !== 'string') {
    return false;
  }

  return true;
}

function isStringInSet<T extends string>(val: unknown, allowed: readonly T[]): val is T {
  return typeof val === 'string' && allowed.includes(val as T);
}

function hasForbiddenField(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some((item) => hasForbiddenField(item));
  }
  if (typeof value !== 'object' || value === null) {
    return false;
  }
  return Object.entries(value).some(([key, child]) => {
    return (
      PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS.includes(
        key as PlayerForbiddenPrivilegedFieldKey,
      ) || hasForbiddenField(child)
    );
  });
}
