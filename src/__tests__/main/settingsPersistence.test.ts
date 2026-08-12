import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import {
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  SETTINGS_SCHEMA_VERSION,
  type DesktopSettingsValues,
} from '../../contracts/settings.js';
import {
  DesktopSettingsStore,
  DesktopSettingsStoreError,
  type DesktopSettingsFileHandle,
  type DesktopSettingsFileSystem,
} from '../../main/persistence/desktopSettingsStore.js';

test('settings persistence returns defaults for missing/corrupt and does not rewrite reads', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const store = new DesktopSettingsStore({ settingsFilePath: file });
  assert.deepEqual(await store.loadSnapshot(), {
    schemaVersion: SETTINGS_SCHEMA_VERSION, revision: 0, status: 'missing', values: DEFAULT_DESKTOP_SETTINGS_VALUES,
  });
  await fs.writeFile(file, '{bad');
  assert.equal((await store.loadSnapshot()).status, 'corrupt');
  assert.equal(await fs.readFile(file, 'utf8'), '{bad');
});

test('settings persistence classifies every non-v3 or malformed record as corrupt without rewriting bytes', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const malformed = [
    '[]',
    '{}',
    '{"schemaVersion":2.5,"revision":0,"values":{}}',
    '{"schemaVersion":2,"revision":0,"values":{},"extra":true}',
    JSON.stringify({ schemaVersion: 1, revision: 7, values: { launchMode: 'fullscreen' } }),
    JSON.stringify({ schemaVersion: 2, revision: 4, values: DEFAULT_DESKTOP_SETTINGS_VALUES }),
    JSON.stringify({ schemaVersion: 4, revision: 2, values: DEFAULT_DESKTOP_SETTINGS_VALUES }),
    JSON.stringify({ schemaVersion: SETTINGS_SCHEMA_VERSION, revision: -1, values: DEFAULT_DESKTOP_SETTINGS_VALUES }),
    JSON.stringify({ schemaVersion: SETTINGS_SCHEMA_VERSION, revision: 0, values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, launchMode: 'sometimes' } }),
  ];
  const store = new DesktopSettingsStore({ settingsFilePath: file });
  for (const bytes of malformed) {
    await fs.writeFile(file, bytes);
    assert.deepEqual(await store.loadSnapshot(), {
      schemaVersion: SETTINGS_SCHEMA_VERSION,
      revision: 0,
      status: 'corrupt',
      values: DEFAULT_DESKTOP_SETTINGS_VALUES,
    });
    assert.equal(await fs.readFile(file, 'utf8'), bytes);
  }
});

test('settings persistence repairs an invalid record through the revision-zero v3 replacement path', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const invalidBytes = JSON.stringify({
    schemaVersion: 2,
    revision: 8,
    values: { launchMode: 'fullscreen' },
  });
  await fs.writeFile(file, invalidBytes);
  const store = new DesktopSettingsStore({ settingsFilePath: file, processId: 17 });
  assert.deepEqual(await store.loadSnapshot(), {
    schemaVersion: SETTINGS_SCHEMA_VERSION,
    revision: 0,
    status: 'corrupt',
    values: DEFAULT_DESKTOP_SETTINGS_VALUES,
  });
  assert.equal(await fs.readFile(file, 'utf8'), invalidBytes);

  const nextValues: DesktopSettingsValues = {
    ...DEFAULT_DESKTOP_SETTINGS_VALUES,
    launchMode: 'fullscreen',
    guideTimeRange: 'wide',
    previewBadgesEnabled: false,
  };
  const repaired = await store.replace(0, nextValues);
  assert.deepEqual(repaired, {
    schemaVersion: SETTINGS_SCHEMA_VERSION,
    revision: 1,
    status: 'ready',
    values: nextValues,
  });
  assert.equal(await fs.readFile(file, 'utf8'), `${JSON.stringify({
    schemaVersion: SETTINGS_SCHEMA_VERSION,
    revision: 1,
    values: nextValues,
  })}\n`);
  if (os.platform() !== 'win32') {
    assert.equal((await fs.stat(file)).mode & 0o777, 0o600);
  }
});

