import type {
  ChannelContentSource,
  ContentFilter,
  PlaybackMode,
  SortOrder,
} from '../channel/types.js';
import {
  CHANNEL_BUILDER_MAX_SOURCE_DEPTH,
  CHANNEL_BUILDER_MAX_SOURCE_LEAVES,
  CHANNEL_DOMAIN_FORBIDDEN_KEYS,
} from './constants.js';
import type {
  ChannelBuilderCandidateId,
  ChannelBuilderCandidateIdentity,
  ChannelBuilderContentFilterIdentity,
  ChannelBuilderFacetId,
  ChannelBuilderLibrarySetBinding,
  ChannelBuilderOriginBinding,
  ChannelBuilderPlanIdentity,
  ChannelBuilderProfileBinding,
  ChannelBuilderSafeSourceReference,
  ChannelBuilderServerBinding,
  ChannelBuilderSourceIdentity,
  ChannelBuilderTagSemanticGroupIdentity,
  PersistedStringV1,
} from './types.js';

export type CanonicalJsonValue =
  | null
  | boolean
  | number
  | string
  | CanonicalJsonArray
  | CanonicalJsonObject;
interface CanonicalJsonArray extends ReadonlyArray<CanonicalJsonValue> {}
interface CanonicalJsonObject {
  readonly [key: string]: CanonicalJsonValue;
}

const forbiddenFilterKeys = new Set<string>(CHANNEL_DOMAIN_FORBIDDEN_KEYS);
// Identity inputs exclude ASCII controls and DEL.
// eslint-disable-next-line no-control-regex
const identityInputPattern = /^[^\u0000-\u001f\u007f]{1,512}$/u;

export type ChannelBuilderIncrementalSha256 = Readonly<{
  updateUtf8(value: string): void;
  digestHex(): string;
}>;

export type ChannelBuilderIncrementalSha256Factory =
  () => ChannelBuilderIncrementalSha256;

function compareCodePoints(left: string, right: string): number {
  let leftIndex = 0;
  let rightIndex = 0;
  while (leftIndex < left.length && rightIndex < right.length) {
    const leftPoint = left.codePointAt(leftIndex)!;
    const rightPoint = right.codePointAt(rightIndex)!;
    if (leftPoint !== rightPoint) return leftPoint - rightPoint;
    leftIndex += leftPoint > 0xffff ? 2 : 1;
    rightIndex += rightPoint > 0xffff ? 2 : 1;
  }
  return left.length - leftIndex - (right.length - rightIndex);
}

function isPlainRecord(value: object): value is Record<string, unknown> {
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

export function canonicalJsonV1(value: unknown): string {
  return serializeCanonicalValue(value, new Set());
}

function serializeCanonicalValue(
  value: unknown,
  seen: Set<object>,
): string {
  if (value === null) return 'null';
  if (typeof value === 'string') return JSON.stringify(value.normalize('NFC'));
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new TypeError('Identity numbers must be finite.');
    return JSON.stringify(Object.is(value, -0) ? 0 : value);
  }
  if (
    typeof value === 'undefined' ||
    typeof value === 'symbol' ||
    typeof value === 'bigint' ||
    typeof value === 'function'
  ) {
    throw new TypeError('Unsupported Identity V1 value.');
  }
  if (seen.has(value)) throw new TypeError('Identity V1 values cannot be cyclic.');
  seen.add(value);
  try {
    if (Array.isArray(value)) {
      const serialized: string[] = [];
      for (let index = 0; index < value.length; index += 1) {
        if (!Object.prototype.hasOwnProperty.call(value, index)) {
          throw new TypeError('Identity V1 arrays cannot be sparse.');
        }
        serialized.push(serializeCanonicalValue(value[index], seen));
      }
      return `[${serialized.join(',')}]`;
    }
    if (!isPlainRecord(value)) {
      throw new TypeError('Identity V1 objects must be plain records.');
    }
    const normalizedKeys = new Map<string, string>();
    for (const rawKey of Object.keys(value)) {
      const normalizedKey = rawKey.normalize('NFC');
      if (normalizedKeys.has(normalizedKey)) {
        throw new TypeError('Identity V1 object keys collide after NFC normalization.');
      }
      normalizedKeys.set(normalizedKey, rawKey);
    }
    const serialized: string[] = [];
    for (const [normalizedKey, rawKey] of [...normalizedKeys.entries()].sort(
      ([left], [right]) => compareCodePoints(left, right),
    )) {
      serialized.push(
        `${JSON.stringify(normalizedKey)}:${serializeCanonicalValue(
          value[rawKey],
          seen,
        )}`,
      );
    }
    return `{${serialized.join(',')}}`;
  } finally {
    seen.delete(value);
  }
}

const sha256Initial = [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c,
  0x1f83d9ab, 0x5be0cd19,
] as const;
const sha256Round = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
] as const;

export function sha256HexV1(value: string): string {
  return channelBuilderIdentityOperations.sha256HexV1(value);
}

class Sha256V1 implements ChannelBuilderIncrementalSha256 {
  private readonly state = new Uint32Array(sha256Initial);
  private readonly buffer = new Uint8Array(64);
  private readonly words = new Uint32Array(16);
  private bufferLength = 0;
  private byteLength = 0;
  private digested = false;

  updateUtf8(value: string): void {
    if (this.digested) throw new TypeError('SHA-256 digest is already finalized.');
    for (let index = 0; index < value.length; index += 1) {
      if (
        this.bufferLength === 0 &&
        index + 64 <= value.length &&
        this.processAsciiBlock(value, index)
      ) {
        this.byteLength += 64;
        index += 63;
        continue;
      }
      const first = value.charCodeAt(index);
      if (first <= 0x7f) {
        this.buffer[this.bufferLength] = first;
        this.bufferLength += 1;
        this.byteLength += 1;
        if (this.bufferLength === 64) {
          this.processBlock();
          this.bufferLength = 0;
        }
        continue;
      }
      let codePoint = first;
      if (
        first >= 0xd800 &&
        first <= 0xdbff &&
        index + 1 < value.length
      ) {
        const second = value.charCodeAt(index + 1);
        if (second >= 0xdc00 && second <= 0xdfff) {
          codePoint =
            0x1_0000 + ((first - 0xd800) << 10) + (second - 0xdc00);
          index += 1;
        }
      }
      if (
        (codePoint >= 0xd800 && codePoint <= 0xdfff)
      ) {
        codePoint = 0xfffd;
      }
      if (codePoint <= 0x7f) {
        this.updateByte(codePoint);
      } else if (codePoint <= 0x7ff) {
        this.updateByte(0xc0 | (codePoint >>> 6));
        this.updateByte(0x80 | (codePoint & 0x3f));
      } else if (codePoint <= 0xffff) {
        this.updateByte(0xe0 | (codePoint >>> 12));
        this.updateByte(0x80 | ((codePoint >>> 6) & 0x3f));
        this.updateByte(0x80 | (codePoint & 0x3f));
      } else {
        this.updateByte(0xf0 | (codePoint >>> 18));
        this.updateByte(0x80 | ((codePoint >>> 12) & 0x3f));
        this.updateByte(0x80 | ((codePoint >>> 6) & 0x3f));
        this.updateByte(0x80 | (codePoint & 0x3f));
      }
    }
  }

