import { PlexLibraryError } from '../plexLibraryError.js';

export function parseRequiredObject<T>(value: unknown, context: string): T {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new PlexLibraryError('parse-error', `Invalid ${context} payload: expected an object`);
  }

  return value as T;
}

export function parseArrayOrEmpty<T>(value: unknown, context: string): T[] {
  if (value === undefined || value === null) {
    return [];
  }

  if (!Array.isArray(value)) {
    throw new PlexLibraryError('parse-error', `Invalid ${context} payload: expected an array`);
  }

  return value as T[];
}

export function parseRequiredArray<T>(value: unknown, context: string): T[] {
  if (!Array.isArray(value)) {
    throw new PlexLibraryError('parse-error', `Invalid ${context} payload: expected an array`);
  }

  return value as T[];
}

export function parseRequiredString(value: unknown, context: string, field: string): string {
  if (typeof value === 'string') {
    return value;
  }

  throwRequiredScalarError(context, field);
}

export function parseRequiredStringLike(value: unknown, context: string, field: string): string {
  if (typeof value === 'string') {
    return value;
  }

  if (typeof value === 'number' && Number.isFinite(value)) {
    return String(value);
  }

  throwRequiredScalarError(context, field);
}

export function parseRequiredFiniteNumber(value: unknown, context: string, field: string): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }

  throwRequiredScalarError(context, field);
}

function throwRequiredScalarError(context: string, field: string): never {
  throw new PlexLibraryError('parse-error', `Invalid ${context} payload: ${field} is required`);
}