test('settings persistence maps non-missing read failures to storage unavailable without exposing details', async () => {
  const store = new DesktopSettingsStore({
    settingsFilePath: ['', 'private', 'settings.json'].join('/'),
    fileSystem: nodeFileSystem({
      readFile: async () => { throw Object.assign(new Error('private read detail'), { code: 'EACCES' }); },
    }),
  });
  await assert.rejects(() => store.loadSnapshot(), hasCode('storage-unavailable'));
});

test('settings persistence synchronizes and closes its private temp handle before atomic publication', async () => {
  const settingsFilePath = path.join('app-data', 'settings.json');
  const operations: string[] = [];
  let openedFilePath: string | null = null;
  let publishedSourcePath: string | null = null;
  let publishedDestinationPath: string | null = null;
  let openFlags: string | null = null;
  let openMode: number | null = null;
  let chmodMode: number | null = null;
  const fileSystem: DesktopSettingsFileSystem = {
    readFile: async () => {
      throw Object.assign(new Error('missing'), { code: 'ENOENT' });
    },
    mkdir: async () => {
      operations.push('mkdir');
    },
    open: async (filePath, flags, mode) => {
      operations.push('open');
      openedFilePath = filePath;
      openFlags = flags;
      openMode = mode;
      return {
        writeFile: async () => {
          operations.push('write');
        },
        chmod: async (nextMode) => {
          operations.push('chmod');
          chmodMode = nextMode;
        },
        sync: async () => {
          operations.push('sync');
        },
        close: async () => {
          operations.push('close');
        },
      };
    },
    rename: async (sourcePath, destinationPath) => {
      operations.push('rename');
      publishedSourcePath = sourcePath;
      publishedDestinationPath = destinationPath;
    },
    unlink: async () => undefined,
  };

  const store = new DesktopSettingsStore({ settingsFilePath, fileSystem, processId: 7 });
  await store.replace(0, { ...DEFAULT_DESKTOP_SETTINGS_VALUES });

  assert.deepEqual(operations, ['mkdir', 'open', 'write', 'chmod', 'sync', 'close', 'rename']);
  assert.notEqual(openedFilePath, settingsFilePath);
  assert.equal(path.dirname(openedFilePath ?? ''), path.dirname(settingsFilePath));
  assert.equal(openFlags, 'wx');
  assert.equal(openMode, 0o600);
  assert.equal(chmodMode, 0o600);
  assert.equal(publishedSourcePath, openedFilePath);
  assert.equal(publishedDestinationPath, settingsFilePath);
});

test('settings persistence repairs corrupt revision zero with an exact atomic record', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  await fs.writeFile(file, '{bad');
  const store = new DesktopSettingsStore({ settingsFilePath: file, processId: 7 });
  const nextValues = {
    ...DEFAULT_DESKTOP_SETTINGS_VALUES,
    guideTimeRange: 'wide' as const,
    audioOutputDeviceId: `audio_${'b'.repeat(43)}` as const,
  };
  const snapshot = await store.replace(0, nextValues);
  assert.deepEqual(snapshot, { schemaVersion: SETTINGS_SCHEMA_VERSION, revision: 1, status: 'ready', values: nextValues });
  assert.deepEqual(JSON.parse(await fs.readFile(file, 'utf8')), {
    schemaVersion: SETTINGS_SCHEMA_VERSION, revision: 1, values: nextValues,
  });
});

test('settings persistence rejects stale revisions without rewriting authoritative bytes', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const store = new DesktopSettingsStore({ settingsFilePath: file });
  await store.replace(0, { ...DEFAULT_DESKTOP_SETTINGS_VALUES });
  const bytes = await fs.readFile(file, 'utf8');
  await assert.rejects(() => store.replace(0, { ...DEFAULT_DESKTOP_SETTINGS_VALUES }), hasCode('revision-conflict'));
  assert.equal(await fs.readFile(file, 'utf8'), bytes);
});

