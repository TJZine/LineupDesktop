import {
  MAX_CHANNELS,
  MAX_CHANNEL_NUMBER,
  MIN_CHANNEL_NUMBER,
} from './constants.js';
import type {
  ChannelConfig,
  ChannelContentSource,
  ChannelCreateInput,
  DomainPlexMediaType,
  ManualContentItem,
  PlaybackMode,
  SortOrder,
} from './types.js';

export type CustomChannelDraftContentEntryInput =
  | {
      type: 'library';
      sourceId: string;
      title: string;
      mediaType: 'movie' | 'show';
      includeWatched?: boolean;
    }
  | {
      type: 'show';
      sourceId: string;
      title: string;
      seasonFilter?: readonly number[];
    }
  | {
      type: 'collection';
      sourceId: string;
      title: string;
    }
  | {
      type: 'playlist';
      sourceId: string;
      title: string;
    }
  | {
      type: 'manualItem';
      ratingKey: string;
      title: string;
      durationMs: number;
      mediaType: 'movie' | 'episode';
      parentTitle?: string;
      year?: number;
      seasonNumber?: number;
      episodeNumber?: number;
    };

export interface CustomChannelDraftInput {
  id?: string;
  expectedRevision?: string;
  number: number;
  name: string;
  description?: string;
  color?: string;
  icon?: string;
  hidden: boolean;
  content: readonly CustomChannelDraftContentEntryInput[];
  playbackMode: PlaybackMode;
  blockSize?: number;
  sortOrder?: SortOrder;
  includeWatched?: boolean;
  startTimeAnchor?: number;
  skipIntros?: boolean;
  skipCredits?: boolean;
}

export type CustomChannelDraftValidationCode =
  | 'missing-name'
  | 'duplicate-number'
  | 'invalid-number'
  | 'empty-content'
  | 'duplicate-content'
  | 'invalid-draft-id'
  | 'invalid-content'
  | 'invalid-playback-mode'
  | 'invalid-block-size'
  | 'invalid-hidden'
  | 'invalid-include-watched'
  | 'invalid-sort-order'
  | 'invalid-start-time-anchor'
  | 'max-channels';

export interface CustomChannelDraftValidationIssue {
  code: CustomChannelDraftValidationCode;
  message: string;
  field: string | null;
  contentIndex?: number;
}

export type CustomChannelDraftBuildResult =
  | {
      ok: true;
      input: ChannelCreateInput;
      contentSource: ChannelContentSource;
    }
  | {
      ok: false;
      issues: readonly CustomChannelDraftValidationIssue[];
    };

