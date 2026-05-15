import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';

import type { DesktopAppDataPaths } from '../persistence/appDataPaths.js';

const CLIENT_IDENTITY_SCHEMA_VERSION = 1;
const CLIENT_IDENTITY_FILE_NAME = 'plex-client-identity.json';
const CLIENT_IDENTITY_LOCK_RETRY_COUNT = 50;
const CLIENT_IDENTITY_LOCK_RETRY_MS = 20;
const CLIENT_IDENTITY_LOCK_STALE_MS = 30_000;
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

  return withDesktopPlexClientIdentityLock(identityPath, async () => {
    const lockedExisting = await readDesktopPlexClientIdentity(identityPath);
    if (lockedExisting !== null) {
      return lockedExisting;
    }

    const identity: DesktopPlexClientIdentityFile = {
      schemaVersion: CLIENT_IDENTITY_SCHEMA_VERSION,
      clientIdentifier: createDesktopPlexClientIdentifier(),
    };
    await writeDesktopPlexClientIdentity(identityPath, identity);

    return await readDesktopPlexClientIdentity(identityPath) ?? identity.clientIdentifier;
  });
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

async function withDesktopPlexClientIdentityLock(
  identityPath: string,
  action: () => Promise<string>,
): Promise<string> {
  const lockPath = `${identityPath}.lock`;
  await fs.mkdir(path.dirname(identityPath), { recursive: true });

  for (let attempt = 0; attempt < CLIENT_IDENTITY_LOCK_RETRY_COUNT; attempt += 1) {
    try {
      const lockHandle = await fs.open(lockPath, 'wx');
      try {
        return await action();
      } finally {
        await lockHandle.close();
        await fs.rm(lockPath, { force: true });
      }
    } catch (error) {
      if (!isFileExistsError(error)) {
        throw error;
      }
      await removeStaleDesktopPlexClientIdentityLock(lockPath);
      await sleep(CLIENT_IDENTITY_LOCK_RETRY_MS);
    }
  }

  const existing = await readDesktopPlexClientIdentity(identityPath);
  if (existing !== null) {
    return existing;
  }
  throw new Error('Timed out acquiring Plex client identity lock');
}

async function removeStaleDesktopPlexClientIdentityLock(lockPath: string): Promise<void> {
  try {
    const stat = await fs.stat(lockPath);
    if (Date.now() - stat.mtimeMs > CLIENT_IDENTITY_LOCK_STALE_MS) {
      await fs.rm(lockPath, { force: true });
    }
  } catch (error) {
    if (!isMissingFileError(error)) {
      throw error;
    }
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

function isFileExistsError(error: unknown): boolean {
  return error instanceof Error && 'code' in error && error.code === 'EEXIST';
}
