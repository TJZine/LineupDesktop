import { createHash } from 'node:crypto';
import { Buffer } from 'node:buffer';

import type { ChannelSetupSummary } from '../../contracts/channel.js';
import type {
  EpgChannelViewModel,
  EpgCurrentProgramViewModel,
  EpgPresentationSource,
  EpgProgramViewModel,
} from '../../contracts/guide.js';
import type { ChannelConfig } from '../../domain/channel/types.js';
import {
  canonicalJsonV1,
  containsChannelBuilderCredentialMarker,
  projectChannelBuilderSafeDisplayString,
} from '../../domain/channelBuilder/index.js';
import type { ChannelAggregate } from '../../domain/channel/channelPersistenceStore.js';

const SAFE_REFERENCE = /^[A-Za-z0-9._-]{1,120}$/u;

export type ChannelPublicReferenceGeneration = Readonly<{
  lineupRevision: number;
  channels: readonly ChannelConfig[];
  currentChannelId: string | null;
  fingerprint: string;
}>;

type ReferenceMapping = Readonly<{
  rawToPublicChannel: ReadonlyMap<string, string>;
  publicToRawChannel: ReadonlyMap<string, string>;
  rawToPublicLibrary: ReadonlyMap<string, string>;
  publicToRawLibrary: ReadonlyMap<string, string>;
}>;

export class ChannelPublicReferenceConsistencyError extends Error {
  public constructor() {
    super('Guide presentation did not match the current channel generation.');
    this.name = 'ChannelPublicReferenceConsistencyError';
  }
}

export class ChannelPublicReferenceOwner {
  private cached: Readonly<{ fingerprint: string; mapping: ReferenceMapping }> | null = null;

  public constructor(
    private readonly digest: (value: string) => string = sha256,
  ) {}

  public createGeneration(aggregate: ChannelAggregate): ChannelPublicReferenceGeneration {
    const channels = aggregate.storedChannelData?.channels ?? [];
    const seen = new Set<string>();
    for (const channel of channels) {
      if (seen.has(channel.id)) throw projectionFailure();
      seen.add(channel.id);
    }
    const tuple = [
      aggregate.lineupRevision,
      channels.map((channel) => [
        channel.id,
        channel.hidden === true,
        channel.sourceLibraryId ?? null,
        channel.contentSource,
      ]),
      aggregate.currentChannelId,
    ];
    return Object.freeze({
      lineupRevision: aggregate.lineupRevision,
      channels,
      currentChannelId: aggregate.currentChannelId,
      fingerprint: sha256(canonicalJsonV1(tuple)),
    });
  }

  public projectStatus(
    generation: ChannelPublicReferenceGeneration,
    aggregate: ChannelAggregate,
    updatedAtMs: number,
  ): ChannelSetupSummary {
    const mapping = this.mappingFor(generation);
    const channels = generation.channels.map((channel) => ({
      id: requireMapped(mapping.rawToPublicChannel, channel.id),
      number: channel.number,
      name: display(channel.name, 'Untitled channel', 160),
      sourceLibraryId:
        channel.sourceLibraryId === null || channel.sourceLibraryId === undefined
          ? null
          : requireMapped(mapping.rawToPublicLibrary, channel.sourceLibraryId),
      sourceLibraryName:
        channel.sourceLibraryName === null || channel.sourceLibraryName === undefined
          ? null
          : display(channel.sourceLibraryName, '', 160),
      itemCount: channel.itemCount,
    }));
    const currentIndex =
      generation.currentChannelId === null
        ? -1
        : generation.channels.findIndex((channel) => channel.id === generation.currentChannelId);
    const current = currentIndex < 0 ? null : channels[currentIndex] ?? null;
    const builder = aggregate.channelBuilderState;
    return {
      status: builder === null ? 'not-configured' : 'configured',
      lineupRevision: generation.lineupRevision,
      channelCount: channels.length,
      currentChannelId: current?.id ?? null,
      currentChannelNumber: current?.number ?? null,
      currentChannelName: current?.name ?? null,
      channelNumbers: channels.map((channel) => channel.number),
      channels,
      builder:
        builder === null
          ? { completion: 'unknown', normalizedConfig: null, completedAtMs: null }
          : {
              completion: 'complete',
              normalizedConfig: builder.normalizedConfig,
              completedAtMs: builder.completedAtMs,
            },
      recovery: { loaded: channels.length > 0, repaired: false },
      updatedAtMs,
    };
  }