export function buildCustomChannelCreateInput(
  draft: CustomChannelDraftInput,
  existingChannels: readonly ChannelConfig[],
): CustomChannelDraftBuildResult {
  const issues: CustomChannelDraftValidationIssue[] = [];
  const draftId = draft.id === undefined ? undefined : (isSafeId(draft.id) ? draft.id.trim() : null);
  const contentEntries = Array.isArray(draft.content) ? draft.content : [];

  if (draftId === null) {
    issues.push({
      code: 'invalid-draft-id',
      message: 'Draft channel id must be an opaque channel id.',
      field: 'id',
    });
  }

  if (existingChannels.length >= MAX_CHANNELS && draftId === undefined) {
    issues.push({
      code: 'max-channels',
      message: 'Maximum channel count has been reached.',
      field: null,
    });
  }

  const name = typeof draft.name === 'string' ? draft.name.trim() : '';
  if (name.length === 0) {
    issues.push({
      code: 'missing-name',
      message: 'Channel name is required.',
      field: 'name',
    });
  }

  if (
    !Number.isInteger(draft.number) ||
    draft.number < MIN_CHANNEL_NUMBER ||
    draft.number > MAX_CHANNEL_NUMBER
  ) {
    issues.push({
      code: 'invalid-number',
      message: `Channel number must be an integer between ${String(MIN_CHANNEL_NUMBER)} and ${String(MAX_CHANNEL_NUMBER)}.`,
      field: 'number',
    });
  } else if (
    existingChannels.some((channel) => channel.number === draft.number && channel.id !== draftId)
  ) {
    issues.push({
      code: 'duplicate-number',
      message: `Channel number ${String(draft.number)} is already used.`,
      field: 'number',
    });
  }

  if (!isPlaybackMode(draft.playbackMode)) {
    issues.push({
      code: 'invalid-playback-mode',
      message: 'Playback mode is invalid.',
      field: 'playbackMode',
    });
  }

  if (typeof draft.hidden !== 'boolean') {
    issues.push({
      code: 'invalid-hidden',
      message: 'Hidden state must be a boolean.',
      field: 'hidden',
    });
  }

  if (draft.includeWatched !== undefined && typeof draft.includeWatched !== 'boolean') {
    issues.push({
      code: 'invalid-include-watched',
      message: 'Include watched must be a boolean.',
      field: 'includeWatched',
    });
  }

  if (draft.sortOrder !== undefined && !isSortOrder(draft.sortOrder)) {
    issues.push({
      code: 'invalid-sort-order',
      message: 'Sort order is invalid.',
      field: 'sortOrder',
    });
  }

  if (
    draft.startTimeAnchor !== undefined &&
    (
      typeof draft.startTimeAnchor !== 'number' ||
      !Number.isFinite(draft.startTimeAnchor) ||
      draft.startTimeAnchor < 0
    )
  ) {
    issues.push({
      code: 'invalid-start-time-anchor',
      message: 'Start time anchor must be a non-negative finite number.',
      field: 'startTimeAnchor',
    });
  }

  if (draft.playbackMode === 'block') {
    if (
      typeof draft.blockSize !== 'number' ||
      !Number.isFinite(draft.blockSize) ||
      !Number.isInteger(draft.blockSize) ||
      draft.blockSize < 1
    ) {
      issues.push({
        code: 'invalid-block-size',
        message: 'Block playback requires a positive block size.',
        field: 'blockSize',
      });
    }
  } else if (draft.blockSize !== undefined) {
    issues.push({
      code: 'invalid-block-size',
      message: 'Block size may only be provided for block playback.',
      field: 'blockSize',
    });
  }

  if (!Array.isArray(draft.content) || draft.content.length === 0) {
    issues.push({
      code: 'empty-content',
      message: 'At least one content entry is required.',
      field: 'content',
    });
  }

  const duplicateIssue = findDuplicateContentIssue(contentEntries);
  if (duplicateIssue) {
    issues.push(duplicateIssue);
  }

  const contentSource = mapDraftContentToSource(contentEntries, draft.includeWatched, issues);
  if (issues.length > 0 || contentSource === null) {
    return { ok: false, issues };
  }

  const input: ChannelCreateInput = {
    number: draft.number,
    name,
    hidden: draft.hidden,
    contentSource,
    playbackMode: draft.playbackMode,
    skipIntros: draft.skipIntros === true,
    skipCredits: draft.skipCredits === true,
  };
  if (typeof draft.description === 'string') {
    input.description = draft.description;
  }
  if (typeof draft.color === 'string') {
    input.color = draft.color;
  }
  if (typeof draft.icon === 'string') {
    input.icon = draft.icon;
  }
  if (draft.startTimeAnchor !== undefined) {
    input.startTimeAnchor = draft.startTimeAnchor;
  }
  if (draft.playbackMode === 'block' && draft.blockSize !== undefined) {
    input.blockSize = draft.blockSize;
  }
  if (draft.sortOrder !== undefined) {
    input.sortOrder = draft.sortOrder;
  }

  return { ok: true, input, contentSource };
}

function mapDraftContentToSource(
  entries: readonly unknown[],
  includeWatched: boolean | undefined,
  issues: CustomChannelDraftValidationIssue[],
): ChannelContentSource | null {
  const sources: ChannelContentSource[] = [];
  const manualItems: ManualContentItem[] = [];

  entries.forEach((entry, index) => {
    const source = mapNonManualEntryToSource(entry, includeWatched, index, issues);
    if (isManualDraftContentEntry(entry)) {
      const manualItem = mapManualEntry(entry, index, issues);
      if (manualItem) {
        manualItems.push(manualItem);
      }
      return;
    }
    if (source) {
      sources.push(source);
    }
  });

  if (manualItems.length > 0) {
    sources.push({ type: 'manual', items: manualItems });
  }

  if (sources.length === 0) {
    return null;
  }
  if (sources.length === 1) {
    return sources[0] ?? null;
  }
  return {
    type: 'mixed',
    mixMode: 'sequential',
    sources,
  };
}

function mapNonManualEntryToSource(
  entry: unknown,
  includeWatched: boolean | undefined,
  index: number,
  issues: CustomChannelDraftValidationIssue[],
): ChannelContentSource | null {
  if (!isDraftContentEntryRecord(entry)) {
    pushInvalidContentIssue(issues, index);
    return null;
  }

  switch (entry.type) {
    case 'library':
      if (
        !isSafeId(entry.sourceId) ||
        !isNonBlank(entry.title) ||
        !isLibraryMediaType(entry.mediaType) ||
        !isOptionalBoolean(entry.includeWatched)
      ) {
        pushInvalidContentIssue(issues, index);
        return null;
      }
      return {
        type: 'library',
        libraryId: entry.sourceId.trim(),
        libraryType: entry.mediaType,
        includeWatched: entry.includeWatched ?? includeWatched ?? true,
      };
    case 'show':
      if (!isSafeId(entry.sourceId) || !isNonBlank(entry.title) || !isValidSeasonFilter(entry.seasonFilter)) {
        pushInvalidContentIssue(issues, index);
        return null;
      }
      return {
        type: 'show',
        showKey: entry.sourceId.trim(),
        showName: entry.title.trim(),
        ...(entry.seasonFilter ? { seasonFilter: [...entry.seasonFilter] } : {}),
      };
    case 'collection':
      if (!isSafeId(entry.sourceId) || !isNonBlank(entry.title)) {
        pushInvalidContentIssue(issues, index);
        return null;
      }
      return {
        type: 'collection',
        collectionKey: entry.sourceId.trim(),
        collectionName: entry.title.trim(),
      };
    case 'playlist':
      if (!isSafeId(entry.sourceId) || !isNonBlank(entry.title)) {
        pushInvalidContentIssue(issues, index);
        return null;
      }
      return {
        type: 'playlist',
        playlistKey: entry.sourceId.trim(),
        playlistName: entry.title.trim(),
      };
    case 'manualItem':
      return null;
    default:
      pushInvalidContentIssue(issues, index);
      return null;
  }
}