  digestHex(): string {
    if (this.digested) throw new TypeError('SHA-256 digest is already finalized.');
    this.digested = true;
    const bitLength = this.byteLength * 8;
    this.appendPaddingByte(0x80);
    while (this.bufferLength !== 56) this.appendPaddingByte(0);
    const high = Math.floor(bitLength / 0x1_0000_0000);
    const low = bitLength >>> 0;
    for (let shift = 24; shift >= 0; shift -= 8) {
      this.appendPaddingByte((high >>> shift) & 0xff);
    }
    for (let shift = 24; shift >= 0; shift -= 8) {
      this.appendPaddingByte((low >>> shift) & 0xff);
    }
    return [...this.state]
      .map((word) => word.toString(16).padStart(8, '0'))
      .join('');
  }

  private updateByte(value: number): void {
    this.buffer[this.bufferLength] = value;
    this.bufferLength += 1;
    this.byteLength += 1;
    if (this.bufferLength === 64) {
      this.processBlock();
      this.bufferLength = 0;
    }
  }

  private appendPaddingByte(value: number): void {
    this.buffer[this.bufferLength] = value;
    this.bufferLength += 1;
    if (this.bufferLength === 64) {
      this.processBlock();
      this.bufferLength = 0;
    }
  }

  private processBlock(): void {
    const words = this.words;
    for (let index = 0; index < 16; index += 1) {
      const position = index * 4;
      words[index] =
        ((this.buffer[position]! << 24) |
          (this.buffer[position + 1]! << 16) |
          (this.buffer[position + 2]! << 8) |
          this.buffer[position + 3]!) >>>
        0;
    }
    this.compressWords();
  }

  private processAsciiBlock(value: string, offset: number): boolean {
    const words = this.words;
    for (let index = 0; index < 16; index += 1) {
      const position = offset + index * 4;
      const first = value.charCodeAt(position);
      const second = value.charCodeAt(position + 1);
      const third = value.charCodeAt(position + 2);
      const fourth = value.charCodeAt(position + 3);
      if ((first | second | third | fourth) > 0x7f) return false;
      words[index] =
        ((first << 24) | (second << 16) | (third << 8) | fourth) >>> 0;
    }
    this.compressWords();
    return true;
  }

  private compressWords(): void {
    const words = this.words;
    let a = this.state[0]!;
    let b = this.state[1]!;
    let c = this.state[2]!;
    let d = this.state[3]!;
    let e = this.state[4]!;
    let f = this.state[5]!;
    let g = this.state[6]!;
    let h = this.state[7]!;
    for (let index = 0; index < 16; index += 1) {
      const word = words[index]!;
      const upper1 =
        ((e >>> 6) | (e << 26)) ^
        ((e >>> 11) | (e << 21)) ^
        ((e >>> 25) | (e << 7));
      const choice = (e & f) ^ (~e & g);
      const temporary1 =
        (h + upper1 + choice + sha256Round[index]! + word) >>> 0;
      const upper0 =
        ((a >>> 2) | (a << 30)) ^
        ((a >>> 13) | (a << 19)) ^
        ((a >>> 22) | (a << 10));
      const majority = (a & b) ^ (a & c) ^ (b & c);
      const temporary2 = (upper0 + majority) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + temporary1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temporary1 + temporary2) >>> 0;
    }
    for (let index = 16; index < 64; index += 1) {
      const wordIndex = index & 15;
      const previous15 = words[(wordIndex + 1) & 15]!;
      const previous2 = words[(wordIndex + 14) & 15]!;
      const sigma0 =
        ((previous15 >>> 7) | (previous15 << 25)) ^
        ((previous15 >>> 18) | (previous15 << 14)) ^
        (previous15 >>> 3);
      const sigma1 =
        ((previous2 >>> 17) | (previous2 << 15)) ^
        ((previous2 >>> 19) | (previous2 << 13)) ^
        (previous2 >>> 10);
      const word =
        (words[wordIndex]! +
          sigma0 +
          words[(wordIndex + 9) & 15]! +
          sigma1) >>>
        0;
      words[wordIndex] = word;
      const upper1 =
        ((e >>> 6) | (e << 26)) ^
        ((e >>> 11) | (e << 21)) ^
        ((e >>> 25) | (e << 7));
      const choice = (e & f) ^ (~e & g);
      const temporary1 =
        (h + upper1 + choice + sha256Round[index]! + word) >>> 0;
      const upper0 =
        ((a >>> 2) | (a << 30)) ^
        ((a >>> 13) | (a << 19)) ^
        ((a >>> 22) | (a << 10));
      const majority = (a & b) ^ (a & c) ^ (b & c);
      const temporary2 = (upper0 + majority) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + temporary1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temporary1 + temporary2) >>> 0;
    }
    this.state[0] = (this.state[0]! + a) >>> 0;
    this.state[1] = (this.state[1]! + b) >>> 0;
    this.state[2] = (this.state[2]! + c) >>> 0;
    this.state[3] = (this.state[3]! + d) >>> 0;
    this.state[4] = (this.state[4]! + e) >>> 0;
    this.state[5] = (this.state[5]! + f) >>> 0;
    this.state[6] = (this.state[6]! + g) >>> 0;
    this.state[7] = (this.state[7]! + h) >>> 0;
  }
}

function updateCanonicalJsonV1(
  hasher: ChannelBuilderIncrementalSha256,
  value: unknown,
): void {
  let buffered = '';
  const shapeCache: CanonicalShapeCacheNode = { children: new Map() };
  const flush = (): void => {
    if (buffered.length === 0) return;
    hasher.updateUtf8(buffered);
    buffered = '';
  };
  const write = (chunk: string): void => {
    buffered += chunk;
    if (buffered.length >= 65_536) flush();
  };
  writeCanonicalValue(value, new Set(), shapeCache, write);
  flush();
}

