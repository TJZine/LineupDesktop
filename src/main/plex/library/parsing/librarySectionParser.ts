import { PlexLibraryError } from '../plexLibraryError.js';
import type { PlexLibrarySection, PlexLibrarySectionType, RawLibrarySection } from '../types.js';
import { parseRequiredObject } from './parserValidation.js';

export function parseLibrarySections(directories: RawLibrarySection[]): PlexLibrarySection[] {
  return directories.map((directory, index) =>
    parseLibrarySection(
      parseRequiredObject<RawLibrarySection>(directory, `library sections[${index}]`),
    ),
  );
}

function parseLibrarySection(data: RawLibrarySection): PlexLibrarySection {
  const key = parseRequiredLibrarySectionString(data.key, 'key');
  const uuid = parseRequiredLibrarySectionString(data.uuid, 'uuid');
  const title = parseRequiredLibrarySectionString(data.title, 'title');
  const type = parseRequiredLibrarySectionString(data.type, 'type');
  const agent = parseRequiredLibrarySectionString(data.agent, 'agent');
  const scanner = parseRequiredLibrarySectionString(data.scanner, 'scanner');

  return {
    id: key,
    uuid,
    title,
    type: mapLibraryType(type),
    agent,
    scanner,
    contentCount: null,
    lastScannedAt: parseLibraryScannedAt(data.scannedAt),
    art: data.art ?? null,
    thumb: data.thumb ?? null,
  };
}

function parseLibraryScannedAt(value: unknown): Date {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return new Date(0);
  }

  const scannedAt = new Date(value * 1000);
  return Number.isNaN(scannedAt.getTime()) ? new Date(0) : scannedAt;
}

function parseRequiredLibrarySectionString(value: unknown, field: string): string {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed.length > 0) {
      return trimmed;
    }
  }

  throw new PlexLibraryError('parse-error', `Invalid library section payload: ${field} is required`);
}

export function mapLibraryType(type: string): PlexLibrarySectionType {
  switch (type) {
    case 'movie':
      return 'movie';
    case 'show':
      return 'show';
    case 'artist':
      return 'artist';
    case 'photo':
      return 'photo';
    default:
      throw new PlexLibraryError(
        'parse-error',
        `Invalid library section payload: unknown library type "${type}"`,
      );
  }
}
