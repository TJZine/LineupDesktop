import { PlexAuthError } from './plexAuthError.js';
import { parseHomeUsersPayloadData } from './plexHomeUsersPayloadParser.js';
import { parseSwitchPayloadData } from './plexSwitchPayloadParser.js';
import type { PlexAuthToken, PlexHomeUser, PlexPinRequest } from './types.js';

export type PlexResponsePayload =
  | { kind: 'json'; data: unknown }
  | { kind: 'text'; data: string }
  | { kind: 'empty' };

export interface PlexTextResponseLike {
  headers?: {
    get(name: string): string | null;
  };
  text(): Promise<string>;
}

const PREFERRED_SUBTITLE_LANGUAGE_KEYS = [
  'preferredSubtitleLanguage',
  'subtitleLanguage',
  'preferredSubtitleLanguageCode',
  'subtitleLanguageCode',
] as const;

export async function readPlexResponse(response: PlexTextResponseLike): Promise<PlexResponsePayload> {
  const contentType = response.headers?.get('Content-Type') ?? '';
  const text = await response.text();
  const trimmed = text.trim();

  if (trimmed.length === 0) {
    return { kind: 'empty' };
  }

  if (contentType.includes('json') || trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      return { kind: 'json', data: JSON.parse(trimmed) };
    } catch {
      throw new PlexAuthError('parse-error', 'Unable to parse Plex response JSON payload');
    }
  }

  return { kind: 'text', data: text };
}

export function parsePinResponse(data: unknown, fallbackClientId: string): PlexPinRequest {
  const payload = requireRecord(data, 'PIN response');
  const id = requireFiniteNumber(payload.id, 'PIN response id');
  const code = requireNonEmptyString(payload.code, 'PIN response code');
  const expiresAt = requireDate(payload.expiresAt, 'PIN response expiresAt');
  const authToken = readNullableString(payload.authToken, 'PIN response authToken');
  const clientIdentifier = readOptionalString(payload.clientIdentifier) ?? fallbackClientId;

  return {
    id,
    code,
    expiresAt,
    authToken,
    clientIdentifier,
  };
}

export function parseUserResponse(data: unknown, token: string): PlexAuthToken {
  const payload = unwrapUserResponseRecord(requireRecord(data, 'User response'));
  const userId = requireUserId(readFirstValue(payload, ['id', 'uuid']), 'Plex user id');
  const username = readFirstNonEmptyString(payload, [
    'username',
    'title',
    'friendlyName',
    'name',
  ]) ?? 'Plex account';
  const email = readOptionalString(payload.email) ?? '';
  const thumb = typeof payload.thumb === 'string' ? payload.thumb : '';
  const preferredSubtitleLanguage = extractPreferredSubtitleLanguage(payload);

  return {
    token,
    userId,
    username,
    email,
    thumb,
    expiresAt: null,
    issuedAt: new Date(),
    preferredSubtitleLanguage,
  };
}

function unwrapUserResponseRecord(payload: Record<string, unknown>): Record<string, unknown> {
  const candidates = [
    payload.user,
    payload.User,
    isRecord(payload.MediaContainer) ? payload.MediaContainer.user : undefined,
    isRecord(payload.MediaContainer) ? payload.MediaContainer.User : undefined,
  ];

  for (const candidate of candidates) {
    if (isRecord(candidate)) {
      return candidate;
    }
  }

  return payload;
}

export function parseHomeUsersPayload(payload: PlexResponsePayload): PlexHomeUser[] {
  if (payload.kind === 'empty') {
    return [];
  }
  return parseHomeUsersPayloadData(payload.data);
}

export function parseSwitchResponsePayload(payload: PlexResponsePayload): { authToken: string } {
  if (payload.kind === 'empty') {
    throw new PlexAuthError('parse-error', 'Plex Home switch response was empty');
  }
  return parseSwitchPayloadData(payload.data);
}

function coerceLanguageValue(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function extractPreferredSubtitleLanguage(data: Record<string, unknown>): string | null {
  return (
    extractPreferredSubtitleLanguageFromRecord(data) ??
    extractPreferredSubtitleLanguageFromSettings(data.settings)
  );
}

function extractPreferredSubtitleLanguageFromRecord(
  record: Record<string, unknown>,
): string | null {
  for (const key of PREFERRED_SUBTITLE_LANGUAGE_KEYS) {
    const value = coerceLanguageValue(record[key]);
    if (value) {
      return value;
    }
  }

  return null;
}

function extractPreferredSubtitleLanguageFromSettings(settings: unknown): string | null {
  if (!settings || typeof settings !== 'object') {
    return null;
  }
  return extractPreferredSubtitleLanguageFromRecord(settings as Record<string, unknown>);
}

function requireRecord(value: unknown, label: string): Record<string, unknown> {
  if (isRecord(value)) {
    return value as Record<string, unknown>;
  }

  throw new PlexAuthError('parse-error', `${label} was not an object`);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function readFirstValue(record: Record<string, unknown>, keys: readonly string[]): unknown {
  for (const key of keys) {
    if (record[key] !== undefined && record[key] !== null) {
      return record[key];
    }
  }
  return undefined;
}

function readFirstNonEmptyString(
  record: Record<string, unknown>,
  keys: readonly string[],
): string | null {
  for (const key of keys) {
    const value = readOptionalString(record[key]);
    if (value !== null) {
      return value;
    }
  }
  return null;
}

function requireFiniteNumber(value: unknown, label: string): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }

  throw new PlexAuthError('parse-error', `${label} was missing or invalid`);
}

function requireNonEmptyString(value: unknown, label: string): string {
  if (typeof value === 'string' && value.trim().length > 0) {
    return value.trim();
  }

  throw new PlexAuthError('parse-error', `${label} was missing or invalid`);
}

function requireUserId(value: unknown, label: string): string {
  if (typeof value === 'string' && value.trim().length > 0) {
    return value.trim();
  }

  if (typeof value === 'number' && Number.isInteger(value) && value > 0) {
    return String(value);
  }

  throw new PlexAuthError('parse-error', `${label} was missing or invalid`);
}

function requireDate(value: unknown, label: string): Date {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new PlexAuthError('parse-error', `${label} was missing or invalid`);
  }

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new PlexAuthError('parse-error', `${label} was missing or invalid`);
  }

  return parsed;
}

function readNullableString(value: unknown, label: string): string | null {
  if (value === undefined || value === null) {
    return null;
  }

  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  throw new PlexAuthError('parse-error', `${label} was invalid`);
}

function readOptionalString(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