function writeCanonicalValue(
  value: unknown,
  seen: Set<object>,
  shapeCache: CanonicalShapeCacheNode,
  write: (chunk: string) => void,
): void {
  if (value === null) {
    write('null');
    return;
  }
  if (typeof value === 'string') {
    write(JSON.stringify(value.normalize('NFC')));
    return;
  }
  if (typeof value === 'boolean') {
    write(value ? 'true' : 'false');
    return;
  }
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      throw new TypeError('Identity numbers must be finite.');
    }
    write(JSON.stringify(Object.is(value, -0) ? 0 : value));
    return;
  }
  if (
    typeof value === 'undefined' ||
    typeof value === 'symbol' ||
    typeof value === 'bigint' ||
    typeof value === 'function'
  ) {
    throw new TypeError('Unsupported Identity V1 value.');
  }
  if (seen.has(value)) {
    throw new TypeError('Identity V1 values cannot be cyclic.');
  }
  seen.add(value);
  try {
    if (Array.isArray(value)) {
      write('[');
      for (let index = 0; index < value.length; index += 1) {
        if (!Object.prototype.hasOwnProperty.call(value, index)) {
          throw new TypeError('Identity V1 arrays cannot be sparse.');
        }
        if (index > 0) write(',');
        writeCanonicalValue(value[index], seen, shapeCache, write);
      }
      write(']');
      return;
    }
    if (!isPlainRecord(value)) {
      throw new TypeError('Identity V1 objects must be plain records.');
    }
    const rawKeys = Object.keys(value);
    let cacheNode = shapeCache;
    for (const rawKey of rawKeys) {
      let child = cacheNode.children.get(rawKey);
      if (child === undefined) {
        child = { children: new Map() };
        cacheNode.children.set(rawKey, child);
      }
      cacheNode = child;
    }
    let shape = cacheNode.shape;
    if (shape === undefined) {
      const normalizedKeys = new Map<string, string>();
      for (const rawKey of rawKeys) {
        const normalizedKey = rawKey.normalize('NFC');
        if (normalizedKeys.has(normalizedKey)) {
          throw new TypeError(
            'Identity V1 object keys collide after NFC normalization.',
          );
        }
        normalizedKeys.set(normalizedKey, rawKey);
      }
      shape = {
        entries: [...normalizedKeys.entries()]
          .sort(([left], [right]) => compareCodePoints(left, right))
          .map(([normalizedKey, rawKey], index) => [
            `${index > 0 ? ',' : ''}${JSON.stringify(normalizedKey)}:`,
            rawKey,
          ]),
      };
      cacheNode.shape = shape;
    }
    write('{');
    for (let index = 0; index < shape.entries.length; index += 1) {
      const [prefix, rawKey] = shape.entries[index]!;
      write(prefix);
      writeCanonicalValue(value[rawKey], seen, shapeCache, write);
    }
    write('}');
  } finally {
    seen.delete(value);
  }
}

type CanonicalObjectShape = Readonly<{
  entries: readonly (readonly [string, string])[];
}>;

type CanonicalShapeCacheNode = {
  children: Map<string, CanonicalShapeCacheNode>;
  shape?: CanonicalObjectShape;
};

function identity<T extends string>(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  prefix: string,
  domain: string,
  preimage: CanonicalJsonValue,
): T {
  return identityBytes(createSha256, prefix, domain, canonicalJsonV1(preimage));
}

function identityBytes<T extends string>(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  prefix: string,
  domain: string,
  bytes: string,
): T {
  const hasher = createSha256();
  hasher.updateUtf8(domain);
  hasher.updateUtf8(bytes);
  return `${prefix}${hasher.digestHex()}` as T;
}

function normalizedIdentityInput(raw: string): string {
  const normalized = raw.normalize('NFC').trim();
  if (!identityInputPattern.test(normalized)) {
    throw new TypeError('Invalid Identity V1 string input.');
  }
  return normalized;
}

export function createPersistedStringV1(raw: string): PersistedStringV1 {
  const utf16: number[] = [];
  for (let index = 0; index < raw.length; index += 1) utf16.push(raw.charCodeAt(index));
  return { nfc: raw.normalize('NFC'), utf16 };
}

export function createProfileBinding(activeProfileId: string): ChannelBuilderProfileBinding {
  return channelBuilderIdentityOperations.createProfileBinding(activeProfileId);
}

function createProfileBindingWithSha256(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  activeProfileId: string,
): ChannelBuilderProfileBinding {
  return identity(
    createSha256,
    'profile-binding:',
    'lineup-builder/profile-binding/v1:',
    { activeProfileId: normalizedIdentityInput(activeProfileId) },
  );
}

export function createServerBinding(serverId: string): ChannelBuilderServerBinding {
  return channelBuilderIdentityOperations.createServerBinding(serverId);
}

function createServerBindingWithSha256(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  serverId: string,
): ChannelBuilderServerBinding {
  return identity(
    createSha256,
    'server-binding:',
    'lineup-builder/server-binding/v1:',
    { serverId: normalizedIdentityInput(serverId) },
  );
}

export function createLibrarySetBinding(
  libraries: readonly Readonly<{ libraryId: string; libraryUuid: string }>[],
): ChannelBuilderLibrarySetBinding {
  return channelBuilderIdentityOperations.createLibrarySetBinding(libraries);
}

function createLibrarySetBindingWithSha256(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  libraries: readonly Readonly<{ libraryId: string; libraryUuid: string }>[],
): ChannelBuilderLibrarySetBinding {
  if (libraries.length < 1) throw new TypeError('Library binding requires a library.');
  const normalized = libraries.map(({ libraryId, libraryUuid }) => ({
    libraryId: normalizedIdentityInput(libraryId),
    libraryUuid: normalizedIdentityInput(libraryUuid),
  }));
  const libraryIds = new Set(normalized.map(({ libraryId }) => libraryId));
  const pairs = new Set(
    normalized.map(({ libraryId, libraryUuid }) => `${libraryId}\u0000${libraryUuid}`),
  );
  if (libraryIds.size !== normalized.length || pairs.size !== normalized.length) {
    throw new TypeError('Library binding entries must be unique.');
  }
  normalized.sort((left, right) => {
    const id = compareCodePoints(left.libraryId, right.libraryId);
    return id !== 0 ? id : compareCodePoints(left.libraryUuid, right.libraryUuid);
  });
  return identity(
    createSha256,
    'library-set-binding:',
    'lineup-builder/library-set-binding/v1:',
    { libraries: normalized },
  );
}

type FacetFamily =
  | 'library'
  | 'playlist'
  | 'collection'
  | 'genre'
  | 'director'
  | 'year'
  | 'studio'
  | 'actor'
  | 'recently-added';

export function createFacetIdentity(
  family: FacetFamily,
  preimage: Readonly<Record<string, CanonicalJsonValue>>,
): ChannelBuilderFacetId {
  return channelBuilderIdentityOperations.createFacetIdentity(family, preimage);
}

