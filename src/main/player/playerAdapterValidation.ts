import {
  PLAYER_ERROR_CATEGORIES,
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  isRendererSafePlayerPlaybackQualitySummary,
  type PlayerErrorCategory,
  type PlayerLoadCommandPayload,
  type PlayerMediaSummary,
  type PlayerPlaybackQualitySummary,
  type PlayerRendererSafeDiagnostic,
  type PlayerTimeRange,
  type PlayerTrackDeliveryType,
  type PlayerTrackId,
  type PlayerTrackKind,
  type PlayerTrackSummary,
  type PlayerRequestId,
} from '../../contracts/player.js';
import type { PlayerRendererIntent } from '../../contracts/ipc.js';

export type UnknownRecord = Record<string, unknown>;

export const PLAYER_TRACK_KINDS = ['audio', 'subtitle', 'video'] as const satisfies readonly PlayerTrackKind[];
export const PLAYER_TRACK_DELIVERY_TYPES = [
  'embedded',
  'sidecar',
  'external',
  'burned-in',
  'unknown',
] as const satisfies readonly PlayerTrackDeliveryType[];

export function validateLoadPayload(
  value: unknown,
): { value: PlayerLoadCommandPayload } | { error: string } {
  const payload = validateObjectPayload(value, ['media', 'policy'], ['capabilityProfileId']);
  if ('error' in payload) {
    return payload;
  }
  const media = validateMediaSummary(payload.value.media);
  const policy = validateLoadPolicy(payload.value.policy);
  if ('error' in media || 'error' in policy) {
    return { error: 'load payload must include safe media and policy' };
  }
  if (
    payload.value.capabilityProfileId !== undefined &&
    !isNonEmptyString(payload.value.capabilityProfileId)
  ) {
    return { error: 'load payload capabilityProfileId must be a string when present' };
  }
  return {
    value: {
      media: media.value,
      policy: policy.value,
      capabilityProfileId: payload.value.capabilityProfileId,
    },
  };
}

export function validateLoadPolicy(
  value: unknown,
): { value: PlayerLoadCommandPayload['policy'] } | { error: string } {
  const payload = validateObjectPayload(
    value,
    ['autoplay'],
    ['startPositionMs', 'preferredAudioTrackId', 'preferredSubtitleTrackId'],
  );
  if ('error' in payload || typeof payload.value.autoplay !== 'boolean') {
    return { error: 'load policy must include autoplay' };
  }
  if (
    payload.value.startPositionMs !== undefined &&
    !isFiniteNonNegativeNumber(payload.value.startPositionMs)
  ) {
    return { error: 'load policy startPositionMs must be non-negative' };
  }
  if (
    payload.value.preferredAudioTrackId !== undefined &&
    !isNullableNonEmptyString(payload.value.preferredAudioTrackId)
  ) {
    return { error: 'load policy preferredAudioTrackId must be opaque or null' };
  }
  if (
    payload.value.preferredSubtitleTrackId !== undefined &&
    !isNullableNonEmptyString(payload.value.preferredSubtitleTrackId)
  ) {
    return { error: 'load policy preferredSubtitleTrackId must be opaque or null' };
  }
  return {
    value: {
      autoplay: payload.value.autoplay,
      startPositionMs: payload.value.startPositionMs,
      preferredAudioTrackId: payload.value.preferredAudioTrackId,
      preferredSubtitleTrackId: payload.value.preferredSubtitleTrackId,
    },
  };
}

export function validateMediaSummary(value: unknown): { value: PlayerMediaSummary } | { error: string } {
  const payload = validateObjectPayload(value, ['id', 'title'], ['subtitle', 'durationMs', 'container']);
  if ('error' in payload || !isNonEmptyString(payload.value.id) || !isNonEmptyString(payload.value.title)) {
    return { error: 'media summary must include id and title' };
  }
  if (payload.value.subtitle !== undefined && typeof payload.value.subtitle !== 'string') {
    return { error: 'media summary subtitle must be a string' };
  }
  if (
    payload.value.durationMs !== undefined &&
    !isNullableFiniteNonNegativeNumber(payload.value.durationMs)
  ) {
    return { error: 'media summary durationMs must be non-negative or null' };
  }
  if (payload.value.container !== undefined && typeof payload.value.container !== 'string') {
    return { error: 'media summary container must be a string' };
  }
  return {
    value: {
      id: payload.value.id,
      title: payload.value.title,
      subtitle: payload.value.subtitle,
      durationMs: payload.value.durationMs,
      container: payload.value.container,
    },
  };
}

