export const CUSTOM_CHANNEL_OPERATIONS = [
  'getSnapshot',
  'listMedia',
  'getMediaMetadata',
  'validateDraft',
  'saveDraft',
  'deleteChannel',
  'duplicateChannelDraft',
  'reorderChannels',
  'setChannelVisibility',
] as const;

export const CUSTOM_CHANNEL_ERROR_CODES = [
  'CUSTOM_CHANNEL_UNAUTHORIZED',
  'CUSTOM_CHANNEL_VALIDATION_FAILED',
  'CUSTOM_CHANNEL_PLEX_REQUIRED',
  'CUSTOM_CHANNEL_STORAGE_UNAVAILABLE',
  'CUSTOM_CHANNEL_STORAGE_CORRUPT',
  'CUSTOM_CHANNEL_NOT_FOUND',
  'CUSTOM_CHANNEL_STALE_MEDIA',
  'CUSTOM_CHANNEL_ARTWORK_UNAVAILABLE',
  'CUSTOM_CHANNEL_CONFLICT',
  'CUSTOM_CHANNEL_UNKNOWN',
] as const;

export const CUSTOM_CHANNEL_CONTENT_TYPES = [
  'library',
  'show',
  'collection',
  'playlist',
  'manualItem',
] as const;

export const CUSTOM_CHANNEL_MEDIA_TYPES = [
  'movie',
  'show',
  'episode',
  'collection',
  'playlist',
] as const;

export const CUSTOM_CHANNEL_PLAYBACK_MODES = [
  'sequential',
  'shuffle',
  'random',
  'block',
] as const;

export const CUSTOM_CHANNEL_SORT_ORDERS = [
  'title_asc',
  'title_desc',
  'year_asc',
  'year_desc',
  'added_asc',
  'added_desc',
  'duration_asc',
  'duration_desc',
  'episode_order',
] as const;

export const CUSTOM_CHANNEL_VALIDATION_CODES = [
  'missing-name',
  'duplicate-number',
  'invalid-number',
  'empty-content',
  'duplicate-content',
  'invalid-draft-id',
  'invalid-content',
  'invalid-playback-mode',
  'invalid-block-size',
  'invalid-hidden',
  'invalid-include-watched',
  'invalid-sort-order',
  'invalid-start-time-anchor',
  'max-channels',
  'stale-content',
  'storage-unavailable',
] as const;

export const CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS = [
  'rawPayload',
  'rawPlexPayload',
  'headers',
  'header',
  'authHeaders',
  'authHeader',
  'rawAuthHeaders',
  'token',
  'accessToken',
  'refreshToken',
  'path',
  'filePath',
  'localPath',
  'url',
  'uri',
  'endpointUrl',
  'baseUrl',
  'tokenizedUrl',
  'serverUri',
  'connectionUri',
  'appPath',
  'userDataPath',
  'filesystemPath',
  'persistenceFilePath',
  'credential',
  'secret',
  'nativeHandle',
  'electronApi',
  'nodeApi',
  'thumb',
  'art',
  'banner',
  'clearLogo',
  'imageKey',
  'artworkKey',
  'storedChannelData',
] as const;

export type CustomChannelOperation = (typeof CUSTOM_CHANNEL_OPERATIONS)[number];
export type CustomChannelErrorCode = (typeof CUSTOM_CHANNEL_ERROR_CODES)[number];
export type CustomChannelContentType = (typeof CUSTOM_CHANNEL_CONTENT_TYPES)[number];
export type CustomChannelMediaType = (typeof CUSTOM_CHANNEL_MEDIA_TYPES)[number];
export type CustomChannelPlaybackMode = (typeof CUSTOM_CHANNEL_PLAYBACK_MODES)[number];
export type CustomChannelSortOrder = (typeof CUSTOM_CHANNEL_SORT_ORDERS)[number];
export type CustomChannelValidationCode = (typeof CUSTOM_CHANNEL_VALIDATION_CODES)[number];
export type CustomChannelForbiddenRendererFieldKey =
  (typeof CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS)[number];

const CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS_NORMALIZED = new Set(
  CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS.map(normalizeForbiddenFieldKey),
);

const CUSTOM_CHANNEL_FORBIDDEN_STRING_PATTERNS = [
  /https?:\/\//iu,
  /file:\/\//iu,
  /(?:^|[\\/\s])\.\.(?:[\\/]|$)/u,
  /^\/(?:Users|private|tmp|var|Volumes|library|metadata|photo|image|transcode|library\/metadata)\b/iu,
  /\/library\/metadata\/[^ \t\r\n]+\/(?:thumb|art|banner|clearLogo)\b/iu,
  /\b[A-Za-z]:[\\/]/u,
  /\\\\[A-Za-z0-9._-]+[\\/]/u,
  /\b(?:bearer|token|authorization|headers?)\s*[:=]/iu,
  /\b(?:accessToken|refreshToken|x-plex-token)\b/iu,
] as const;

export interface CustomChannelRuntimeError {
  code: CustomChannelErrorCode;
  message: string;
  retryable: boolean;
  recoverable: boolean;
  operation: CustomChannelOperation;
}

export type CustomChannelIpcResult<TValue> =
  | { ok: true; requestId: string; value: TValue }
  | { ok: false; requestId: string; error: CustomChannelRuntimeError };

export interface CustomChannelStorageSummary {
  status: 'ready' | 'not-configured' | 'unavailable' | 'corrupt';
  repaired: boolean;
}

export interface CustomChannelSummary {
  id: string;
  number: number;
  name: string;
  description: string | null;
  itemCount: number;
  estimatedDurationMs: number;
  sourceSummary: string;
  playbackMode: CustomChannelPlaybackMode;
  hidden: boolean;
  updatedAtMs: number;
  isCurrent: boolean;
}

export interface CustomChannelSnapshot {
  channels: readonly CustomChannelSummary[];
  currentChannelId: string | null;
  visibleChannelCount: number;
  hiddenChannelCount: number;
  maxChannels: number;
  nextAvailableNumber: number | null;
  updatedAtMs: number;
  storage: CustomChannelStorageSummary;
}

export interface CustomChannelSourceRef {
  sourceType: CustomChannelContentType;
  sourceId: string;
  title: string;
}

export interface CustomChannelMediaCard {
  ratingKey: string;
  type: CustomChannelMediaType;
  title: string;
  subtitle: string;
  year: number | null;
  durationMs: number | null;
  parentTitle?: string;
  seasonNumber?: number;
  episodeNumber?: number;
  contentRating?: string;
  source: CustomChannelSourceRef;
  availability: 'available' | 'stale' | 'unsupported';
}

export interface CustomChannelMediaMetadata {
  ratingKey: string;
  type: CustomChannelMediaType;
  title: string;
  subtitle: string;
  summary: string | null;
  year: number | null;
  durationMs: number | null;
  parentTitle?: string;
  seasonNumber?: number;
  episodeNumber?: number;
  contentRating?: string;
  genres: readonly string[];
  availability: 'available' | 'stale' | 'unsupported';
}

export type CustomChannelContentEntryInput =
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
  content: readonly CustomChannelContentEntryInput[];
  playbackMode: CustomChannelPlaybackMode;
  blockSize?: number;
  sortOrder?: CustomChannelSortOrder;
  includeWatched?: boolean;
  startTimeAnchor?: number;
  skipIntros?: boolean;
  skipCredits?: boolean;
}

export interface CustomChannelDraftValidationIssue {
  code: CustomChannelValidationCode;
  message: string;
  field: string | null;
  contentIndex?: number;
}

export interface CustomChannelDraftValidationSummary {
  valid: boolean;
  issues: readonly CustomChannelDraftValidationIssue[];
}

export interface CustomChannelMediaPage {
  items: readonly CustomChannelMediaCard[];
  offset: number;
  limit: number;
  total: number | null;
  hasMore: boolean;
}