function createFacetIdentityWithSha256(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  family: FacetFamily,
  preimage: Readonly<Record<string, CanonicalJsonValue>>,
): ChannelBuilderFacetId {
  const commonValid =
    isPlainRecord(preimage) &&
    preimage.family === family &&
    typeof preimage.profileBinding === 'string' &&
    /^profile-binding:[a-f0-9]{64}$/u.test(preimage.profileBinding) &&
    typeof preimage.serverBinding === 'string' &&
    /^server-binding:[a-f0-9]{64}$/u.test(preimage.serverBinding);
  if (!commonValid) throw new TypeError('Invalid facet identity input.');
  let normalizedPreimage: CanonicalJsonObject;
  if (family === 'library') {
    if (
      !hasExactOwnKeys(preimage, [
        'profileBinding',
        'serverBinding',
        'family',
        'libraryId',
        'libraryUuid',
        'libraryType',
      ]) ||
      typeof preimage.libraryId !== 'string' ||
      typeof preimage.libraryUuid !== 'string' ||
      !['movie', 'show'].includes(String(preimage.libraryType))
    ) throw new TypeError('Invalid facet identity input.');
    normalizedPreimage = {
      profileBinding: preimage.profileBinding,
      serverBinding: preimage.serverBinding,
      family,
      libraryId: normalizedIdentityInput(preimage.libraryId),
      libraryUuid: normalizedIdentityInput(preimage.libraryUuid),
      libraryType: preimage.libraryType,
    };
  } else if (family === 'playlist') {
    if (
      !hasExactOwnKeys(preimage, [
        'profileBinding',
        'serverBinding',
        'family',
        'libraryId',
        'libraryUuid',
        'ratingKey',
        'key',
      ]) ||
      preimage.libraryId !== null ||
      preimage.libraryUuid !== null ||
      typeof preimage.ratingKey !== 'string' ||
      typeof preimage.key !== 'string'
    ) throw new TypeError('Invalid facet identity input.');
    normalizedPreimage = {
      profileBinding: preimage.profileBinding,
      serverBinding: preimage.serverBinding,
      family,
      libraryId: null,
      libraryUuid: null,
      ratingKey: normalizedIdentityInput(preimage.ratingKey),
      key: normalizedIdentityInput(preimage.key),
    };
  } else if (family === 'collection') {
    if (
      !hasExactOwnKeys(preimage, [
        'profileBinding',
        'serverBinding',
        'family',
        'libraryId',
        'libraryUuid',
        'ratingKey',
        'key',
      ]) ||
      typeof preimage.libraryId !== 'string' ||
      typeof preimage.libraryUuid !== 'string' ||
      typeof preimage.ratingKey !== 'string' ||
      typeof preimage.key !== 'string'
    ) throw new TypeError('Invalid facet identity input.');
    normalizedPreimage = {
      profileBinding: preimage.profileBinding,
      serverBinding: preimage.serverBinding,
      family,
      libraryId: normalizedIdentityInput(preimage.libraryId),
      libraryUuid: normalizedIdentityInput(preimage.libraryUuid),
      ratingKey: normalizedIdentityInput(preimage.ratingKey),
      key: normalizedIdentityInput(preimage.key),
    };
  } else if (family === 'recently-added') {
    if (
      !hasExactOwnKeys(preimage, [
        'profileBinding',
        'serverBinding',
        'family',
        'libraryId',
        'libraryUuid',
        'libraryType',
      ]) ||
      typeof preimage.libraryId !== 'string' ||
      typeof preimage.libraryUuid !== 'string' ||
      !['movie', 'show'].includes(String(preimage.libraryType))
    ) throw new TypeError('Invalid facet identity input.');
    normalizedPreimage = {
      profileBinding: preimage.profileBinding,
      serverBinding: preimage.serverBinding,
      family,
      libraryId: normalizedIdentityInput(preimage.libraryId),
      libraryUuid: normalizedIdentityInput(preimage.libraryUuid),
      libraryType: preimage.libraryType,
    };
  } else {
    if (
      !hasExactOwnKeys(preimage, [
        'profileBinding',
        'serverBinding',
        'family',
        'libraryId',
        'libraryUuid',
        'key',
        'tagValue',
        'fastKey',
      ]) ||
      typeof preimage.libraryId !== 'string' ||
      typeof preimage.libraryUuid !== 'string' ||
      typeof preimage.key !== 'string' ||
      typeof preimage.tagValue !== 'string' ||
      (preimage.fastKey !== null && typeof preimage.fastKey !== 'string')
    ) throw new TypeError('Invalid facet identity input.');
    normalizedPreimage = {
      profileBinding: preimage.profileBinding,
      serverBinding: preimage.serverBinding,
      family,
      libraryId: normalizedIdentityInput(preimage.libraryId),
      libraryUuid: normalizedIdentityInput(preimage.libraryUuid),
      key: normalizedIdentityInput(preimage.key),
      tagValue: normalizedIdentityInput(preimage.tagValue),
      fastKey:
        preimage.fastKey === null ? null : preimage.fastKey.normalize('NFC'),
    };
  }
  return identity(
    createSha256,
    `${family}:`,
    `lineup-builder/facet/${family}/v1:`,
    normalizedPreimage,
  );
}

function canonicalLibraryFilter(
  filter: Record<string, string | number> | undefined,
): readonly CanonicalJsonValue[] | null {
  if (filter === undefined) return null;
  if (filter === null || typeof filter !== 'object' || Array.isArray(filter)) {
    throw new TypeError('Invalid library filter.');
  }
  const entries = Object.entries(filter).map(([key, value]) => {
    if (forbiddenFilterKeys.has(key) || !['string', 'number'].includes(typeof value)) {
      throw new TypeError('Invalid library filter entry.');
    }
    if (typeof value === 'number' && !Number.isFinite(value)) {
      throw new TypeError('Invalid library filter number.');
    }
    return {
      keyNfc: key.normalize('NFC'),
      keyUtf16: createPersistedStringV1(key).utf16,
      value: typeof value === 'string' ? value.normalize('NFC') : value,
    };
  });
  entries.sort((left, right) => {
    const nfc = compareCodePoints(left.keyNfc, right.keyNfc);
    if (nfc !== 0) return nfc;
    const length = Math.min(left.keyUtf16.length, right.keyUtf16.length);
    for (let index = 0; index < length; index += 1) {
      if (left.keyUtf16[index] !== right.keyUtf16[index]) {
        return left.keyUtf16[index]! - right.keyUtf16[index]!;
      }
    }
    return left.keyUtf16.length - right.keyUtf16.length;
  });
  return entries;
}

type SourceTreeTraversal = { leafCount: number };

export function createSourceIdentity(source: ChannelContentSource): ChannelBuilderSourceIdentity {
  return channelBuilderIdentityOperations.createSourceIdentity(source);
}

function createSourceIdentityWithSha256(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  source: ChannelContentSource,
): ChannelBuilderSourceIdentity {
  return createSourceIdentityAtDepth(createSha256, source, 1, { leafCount: 0 });
}

