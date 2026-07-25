import {
  CHANNEL_BUILDER_MAX_EXISTING_LINEUP,
} from './constants.js';
import type {
  ChannelBuilderChannelProvenanceV1,
  ChannelBuilderPersistedStateV1,
} from './types.js';
import { normalizeChannelSetupConfig } from './config.js';
import { cloneOwnEnumerableStringRecordWithNullPrototype } from '../channel/channelDomainClone.js';

const profileBindingPattern = /^profile-binding:[a-f0-9]{64}$/u;
const serverBindingPattern = /^server-binding:[a-f0-9]{64}$/u;
const librarySetBindingPattern = /^library-set-binding:[a-f0-9]{64}$/u;
const sourceIdentityPattern = /^source:[a-f0-9]{64}$/u;
const candidateIdentityPattern = /^candidate-identity:[a-f0-9]{64}$/u;

export function isChannelBuilderChannelProvenanceV1(
  value: unknown,
): value is ChannelBuilderChannelProvenanceV1 {
  if (!isOwnDataRecord(value) || !hasOnlyEnumerableStringDataProperties(value)) return false;
  const record = value;
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
  const normalized = normalizeChannelBuilderPersistedStateV1(value);
  return normalized.result !== null && !normalized.didMutate;
}

export function normalizeChannelBuilderPersistedStateV1(
  value: unknown,
  channelIds?: ReadonlySet<string>,
): Readonly<{
  result: ChannelBuilderPersistedStateV1 | null;
  didMutate: boolean;
}> {
  if (!isOwnDataRecord(value) || !hasOnlyEnumerableStringDataProperties(value)) {
    return { result: null, didMutate: false };
  }
  const record = value;
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
    record.channelProvenance === null
  ) {
    return { result: null, didMutate: false };
  }
  const configRecord = record.normalizedConfig;
  if (!isOwnDataRecord(configRecord) || !isDescriptorSafeDataTree(configRecord)) {
    return { result: null, didMutate: false };
  }
  const normalizedConfig = normalizeChannelSetupConfig(configRecord, {
    serverId: configRecord.serverId as string,
    selectedLibraryIds: configRecord.selectedLibraryIds as readonly string[],
  });
  if (!normalizedConfig.ok) return { result: null, didMutate: false };
  const provenance = normalizeProvenance(record.channelProvenance, channelIds);
  const result: ChannelBuilderPersistedStateV1 = {
    schemaVersion: 1,
    normalizedConfig: normalizedConfig.config,
    completedAtMs: record.completedAtMs as number,
    profileBinding: record.profileBinding as ChannelBuilderPersistedStateV1['profileBinding'],
    serverBinding: record.serverBinding as ChannelBuilderPersistedStateV1['serverBinding'],
    librarySetBinding: record.librarySetBinding as ChannelBuilderPersistedStateV1['librarySetBinding'],
    channelProvenance: provenance.result,
  };
  return {
    result,
    didMutate:
      provenance.didMutate ||
      JSON.stringify(normalizedConfig.config) !== JSON.stringify(configRecord),
  };
}

function normalizeProvenance(
  value: unknown,
  channelIds?: ReadonlySet<string>,
): Readonly<{
  result: Readonly<Record<string, ChannelBuilderChannelProvenanceV1>>;
  didMutate: boolean;
}> {
  if (!isOwnDataRecord(value) || !hasOnlyEnumerableStringDataProperties(value)) {
    return {
      result: Object.create(null) as Record<string, ChannelBuilderChannelProvenanceV1>,
      didMutate: true,
    };
  }
  const valid = Object.create(null) as Record<string, ChannelBuilderChannelProvenanceV1>;
  let didMutate = false;
  for (const key of Object.keys(value)) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    const marker = descriptor && 'value' in descriptor ? descriptor.value : undefined;
    if (
      Object.keys(valid).length >= CHANNEL_BUILDER_MAX_EXISTING_LINEUP ||
      (channelIds !== undefined && !channelIds.has(key)) ||
      !isChannelBuilderChannelProvenanceV1(marker)
    ) {
      didMutate = true;
      continue;
    }
    Object.defineProperty(valid, key, {
      value: cloneMarker(marker),
      enumerable: true,
      writable: true,
      configurable: true,
    });
  }
  return { result: valid, didMutate };
}

function cloneMarker(
  marker: ChannelBuilderChannelProvenanceV1,
): ChannelBuilderChannelProvenanceV1 {
  return {
    schemaVersion: 1,
    identityVersion: 1,
    profileBinding: marker.profileBinding,
    serverBinding: marker.serverBinding,
    librarySetBinding: marker.librarySetBinding,
    sourceIdentity: marker.sourceIdentity,
    candidateIdentity: marker.candidateIdentity,
  };
}

function isOwnDataRecord(value: unknown): value is Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function hasOnlyEnumerableStringDataProperties(value: Record<string, unknown>): boolean {
  if (Object.getOwnPropertySymbols(value).length > 0) return false;
  return Reflect.ownKeys(value).every((key) => {
    if (typeof key !== 'string') return false;
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    return descriptor !== undefined && descriptor.enumerable && 'value' in descriptor;
  });
}

function isDescriptorSafeDataTree(value: unknown, seen = new Set<object>()): boolean {
  if (value === null || typeof value !== 'object') return true;
  if (seen.has(value)) return false;
  seen.add(value);
  if (Object.getOwnPropertySymbols(value).length > 0) return false;
  const prototype = Object.getPrototypeOf(value);
  if (!Array.isArray(value) && prototype !== Object.prototype && prototype !== null) {
    return false;
  }
  const keys = Reflect.ownKeys(value);
  if (
    Array.isArray(value) &&
    keys.some((key) => key !== 'length' && typeof key === 'string' && !/^(?:0|[1-9]\d*)$/u.test(key))
  ) {
    return false;
  }
  return keys.every((key) => {
    if (typeof key !== 'string') return false;
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (Array.isArray(value) && key === 'length') {
      return descriptor !== undefined && 'value' in descriptor;
    }
    return (
      descriptor !== undefined &&
      descriptor.enumerable &&
      'value' in descriptor &&
      isDescriptorSafeDataTree(descriptor.value, seen)
    );
  });
}

export function cloneChannelBuilderProvenance(
  provenance: Readonly<Record<string, ChannelBuilderChannelProvenanceV1>>,
): Readonly<Record<string, ChannelBuilderChannelProvenanceV1>> {
  return cloneOwnEnumerableStringRecordWithNullPrototype(
    provenance,
    cloneMarker,
  );
}