export interface CustomChannelMutationResult {
  snapshot: CustomChannelSnapshot;
  changedChannelId: string | null;
  currentChannelId: string | null;
}

export interface CustomChannelDraftResult {
  draft: CustomChannelDraftInput;
  validation: CustomChannelDraftValidationSummary;
}

export type CustomChannelEmptyRequest = {
  requestId: string;
  payload: Record<string, never>;
};

export type CustomChannelListMediaRequest = {
  requestId: string;
  payload: {
    sourceType: 'library' | 'collection' | 'playlist' | 'show' | 'search';
    sourceId?: string;
    query?: string;
    offset?: number;
    limit?: number;
    mediaTypes?: readonly CustomChannelMediaType[];
    draftContent?: readonly CustomChannelContentEntryInput[];
  };
};

export type CustomChannelGetMediaMetadataRequest = {
  requestId: string;
  payload: {
    ratingKey: string;
  };
};

export type CustomChannelDraftRequest = {
  requestId: string;
  payload: CustomChannelDraftInput;
};

export type CustomChannelDeleteRequest = {
  requestId: string;
  payload: {
    channelId: string;
    confirm: boolean;
  };
};

export type CustomChannelDuplicateDraftRequest = {
  requestId: string;
  payload: {
    channelId: string;
  };
};

export type CustomChannelReorderRequest = {
  requestId: string;
  payload: {
    channelIds: readonly string[];
  };
};

export type CustomChannelVisibilityRequest = {
  requestId: string;
  payload: {
    channelId: string;
    hidden: boolean;
  };
};

export type CustomChannelRequest =
  | CustomChannelEmptyRequest
  | CustomChannelListMediaRequest
  | CustomChannelGetMediaMetadataRequest
  | CustomChannelDraftRequest
  | CustomChannelDeleteRequest
  | CustomChannelDuplicateDraftRequest
  | CustomChannelReorderRequest
  | CustomChannelVisibilityRequest;

export function customChannelSuccess<TValue>(
  requestId: string,
  value: TValue,
): CustomChannelIpcResult<TValue> {
  return { ok: true, requestId, value };
}

export function customChannelFailure<TValue>(
  requestId: string,
  error: CustomChannelRuntimeError,
): CustomChannelIpcResult<TValue> {
  return { ok: false, requestId, error };
}

export function containsCustomChannelForbiddenRendererField(value: unknown): boolean {
  return findCustomChannelForbiddenRendererField(value) !== null;
}

export function findCustomChannelForbiddenRendererField(
  value: unknown,
  rootPath = '$',
): { path: string; key: string } | null {
  return findForbiddenField(value, rootPath, new WeakSet<object>());
}

function findForbiddenField(
  value: unknown,
  path: string,
  seen: WeakSet<object>,
): { path: string; key: string } | null {
  if (typeof value === 'string') {
    return hasForbiddenString(value) ? { path, key: '<string>' } : null;
  }
  if (!value || typeof value !== 'object') {
    return null;
  }
  if (seen.has(value)) {
    return null;
  }
  seen.add(value);

  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index++) {
      const finding = findForbiddenField(value[index], `${path}[${String(index)}]`, seen);
      if (finding) {
        return finding;
      }
    }
    return null;
  }

  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    if (isCustomChannelForbiddenRendererFieldKey(key)) {
      return { path, key };
    }
    const finding = findForbiddenField(child, `${path}.${key}`, seen);
    if (finding) {
      return finding;
    }
  }
  return null;
}

function isCustomChannelForbiddenRendererFieldKey(
  value: string,
): boolean {
  return CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS_NORMALIZED.has(
    normalizeForbiddenFieldKey(value),
  );
}

function normalizeForbiddenFieldKey(value: string): string {
  return value.toLowerCase().replaceAll(/[^a-z0-9]/gu, '');
}

function hasForbiddenString(value: string): boolean {
  return CUSTOM_CHANNEL_FORBIDDEN_STRING_PATTERNS.some((pattern) => pattern.test(value));
}