function createSourceIdentityAtDepth(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  source: ChannelContentSource,
  depth: number,
  traversal: SourceTreeTraversal,
): ChannelBuilderSourceIdentity {
  if (depth > CHANNEL_BUILDER_MAX_SOURCE_DEPTH) {
    throw new TypeError('Invalid source identity input.');
  }
  if (source === null || typeof source !== 'object' || !isPlainRecord(source)) {
    throw new TypeError('Invalid source identity input.');
  }
  switch (source.type) {
    case 'library': {
      const expectedKeys = source.libraryFilter === undefined
        ? ['type', 'libraryId', 'libraryType', 'includeWatched']
        : ['type', 'libraryId', 'libraryType', 'includeWatched', 'libraryFilter'];
      if (
        !hasExactOwnKeys(source, expectedKeys) ||
        !['movie', 'show'].includes(source.libraryType) ||
        typeof source.includeWatched !== 'boolean'
      ) {
        throw new TypeError('Invalid source identity input.');
      }
      addSourceLeaves(traversal, 1);
      return identity(createSha256, 'source:', 'lineup-builder/source/library/v1:', {
        type: 'library',
        libraryId: normalizedIdentityInput(source.libraryId),
        libraryType: source.libraryType,
        includeWatched: source.includeWatched,
        libraryFilter: canonicalLibraryFilter(source.libraryFilter),
      });
    }
    case 'collection':
      if (
        !hasExactOwnKeys(source, ['type', 'collectionKey', 'collectionName']) ||
        typeof source.collectionName !== 'string'
      ) {
        throw new TypeError('Invalid source identity input.');
      }
      addSourceLeaves(traversal, 1);
      return identity(createSha256, 'source:', 'lineup-builder/source/collection/v1:', {
        type: 'collection',
        collectionKey: normalizedIdentityInput(source.collectionKey),
      });
    case 'show': {
      const expectedKeys = source.seasonFilter === undefined
        ? ['type', 'showKey', 'showName']
        : ['type', 'showKey', 'showName', 'seasonFilter'];
      if (
        !hasExactOwnKeys(source, expectedKeys) ||
        typeof source.showName !== 'string' ||
        (source.seasonFilter !== undefined && !Array.isArray(source.seasonFilter))
      ) {
        throw new TypeError('Invalid source identity input.');
      }
      const seasons = [...new Set(source.seasonFilter ?? [])].sort((left, right) => left - right);
      if (!seasons.every((value) => Number.isSafeInteger(value) && value > 0)) {
        throw new TypeError('Invalid show season filter.');
      }
      addSourceLeaves(traversal, 1);
      return identity(createSha256, 'source:', 'lineup-builder/source/show/v1:', {
        type: 'show',
        showKey: normalizedIdentityInput(source.showKey),
        seasonFilter: seasons,
      });
    }
    case 'playlist':
      if (
        !hasExactOwnKeys(source, ['type', 'playlistKey', 'playlistName']) ||
        typeof source.playlistName !== 'string'
      ) {
        throw new TypeError('Invalid source identity input.');
      }
      addSourceLeaves(traversal, 1);
      return identity(createSha256, 'source:', 'lineup-builder/source/playlist/v1:', {
        type: 'playlist',
        playlistKey: normalizedIdentityInput(source.playlistKey),
      });
    case 'manual': {
      if (
        !hasExactOwnKeys(source, ['type', 'items']) ||
        !Array.isArray(source.items) ||
        source.items.length < 1 ||
        source.items.length > CHANNEL_BUILDER_MAX_SOURCE_LEAVES
      ) {
        throw new TypeError('Invalid manual source.');
      }
      if (depth + 1 > CHANNEL_BUILDER_MAX_SOURCE_DEPTH) {
        throw new TypeError('Invalid manual source.');
      }
      addSourceLeaves(traversal, source.items.length);
      const items = source.items.map((item) => {
        if (
          item === null ||
          typeof item !== 'object' ||
          !isPlainRecord(item) ||
          !hasExactOwnKeys(item, ['ratingKey', 'title', 'durationMs']) ||
          typeof item.ratingKey !== 'string' ||
          typeof item.title !== 'string'
        ) {
          throw new TypeError('Invalid manual source.');
        }
        return identity<string>(
          createSha256,
          'source:',
          'lineup-builder/source/manual-item/v1:',
          {
            ratingKey: normalizedIdentityInput(item.ratingKey),
            title: item.title.normalize('NFC'),
            durationMs: requirePositiveSafeInteger(item.durationMs),
          },
        );
      });
      return identity(createSha256, 'source:', 'lineup-builder/source/manual/v1:', {
        type: 'manual',
        items,
      });
    }
    case 'mixed': {
      if (
        !hasExactOwnKeys(source, ['type', 'sources', 'mixMode']) ||
        !Array.isArray(source.sources) ||
        source.sources.length < 1 ||
        source.sources.length > CHANNEL_BUILDER_MAX_SOURCE_LEAVES ||
        !['sequential', 'interleave'].includes(source.mixMode)
      ) {
        throw new TypeError('Invalid mixed source.');
      }
      return identity(createSha256, 'source:', 'lineup-builder/source/mixed/v1:', {
        type: 'mixed',
        mixMode: source.mixMode,
        sources: source.sources.map((child) =>
          createSourceIdentityAtDepth(createSha256, child, depth + 1, traversal),
        ),
      });
    }
    default:
      throw new TypeError('Invalid source identity input.');
  }
}

function addSourceLeaves(traversal: SourceTreeTraversal, count: number): void {
  traversal.leafCount += count;
  if (traversal.leafCount > CHANNEL_BUILDER_MAX_SOURCE_LEAVES) {
    throw new TypeError('Invalid source identity input.');
  }
}

export function createMixedSourceIdentity(
  mixMode: 'sequential' | 'interleave',
  sources: readonly ChannelBuilderSourceIdentity[],
): ChannelBuilderSourceIdentity {
  return channelBuilderIdentityOperations.createMixedSourceIdentity(mixMode, sources);
}

function createMixedSourceIdentityWithSha256(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  mixMode: 'sequential' | 'interleave',
  sources: readonly ChannelBuilderSourceIdentity[],
): ChannelBuilderSourceIdentity {
  if (
    !['sequential', 'interleave'].includes(mixMode) ||
    !Array.isArray(sources) ||
    sources.length < 1 ||
    sources.length > CHANNEL_BUILDER_MAX_SOURCE_LEAVES ||
    !sources.every((source) => /^source:[a-f0-9]{64}$/u.test(source))
  ) {
    throw new TypeError('Invalid mixed source identity input.');
  }
  return identity(createSha256, 'source:', 'lineup-builder/source/mixed/v1:', {
    type: 'mixed',
    mixMode,
    sources,
  });
}

function requirePositiveSafeInteger(value: number): number {
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new TypeError('Expected a positive safe integer.');
  }
  return value;
}

const filterFields = new Set([
  'year',
  'rating',
  'contentRating',
  'genre',
  'director',
  'duration',
  'watched',
  'addedAt',
]);
const filterOperators = new Set([
  'eq',
  'neq',
  'gt',
  'gte',
  'lt',
  'lte',
  'contains',
  'notContains',
]);

function hasExactOwnKeys(value: object, expected: readonly string[]): boolean {
  const keys = Object.keys(value);
  return (
    keys.length === expected.length &&
    expected.every((key) => Object.prototype.hasOwnProperty.call(value, key))
  );
}

