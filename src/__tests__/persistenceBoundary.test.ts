import { Buffer } from 'node:buffer';
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import {
  PERSISTENCE_FORBIDDEN_RENDERER_FIELD_KEYS,
  containsPersistenceForbiddenRendererField,
  type PlexSelectedServerSummary,
} from '../contracts/persistence.js';
import { resolveDesktopAppDataPaths } from '../main/persistence/appDataPaths.js';
import { DesktopPersistenceStore } from '../main/persistence/desktopPersistenceStore.js';
import {
  SecureStorageUnavailableError,
  createElectronSafeStorageCodec,
  type ElectronSafeStorageLike,
  type SecureStorageAvailability,
  type SecureStringCodec,
  type SecureStringDecryptResult,
} from '../main/persistence/secureStorageCodec.js';

class FakeSecureStringCodec implements SecureStringCodec {
  public availability: SecureStorageAvailability = {
    available: true,
    backend: 'electron-safe-storage',
  };

  public shouldReencrypt = false;
  public encryptions = 0;

  async getAvailability(): Promise<SecureStorageAvailability> {
    return this.availability;
  }

  async encryptString(value: string): Promise<Buffer> {
    if (!this.availability.available) {
      throw new SecureStorageUnavailableError();
    }
    this.encryptions += 1;
    return Buffer.from(`encrypted:${value.split('').reverse().join('')}`, 'utf8');
  }

  async decryptString(encrypted: Buffer): Promise<SecureStringDecryptResult> {
    if (!this.availability.available) {
      throw new SecureStorageUnavailableError();
    }
    const serialized = encrypted.toString('utf8');
    if (!serialized.startsWith('encrypted:')) {
      throw new Error('Invalid encrypted payload.');
    }
    return {
      value: serialized.slice('encrypted:'.length).split('').reverse().join(''),
      shouldReencrypt: this.shouldReencrypt,
    };
  }
}

test('desktop persistence store encrypts credentials and returns renderer-safe snapshots', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const codec = new FakeSecureStringCodec();
  const store = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: codec,
    nowMs: () => 1_000,
  });

  const saveResult = await store.savePlexCredential({
    accountId: 'account-1',
    secretValue: 'rd09-secret-value',
    profile: {
      accountId: 'account-1',
      username: 'viewer',
      displayName: 'Viewer',
    },
  });

  assert.equal(saveResult.ok, true);
  assert.equal(codec.encryptions, 1);
  if (saveResult.ok) {
    assert.deepEqual(saveResult.handle, {
      credentialId: 'plex-account:account-1',
      accountId: 'account-1',
      kind: 'plex-account',
      createdAtMs: 1_000,
      updatedAtMs: 1_000,
    });
  }

  const persisted = await fs.readFile(path.join(temporaryDirectory, 'persistence.json'), 'utf8');
  assert.equal(persisted.includes('rd09-secret-value'), false);
  const persistedFile = JSON.parse(persisted) as {
    credentials?: readonly {
      credentialId?: unknown;
      accountId?: unknown;
      kind?: unknown;
    }[];
  };
  assert.deepEqual(
    persistedFile.credentials?.map(({ credentialId, accountId, kind }) => ({
      credentialId,
      accountId,
      kind,
    })),
    [
      {
        credentialId: 'plex-account:account-1',
        accountId: 'account-1',
        kind: 'plex-account',
      },
    ],
  );

  const readResult = await store.readPlexCredentialSecret('account-1');
  assert.equal(readResult.status, 'present');
  if (readResult.status === 'present') {
    assert.equal(readResult.secretValue, 'rd09-secret-value');
    assert.equal(readResult.shouldReencrypt, false);
  }

  const snapshot = await store.getRendererSafeSnapshot();
  assert.equal(containsPersistenceForbiddenRendererField(snapshot), false);
  assert.equal(JSON.stringify(snapshot).includes('rd09-secret-value'), false);
  assert.deepEqual(snapshot.accounts, [
    {
      accountId: 'account-1',
      username: 'viewer',
      displayName: 'Viewer',
    },
  ]);
  assert.equal(snapshot.credentialHandles[0]?.credentialId, 'plex-account:account-1');
  assert.equal(snapshot.storage.credentials, 'available');
});

