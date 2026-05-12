import test from 'node:test';
import assert from 'node:assert/strict';
import type { Buffer } from 'node:buffer';
import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import process from 'node:process';
import { PassThrough } from 'node:stream';
import { setImmediate } from 'node:timers';
import { setTimeout as delay } from 'node:timers/promises';

import {
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  type PlayerCommand,
} from '../../../contracts/player.js';
import {
  NativePlayerHostProcess,
  type NativePlayerHostChildProcess,
} from '../../../main/player/nativePlayerHostProcess.js';
import type { NativePlayerHostLifecycleFailure } from '../../../main/player/nativePlayerHostPort.js';

type SpawnedNativeHostChildProcess = NativePlayerHostChildProcess & {
  readonly exitCode: number | null;
};

class FakeHostChildProcess extends EventEmitter implements NativePlayerHostChildProcess {
  readonly stdin = new PassThrough();
  readonly stdout = new PassThrough();
  readonly stderr = new PassThrough();
  readonly writes: unknown[] = [];
  killed = false;
  readonly killSignals: string[] = [];
  autoCloseOnKill = true;

  constructor() {
    super();
    this.stdin.on('data', (chunk: Buffer) => {
      for (const line of chunk.toString().trim().split('\n')) {
        if (line.length > 0) {
          this.writes.push(JSON.parse(line));
        }
      }
    });
  }

  kill(signal?: string): boolean {
    this.killed = true;
    this.killSignals.push(signal ?? 'SIGTERM');
    if (this.autoCloseOnKill) {
      setImmediate(() => this.emitClose(signal));
    }
    return true;
  }

  emitClose(signal: string | null = null): void {
    this.emit('close', 0, signal);
  }

  send(value: unknown): void {
    this.stdout.write(`${JSON.stringify(value)}\n`);
  }

  sendRaw(value: string): void {
    this.stdout.write(`${value}\n`);
  }
}

const loadCommand: PlayerCommand = {
  command: 'load',
  requestId: 'native-load-1',
  payload: {
    media: {
      id: 'media-1',
      title: 'Episode 1',
      durationMs: 1_000,
      container: 'mkv',
    },
    policy: {
      autoplay: true,
      startPositionMs: 0,
      preferredAudioTrackId: null,
      preferredSubtitleTrackId: null,
    },
    capabilityProfileId: 'native-process-test',
  },
};

function assertNoForbiddenKeys(value: unknown): void {
  if (Array.isArray(value)) {
    for (const item of value) {
      assertNoForbiddenKeys(item);
    }
    return;
  }

  if (value === null || typeof value !== 'object') {
    return;
  }

  for (const [key, child] of Object.entries(value)) {
    assert.equal(
      PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS.includes(
        key as (typeof PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS)[number],
      ),
      false,
      `native host process value contains forbidden key ${key}`,
    );
    assertNoForbiddenKeys(child);
  }
}

function assertTextAbsent(value: unknown, text: string): void {
  assert.equal(JSON.stringify(value).includes(text), false, `unexpected renderer-facing text ${text}`);
}

function spawnNodeHost(script: string): SpawnedNativeHostChildProcess {
  return spawn(process.execPath, ['-e', script], {
    stdio: 'pipe',
    windowsHide: true,
  }) as unknown as SpawnedNativeHostChildProcess;
}

const spawnedSuccessHostScript = String.raw`
let buffer = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  buffer += chunk;
  let newlineIndex = buffer.indexOf('\n');
  while (newlineIndex >= 0) {
    const line = buffer.slice(0, newlineIndex).trim();
    buffer = buffer.slice(newlineIndex + 1);
    if (line.length > 0) {
      const message = JSON.parse(line);
      if (message.type === 'command') {
        process.stdout.write(JSON.stringify({
          type: 'event',
          event: {
            type: 'playback.state',
            requestId: message.requestId,
            status: 'buffering',
            playing: false,
          },
        }) + '\n');
        process.stdout.write(JSON.stringify({
          type: 'result',
          requestId: message.requestId,
          ok: true,
          events: [
            {
              type: 'media.loaded',
              requestId: message.requestId,
              media: message.payload.media,
              durationMs: message.payload.media.durationMs ?? null,
              tracks: [],
            },
            {
              type: 'playback.state',
              requestId: message.requestId,
              status: 'playing',
              playing: true,
            },
          ],
        }) + '\n');
      }
      if (message.type === 'cleanup') {
        setTimeout(() => process.exit(0), 5);
      }
    }
    newlineIndex = buffer.indexOf('\n');
  }
});
`;

const spawnedCrashHostScript = String.raw`
process.stdin.resume();
process.stdin.once('data', () => process.exit(42));
`;