function normalizedFilters(
  filters: readonly ContentFilter[],
): readonly CanonicalJsonObject[] {
  if (!Array.isArray(filters) || filters.length === 0) {
    throw new TypeError('Invalid content filter identity input.');
  }
  return filters
    .map((filter): CanonicalJsonObject => {
      if (
        filter === null ||
        typeof filter !== 'object' ||
        Array.isArray(filter) ||
        !isPlainRecord(filter) ||
        !hasExactOwnKeys(filter, ['field', 'operator', 'value'])
      ) {
        throw new TypeError('Invalid content filter identity input.');
      }
      const field = filter.field;
      const operator = filter.operator;
      const value = filter.value;
      if (
        typeof field !== 'string' ||
        typeof operator !== 'string' ||
        !filterFields.has(field) ||
        !filterOperators.has(operator)
      ) {
        throw new TypeError('Invalid content filter identity input.');
      }
      let normalizedValue: string | number | boolean;
      if (typeof value === 'string') normalizedValue = value.normalize('NFC');
      else if (typeof value === 'boolean') normalizedValue = value;
      else if (typeof value === 'number' && Number.isFinite(value)) {
        normalizedValue = value;
      } else {
        throw new TypeError('Invalid content filter identity input.');
      }
      return {
        field,
        operator,
        value: normalizedValue,
      };
    })
    .sort((left, right) =>
      compareCodePoints(canonicalJsonV1(left), canonicalJsonV1(right)),
    );
}

export function createTagSemanticGroupIdentity(input: Readonly<{
  profileBinding: ChannelBuilderProfileBinding;
  serverBinding: ChannelBuilderServerBinding;
  family: 'genre' | 'director' | 'studio' | 'actor';
  tagValue: string;
}>): ChannelBuilderTagSemanticGroupIdentity {
  return channelBuilderIdentityOperations.createTagSemanticGroupIdentity(input);
}

function createTagSemanticGroupIdentityWithSha256(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  input: Readonly<{
    profileBinding: ChannelBuilderProfileBinding;
    serverBinding: ChannelBuilderServerBinding;
    family: 'genre' | 'director' | 'studio' | 'actor';
    tagValue: string;
  }>,
): ChannelBuilderTagSemanticGroupIdentity {
  if (
    !isPlainRecord(input) ||
    !hasExactOwnKeys(input, [
      'profileBinding',
      'serverBinding',
      'family',
      'tagValue',
    ]) ||
    !/^profile-binding:[a-f0-9]{64}$/u.test(input.profileBinding) ||
    !/^server-binding:[a-f0-9]{64}$/u.test(input.serverBinding) ||
    !['genre', 'director', 'studio', 'actor'].includes(input.family)
  ) {
    throw new TypeError('Invalid tag semantic group identity input.');
  }
  const groupValue = normalizedIdentityInput(input.tagValue)
    .toLowerCase()
    .normalize('NFC');
  return identity<ChannelBuilderTagSemanticGroupIdentity>(
    createSha256,
    'tag-group:',
    'lineup-builder/tag-group/v1:',
    {
      profileBinding: input.profileBinding,
      serverBinding: input.serverBinding,
      family: input.family,
      groupValue,
    },
  );
}

export function createContentFilterIdentity(input: Readonly<{
  profileBinding: ChannelBuilderProfileBinding;
  serverBinding: ChannelBuilderServerBinding;
  filters: readonly ContentFilter[] | null | undefined;
}>): ChannelBuilderContentFilterIdentity | null {
  return channelBuilderIdentityOperations.createContentFilterIdentity(input);
}

function createContentFilterIdentityWithSha256(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  input: Readonly<{
    profileBinding: ChannelBuilderProfileBinding;
    serverBinding: ChannelBuilderServerBinding;
    filters: readonly ContentFilter[] | null | undefined;
  }>,
): ChannelBuilderContentFilterIdentity | null {
  if (
    !isPlainRecord(input) ||
    !hasExactOwnKeys(input, ['profileBinding', 'serverBinding', 'filters']) ||
    !/^profile-binding:[a-f0-9]{64}$/u.test(input.profileBinding) ||
    !/^server-binding:[a-f0-9]{64}$/u.test(input.serverBinding)
  ) {
    throw new TypeError('Invalid content filter identity input.');
  }
  if (input.filters === null || input.filters === undefined) return null;
  if (input.filters.length === 0) return null;
  return identity<ChannelBuilderContentFilterIdentity>(
    createSha256,
    'content-filters:',
    'lineup-builder/content-filters/v1:',
    {
      profileBinding: input.profileBinding,
      serverBinding: input.serverBinding,
      filters: normalizedFilters(input.filters),
    },
  );
}

function sourceTreeIdentity(source: ChannelBuilderSafeSourceReference): CanonicalJsonValue {
  if (source.kind === 'facet') {
    return { kind: 'facet', sourceIdentity: source.sourceIdentity };
  }
  if (source.kind === 'manual') {
    return {
      kind: 'manual',
      sourceIdentity: source.sourceIdentity,
      items: source.items.map((item) => ({
        kind: 'facet',
        sourceIdentity: item.sourceIdentity,
      })),
    };
  }
  return {
    kind: 'mixed',
    sourceIdentity: source.sourceIdentity,
    mixMode: source.mixMode,
    sources: source.sources.map(sourceTreeIdentity),
  };
}

function isValidSafeSourceReference(
  source: unknown,
  seen: Set<object> = new Set(),
  traversal: Readonly<{ depth: number; state: SourceTreeTraversal }> = {
    depth: 1,
    state: { leafCount: 0 },
  },
): source is ChannelBuilderSafeSourceReference {
  if (
    traversal.depth > CHANNEL_BUILDER_MAX_SOURCE_DEPTH ||
    source === null ||
    typeof source !== 'object' ||
    Array.isArray(source) ||
    !isPlainRecord(source) ||
    seen.has(source) ||
    typeof source.kind !== 'string' ||
    typeof source.sourceIdentity !== 'string' ||
    !/^source:[a-f0-9]{64}$/u.test(source.sourceIdentity)
  ) {
    return false;
  }
  seen.add(source);
  try {
    if (source.kind === 'facet') {
      const valid =
        hasExactOwnKeys(source, ['kind', 'facetId', 'sourceIdentity']) &&
        (source.facetId === null ||
          (typeof source.facetId === 'string' &&
            /^(library|playlist|collection|genre|director|year|studio|actor|recently-added):[a-f0-9]{64}$/u.test(
              source.facetId,
            )));
      if (valid) addSourceLeaves(traversal.state, 1);
      return valid;
    }
    if (source.kind === 'manual') {
      const items = source.items;
      const valid =
        hasExactOwnKeys(source, ['kind', 'sourceIdentity', 'items']) &&
        Array.isArray(items) &&
        items.length >= 1 &&
        items.length <= CHANNEL_BUILDER_MAX_SOURCE_LEAVES &&
        traversal.depth + 1 <= CHANNEL_BUILDER_MAX_SOURCE_DEPTH &&
        items.every(
          (item) =>
            item !== null &&
            typeof item === 'object' &&
            !Array.isArray(item) &&
            isPlainRecord(item) &&
            hasExactOwnKeys(item, ['kind', 'facetId', 'sourceIdentity']) &&
            item.kind === 'facet' &&
            item.facetId === null &&
            typeof item.sourceIdentity === 'string' &&
            /^source:[a-f0-9]{64}$/u.test(item.sourceIdentity),
        );
      if (valid && Array.isArray(items)) {
        addSourceLeaves(traversal.state, items.length);
      }
      return valid;
    }
    return (
      source.kind === 'mixed' &&
      hasExactOwnKeys(source, [
        'kind',
        'sourceIdentity',
        'mixMode',
        'sources',
      ]) &&
      ['sequential', 'interleave'].includes(String(source.mixMode)) &&
      Array.isArray(source.sources) &&
      source.sources.length >= 1 &&
      source.sources.length <= CHANNEL_BUILDER_MAX_SOURCE_LEAVES &&
      source.sources.every((child) =>
        isValidSafeSourceReference(child, seen, {
          depth: traversal.depth + 1,
          state: traversal.state,
        }),
      )
    );
  } finally {
    seen.delete(source);
  }
}