function mapManualEntry(
  entry: Extract<CustomChannelDraftContentEntryInput, { type: 'manualItem' }>,
  index: number,
  issues: CustomChannelDraftValidationIssue[],
): ManualContentItem | null {
  if (
    !isSafeId(entry.ratingKey) ||
    !isNonBlank(entry.title) ||
    typeof entry.durationMs !== 'number' ||
    !Number.isFinite(entry.durationMs) ||
    !Number.isInteger(entry.durationMs) ||
    entry.durationMs <= 0 ||
    !isManualMediaType(entry.mediaType)
  ) {
    pushInvalidContentIssue(issues, index);
    return null;
  }
  return {
    ratingKey: entry.ratingKey.trim(),
    title: entry.title.trim(),
    durationMs: entry.durationMs,
  };
}

function findDuplicateContentIssue(
  entries: readonly unknown[],
): CustomChannelDraftValidationIssue | null {
  const seen = new Map<string, number>();
  for (let index = 0; index < entries.length; index++) {
    const entry = entries[index];
    if (!entry) {
      continue;
    }
    const key = contentIdentity(entry);
    if (key === null) {
      continue;
    }
    const firstIndex = seen.get(key);
    if (firstIndex !== undefined) {
      return {
        code: 'duplicate-content',
        message: 'Duplicate media or source entries are not allowed in a channel draft.',
        field: 'content',
        contentIndex: index,
      };
    }
    seen.set(key, index);
  }
  return null;
}

function contentIdentity(entry: unknown): string | null {
  if (!isDraftContentEntryRecord(entry)) {
    return null;
  }
  if (entry.type === 'manualItem') {
    return isSafeId(entry.ratingKey) ? `${entry.type}:${entry.ratingKey.trim()}` : null;
  }
  return isSafeId(entry.sourceId) ? `${entry.type}:${entry.sourceId.trim()}` : null;
}

function pushInvalidContentIssue(
  issues: CustomChannelDraftValidationIssue[],
  contentIndex: number,
): void {
  issues.push({
    code: 'invalid-content',
    message: 'One selected content entry is invalid.',
    field: 'content',
    contentIndex,
  });
}

function isPlaybackMode(value: unknown): value is PlaybackMode {
  return value === 'sequential' || value === 'shuffle' || value === 'block' || value === 'random';
}

function isSortOrder(value: unknown): value is SortOrder {
  return (
    value === 'title_asc' ||
    value === 'title_desc' ||
    value === 'year_asc' ||
    value === 'year_desc' ||
    value === 'added_asc' ||
    value === 'added_desc' ||
    value === 'duration_asc' ||
    value === 'duration_desc' ||
    value === 'episode_order'
  );
}

function isLibraryMediaType(value: unknown): value is Extract<DomainPlexMediaType, 'movie' | 'show'> {
  return value === 'movie' || value === 'show';
}

function isManualMediaType(value: unknown): value is Extract<DomainPlexMediaType, 'movie' | 'episode'> {
  return value === 'movie' || value === 'episode';
}

function isDraftContentEntryRecord(value: unknown): value is CustomChannelDraftContentEntryInput {
  return value !== null && typeof value === 'object' && 'type' in value;
}

function isManualDraftContentEntry(
  value: unknown,
): value is Extract<CustomChannelDraftContentEntryInput, { type: 'manualItem' }> {
  return isDraftContentEntryRecord(value) && value.type === 'manualItem';
}

function isSafeId(value: unknown): value is string {
  if (typeof value !== 'string') {
    return false;
  }
  const trimmed = value.trim();
  return (
    trimmed.length > 0 &&
    trimmed.length <= 128 &&
    trimmed !== 'undefined' &&
    /^[A-Za-z0-9._~-]+$/u.test(trimmed) &&
    !/(?:token|header|url|uri|path|secret)/iu.test(trimmed)
  );
}

function isNonBlank(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isValidSeasonFilter(value: unknown): boolean {
  return (
    value === undefined ||
    (
      Array.isArray(value) &&
      value.every(
        (entry) =>
          typeof entry === 'number' &&
          Number.isInteger(entry) &&
          Number.isFinite(entry) &&
          entry > 0,
      )
    )
  );
}

function isOptionalBoolean(value: unknown): boolean {
  return value === undefined || typeof value === 'boolean';
}