  public projectPresentation(
    generation: ChannelPublicReferenceGeneration,
    presentation: EpgPresentationSource,
  ): EpgPresentationSource {
    const mapping = this.mappingFor(generation);
    const visible = new Set(
      generation.channels
        .filter((channel) => channel.hidden !== true)
        .map((channel) => channel.id),
    );
    for (const channel of presentation.channels) {
      if (!visible.has(channel.id)) throw new ChannelPublicReferenceConsistencyError();
    }
    if (presentation.nowWatching !== null && !visible.has(presentation.nowWatching.channelId)) {
      throw new ChannelPublicReferenceConsistencyError();
    }

    const channelRefs = presentation.channels.map((channel) =>
      requireConsistentMapped(mapping.rawToPublicChannel, channel.id),
    );
    const programTuples = presentation.channels.flatMap((channel, channelIndex) => {
      const occurrences = new Map<string, number>();
      return channel.programs.map((program) => {
        const publicChannelId = channelRefs[channelIndex]!;
        const base = canonicalJsonV1([
          publicChannelId,
          program.id,
          program.startsAtMs,
          program.endsAtMs,
        ]);
        const occurrence = occurrences.get(base) ?? 0;
        occurrences.set(base, occurrence + 1);
        const canonical = canonicalJsonV1({
          publicChannelId,
          rawProgramId: program.id,
          startsAtMs: program.startsAtMs,
          endsAtMs: program.endsAtMs,
          occurrence,
        });
        return { program, canonical, digest: this.digest(`lineup-guide-program-ref/v1:${canonical}`) };
      });
    });
    if (programTuples.length > 50_000) throw projectionFailure();
    const collisionOrdinal = allocateCollisionOrdinals(programTuples);
    const programIds = new Map(
      programTuples.map((entry) => [
        entry,
        `guide-program-${entry.digest}-${collisionOrdinal.get(entry)}`,
      ]),
    );
    if (new Set(programIds.values()).size !== programIds.size) throw projectionFailure();
    let programOffset = 0;
    const channels: EpgChannelViewModel[] = presentation.channels.map((channel, index) => {
      const programs = channel.programs.map((program) => {
        const entry = programTuples[programOffset++];
        if (entry === undefined) throw projectionFailure();
        return projectProgram(program, requireMapped(programIds, entry));
      });
      return {
        id: channelRefs[index]!,
        number: channel.number,
        name: display(channel.name, 'Untitled channel', 160),
        programs,
      };
    });
    return {
      channels,
      nowWatching:
        presentation.nowWatching === null
          ? null
          : projectCurrent(
              presentation.nowWatching,
              requireConsistentMapped(
                mapping.rawToPublicChannel,
                presentation.nowWatching.channelId,
              ),
            ),
    };
  }

  public resolveChannel(
    generation: ChannelPublicReferenceGeneration,
    publicChannelId: string,
  ): string | null {
    return this.mappingFor(generation).publicToRawChannel.get(publicChannelId) ?? null;
  }

  public projectChannelReference(generation: ChannelPublicReferenceGeneration, rawChannelId: string): string {
    return requireConsistentMapped(this.mappingFor(generation).rawToPublicChannel, rawChannelId);
  }

  public projectLibraryReference(generation: ChannelPublicReferenceGeneration, rawLibraryId: string): string {
    return requireConsistentMapped(this.mappingFor(generation).rawToPublicLibrary, rawLibraryId);
  }

  public projectLibraryName(rawName: string): string {
    return display(rawName, 'Library', 160);
  }

  public resolveLibrary(generation: ChannelPublicReferenceGeneration, publicLibraryId: string): string | null {
    return this.mappingFor(generation).publicToRawLibrary.get(publicLibraryId) ?? null;
  }

  private mappingFor(generation: ChannelPublicReferenceGeneration): ReferenceMapping {
    if (this.cached?.fingerprint === generation.fingerprint) return this.cached.mapping;
    const channelValues = generation.channels.map((channel) => channel.id);
    const libraryValues = generation.channels.flatMap((channel) => [
      ...(channel.sourceLibraryId === null || channel.sourceLibraryId === undefined ? [] : [channel.sourceLibraryId]),
      ...libraryIdsFromSource(channel.contentSource),
    ]);
    const allSafe = new Set(
      [...channelValues, ...libraryValues].filter(isSafeReference),
    );
    const rawToPublicChannel = allocateReferences(
      channelValues,
      allSafe,
      'lineup-status-channel-ref/v1:',
      'legacy-channel-',
      this.digest,
    );
    const rawToPublicLibrary = allocateReferences(
      libraryValues,
      allSafe,
      'lineup-status-library-ref/v1:',
      'legacy-library-',
      this.digest,
    );
    const mapping = Object.freeze({
      rawToPublicChannel,
      publicToRawChannel: new Map(
        [...rawToPublicChannel].map(([raw, publicValue]) => [publicValue, raw]),
      ),
      rawToPublicLibrary,
      publicToRawLibrary: new Map(
        [...rawToPublicLibrary].map(([raw, publicValue]) => [publicValue, raw]),
      ),
    });
    this.cached = { fingerprint: generation.fingerprint, mapping };
    return mapping;
  }
}