export type CandidateIdentityInput = Readonly<{
  origin: ChannelBuilderOriginBinding;
  sourceReference: ChannelBuilderSafeSourceReference;
  contentFilterIdentity: ChannelBuilderContentFilterIdentity | null;
  sortOrder: SortOrder | null;
  lineupReplicaIndex: number | null;
  isPlaybackModeVariant: boolean | null;
  playbackMode: PlaybackMode;
  blockSize: number | null;
}>;

export function createCandidateIdentityPreimage(
  input: CandidateIdentityInput,
): Readonly<Record<string, CanonicalJsonValue>> {
  if (
    !isPlainRecord(input) ||
    !hasExactOwnKeys(input, [
      'origin',
      'sourceReference',
      'contentFilterIdentity',
      'sortOrder',
      'lineupReplicaIndex',
      'isPlaybackModeVariant',
      'playbackMode',
      'blockSize',
    ]) ||
    input.origin === null ||
    typeof input.origin !== 'object' ||
    !isPlainRecord(input.origin) ||
    !hasExactOwnKeys(input.origin, [
      'profileBinding',
      'serverBinding',
      'librarySetBinding',
    ]) ||
    !/^profile-binding:[a-f0-9]{64}$/u.test(input.origin.profileBinding) ||
    !/^server-binding:[a-f0-9]{64}$/u.test(input.origin.serverBinding) ||
    !/^library-set-binding:[a-f0-9]{64}$/u.test(
      input.origin.librarySetBinding,
    ) ||
    !isValidSafeSourceReference(input.sourceReference) ||
    (input.contentFilterIdentity !== null &&
      !/^content-filters:[a-f0-9]{64}$/u.test(
        input.contentFilterIdentity,
      )) ||
    (input.sortOrder !== null &&
      ![
        'title_asc',
        'title_desc',
        'year_asc',
        'year_desc',
        'added_asc',
        'added_desc',
        'duration_asc',
        'duration_desc',
        'episode_order',
      ].includes(input.sortOrder)) ||
    (input.isPlaybackModeVariant !== null &&
      typeof input.isPlaybackModeVariant !== 'boolean') ||
    !['sequential', 'shuffle', 'block', 'random'].includes(
      input.playbackMode,
    ) ||
    (input.lineupReplicaIndex !== null &&
      (!Number.isInteger(input.lineupReplicaIndex) ||
        input.lineupReplicaIndex < 0 ||
        input.lineupReplicaIndex > 3))
  ) {
    throw new TypeError('Invalid candidate identity input.');
  }
  if (
    input.blockSize !== null &&
    (!Number.isInteger(input.blockSize) || input.blockSize < 2 || input.blockSize > 5)
  ) {
    throw new TypeError('Invalid candidate identity input.');
  }
  const isVariant = input.isPlaybackModeVariant === true;
  return {
    identityVersion: 1,
    origin: input.origin,
    sourceTree: sourceTreeIdentity(input.sourceReference),
    contentFilterIdentity: input.contentFilterIdentity,
    sortOrder: input.sortOrder,
    lineupReplicaIndex: input.lineupReplicaIndex ?? 0,
    isPlaybackModeVariant: isVariant,
    variantPlaybackMode: isVariant ? input.playbackMode : null,
    variantBlockSize:
      isVariant && input.playbackMode === 'block' ? input.blockSize : null,
  };
}

export function createCandidateIdentity(
  input: CandidateIdentityInput,
): ChannelBuilderCandidateIdentity {
  return channelBuilderIdentityOperations.createCandidateIdentity(input);
}

function createCandidateIdentityWithSha256(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  input: CandidateIdentityInput,
): ChannelBuilderCandidateIdentity {
  const bytes = createCandidateIdentityBytes(input);
  return identityBytes(
    createSha256,
    'candidate-identity:',
    'lineup-builder/candidate-identity/v1:',
    bytes,
  );
}

export type CandidateIdentityTuple = Readonly<{
  identity: ChannelBuilderCandidateIdentity;
  bytes: string;
}>;

export function createCandidateIdentityTuple(
  input: CandidateIdentityInput,
): CandidateIdentityTuple {
  return channelBuilderIdentityOperations.createCandidateIdentityTuple(input);
}

function createCandidateIdentityTupleWithSha256(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  input: CandidateIdentityInput,
): CandidateIdentityTuple {
  const bytes = createCandidateIdentityBytes(input);
  const hasher = createSha256();
  hasher.updateUtf8('lineup-builder/candidate-identity/v1:');
  hasher.updateUtf8(bytes);
  return {
    identity: `candidate-identity:${hasher.digestHex()}`,
    bytes,
  };
}

export function findByteEqualCandidateTupleIndex(
  candidates: readonly CandidateIdentityTuple[],
  existing: CandidateIdentityTuple,
): number {
  return candidates.findIndex(
    (candidate) =>
      candidate.identity === existing.identity && candidate.bytes === existing.bytes,
  );
}

export function createCandidateId(input: Readonly<{
  seed: string;
  strategy: string;
  candidateIdentity: ChannelBuilderCandidateIdentity;
  occurrence: number;
}>): ChannelBuilderCandidateId {
  return channelBuilderIdentityOperations.createCandidateId(input);
}

function createCandidateIdWithSha256(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  input: Readonly<{
    seed: string;
    strategy: string;
    candidateIdentity: ChannelBuilderCandidateIdentity;
    occurrence: number;
  }>,
): ChannelBuilderCandidateId {
  if (!Number.isSafeInteger(input.occurrence) || input.occurrence < 0) {
    throw new TypeError('Invalid candidate occurrence.');
  }
  const seed = normalizedIdentityInput(input.seed);
  const strategy = input.strategy.normalize('NFC');
  const bytes =
    `{"candidateIdentity":${JSON.stringify(input.candidateIdentity)},` +
    `"occurrence":${input.occurrence},` +
    `"seed":${JSON.stringify(seed)},` +
    `"strategy":${JSON.stringify(strategy)}}`;
  return identityBytes(
    createSha256,
    'candidate:',
    'lineup-builder/candidate-id/v1:',
    bytes,
  );
}

