import {
  CHANNEL_BUILDER_MAX_EXISTING_LINEUP,
  CHANNEL_BUILDER_STRATEGY_KEYS,
} from './constants.js';
import type {
  ChannelBuilderChannelProvenanceV1,
  ChannelBuilderPersistedStateV1,
} from './types.js';

const profileBindingPattern = /^profile-binding:[a-f0-9]{64}$/u;
const serverBindingPattern = /^server-binding:[a-f0-9]{64}$/u;
const librarySetBindingPattern = /^library-set-binding:[a-f0-9]{64}$/u;
const sourceIdentityPattern = /^source:[a-f0-9]{64}$/u;
const candidateIdentityPattern = /^candidate-identity:[a-f0-9]{64}$/u;

export function isChannelBuilderChannelProvenanceV1(
  value: unknown,
): value is ChannelBuilderChannelProvenanceV1 {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record);
  return (
    keys.length === 7 &&
    [
      'schemaVersion',
      'identityVersion',
      'profileBinding',
      'serverBinding',
      'librarySetBinding',
      'sourceIdentity',
      'candidateIdentity',
    ].every((key) => keys.includes(key)) &&
    record.schemaVersion === 1 &&
    record.identityVersion === 1 &&
    typeof record.profileBinding === 'string' &&
    profileBindingPattern.test(record.profileBinding) &&
    typeof record.serverBinding === 'string' &&
    serverBindingPattern.test(record.serverBinding) &&
    typeof record.librarySetBinding === 'string' &&
    librarySetBindingPattern.test(record.librarySetBinding) &&
    typeof record.sourceIdentity === 'string' &&
    sourceIdentityPattern.test(record.sourceIdentity) &&
    typeof record.candidateIdentity === 'string' &&
    candidateIdentityPattern.test(record.candidateIdentity)
  );
}

export function isChannelBuilderPersistedStateV1(
  value: unknown,
): value is ChannelBuilderPersistedStateV1 {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record);
  if (
    keys.length !== 7 ||
    ![
      'schemaVersion',
      'normalizedConfig',
      'completedAtMs',
      'profileBinding',
      'serverBinding',
      'librarySetBinding',
      'channelProvenance',
    ].every((key) => keys.includes(key)) ||
    record.schemaVersion !== 1 ||
    !Number.isSafeInteger(record.completedAtMs) ||
    (record.completedAtMs as number) < 0 ||
    typeof record.profileBinding !== 'string' ||
    !profileBindingPattern.test(record.profileBinding) ||
    typeof record.serverBinding !== 'string' ||
    !serverBindingPattern.test(record.serverBinding) ||
    typeof record.librarySetBinding !== 'string' ||
    !librarySetBindingPattern.test(record.librarySetBinding) ||
    record.channelProvenance === null ||
    typeof record.channelProvenance !== 'object' ||
    Array.isArray(record.channelProvenance)
  ) {
    return false;
  }
  const config = record.normalizedConfig as Record<string, unknown> | null;
  if (
    config === null ||
    typeof config !== 'object' ||
    !CHANNEL_BUILDER_STRATEGY_KEYS.every(
      (key) =>
        typeof (config.strategyConfig as Record<string, unknown> | undefined)?.[key] ===
        'object',
    )
  ) {
    return false;
  }
  const provenance = record.channelProvenance as Record<string, unknown>;
  const provenanceKeys = Object.keys(provenance);
  return (
    provenanceKeys.length <= CHANNEL_BUILDER_MAX_EXISTING_LINEUP &&
    provenanceKeys.every((key) => isChannelBuilderChannelProvenanceV1(provenance[key]))
  );
}
