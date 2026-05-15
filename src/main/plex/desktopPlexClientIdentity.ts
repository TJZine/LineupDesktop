import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

import type { DesktopAppDataPaths } from '../persistence/appDataPaths.js';

const CLIENT_IDENTITY_SCHEMA_VERSION = 1;
const CLIENT_IDENTITY_FILE_NAME = 'plex-client-identity.json';
const CLIENT_IDENTIFIER_PATTERN = /^lineup-desktop-[a-z0-9_-]+-[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

interface DesktopPlexClientIdentityFile {
  schemaVersion: typeof CLIENT_IDENTITY_SCHEMA_VERSION;
  clientIdentifier: string;
}

export async function readOrCreateDesktopPlexClientIdentifier(paths: DesktopAppDataPaths): Promise<string> {
  const identityPath = desktopPlexClientIdentityPath(paths);
  const existing = await readDesktopPlexClientIdentity(identityPath);
  if (existing !== null) {
    return existing;
  }

  const identity: DesktopPlexClientIdentityFile = {
    schemaVersion: CLIENT_IDENTITY_SCHEMA_VERSION,
    clientIdentifier: createDesktopPlexClientIdentifier(),
  };
  await writeDesktopPlexClientIdentity(identityPath, identity);
  return identity.clientIdentifier;
}

export function desktopPlexClientIdentityPath(paths: DesktopAppDataPaths): string {
  return path.join(paths.persistenceDirectory, CLIENT_IDENTITY_FILE_NAME);
}

async function readDesktopPlexClientIdentity(identityPath: string): Promise<string | null> {
  try {
    const parsed = JSON.parse(await fs.readFile(identityPath, 'utf8')) as Partial<DesktopPlexClientIdentityFile>;
    return isDesktopPlexClientIdentityFile(parsed) ? parsed.clientIdentifier : null;
  } catch (error) {
    if (isMissingFileError(error)) {
      return null;
    }
    return null;
  }
}

async function writeDesktopPlexClientIdentity(
  identityPath: string,
  identity: DesktopPlexClientIdentityFile,
): Promise<void> {
  await fs.mkdir(path.dirname(identityPath), { recursive: true });
  const temporaryPath = `${identityPath}.${process.pid}.${Date.now()}.tmp`;
  try {
    await fs.writeFile(temporaryPath, `${JSON.stringify(identity)}\n`, { encoding: 'utf8', flag: 'wx' });
    await fs.rename(temporaryPath, identityPath);
  } catch (error) {
    await fs.rm(temporaryPath, { force: true });
    throw error;
  }
}

function createDesktopPlexClientIdentifier(): string {
  return `lineup-desktop-${process.platform}-${randomUUID()}`;
}

function isDesktopPlexClientIdentityFile(value: Partial<DesktopPlexClientIdentityFile>): value is DesktopPlexClientIdentityFile {
  return (
    value.schemaVersion === CLIENT_IDENTITY_SCHEMA_VERSION &&
    typeof value.clientIdentifier === 'string' &&
    CLIENT_IDENTIFIER_PATTERN.test(value.clientIdentifier)
  );
}

function isMissingFileError(error: unknown): boolean {
  return error instanceof Error && 'code' in error && error.code === 'ENOENT';
}