function createCandidateIdentityBytes(input: CandidateIdentityInput): string {
  // This is the planner hot path. Keep its fixed-order encoding byte-identical
  // to canonicalJsonV1(createCandidateIdentityPreimage(input)); the identity
  // conformance test pins that invariant independently of the digest.
  const preimage = createCandidateIdentityPreimage(input);
  const isVariant = input.isPlaybackModeVariant === true;
  const origin =
    `{"librarySetBinding":${JSON.stringify(input.origin.librarySetBinding)},` +
    `"profileBinding":${JSON.stringify(input.origin.profileBinding)},` +
    `"serverBinding":${JSON.stringify(input.origin.serverBinding)}}`;
  const sourceTree = input.sourceReference.kind === 'facet'
    ? `{"kind":"facet","sourceIdentity":${JSON.stringify(
        input.sourceReference.sourceIdentity,
      )}}`
    : canonicalJsonV1(preimage.sourceTree);
  return (
    `{"contentFilterIdentity":${jsonScalar(input.contentFilterIdentity)},` +
    `"identityVersion":1,` +
    `"isPlaybackModeVariant":${String(isVariant)},` +
    `"lineupReplicaIndex":${String(input.lineupReplicaIndex ?? 0)},` +
    `"origin":${origin},` +
    `"sortOrder":${jsonScalar(input.sortOrder)},` +
    `"sourceTree":${sourceTree},` +
    `"variantBlockSize":${String(
      isVariant && input.playbackMode === 'block' ? input.blockSize : null,
    )},` +
    `"variantPlaybackMode":${jsonScalar(
      isVariant ? input.playbackMode : null,
    )}}`
  );
}

function jsonScalar(value: string | null): string {
  return value === null ? 'null' : JSON.stringify(value);
}

export function createPlanIdentity(
  input: CanonicalJsonValue,
  output: CanonicalJsonValue,
): ChannelBuilderPlanIdentity {
  return channelBuilderIdentityOperations.createPlanIdentity(input, output);
}

function createPlanIdentityWithSha256(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  input: CanonicalJsonValue,
  output: CanonicalJsonValue,
): ChannelBuilderPlanIdentity {
  const hasher = createSha256();
  hasher.updateUtf8('lineup-builder/plan-identity/v1:');
  updateCanonicalJsonV1(hasher, {
    input,
    output,
  });
  return `plan-identity:${hasher.digestHex()}`;
}

export function createDeterministicShuffleSeed(seed: string, value: string): number {
  return channelBuilderIdentityOperations.createDeterministicShuffleSeed(seed, value);
}

function createDeterministicShuffleSeedWithSha256(
  createSha256: ChannelBuilderIncrementalSha256Factory,
  seed: string,
  value: string,
): number {
  const normalizedSeed = normalizedIdentityInput(seed);
  const normalizedValue = value.normalize('NFC');
  const hasher = createSha256();
  hasher.updateUtf8(
    'lineup-builder/shuffle-seed/v1:' +
      `{"seed":${JSON.stringify(normalizedSeed)},"value":${JSON.stringify(normalizedValue)}}`,
  );
  const digest = hasher.digestHex();
  return Number.parseInt(digest.slice(0, 8), 16) | 0;
}

export type ChannelBuilderIdentityOperations = Readonly<{
  canonicalJsonV1: typeof canonicalJsonV1;
  sha256HexV1: typeof sha256HexV1;
  createPersistedStringV1: typeof createPersistedStringV1;
  createProfileBinding: typeof createProfileBinding;
  createServerBinding: typeof createServerBinding;
  createLibrarySetBinding: typeof createLibrarySetBinding;
  createFacetIdentity: typeof createFacetIdentity;
  createSourceIdentity: typeof createSourceIdentity;
  createMixedSourceIdentity: typeof createMixedSourceIdentity;
  createTagSemanticGroupIdentity: typeof createTagSemanticGroupIdentity;
  createContentFilterIdentity: typeof createContentFilterIdentity;
  createCandidateIdentityPreimage: typeof createCandidateIdentityPreimage;
  createCandidateIdentity: typeof createCandidateIdentity;
  createCandidateIdentityTuple: typeof createCandidateIdentityTuple;
  findByteEqualCandidateTupleIndex: typeof findByteEqualCandidateTupleIndex;
  createCandidateId: typeof createCandidateId;
  createPlanIdentity: typeof createPlanIdentity;
  createDeterministicShuffleSeed: typeof createDeterministicShuffleSeed;
}>;

export function createChannelBuilderIdentityOperations(
  createSha256: ChannelBuilderIncrementalSha256Factory,
): ChannelBuilderIdentityOperations {
  return Object.freeze({
    canonicalJsonV1,
    sha256HexV1(value: string): string {
      const hasher = createSha256();
      hasher.updateUtf8(value);
      return hasher.digestHex();
    },
    createPersistedStringV1,
    createProfileBinding: (activeProfileId) =>
      createProfileBindingWithSha256(createSha256, activeProfileId),
    createServerBinding: (serverId) =>
      createServerBindingWithSha256(createSha256, serverId),
    createLibrarySetBinding: (libraries) =>
      createLibrarySetBindingWithSha256(createSha256, libraries),
    createFacetIdentity: (family, preimage) =>
      createFacetIdentityWithSha256(createSha256, family, preimage),
    createSourceIdentity: (source) =>
      createSourceIdentityWithSha256(createSha256, source),
    createMixedSourceIdentity: (mixMode, sources) =>
      createMixedSourceIdentityWithSha256(createSha256, mixMode, sources),
    createTagSemanticGroupIdentity: (input) =>
      createTagSemanticGroupIdentityWithSha256(createSha256, input),
    createContentFilterIdentity: (input) =>
      createContentFilterIdentityWithSha256(createSha256, input),
    createCandidateIdentityPreimage,
    createCandidateIdentity: (input) =>
      createCandidateIdentityWithSha256(createSha256, input),
    createCandidateIdentityTuple: (input) =>
      createCandidateIdentityTupleWithSha256(createSha256, input),
    findByteEqualCandidateTupleIndex,
    createCandidateId: (input) =>
      createCandidateIdWithSha256(createSha256, input),
    createPlanIdentity: (input, output) =>
      createPlanIdentityWithSha256(createSha256, input, output),
    createDeterministicShuffleSeed: (seed, value) =>
      createDeterministicShuffleSeedWithSha256(createSha256, seed, value),
  });
}

export const channelBuilderIdentityOperations =
  createChannelBuilderIdentityOperations(() => new Sha256V1());