function libraryIdsFromSource(source: ChannelConfig['contentSource']): string[] {
  if (source.type === 'library') return [source.libraryId];
  if (source.type === 'mixed') return source.sources.flatMap(libraryIdsFromSource);
  return [];
}

function allocateReferences(
  values: readonly string[],
  reservedInput: ReadonlySet<string>,
  domain: string,
  prefix: string,
  digest: (value: string) => string,
): ReadonlyMap<string, string> {
  const unique = [...new Set(values)];
  const result = new Map<string, string>();
  const reserved = new Set(reservedInput);
  for (const value of unique) {
    if (isSafeReference(value)) result.set(value, value);
  }
  const unsafe = unique
    .filter((value) => !isSafeReference(value))
    .map((raw) => ({ raw, digest: digest(`${domain}${raw}`) }));
  const grouped = groupBy(unsafe, (entry) => entry.digest);
  for (const entries of grouped.values()) {
    entries.sort((left, right) => compareUtf16(left.raw, right.raw));
    entries.forEach((entry, ordinal) => {
      if (ordinal > 499) throw projectionFailure();
      let allocated: string | null = null;
      for (let attempt = 0; attempt <= 500; attempt += 1) {
        const candidate = `${prefix}${entry.digest}-${ordinal}-${attempt}`;
        if (!reserved.has(candidate)) {
          allocated = candidate;
          break;
        }
      }
      if (allocated === null) throw projectionFailure();
      reserved.add(allocated);
      result.set(entry.raw, allocated);
    });
  }
  return result;
}

function allocateCollisionOrdinals<T extends { canonical: string; digest: string }>(
  entries: readonly T[],
): ReadonlyMap<T, number> {
  const result = new Map<T, number>();
  for (const group of groupBy(entries, (entry) => entry.digest).values()) {
    group.sort((left, right) => Buffer.compare(Buffer.from(left.canonical), Buffer.from(right.canonical)));
    group.forEach((entry, index) => {
      if (index > 49_999) throw projectionFailure();
      result.set(entry, index);
    });
  }
  return result;
}

function groupBy<T>(values: readonly T[], keyOf: (value: T) => string): Map<string, T[]> {
  const groups = new Map<string, T[]>();
  for (const value of values) {
    const key = keyOf(value);
    const group = groups.get(key);
    if (group === undefined) groups.set(key, [value]);
    else group.push(value);
  }
  return groups;
}

function projectProgram(program: EpgProgramViewModel, id: string): EpgProgramViewModel {
  const title = display(program.title, 'Untitled program', 160);
  const artworkFallback = `Poster for ${title}`.length <= 160
    ? `Poster for ${title}`
    : 'Program poster';
  return {
    id,
    title,
    subtitle: display(program.subtitle, '', 2_000),
    description: display(program.description, '', 600),
    showTitle: display(program.showTitle, '', 2_000),
    episodeLabel: display(program.episodeLabel, '', 2_000),
    rating: display(program.rating, '', 2_000),
    quality: program.quality.map((value) => display(value, '', 2_000)).slice(0, 20),
    genres: program.genres.map((value) => display(value, '', 2_000)).slice(0, 20),
    startsAtMs: program.startsAtMs,
    endsAtMs: program.endsAtMs,
    artwork: program.artwork === null
      ? null
      : Object.freeze({
          id: program.artwork.id,
          kind: program.artwork.kind,
          expiresAtMs: program.artwork.expiresAtMs,
          altText: display(program.artwork.altText, artworkFallback, 160),
          status: program.artwork.status,
        }),
  };
}

function projectCurrent(
  current: EpgCurrentProgramViewModel,
  channelId: string,
): EpgCurrentProgramViewModel {
  return {
    title: display(current.title, 'Untitled program', 2_000),
    subtitle: display(current.subtitle, '', 2_000),
    channelId,
    startsAtMs: current.startsAtMs,
    endsAtMs: current.endsAtMs,
  };
}

function display(raw: string, fallback: string, maxUtf16Units: number): string {
  return projectChannelBuilderSafeDisplayString(raw, { fallback, maxUtf16Units });
}

function isSafeReference(value: string): boolean {
  return SAFE_REFERENCE.test(value) && !containsChannelBuilderCredentialMarker(value);
}

function compareUtf16(left: string, right: string): number {
  const length = Math.min(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    const difference = left.charCodeAt(index) - right.charCodeAt(index);
    if (difference !== 0) return difference;
  }
  return left.length - right.length;
}

function requireMapped<K, V>(map: ReadonlyMap<K, V>, key: K): V {
  const value = map.get(key);
  if (value === undefined) throw projectionFailure();
  return value;
}

function requireConsistentMapped<K, V>(map: ReadonlyMap<K, V>, key: K): V {
  const value = map.get(key);
  if (value === undefined) throw new ChannelPublicReferenceConsistencyError();
  return value;
}

function sha256(value: string): string {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

function projectionFailure(): Error {
  return new Error('Public channel reference projection failed.');
}