test('native host process translates commands and returns safe host events', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
  });

  const pending = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));

  assert.deepEqual(child.writes[0], {
    type: 'command',
    requestId: 'native-load-1',
    command: 'load',
    payload: loadCommand.payload,
  });

  child.send({
    type: 'event',
    event: {
      type: 'playback.state',
      requestId: 'native-load-1',
      status: 'buffering',
      playing: false,
    },
  });
  child.send({
    type: 'result',
    requestId: 'native-load-1',
    ok: true,
    events: [
      {
        type: 'media.loaded',
        requestId: 'native-load-1',
        media: loadCommand.payload.media,
        durationMs: 1_000,
        tracks: [],
      },
    ],
  });

  const result = await pending;

  assert.equal(result.ok, true);
  assert.equal(result.ok ? result.events?.length : 0, 2);
  assertNoForbiddenKeys(child.writes);
  assertNoForbiddenKeys(result);
});

test('native host process reports idle helper lifecycle failures to subscribers', async () => {
  const child = new FakeHostChildProcess();
  const lifecycleFailures: NativePlayerHostLifecycleFailure[] = [];
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
  });
  const unsubscribe = host.onLifecycleFailure((failure) => lifecycleFailures.push(failure));

  const pending = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.send({ type: 'result', requestId: 'native-load-1', ok: true, events: [] });
  assert.equal((await pending).ok, true);

  child.emit('close', 1, null);

  assert.equal(lifecycleFailures.length, 1);
  assert.equal(lifecycleFailures[0]?.requestId, null);
  assert.equal(lifecycleFailures[0]?.error.code, 'PLAYER_HELPER_EXITED');
  assertNoForbiddenKeys(lifecycleFailures);
  unsubscribe();
});

test('native host process keeps active command close failures on the command result', async () => {
  const child = new FakeHostChildProcess();
  const lifecycleFailures: NativePlayerHostLifecycleFailure[] = [];
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
  });
  host.onLifecycleFailure((failure) => lifecycleFailures.push(failure));

  const pending = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.emit('close', 1, null);
  const result = await pending;

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.code, 'PLAYER_HELPER_EXITED');
  assert.equal(lifecycleFailures.length, 0);
  assertNoForbiddenKeys(result);
});

test('native host process starts a real helper process and reaps it on cleanup', async () => {
  const child = spawnNodeHost(spawnedSuccessHostScript);
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 5_000,
    cleanupGraceMs: 100,
  });

  try {
    const result = await host.execute(loadCommand);

    assert.equal(result.ok, true);
    assert.equal(result.ok ? result.events?.length : 0, 3);
    assert.equal(child.killed, false);
    assertNoForbiddenKeys(result);

    await host.cleanup('native-load-1');
    assert.equal(child.killed, true);
  } finally {
    if (!child.killed && child.exitCode === null) {
      child.kill('SIGKILL');
    }
  }
});

test('native host process normalizes real helper process exits without raw details', async () => {
  const child = spawnNodeHost(spawnedCrashHostScript);
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 5_000,
    cleanupGraceMs: 100,
  });

  try {
    const result = await host.execute(loadCommand);

    assert.equal(result.ok, false);
    assert.equal(result.ok ? null : result.error.code, 'PLAYER_HELPER_EXITED');
    assert.equal(JSON.stringify(result).includes(process.execPath), false);
    assertNoForbiddenKeys(result);
  } finally {
    if (!child.killed && child.exitCode === null) {
      child.kill('SIGKILL');
    }
  }
});