test('settings persistence rejects a maximum revision without rewriting authoritative bytes', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const bytes = JSON.stringify({
    schemaVersion: SETTINGS_SCHEMA_VERSION,
    revision: Number.MAX_SAFE_INTEGER,
    values: DEFAULT_DESKTOP_SETTINGS_VALUES,
  });
  await fs.writeFile(file, bytes);
  const store = new DesktopSettingsStore({ settingsFilePath: file });
  await assert.rejects(
    () => store.replace(Number.MAX_SAFE_INTEGER, { ...DEFAULT_DESKTOP_SETTINGS_VALUES }),
    hasCode('operation-failed'),
  );
  assert.equal(await fs.readFile(file, 'utf8'), bytes);
});

test('settings persistence serializes replacements and preserves authoritative bytes on rename failure', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const baseStore = new DesktopSettingsStore({ settingsFilePath: file });
  await baseStore.replace(0, { ...DEFAULT_DESKTOP_SETTINGS_VALUES });
  const oldBytes = await fs.readFile(file, 'utf8');
  const failing = new DesktopSettingsStore({
    settingsFilePath: file,
    fileSystem: nodeFileSystem({ rename: async () => { throw new Error('private rename detail'); } }),
  });
  await assert.rejects(
    () => failing.replace(1, { ...DEFAULT_DESKTOP_SETTINGS_VALUES, setupReminderEnabled: false }),
    hasCode('operation-failed'),
  );
  assert.equal(await fs.readFile(file, 'utf8'), oldBytes);

  const store = new DesktopSettingsStore({ settingsFilePath: file });
  const first = store.replace(1, { ...DEFAULT_DESKTOP_SETTINGS_VALUES, guideTimeRange: 'wide' });
  const second = store.replace(2, { ...DEFAULT_DESKTOP_SETTINGS_VALUES, previewBadgesEnabled: false });
  assert.equal((await first).revision, 2);
  assert.equal((await second).revision, 3);
});

test('settings persistence cleans its owned temp file when handle write rejects', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const baseStore = new DesktopSettingsStore({ settingsFilePath: file });
  await baseStore.replace(0, { ...DEFAULT_DESKTOP_SETTINGS_VALUES });
  const oldBytes = await fs.readFile(file, 'utf8');
  const unlinked: string[] = [];
  const store = new DesktopSettingsStore({
    settingsFilePath: file,
    processId: 91,
    fileSystem: nodeFileSystem({
      unlink: async (tempFile) => {
        unlinked.push(tempFile);
        await fs.unlink(tempFile);
      },
    }, () => ({
      writeFile: async () => {
        throw new Error('private partial write detail');
      },
    })),
  });
  await assert.rejects(
    () => store.replace(1, { ...DEFAULT_DESKTOP_SETTINGS_VALUES, previewBadgesEnabled: false }),
    hasCode('operation-failed'),
  );
  assert.equal(await fs.readFile(file, 'utf8'), oldBytes);
  assert.deepEqual(unlinked, [`${file}.91.1.tmp`]);
  assert.deepEqual(await fs.readdir(directory), ['settings.json']);
});

test('settings persistence keeps cleanup failure secondary to a partial-write failure', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const baseStore = new DesktopSettingsStore({ settingsFilePath: file });
  await baseStore.replace(0, { ...DEFAULT_DESKTOP_SETTINGS_VALUES });
  const oldBytes = await fs.readFile(file, 'utf8');
  const store = new DesktopSettingsStore({
    settingsFilePath: file,
    fileSystem: nodeFileSystem({
      unlink: async () => { throw new Error('private cleanup failure'); },
    }, () => ({
      writeFile: async () => {
        throw new Error('private primary failure');
      },
    })),
  });
  await assert.rejects(
    () => store.replace(1, { ...DEFAULT_DESKTOP_SETTINGS_VALUES, setupReminderEnabled: false }),
    hasCode('operation-failed'),
  );
  assert.equal(await fs.readFile(file, 'utf8'), oldBytes);
});

