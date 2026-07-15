import test, { type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import { DEFAULT_DESKTOP_SETTINGS_VALUES } from '../../contracts/settings.js';
import {
  DesktopSettingsStore,
  DesktopSettingsStoreError,
  type DesktopSettingsFileSystem,
} from '../../main/persistence/desktopSettingsStore.js';

test('settings persistence returns defaults for missing/corrupt and does not rewrite reads', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const store = new DesktopSettingsStore({ settingsFilePath: file });
  assert.deepEqual(await store.loadSnapshot(), {
    schemaVersion: 1, revision: 0, status: 'missing', values: DEFAULT_DESKTOP_SETTINGS_VALUES,
  });
  await fs.writeFile(file, '{bad');
  assert.equal((await store.loadSnapshot()).status, 'corrupt');
  assert.equal(await fs.readFile(file, 'utf8'), '{bad');
});

test('settings persistence classifies representative malformed records as corrupt without rewriting bytes', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const malformed = [
    '[]',
    '{}',
    '{"schemaVersion":1.5,"revision":0,"values":{}}',
    '{"schemaVersion":1,"revision":0,"values":{},"extra":true}',
    JSON.stringify({ schemaVersion: 1, revision: -1, values: DEFAULT_DESKTOP_SETTINGS_VALUES }),
    JSON.stringify({ schemaVersion: 1, revision: 0, values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, launchMode: 'sometimes' } }),
  ];
  const store = new DesktopSettingsStore({ settingsFilePath: file });
  for (const bytes of malformed) {
    await fs.writeFile(file, bytes);
    const result = await store.loadSnapshot();
    assert.deepEqual(result, {
      schemaVersion: 1,
      revision: 0,
      status: 'corrupt',
      values: DEFAULT_DESKTOP_SETTINGS_VALUES,
    });
    assert.equal(await fs.readFile(file, 'utf8'), bytes);
  }
});

test('settings persistence maps non-missing read failures to storage unavailable without exposing details', async () => {
  const store = new DesktopSettingsStore({
    settingsFilePath: '/private/settings.json',
    fileSystem: nodeFileSystem({
      readFile: async () => { throw Object.assign(new Error('private read detail'), { code: 'EACCES' }); },
    }),
  });
  await assert.rejects(() => store.loadSnapshot(), hasCode('storage-unavailable'));
});

test('settings persistence repairs corrupt revision zero with an exact atomic record', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  await fs.writeFile(file, '{bad');
  const store = new DesktopSettingsStore({ settingsFilePath: file, processId: 7 });
  const nextValues = { ...DEFAULT_DESKTOP_SETTINGS_VALUES, guideDensity: 'compact' as const };
  const snapshot = await store.replace(0, nextValues);
  assert.deepEqual(snapshot, { schemaVersion: 1, revision: 1, status: 'ready', values: nextValues });
  assert.deepEqual(JSON.parse(await fs.readFile(file, 'utf8')), {
    schemaVersion: 1, revision: 1, values: nextValues,
  });
  if (os.platform() !== 'win32') {
    assert.equal((await fs.stat(file)).mode & 0o777, 0o600);
  }
});