test('native host process normalizes malformed and privileged output', async () => {
  const malformedChild = new FakeHostChildProcess();
  const privilegedChild = new FakeHostChildProcess();
  const failedChild = new FakeHostChildProcess();
  const children = [malformedChild, privilegedChild, failedChild];
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => {
      const child = children.shift();
      assert.ok(child, 'expected a fake child process');
      return child;
    },
    requestTimeoutMs: 100,
    cleanupGraceMs: 10,
  });

  const malformed = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));
  malformedChild.sendRaw('{not-json');
  const malformedResult = await malformed;
  await delay(15);

  assert.equal(malformedResult.ok, false);
  assert.equal(malformedResult.ok ? null : malformedResult.error.category, 'helper-failure');
  assert.equal(JSON.stringify(malformedResult).includes('not-json'), false);
  assert.deepEqual(malformedChild.killSignals, ['SIGTERM']);

  const privileged = host.execute({ ...loadCommand, requestId: 'native-load-2' });
  await new Promise<void>((resolve) => setImmediate(resolve));
  privilegedChild.send({
    type: 'result',
    requestId: 'native-load-2',
    ok: false,
    error: {
      code: 'PLAYER_NATIVE_RAW_FAILURE',
      category: 'helper-failure',
      message: 'do not expose this raw detail',
      nativeHandle: 'native-secret',
    },
  });
  const privilegedResult = await privileged;

  assert.equal(privilegedResult.ok, false);
  assert.equal(privilegedResult.ok ? null : privilegedResult.error.code, 'PLAYER_HELPER_MALFORMED_OUTPUT');
  assertTextAbsent(privilegedResult, 'native-secret');
  assertTextAbsent(privilegedResult, 'do not expose this raw detail');
  assertNoForbiddenKeys(privilegedResult);
  await delay(15);
  assert.deepEqual(privilegedChild.killSignals, ['SIGTERM']);

  const failed = host.execute({ ...loadCommand, requestId: 'native-load-3' });
  await new Promise<void>((resolve) => setImmediate(resolve));
  failedChild.send({
    type: 'result',
    requestId: 'native-load-3',
    ok: false,
    error: {
      code: 'PLAYER_HELPER_TEST_FAILURE',
      category: 'helper-failure',
      message: 'raw helper process detail',
      recoverable: false,
      retryable: false,
    },
  });
  const failedResult = await failed;

  assert.equal(failedResult.ok, false);
  assert.equal(failedResult.ok ? null : failedResult.error.code, 'PLAYER_HELPER_TEST_FAILURE');
  assertTextAbsent(failedResult, 'raw helper process detail');
  assertNoForbiddenKeys(failedResult);
  assert.deepEqual(failedChild.killSignals, []);
});

test('native host process quarantines oversized output before the next command', async () => {
  const oversizedChild = new FakeHostChildProcess();
  const replacementChild = new FakeHostChildProcess();
  const children = [oversizedChild, replacementChild];
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => {
      const child = children.shift();
      assert.ok(child, 'expected a fake child process');
      return child;
    },
    requestTimeoutMs: 100,
    cleanupGraceMs: 10,
  });

  const oversized = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));
  oversizedChild.stdout.write('x'.repeat(64 * 1024 + 1));
  const oversizedResult = await oversized;
  await delay(15);

  assert.equal(oversizedResult.ok, false);
  assert.equal(oversizedResult.ok ? null : oversizedResult.error.code, 'PLAYER_HELPER_MALFORMED_OUTPUT');
  assert.deepEqual(oversizedChild.killSignals, ['SIGTERM']);
  assertNoForbiddenKeys(oversizedResult);

  const replacement = host.execute({ ...loadCommand, requestId: 'native-load-after-oversized' });
  await new Promise<void>((resolve) => setImmediate(resolve));
  replacementChild.send({ type: 'result', requestId: 'native-load-after-oversized', ok: true, events: [] });
  assert.equal((await replacement).ok, true);
  assert.deepEqual(replacementChild.writes[0], {
    type: 'command',
    requestId: 'native-load-after-oversized',
    command: 'load',
    payload: loadCommand.payload,
  });
});

test('native host process normalizes timeout, spawn failure, and exit failure', async () => {
  const timeoutChild = new FakeHostChildProcess();
  const replacementChild = new FakeHostChildProcess();
  const timeoutChildren = [timeoutChild, replacementChild];
  const timeoutHost = new NativePlayerHostProcess({
    spawnHostProcess: () => {
      const child = timeoutChildren.shift();
      assert.ok(child, 'expected a fake child process');
      return child;
    },
    requestTimeoutMs: 1,
    cleanupGraceMs: 10,
  });

  const timeoutResult = await timeoutHost.execute(loadCommand);
  await delay(15);
  assert.equal(timeoutResult.ok, false);
  assert.equal(timeoutResult.ok ? null : timeoutResult.error.category, 'timeout');
  assert.deepEqual(timeoutChild.killSignals, ['SIGTERM']);

  const replacementResult = timeoutHost.execute({ ...loadCommand, requestId: 'native-load-after-timeout' });
  await new Promise<void>((resolve) => setImmediate(resolve));
  replacementChild.send({ type: 'result', requestId: 'native-load-after-timeout', ok: true, events: [] });
  assert.equal((await replacementResult).ok, true);
  assert.deepEqual(replacementChild.writes[0], {
    type: 'command',
    requestId: 'native-load-after-timeout',
    command: 'load',
    payload: loadCommand.payload,
  });

  const spawnHost = new NativePlayerHostProcess({
    spawnHostProcess: () => {
      throw new Error('local path /tmp/helper-secret');
    },
  });
  const spawnResult = await spawnHost.execute(loadCommand);
  assert.equal(spawnResult.ok, false);
  assert.equal(spawnResult.ok ? null : spawnResult.error.code, 'PLAYER_HELPER_SPAWN_FAILED');
  assertTextAbsent(spawnResult, '/tmp/helper-secret');

  const exitChild = new FakeHostChildProcess();
  const exitHost = new NativePlayerHostProcess({
    spawnHostProcess: () => exitChild,
    requestTimeoutMs: 100,
  });
  const exitPending = exitHost.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));
  exitChild.emit('close', 1, null);
  const exitResult = await exitPending;
  assert.equal(exitResult.ok, false);
  assert.equal(exitResult.ok ? null : exitResult.error.code, 'PLAYER_HELPER_EXITED');
  assertNoForbiddenKeys([timeoutResult, spawnResult, exitResult]);
});

