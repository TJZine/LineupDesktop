export const SETTINGS_SCHEMA_VERSION = 3 as const;

export const AUDIO_OUTPUT_DEVICE_ID_PATTERN = /^audio_[A-Za-z0-9_-]{43}$/u;
export const DESKTOP_AUDIO_OUTPUT_MAX_DEVICE_COUNT = 32;
export const DESKTOP_AUDIO_OUTPUT_MAX_LABEL_LENGTH = 80;

export const DESKTOP_AUDIO_OUTPUT_LIST_STATUSES = [
  'ready',
  'partial',
  'unavailable',
] as const;

export const DESKTOP_AUDIO_OUTPUT_LIST_REASONS = [
  'available',
  'platform-unsupported',
  'helper-unavailable',
  'enumeration-failed',
  'device-list-sanitized',
  'device-list-truncated',
] as const;

export interface SharedDesktopAudioOutputList {
  status: (typeof DESKTOP_AUDIO_OUTPUT_LIST_STATUSES)[number];
  reason: (typeof DESKTOP_AUDIO_OUTPUT_LIST_REASONS)[number];
  outputs: Array<
    | { kind: 'system-default'; id: 'system-default'; label: 'System default' }
    | { kind: 'device'; id: string; label: string }
  >;
}

export function isSharedDesktopAudioOutputList(
  value: unknown,
): value is SharedDesktopAudioOutputList {
  if (
    !isPlainRecord(value) ||
    !hasOnlyKeys(value, ['status', 'reason', 'outputs']) ||
    !isDesktopAudioOutputStatusReason(value.status, value.reason) ||
    !Array.isArray(value.outputs) ||
    value.outputs.length < 1 ||
    value.outputs.length > DESKTOP_AUDIO_OUTPUT_MAX_DEVICE_COUNT + 1
  ) {
    return false;
  }

  const [systemRow, ...deviceRows] = value.outputs;
  if (
    !isPlainRecord(systemRow) ||
    !hasOnlyKeys(systemRow, ['kind', 'id', 'label']) ||
    systemRow.kind !== 'system-default' ||
    systemRow.id !== 'system-default' ||
    systemRow.label !== 'System default'
  ) {
    return false;
  }

  const ids = new Set<string>(['system-default']);
  let previous: { label: string; id: string } | null = null;
  for (const row of deviceRows) {
    if (
      !isPlainRecord(row) ||
      !hasOnlyKeys(row, ['kind', 'id', 'label']) ||
      row.kind !== 'device' ||
      typeof row.id !== 'string' ||
      !AUDIO_OUTPUT_DEVICE_ID_PATTERN.test(row.id) ||
      typeof row.label !== 'string' ||
      row.label.length === 0 ||
      row.label !== sanitizeAudioOutputLabel(row.label) ||
      [...row.label].length > DESKTOP_AUDIO_OUTPUT_MAX_LABEL_LENGTH ||
      ids.has(row.id)
    ) {
      return false;
    }
    if (
      previous !== null &&
      (previous.label > row.label ||
        (previous.label === row.label && previous.id >= row.id))
    ) {
      return false;
    }
    ids.add(row.id);
    previous = { label: row.label, id: row.id };
  }

  if (value.status === 'unavailable') return deviceRows.length === 0;
  return value.status !== 'partial' || deviceRows.length > 0;
}

export function isDesktopAudioOutputStatusReason(
  status: unknown,
  reason: unknown,
): boolean {
  if (status === 'ready') return reason === 'available';
  if (status === 'partial') {
    return reason === 'device-list-sanitized' || reason === 'device-list-truncated';
  }
  return status === 'unavailable' &&
    (reason === 'platform-unsupported' ||
      reason === 'helper-unavailable' ||
      reason === 'enumeration-failed');
}

export function sanitizeAudioOutputLabel(value: string): string {
  const normalized = value.normalize('NFKC')
    .replace(/[\p{Cc}\p{Cf}]/gu, ' ')
    .replace(/\s+/gu, ' ')
    .trim();

  return [...normalized]
    .slice(0, DESKTOP_AUDIO_OUTPUT_MAX_LABEL_LENGTH)
    .join('')
    .trim();
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' &&
    value !== null &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function hasOnlyKeys(
  value: Record<string, unknown>,
  requiredKeys: readonly string[],
): boolean {
  return Object.keys(value).length === requiredKeys.length &&
    requiredKeys.every((key) => Object.hasOwn(value, key));
}
