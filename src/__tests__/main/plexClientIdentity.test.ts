import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  desktopPlexClientIdentityPath,
  readOrCreateDesktopPlexClientIdentifier,
} from '../../main/plex/desktopPlexClientIdentity.js';

test('desktop Plex client identity is created once and reused from app data', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-plex-identity-'));
  const paths = {
    userDataDirectory: root,
    persistenceDirectory: path.join(root, 'persistence'),
    persistenceFilePath: path.join(root, 'persistence', 'lineup-desktop-persistence.json'),
  };

  const first = await readOrCreateDesktopPlexClientIdentifier(paths);
  const second = await readOrCreateDesktopPlexClientIdentifier(paths);
  const serialized = JSON.parse(await fs.readFile(desktopPlexClientIdentityPath(paths), 'utf8')) as {
    schemaVersion: number;
    clientIdentifier: string;
  };

  assert.match(first, /^lineup-desktop-/u);
  assert.equal(second, first);
  assert.equal(serialized.schemaVersion, 1);
  assert.equal(serialized.clientIdentifier, first);
});

test('desktop Plex client identity replaces invalid local identity files', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-plex-identity-invalid-'));
  const paths = {
    userDataDirectory: root,
    persistenceDirectory: path.join(root, 'persistence'),
    persistenceFilePath: path.join(root, 'persistence', 'lineup-desktop-persistence.json'),
  };
  await fs.mkdir(paths.persistenceDirectory, { recursive: true });
  await fs.writeFile(desktopPlexClientIdentityPath(paths), '{"schemaVersion":1,"clientIdentifier":"invalid"}\n');

  const identifier = await readOrCreateDesktopPlexClientIdentifier(paths);

  assert.match(identifier, /^lineup-desktop-/u);
  assert.notEqual(identifier, 'invalid');
});

test('desktop Plex client identity uses one identifier for concurrent first-run callers', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-plex-identity-concurrent-'));
  const paths = {
    userDataDirectory: root,
    persistenceDirectory: path.join(root, 'persistence'),
    persistenceFilePath: path.join(root, 'persistence', 'lineup-desktop-persistence.json'),
  };

  const identifiers = await Promise.all(
    Array.from({ length: 8 }, () => readOrCreateDesktopPlexClientIdentifier(paths)),
  );
  const serialized = JSON.parse(await fs.readFile(desktopPlexClientIdentityPath(paths), 'utf8')) as {
    schemaVersion: number;
    clientIdentifier: string;
  };

  assert.equal(new Set(identifiers).size, 1);
  assert.equal(serialized.clientIdentifier, identifiers[0]);
});

test('desktop Plex client identity serializes concurrent replacement of invalid files', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-plex-identity-invalid-concurrent-'));
  const paths = {
    userDataDirectory: root,
    persistenceDirectory: path.join(root, 'persistence'),
    persistenceFilePath: path.join(root, 'persistence', 'lineup-desktop-persistence.json'),
  };
  await fs.mkdir(paths.persistenceDirectory, { recursive: true });
  await fs.writeFile(desktopPlexClientIdentityPath(paths), '{"schemaVersion":1,"clientIdentifier":"invalid"}\n');

  const identifiers = await Promise.all(
    Array.from({ length: 8 }, () => readOrCreateDesktopPlexClientIdentifier(paths)),
  );
  const serialized = JSON.parse(await fs.readFile(desktopPlexClientIdentityPath(paths), 'utf8')) as {
    schemaVersion: number;
    clientIdentifier: string;
  };

  assert.equal(new Set(identifiers).size, 1);
  assert.equal(serialized.clientIdentifier, identifiers[0]);
  assert.notEqual(serialized.clientIdentifier, 'invalid');
});