test('native host process cleanup reaps child and ignores late output', async () => {
  const firstChild = new FakeHostChildProcess();
  const secondChild = new FakeHostChildProcess();
  const children = [firstChild, secondChild];
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => {
      const child = children.shift();
      assert.ok(child, 'expected a fake child process');
      return child;
    },
    requestTimeoutMs: 100,
    cleanupGraceMs: 10,
  });

  const pending = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));

  await host.cleanup('native-load-1');
  const result = await pending;

  firstChild.send({
    type: 'result',
    requestId: 'native-load-1',
    ok: true,
    events: [
      {
        type: 'time.updated',
        requestId: 'native-load-1',
        positionMs: 500,
        durationMs: 1_000,
      },
    ],
  });

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.category, 'aborted');
  assert.equal(firstChild.killSignals.includes('SIGTERM'), true);
  assert.deepEqual(firstChild.writes[1], { type: 'cleanup', requestId: 'native-load-1' });
  assertNoForbiddenKeys(result);

  const nextPending = host.execute({ ...loadCommand, requestId: 'native-load-2' });
  await new Promise<void>((resolve) => setImmediate(resolve));
  secondChild.send({ type: 'result', requestId: 'native-load-2', ok: true, events: [] });
  assert.equal((await nextPending).ok, true);
  assert.deepEqual(secondChild.writes[0], {
    type: 'command',
    requestId: 'native-load-2',
    command: 'load',
    payload: loadCommand.payload,
  });
});

test('native host process escalates cleanup and waits for close before resolving', async () => {
  const child = new FakeHostChildProcess();
  child.autoCloseOnKill = false;
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
    cleanupGraceMs: 10,
  });

  const pending = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));

  let cleanupResolved = false;
  const cleanup = host.cleanup('native-load-1').then(() => {
    cleanupResolved = true;
  });
  const result = await pending;
  await delay(15);

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.category, 'aborted');
  assert.deepEqual(child.killSignals, ['SIGTERM', 'SIGKILL']);
  assert.equal(cleanupResolved, false);

  child.emitClose('SIGKILL');
  await cleanup;
  assert.equal(cleanupResolved, true);
  assertNoForbiddenKeys(result);
});

test('native host process reaps child when cleanup write throws', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
    cleanupGraceMs: 10,
  });

  const pending = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.stdin.write = (() => {
    throw new Error('cleanup write failed');
  }) as typeof child.stdin.write;

  await assert.rejects(host.cleanup('native-load-1'), /cleanup write failed/);
  const result = await pending;

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.category, 'aborted');
  assert.deepEqual(child.killSignals, ['SIGTERM']);
  assertNoForbiddenKeys(result);
});

test('native host process normalizes stdio stream errors without raw details', async () => {
  for (const streamName of ['stdin', 'stdout', 'stderr'] as const) {
    const child = new FakeHostChildProcess();
    child.autoCloseOnKill = false;
    const host = new NativePlayerHostProcess({
      spawnHostProcess: () => child,
      requestTimeoutMs: 100,
      cleanupGraceMs: 10,
    });

    const pending = host.execute({ ...loadCommand, requestId: `native-${streamName}-error` });
    await new Promise<void>((resolve) => setImmediate(resolve));
    child[streamName].emit('error', new Error('nativeHandle=secret tokenizedUrl=http://secret.example'));
    const result = await pending;
    await delay(15);

    assert.equal(result.ok, false);
    assert.equal(result.ok ? null : result.error.code, 'PLAYER_HELPER_STREAM_FAILED');
    assert.deepEqual(child.killSignals, ['SIGTERM', 'SIGKILL']);
    assert.equal(JSON.stringify(result).includes('nativeHandle'), false);
    assert.equal(JSON.stringify(result).includes('tokenizedUrl'), false);
    assert.equal(JSON.stringify(result).includes('secret.example'), false);
    assertNoForbiddenKeys(result);
    child.emitClose('SIGKILL');
  }
});