test('settings persistence requests private temp-file permissions before atomic publication', async () => {
  const settingsFilePath = path.join('app-data', 'settings.json');
  const operations: string[] = [];
  let writtenFilePath: string | null = null;
  let chmodFilePath: string | null = null;
  let publishedSourcePath: string | null = null;
  let publishedDestinationPath: string | null = null;
  let writeMode: number | null = null;
  let chmodMode: number | null = null;
  const fileSystem: DesktopSettingsFileSystem = {
    readFile: async () => {
      throw Object.assign(new Error('missing'), { code: 'ENOENT' });
    },
    mkdir: async () => undefined,
    writeFile: async (filePath, _content, options) => {
      operations.push('write');
      writtenFilePath = filePath;
      writeMode = options.mode;
    },
    chmod: async (filePath, mode) => {
      operations.push('chmod');
      chmodFilePath = filePath;
      chmodMode = mode;
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

  assert.deepEqual(operations, ['write', 'chmod', 'rename']);
  assert.notEqual(writtenFilePath, settingsFilePath);
  assert.equal(path.dirname(writtenFilePath ?? ''), path.dirname(settingsFilePath));
  assert.equal(writeMode, 0o600);
  assert.equal(chmodFilePath, writtenFilePath);
  assert.equal(chmodMode, 0o600);
  assert.equal(publishedSourcePath, writtenFilePath);
  assert.equal(publishedDestinationPath, settingsFilePath);
});

test('settings persistence rejects unsupported versions and stale revisions without rewriting', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const unsupported = '{"schemaVersion":2,"revision":8,"values":{}}\n';
  await fs.writeFile(file, unsupported);
  const store = new DesktopSettingsStore({ settingsFilePath: file });
  assert.equal((await store.loadSnapshot()).status, 'unsupported-version');
  await assert.rejects(() => store.replace(0, { ...DEFAULT_DESKTOP_SETTINGS_VALUES }), hasCode('unsupported-version'));
  assert.equal(await fs.readFile(file, 'utf8'), unsupported);

  await fs.writeFile(file, JSON.stringify({ schemaVersion: 1, revision: 3, values: DEFAULT_DESKTOP_SETTINGS_VALUES }));
  await assert.rejects(() => store.replace(2, { ...DEFAULT_DESKTOP_SETTINGS_VALUES }), hasCode('revision-conflict'));
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
  const first = store.replace(1, { ...DEFAULT_DESKTOP_SETTINGS_VALUES, guideDensity: 'compact' });
  const second = store.replace(2, { ...DEFAULT_DESKTOP_SETTINGS_VALUES, previewBadgesEnabled: false });
  assert.equal((await first).revision, 2);
  assert.equal((await second).revision, 3);
});

test('settings persistence cleans a partially created temp file when write rejects', async (context) => {
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
      writeFile: async (tempFile, _content, options) => {
        await fs.writeFile(tempFile, 'partial private bytes', options);
        throw new Error('private partial write detail');
      },
      unlink: async (tempFile) => {
        unlinked.push(tempFile);
        await fs.unlink(tempFile);
      },
    }),
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
      writeFile: async (tempFile, _content, options) => {
        await fs.writeFile(tempFile, 'partial private bytes', options);
        throw new Error('private primary failure');
      },
      unlink: async () => { throw new Error('private cleanup failure'); },
    }),
  });
  await assert.rejects(
    () => store.replace(1, { ...DEFAULT_DESKTOP_SETTINGS_VALUES, setupReminderEnabled: false }),
    hasCode('operation-failed'),
  );
  assert.equal(await fs.readFile(file, 'utf8'), oldBytes);
});

test('settings persistence preserves authoritative bytes across mkdir, write, and chmod failures', async (context) => {
  for (const stage of ['mkdir', 'writeFile', 'chmod'] as const) {
    const directory = await createSettingsWorkspace(context, `lineup-settings-${stage}-`);
    const file = path.join(directory, 'settings.json');
    const baseStore = new DesktopSettingsStore({ settingsFilePath: file });
    await baseStore.replace(0, { ...DEFAULT_DESKTOP_SETTINGS_VALUES });
    const oldBytes = await fs.readFile(file, 'utf8');
    const overrides: Partial<DesktopSettingsFileSystem> = stage === 'mkdir'
      ? { mkdir: async () => { throw new Error('private mkdir detail'); } }
      : stage === 'writeFile'
        ? { writeFile: async () => { throw new Error('private write detail'); } }
        : { chmod: async () => { throw new Error('private chmod detail'); } };
    const store = new DesktopSettingsStore({ settingsFilePath: file, fileSystem: nodeFileSystem(overrides) });
    await assert.rejects(
      () => store.replace(1, { ...DEFAULT_DESKTOP_SETTINGS_VALUES, guideDensity: 'compact' }),
      hasCode('operation-failed'),
    );
    assert.equal(await fs.readFile(file, 'utf8'), oldBytes);
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

function nodeFileSystem(overrides: Partial<DesktopSettingsFileSystem>): DesktopSettingsFileSystem {
  return {
    readFile: (file, encoding) => fs.readFile(file, encoding),
    mkdir: (directory, options) => fs.mkdir(directory, options),
    writeFile: (file, content, options) => fs.writeFile(file, content, options),
    chmod: (file, mode) => fs.chmod(file, mode),
    rename: (source, destination) => fs.rename(source, destination),
    unlink: (file) => fs.unlink(file),
    ...overrides,
  };
}
