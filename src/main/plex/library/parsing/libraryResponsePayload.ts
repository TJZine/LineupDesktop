import { PlexLibraryError } from '../plexLibraryError.js';
import type {
  PlexMediaContainer,
  RawCollection,
  RawDirectoryTag,
  RawLibrarySection,
  RawMediaItem,
  RawPlaylist,
  RawSeason,
} from '../types.js';
import { parseRequiredArray, parseRequiredObject } from './parserValidation.js';

type SearchHubPayload = {
  type: string;
  Metadata?: unknown;
};

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function extractMediaContainer<T>(
  response: PlexMediaContainer<T>,
  context: string,
): PlexMediaContainer<T>['MediaContainer'] {
  const mediaContainer = response.MediaContainer;

  if (!isObject(mediaContainer)) {
    throw new PlexLibraryError(
      'parse-error',
      `Invalid ${context} payload: missing MediaContainer object`,
    );
  }

  return mediaContainer as PlexMediaContainer<T>['MediaContainer'];
}

export function extractLibrarySectionDirectories(
  response: PlexMediaContainer<RawLibrarySection>,
  context: string,
): RawLibrarySection[] {
  return extractDirectoryArray<RawLibrarySection>(response, context);
}

export function extractMetadataArray<T>(response: PlexMediaContainer<T>, context: string): T[] {
  const mediaContainer = extractMediaContainer(response, context);
  const metadata = (mediaContainer as { Metadata?: unknown }).Metadata;

  if (metadata === undefined) {
    return [];
  }

  if (!Array.isArray(metadata)) {
    throw new PlexLibraryError('parse-error', `Invalid ${context} payload: Metadata must be an array`);
  }

  return metadata as T[];
}

export function extractDirectoryArray<T>(response: PlexMediaContainer<T>, context: string): T[] {
  const mediaContainer = extractMediaContainer(response, context);
  const directory = (mediaContainer as { Directory?: unknown }).Directory;

  if (directory === undefined) {
    return [];
  }

  if (!Array.isArray(directory)) {
    throw new PlexLibraryError('parse-error', `Invalid ${context} payload: Directory must be an array`);
  }

  return directory as T[];
}

export function extractSearchHubs(
  response: PlexMediaContainer<RawMediaItem>,
  context: string,
): SearchHubPayload[] {
  const mediaContainer = extractMediaContainer(response, context);
  const hubs = (mediaContainer as { Hub?: unknown }).Hub;

  if (hubs === undefined) {
    return [];
  }

  return parseRequiredArray<unknown>(hubs, `${context} Hub`).map((hub, index) =>
    parseRequiredObject<SearchHubPayload>(hub, `${context} Hub[${index}]`),
  );
}

export function extractSearchHubMetadata(hub: SearchHubPayload, context: string): RawMediaItem[] {
  if (hub.Metadata === undefined) {
    return [];
  }

  return parseRequiredArray<RawMediaItem>(hub.Metadata, `${context} Metadata`);
}

export type { RawCollection, RawDirectoryTag, RawLibrarySection, RawPlaylist, RawSeason };