export function validateTracks(value: unknown): { value: readonly PlayerTrackSummary[] } | { error: string } {
  if (!Array.isArray(value)) {
    return { error: 'tracks must be an array' };
  }
  const tracks: PlayerTrackSummary[] = [];
  for (const item of value) {
    const track = validateTrack(item);
    if ('error' in track) {
      return track;
    }
    tracks.push(track.value);
  }
  return { value: tracks };
}

export function validateTrack(value: unknown): { value: PlayerTrackSummary } | { error: string } {
  const payload = validateObjectPayload(
    value,
    ['id', 'kind', 'label', 'selected', 'available'],
    ['language', 'codec', 'format', 'channelCount', 'deliveryType', 'forced', 'default'],
  );
  if (
    'error' in payload ||
    !isNonEmptyString(payload.value.id) ||
    !isStringInSet(payload.value.kind, PLAYER_TRACK_KINDS) ||
    !isNonEmptyString(payload.value.label) ||
    typeof payload.value.selected !== 'boolean' ||
    typeof payload.value.available !== 'boolean'
  ) {
    return { error: 'track summary must include safe opaque fields' };
  }
  if (payload.value.language !== undefined && typeof payload.value.language !== 'string') {
    return { error: 'track language must be a string' };
  }
  if (payload.value.codec !== undefined && typeof payload.value.codec !== 'string') {
    return { error: 'track codec must be a string' };
  }
  if (payload.value.format !== undefined && typeof payload.value.format !== 'string') {
    return { error: 'track format must be a string' };
  }
  if (
    payload.value.channelCount !== undefined &&
    !isFiniteRangeNumber(payload.value.channelCount, 1, 64)
  ) {
    return { error: 'track channel count must be in range' };
  }
  if (
    payload.value.deliveryType !== undefined &&
    !isStringInSet(payload.value.deliveryType, PLAYER_TRACK_DELIVERY_TYPES)
  ) {
    return { error: 'track delivery type is unsupported' };
  }
  if (payload.value.forced !== undefined && typeof payload.value.forced !== 'boolean') {
    return { error: 'track forced flag must be boolean' };
  }
  if (payload.value.default !== undefined && typeof payload.value.default !== 'boolean') {
    return { error: 'track default flag must be boolean' };
  }
  return {
    value: {
      id: payload.value.id,
      kind: payload.value.kind,
      label: payload.value.label,
      language: payload.value.language,
      codec: payload.value.codec,
      format: payload.value.format,
      channelCount: payload.value.channelCount,
      deliveryType: payload.value.deliveryType,
      forced: payload.value.forced,
      default: payload.value.default,
      selected: payload.value.selected,
      available: payload.value.available,
    },
  };
}

export function validateTimeRanges(value: unknown): { value: readonly PlayerTimeRange[] } | { error: string } {
  if (!Array.isArray(value)) {
    return { error: 'buffered ranges must be an array' };
  }
  const ranges: PlayerTimeRange[] = [];
  for (const item of value) {
    const payload = validateObjectPayload(item, ['startMs', 'endMs']);
    if (
      'error' in payload ||
      !isFiniteNonNegativeNumber(payload.value.startMs) ||
      !isFiniteNonNegativeNumber(payload.value.endMs) ||
      payload.value.endMs < payload.value.startMs
    ) {
      return { error: 'buffered range must include startMs and endMs' };
    }
    ranges.push({ startMs: payload.value.startMs, endMs: payload.value.endMs });
  }
  return { value: ranges };
}

