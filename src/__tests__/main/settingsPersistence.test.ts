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
  type DesktopSettingsFileSystem,
} from '../../main/persistence/desktopSettingsStore.js';

test('settings persistence returns defaults for missing/corrupt and does not rewrite reads', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const events: unknown[] = [];
  const store = new DesktopSettingsStore({
    settingsFilePath: file,
    migrationEventSink: (event) => events.push(event),
  });
  assert.deepEqual(await store.loadSnapshot(), {
    schemaVersion: 2, revision: 0, status: 'missing', values: DEFAULT_DESKTOP_SETTINGS_VALUES,
  });
  await fs.writeFile(file, '{bad');
  assert.equal((await store.loadSnapshot()).status, 'corrupt');
  assert.equal(await fs.readFile(file, 'utf8'), '{bad');
  assert.deepEqual(events, []);
});

test('settings persistence classifies representative malformed records as corrupt without rewriting bytes', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const malformed = [
    '[]',
    '{}',
    '{"schemaVersion":2.5,"revision":0,"values":{}}',
    '{"schemaVersion":2,"revision":0,"values":{},"extra":true}',
    JSON.stringify({ schemaVersion: 2, revision: -1, values: DEFAULT_DESKTOP_SETTINGS_VALUES }),
    JSON.stringify({ schemaVersion: 2, revision: 0, values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, launchMode: 'sometimes' } }),
  ];
  const events: unknown[] = [];
  const store = new DesktopSettingsStore({
    settingsFilePath: file,
    migrationEventSink: (event) => events.push(event),
  });
  for (const bytes of malformed) {
    await fs.writeFile(file, bytes);
    const result = await store.loadSnapshot();
    assert.deepEqual(result, {
      schemaVersion: 2,
      revision: 0,
      status: 'corrupt',
      values: DEFAULT_DESKTOP_SETTINGS_VALUES,
    });
    assert.equal(await fs.readFile(file, 'utf8'), bytes);
  }
  assert.deepEqual(events, []);
});

test('settings persistence atomically migrates version one once with fixed diagnostics', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const versionOne = {
    schemaVersion: 1,
    revision: 7,
    values: {
      launchMode: 'fullscreen',
      guideDensity: 'compact',
      previewBadgesEnabled: false,
      setupReminderEnabled: false,
    },
  } as const;
  await fs.writeFile(file, `${JSON.stringify(versionOne)}\n`);
  const events: unknown[] = [];
  const store = new DesktopSettingsStore({
    settingsFilePath: file,
    processId: 17,
    migrationEventSink: (event) => events.push(event),
  });

  const migrated = await store.loadSnapshot();
  const expectedValues: DesktopSettingsValues = {
    ...DEFAULT_DESKTOP_SETTINGS_VALUES,
    launchMode: 'fullscreen',
    guideDensity: 'compact',
    previewBadgesEnabled: false,
    setupReminderEnabled: false,
  };
  assert.deepEqual(migrated, {
    schemaVersion: SETTINGS_SCHEMA_VERSION,
    revision: 8,
    status: 'ready',
    values: expectedValues,
  });
  assert.equal(await fs.readFile(file, 'utf8'), `${JSON.stringify({
    schemaVersion: SETTINGS_SCHEMA_VERSION,
    revision: 8,
    values: expectedValues,
  })}\n`);
  assert.deepEqual(events, [{
    fromVersion: 1,
    toVersion: 2,
    status: 'succeeded',
    revision: 8,
  }]);

  assert.deepEqual(await store.loadSnapshot(), migrated);
  assert.equal(events.length, 1);
});

test('settings persistence preserves version-one bytes and emits a fixed event when migration publication fails', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const versionOneBytes = `${JSON.stringify({
    schemaVersion: 1,
    revision: 4,
    values: {
      launchMode: 'windowed',
      guideDensity: 'comfortable',
      previewBadgesEnabled: true,
      setupReminderEnabled: false,
    },
  })}\n`;
  await fs.writeFile(file, versionOneBytes);
  const events: unknown[] = [];
  const store = new DesktopSettingsStore({
    settingsFilePath: file,
    fileSystem: nodeFileSystem({ rename: async () => { throw new Error('private migration failure'); } }),
    migrationEventSink: (event) => events.push(event),
  });
  await assert.rejects(() => store.loadSnapshot(), hasCode('operation-failed'));
  assert.equal(await fs.readFile(file, 'utf8'), versionOneBytes);
  assert.deepEqual(events, [{
    fromVersion: 1,
    toVersion: 2,
    status: 'failed',
    revision: 5,
  }]);
});

test('settings persistence rejects maximum version-one revision without rewriting or emitting', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  const bytes = JSON.stringify({
    schemaVersion: 1,
    revision: Number.MAX_SAFE_INTEGER,
    values: {
      launchMode: 'windowed',
      guideDensity: 'comfortable',
      previewBadgesEnabled: true,
      setupReminderEnabled: true,
    },
  });
  await fs.writeFile(file, bytes);
  const events: unknown[] = [];
  const store = new DesktopSettingsStore({
    settingsFilePath: file,
    migrationEventSink: (event) => events.push(event),
  });
  await assert.rejects(() => store.loadSnapshot(), hasCode('operation-failed'));
  assert.equal(await fs.readFile(file, 'utf8'), bytes);
  assert.deepEqual(events, []);
});

test('settings persistence migration sink failure cannot change a successful outcome', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  await fs.writeFile(file, JSON.stringify({
    schemaVersion: 1,
    revision: 0,
    values: {
      launchMode: 'windowed',
      guideDensity: 'comfortable',
      previewBadgesEnabled: true,
      setupReminderEnabled: true,
    },
  }));
  const store = new DesktopSettingsStore({
    settingsFilePath: file,
    migrationEventSink: () => { throw new Error('sink private failure'); },
  });
  assert.equal((await store.loadSnapshot()).revision, 1);
  assert.equal(JSON.parse(await fs.readFile(file, 'utf8')).schemaVersion, 2);
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

test('settings persistence repairs corrupt revision zero with an exact atomic record', async (context) => {
  const directory = await createSettingsWorkspace(context);
  const file = path.join(directory, 'settings.json');
  await fs.writeFile(file, '{bad');
  const store = new DesktopSettingsStore({ settingsFilePath: file, processId: 7 });
  const nextValues = {
    ...DEFAULT_DESKTOP_SETTINGS_VALUES,
    guideDensity: 'compact' as const,
    audioOutputDeviceId: `audio_${'b'.repeat(43)}` as const,
  };
  const snapshot = await store.replace(0, nextValues);
  assert.deepEqual(snapshot, { schemaVersion: 2, revision: 1, status: 'ready', values: nextValues });
  assert.deepEqual(JSON.parse(await fs.readFile(file, 'utf8')), {
    schemaVersion: 2, revision: 1, values: nextValues,
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
  const unsupported = '{"schemaVersion":3,"revision":8,"values":{}}\n';
  await fs.writeFile(file, unsupported);
  const events: unknown[] = [];
  const store = new DesktopSettingsStore({
    settingsFilePath: file,
    migrationEventSink: (event) => events.push(event),
  });
  assert.equal((await store.loadSnapshot()).status, 'unsupported-version');
  await assert.rejects(() => store.replace(0, { ...DEFAULT_DESKTOP_SETTINGS_VALUES }), hasCode('unsupported-version'));
  assert.equal(await fs.readFile(file, 'utf8'), unsupported);
  assert.deepEqual(events, []);

  await fs.writeFile(file, JSON.stringify({ schemaVersion: 2, revision: 3, values: DEFAULT_DESKTOP_SETTINGS_VALUES }));
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