test('desktop persistence store records selected server state without secure storage custody', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const store = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: new FakeSecureStringCodec(),
  });
  const selectedServer: PlexSelectedServerSummary = {
    serverId: 'server-1',
    name: 'Living Room Server',
    source: 'discovery',
    lastSelectedAtMs: 2_000,
  };

  const snapshot = await store.setSelectedPlexServer(selectedServer);

  assert.deepEqual(snapshot.selectedServer, selectedServer);
  assert.equal(containsPersistenceForbiddenRendererField(snapshot), false);
});

test('desktop persistence store fails closed when secure storage is unavailable', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const codec = new FakeSecureStringCodec();
  codec.availability = {
    available: false,
    backend: 'electron-safe-storage',
    reason: 'encryption-unavailable',
  };
  const store = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: codec,
  });

  const saveResult = await store.savePlexCredential({
    accountId: 'account-1',
    secretValue: 'rd09-secret-value',
  });
  const readResult = await store.readPlexCredentialSecret('account-1');
  const snapshot = await store.getRendererSafeSnapshot();

  assert.equal(saveResult.ok, false);
  if (!saveResult.ok) {
    assert.equal(saveResult.status, 'unavailable');
  }
  assert.equal(readResult.status, 'missing');
  assert.equal(snapshot.storage.credentials, 'unavailable');
  await assert.rejects(
    fs.readFile(path.join(temporaryDirectory, 'persistence.json'), 'utf8'),
    { code: 'ENOENT' },
  );
});

test('desktop persistence store classifies corrupt files without leaking secret-shaped content', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const persistenceFilePath = path.join(temporaryDirectory, 'persistence.json');
  await fs.writeFile(persistenceFilePath, '{"schemaVersion":1,"credentials":"not-array"}\n');
  const store = new DesktopPersistenceStore({
    persistenceFilePath,
    secureStringCodec: new FakeSecureStringCodec(),
  });

  const readResult = await store.readPlexCredentialSecret('account-1');
  const snapshot = await store.getRendererSafeSnapshot();
  const saveResult = await store.savePlexCredential({
    accountId: 'account-1',
    secretValue: 'rd09-secret-value',
  });
  const selectedServerResult = await store.setSelectedPlexServer({
    serverId: 'server-1',
    name: 'Server',
    source: 'manual',
    lastSelectedAtMs: 1,
  });

  assert.equal(readResult.status, 'corrupt');
  assert.equal(snapshot.storage.credentials, 'corrupt');
  assert.equal(snapshot.storage.appData, 'corrupt');
  assert.equal(saveResult.ok, false);
  if (!saveResult.ok) {
    assert.equal(saveResult.status, 'corrupt');
  }
  assert.equal(selectedServerResult.storage.appData, 'corrupt');
  assert.deepEqual(JSON.parse(await fs.readFile(persistenceFilePath, 'utf8')), {
    schemaVersion: 1,
    credentials: 'not-array',
  });
  assert.equal(JSON.stringify(snapshot).includes('rd09-secret-value'), false);
});

test('desktop persistence store reencrypts credentials when secure storage requests it', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const codec = new FakeSecureStringCodec();
  const store = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: codec,
    nowMs: () => 1_000,
  });
  await store.savePlexCredential({
    accountId: 'account-1',
    secretValue: 'rd09-secret-value',
  });

  codec.shouldReencrypt = true;
  const readResult = await store.readPlexCredentialSecret('account-1');

  assert.equal(readResult.status, 'present');
  assert.equal(codec.encryptions, 2);
  if (readResult.status === 'present') {
    assert.equal(readResult.shouldReencrypt, true);
  }
});