export function validatePlaybackQualitySummary(
  value: unknown,
): { value: PlayerPlaybackQualitySummary } | { error: string } {
  if (!isRendererSafePlayerPlaybackQualitySummary(value)) {
    return { error: 'playback quality summary must include safe fields' };
  }
  return { value };
}

export function validateObjectPayload(
  value: unknown,
  requiredKeys: readonly string[],
  optionalKeys: readonly string[] = [],
): { value: UnknownRecord } | { error: string } {
  if (!isRecord(value)) {
    return { error: 'payload must be an object' };
  }
  if (hasForbiddenPrivilegedField(value)) {
    return { error: 'payload contained privileged fields' };
  }
  const allowed = new Set([...requiredKeys, ...optionalKeys]);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      return { error: 'payload contained unsupported fields' };
    }
  }
  for (const key of requiredKeys) {
    if (!Object.hasOwn(value, key)) {
      return { error: `payload missing required field ${key}` };
    }
  }
  return { value };
}

export function isEmptyPayload(value: unknown): boolean {
  return isRecord(value) && Object.keys(value).length === 0 && !hasForbiddenPrivilegedField(value);
}

export function isRecord(value: unknown): value is UnknownRecord {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

export function isNullableNonEmptyString(value: unknown): value is string | null {
  return value === null || isNonEmptyString(value);
}

export function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

export function isFiniteNonNegativeNumber(value: unknown): value is number {
  return isFiniteNumber(value) && value >= 0;
}

export function isFiniteRangeNumber(value: unknown, min: number, max: number): value is number {
  return isFiniteNumber(value) && value >= min && value <= max;
}

export function isNullableFiniteNonNegativeNumber(value: unknown): value is number | null {
  return value === null || isFiniteNonNegativeNumber(value);
}

export function isStringInSet<TValue extends string>(
  value: unknown,
  allowed: readonly TValue[],
): value is TValue {
  return typeof value === 'string' && allowed.includes(value as TValue);
}

export function isPlayerErrorCategory(value: unknown): value is PlayerErrorCategory {
  return isStringInSet(value, PLAYER_ERROR_CATEGORIES);
}

export function isPlayerRendererIntent(
  value: unknown,
  commandMap: Readonly<Record<PlayerRendererIntent, string>>,
): value is PlayerRendererIntent {
  return typeof value === 'string' && Object.hasOwn(commandMap, value);
}

export function assertNever(value: never): never {
  throw new Error(`Unhandled player error category: ${String(value)}`);
}

export function hasForbiddenPrivilegedField(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some((item) => hasForbiddenPrivilegedField(item));
  }
  if (!isRecord(value)) {
    return false;
  }
  for (const [key, child] of Object.entries(value)) {
    if (
      PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS.includes(
        key as (typeof PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS)[number],
      ) ||
      hasForbiddenPrivilegedField(child)
    ) {
      return true;
    }
  }
  return false;
}

export function readRequestId(value: UnknownRecord): PlayerRequestId | undefined {
  return isNonEmptyString(value.requestId) ? value.requestId : undefined;
}

export function sanitizeCounts(value: UnknownRecord): Readonly<Record<string, number>> | undefined {
  const counts: Record<string, number> = {};
  for (const [key, count] of Object.entries(value)) {
    if (isNonEmptyString(key) && isFiniteNonNegativeNumber(count)) {
      counts[key] = count;
    }
  }
  return Object.keys(counts).length === 0 ? undefined : counts;
}

export function validateTrackIds(value: unknown): readonly PlayerTrackId[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }
  const ids: PlayerTrackId[] = [];
  for (const item of value) {
    if (!isNonEmptyString(item)) {
      return undefined;
    }
    ids.push(item);
  }
  return ids;
}

export function validateMediaDiagnostic(value: unknown): PlayerRendererSafeDiagnostic['media'] | undefined {
  if (!isRecord(value) || !isNonEmptyString(value.id) || !isNonEmptyString(value.title)) {
    return undefined;
  }
  return { id: value.id, title: value.title };
}