test('settings persistence preserves authoritative bytes across every pre-publication failure', async (context) => {
  for (const stage of ['mkdir', 'open', 'writeFile', 'chmod', 'sync', 'close', 'rename'] as const) {
    const directory = await createSettingsWorkspace(context, `lineup-settings-${stage}-`);
    const file = path.join(directory, 'settings.json');
    const baseStore = new DesktopSettingsStore({ settingsFilePath: file });
    await baseStore.replace(0, { ...DEFAULT_DESKTOP_SETTINGS_VALUES });
    const oldBytes = await fs.readFile(file, 'utf8');
    const cleanupAttempts: string[] = [];
    let closeAttempts = 0;
    const fileSystemOverrides: Partial<DesktopSettingsFileSystem> = stage === 'mkdir'
      ? { mkdir: async () => { throw new Error('private mkdir detail'); } }
      : stage === 'open'
        ? { open: async () => { throw new Error('private open detail'); } }
        : stage === 'rename'
          ? { rename: async () => { throw new Error('private rename detail'); } }
          : {};
    const createHandleOverrides = (handle: DesktopSettingsFileHandle): Partial<DesktopSettingsFileHandle> => ({
      ...(stage === 'writeFile'
        ? { writeFile: async () => { throw new Error('private write detail'); } }
        : stage === 'chmod'
          ? { chmod: async () => { throw new Error('private chmod detail'); } }
          : stage === 'sync'
            ? { sync: async () => { throw new Error('private sync detail'); } }
            : {}),
      close: async () => {
        closeAttempts += 1;
        await handle.close();
        if (stage === 'close') throw new Error('private close detail');
      },
    });
    const fileSystem = nodeFileSystem({
      ...fileSystemOverrides,
      unlink: async (tempFile) => {
        cleanupAttempts.push(tempFile);
        try {
          await fs.unlink(tempFile);
        } catch (error: unknown) {
          if (!(error instanceof Error && 'code' in error && error.code === 'ENOENT')) throw error;
        }
      },
    }, createHandleOverrides);
    const store = new DesktopSettingsStore({ settingsFilePath: file, fileSystem });
    await assert.rejects(
      () => store.replace(1, { ...DEFAULT_DESKTOP_SETTINGS_VALUES, guideTimeRange: 'wide' }),
      hasCode('operation-failed'),
    );
    assert.equal(await fs.readFile(file, 'utf8'), oldBytes);
    assert.equal(closeAttempts, stage === 'mkdir' || stage === 'open' ? 0 : 1);
    assert.equal(cleanupAttempts.length, stage === 'mkdir' || stage === 'open' ? 0 : 1);
  }
});

async function createSettingsWorkspace(
  context: TestContext,
  prefix = 'lineup-settings-',
): Promise<string> {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
  context.after(async () => {
    await fs.rm(directory, { recursive: true, force: true });
  });
  return directory;
}

function hasCode(code: DesktopSettingsStoreError['code']) {
  return (error: unknown): boolean => error instanceof DesktopSettingsStoreError && error.code === code &&
    !error.message.includes('private');
}

function nodeFileSystem(
  overrides: Partial<DesktopSettingsFileSystem>,
  createHandleOverrides: (
    handle: DesktopSettingsFileHandle,
  ) => Partial<DesktopSettingsFileHandle> = () => ({}),
): DesktopSettingsFileSystem {
  return {
    readFile: (file, encoding) => fs.readFile(file, encoding),
    mkdir: (directory, options) => fs.mkdir(directory, options),
    open: async (file, flags, mode) => {
      const handle = await fs.open(file, flags, mode);
      const settingsHandle: DesktopSettingsFileHandle = {
        writeFile: async (content, encoding) => {
          await handle.writeFile(content, { encoding });
        },
        chmod: (nextMode) => handle.chmod(nextMode),
        sync: () => handle.sync(),
        close: () => handle.close(),
      };
      return {
        ...settingsHandle,
        ...createHandleOverrides(settingsHandle),
      };
    },
    rename: (source, destination) => fs.rename(source, destination),
    unlink: (file) => fs.unlink(file),
    ...overrides,
  };
}