test('persistence contracts recursively reject renderer-forbidden fields', () => {
  assert.equal(
    containsPersistenceForbiddenRendererField({
      storage: { credentials: 'available', appData: 'available' },
      nested: { credentialMaterial: 'redacted-by-rejection' },
    }),
    true,
  );
  assert.equal(
    containsPersistenceForbiddenRendererField({
      storage: { credentials: 'available', appData: 'available' },
      selectedServer: {
        serverId: 'server-1',
        name: 'Server',
        source: 'manual',
        lastSelectedAtMs: 1,
      },
    }),
    false,
  );
  assert.equal(PERSISTENCE_FORBIDDEN_RENDERER_FIELD_KEYS.includes('userDataPath'), true);
  assert.equal(PERSISTENCE_FORBIDDEN_RENDERER_FIELD_KEYS.includes('secretValue'), true);
});

test('app-data path resolver keeps filesystem ownership in main persistence', () => {
  const paths = resolveDesktopAppDataPaths({
    getPath(name) {
      assert.equal(name, 'userData');
      return path.join('/tmp', 'lineup-desktop-user-data');
    },
  });

  assert.equal(paths.userDataDirectory, path.join('/tmp', 'lineup-desktop-user-data'));
  assert.equal(
    paths.persistenceDirectory,
    path.join('/tmp', 'lineup-desktop-user-data', 'persistence'),
  );
  assert.equal(
    paths.persistenceFilePath,
    path.join('/tmp', 'lineup-desktop-user-data', 'persistence', 'lineup-desktop-persistence.json'),
  );
});

test('Electron safeStorage codec uses async availability and fails closed', async () => {
  const safeStorage = new FakeElectronSafeStorage();
  const codec = createElectronSafeStorageCodec(safeStorage);

  assert.deepEqual(await codec.getAvailability(), {
    available: true,
    backend: 'electron-safe-storage',
    selectedStorageBackend: 'test-backend',
  });
  const encrypted = await codec.encryptString('rd09-secret-value');
  const decrypted = await codec.decryptString(encrypted);

  assert.equal(encrypted.toString('utf8').includes('rd09-secret-value'), false);
  assert.deepEqual(decrypted, {
    value: 'rd09-secret-value',
    shouldReencrypt: false,
  });

  safeStorage.asyncAvailable = false;
  assert.deepEqual(await codec.getAvailability(), {
    available: false,
    backend: 'electron-safe-storage',
    reason: 'encryption-unavailable',
    selectedStorageBackend: 'test-backend',
  });
  await assert.rejects(
    () => codec.encryptString('rd09-secret-value'),
    SecureStorageUnavailableError,
  );
});

class FakeElectronSafeStorage implements ElectronSafeStorageLike {
  public asyncAvailable = true;
  public syncAvailable = true;

  async isAsyncEncryptionAvailable(): Promise<boolean> {
    return this.asyncAvailable;
  }

  isEncryptionAvailable(): boolean {
    return this.syncAvailable;
  }

  async encryptStringAsync(plainText: string): Promise<Buffer> {
    return Buffer.from(`safe-storage:${plainText.split('').reverse().join('')}`, 'utf8');
  }

  async decryptStringAsync(encrypted: Buffer): Promise<{
    result: string;
    shouldReEncrypt: boolean;
  }> {
    const serialized = encrypted.toString('utf8');
    assert.equal(serialized.startsWith('safe-storage:'), true);
    return {
      result: serialized.slice('safe-storage:'.length).split('').reverse().join(''),
      shouldReEncrypt: false,
    };
  }

  getSelectedStorageBackend(): string {
    return 'test-backend';
  }
}

async function createTemporaryDirectory(): Promise<string> {
  return fs.mkdtemp(path.join(os.tmpdir(), 'lineup-rd09-'));
}
