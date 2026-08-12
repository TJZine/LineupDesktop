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
  type PlayerCommand,
} from '../../../contracts/player.js';
import { assertPublicSafe } from './playerPublicSafetyAssertions.js';
import {
  NativePlayerHostProcess as ProductionNativePlayerHostProcess,
  type NativePlayerHostChildProcess,
  type NativePlayerHostProcessOptions,
} from '../../../main/player/nativePlayerHostProcess.js';
import { DiagnosticEventStore } from '../../../main/diagnostics/diagnosticEventStore.js';
import type { NativePlayerHostLifecycleFailure } from '../../../main/player/nativePlayerHostPort.js';

type SpawnedNativeHostChildProcess = NativePlayerHostChildProcess & {
  readonly exitCode: number | null;
};

class NativePlayerHostProcess extends ProductionNativePlayerHostProcess {
  constructor(options: Omit<NativePlayerHostProcessOptions, 'getNativeParentIdentity'> &
    Partial<Pick<NativePlayerHostProcessOptions, 'getNativeParentIdentity'>>) {
    super({ getNativeParentIdentity: () => ({ hwnd: '42', pid: 9 }), ...options });
  }
}

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

const loadCommand: Extract<PlayerCommand, { command: 'load' }> = {
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
    seekSupport: 'supported',
    capabilityProfileId: 'native-process-test',
  },
};

async function completeActiveLoad(
  host: NativePlayerHostProcess,
  child: FakeHostChildProcess,
): Promise<void> {
  const load = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.send({ type: 'result', requestId: loadCommand.requestId, ok: true, events: [] });
  assert.equal((await load).ok, true);
}

function assertNoForbiddenKeys(value: unknown): void {
  assertPublicSafe(value, []);
}

function assertTextAbsent(value: unknown, text: string): void {
  assertPublicSafe(value, [text]);
}

function isHiddenPresentationMessage(value: unknown): boolean {
  return typeof value === 'object' && value !== null &&
    Reflect.get(value, 'type') === 'presentation.update' &&
    Reflect.get(value, 'mode') === 'hidden';
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
    parentHwnd: '42',
    parentPid: 9,
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
  assert.equal(result.ok && Array.isArray(result.events) ? result.events.length : 0, 2);
  assertNoForbiddenKeys(child.writes);
  assertNoForbiddenKeys(result);
});

test('native host process correlates presentation execution on the shared helper', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({ spawnHostProcess: () => child, requestTimeoutMs: 100 });
  const update = {
    documentEpoch: 2, revision: 3,
    parentHwnd: '42', parentPid: 9, loadedRequestId: 'native-load-1',
    mode: 'player-full' as const, bounds: { x: 0, y: 0, width: 1, height: 1 },
  };
  const pending = host.updatePresentation(update);
  await new Promise<void>((resolve) => setImmediate(resolve));
  const sent = child.writes[0] as typeof update & { type: string; version: number };
  assert.deepEqual(sent, { type: 'presentation.update', version: 1, operationId: 'presentation-1', ...update });
  child.send({ type: 'presentation.result', version: 1, operationId: sent.operationId, documentEpoch: 2, revision: 3, status: 'applied' });
  assert.deepEqual(await pending, { ok: true, status: 'applied' });
  const cleanup = host.cleanup(null);
  await new Promise<void>((resolve) => setImmediate(resolve));
  const hidden = child.writes[1] as { operationId: string };
  child.send({ type: 'presentation.result', version: 1, operationId: hidden.operationId, documentEpoch: 2, revision: 3, status: 'hidden' });
  await cleanup;
  assert.deepEqual(child.writes[2], { type: 'cleanup', requestId: null });
});

test('native host process settles colliding command and presentation identifiers independently', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({ spawnHostProcess: () => child, requestTimeoutMs: 100 });
  const command = host.execute({ command: 'play', requestId: 'presentation-1', payload: {} });
  const presentation = host.updatePresentation({
    documentEpoch: 2,
    revision: 3,
    parentHwnd: '42',
    parentPid: 9,
    loadedRequestId: 'presentation-1',
    mode: 'player-full',
    bounds: { x: 0, y: 0, width: 1, height: 1 },
  });
  await new Promise<void>((resolve) => setImmediate(resolve));

  assert.equal(child.writes.length, 2);
  child.send({
    type: 'presentation.result',
    version: 1,
    operationId: 'presentation-1',
    documentEpoch: 2,
    revision: 3,
    status: 'applied',
  });
  assert.deepEqual(await presentation, { ok: true, status: 'applied' });

  child.send({ type: 'result', requestId: 'presentation-1', ok: true, events: [] });
  assert.equal((await command).ok, true);
  assert.equal(child.killed, false);
});

test('native host process assigns monotonic presentation ids beyond the former retention cap', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({ spawnHostProcess: () => child, requestTimeoutMs: 100 });

  for (let sequence = 1; sequence <= 300; sequence += 1) {
    const pending = host.updatePresentation({
      documentEpoch: 2, revision: sequence,
      parentHwnd: '42', parentPid: 9, loadedRequestId: 'native-load-1',
      mode: 'hidden', bounds: null,
    });
    await new Promise<void>((resolve) => setImmediate(resolve));
    const sent = child.writes.at(-1) as {
      operationId: string; documentEpoch: number; revision: number;
    };
    assert.equal(sent.operationId, `presentation-${sequence}`);
    child.send({
      type: 'presentation.result', version: 1, operationId: sent.operationId,
      documentEpoch: sent.documentEpoch, revision: sent.revision, status: 'hidden',
    });
    assert.deepEqual(await pending, { ok: true, status: 'hidden' });
  }
  assert.equal(child.writes.length, 300);
});

test('native host process rejects invalid presentation updates before spawning or writing', async () => {
  let spawns = 0;
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => { spawns += 1; return new FakeHostChildProcess(); },
    requestTimeoutMs: 100,
  });
  const result = await host.updatePresentation({
    documentEpoch: 2, revision: 3,
    parentHwnd: '0', parentPid: 9, loadedRequestId: 'native-load-1',
    mode: 'player-full', bounds: { x: 0, y: 0, width: 1, height: 1 },
  });
  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.classification, 'pre-send-rejected');
  assert.equal(spawns, 0);
});

test('native host process hides the exact current loaded request before a replacement load', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({ spawnHostProcess: () => child, requestTimeoutMs: 100 });
  const presentation = host.updatePresentation({
    documentEpoch: 2, revision: 3,
    parentHwnd: '42', parentPid: 9, loadedRequestId: 'native-load-1',
    mode: 'player-full', bounds: { x: 0, y: 0, width: 1, height: 1 },
  });
  await new Promise<void>((resolve) => setImmediate(resolve));
  const sent = child.writes[0] as { operationId: string };
  child.send({ type: 'presentation.result', version: 1, operationId: sent.operationId, documentEpoch: 2, revision: 3, status: 'applied' });
  assert.equal((await presentation).ok, true);

  const replacementCommand = { ...loadCommand, requestId: 'native-load-2' };
  const replacement = host.execute(replacementCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));
  const hidden = child.writes[1] as {
    operationId: string; documentEpoch: number; revision: number; loadedRequestId: string; mode: string;
  };
  assert.equal(hidden.mode, 'hidden');
  assert.equal(hidden.loadedRequestId, 'native-load-1');
  assert.equal(child.writes.length, 2);
  child.send({
    type: 'presentation.result', version: 1, operationId: hidden.operationId,
    documentEpoch: hidden.documentEpoch, revision: hidden.revision, status: 'hidden',
  });
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.deepEqual(child.writes[2], {
    type: 'command', requestId: 'native-load-2', command: 'load', payload: loadCommand.payload,
    parentHwnd: '42', parentPid: 9,
  });
  child.send({ type: 'result', requestId: 'native-load-2', ok: true, events: [] });
  assert.equal((await replacement).ok, true);
});

test('native host process returns a typed failure when hide-boundary serialization fails', async () => {
  const child = new FakeHostChildProcess();
  let rejectHiddenPresentation = false;
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
    encodeMessage: (message) => {
      if (rejectHiddenPresentation && isHiddenPresentationMessage(message)) {
        throw new Error('serialization failed');
      }
      const encoded = JSON.stringify(message);
      if (encoded === undefined) throw new Error('message was not serializable');
      return encoded;
    },
  });
  const presentation = host.updatePresentation({
    documentEpoch: 2,
    revision: 3,
    parentHwnd: '42',
    parentPid: 9,
    loadedRequestId: 'native-load-1',
    mode: 'player-full',
    bounds: { x: 0, y: 0, width: 1, height: 1 },
  });
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.send({
    type: 'presentation.result',
    version: 1,
    operationId: 'presentation-1',
    documentEpoch: 2,
    revision: 3,
    status: 'applied',
  });
  assert.equal((await presentation).ok, true);

  rejectHiddenPresentation = true;
  const replacement = await host.execute({ ...loadCommand, requestId: 'native-load-2' });
  assert.deepEqual(replacement, {
    ok: false,
    error: {
      code: 'PLAYER_HELPER_PRESENTATION_REJECTED',
      message: 'The player helper failed while handling the command.',
      category: 'helper-failure',
      recoverable: true,
      retryable: false,
    },
  });
  assert.equal(child.writes.length, 1);
  assert.equal(child.killed, false);
});

test('native host process accepts a stale active presentation ACK and sends the replacement load', async () => {
  const child = new FakeHostChildProcess();
  const lifecycle: NativePlayerHostLifecycleFailure[] = [];
  const host = new NativePlayerHostProcess({ spawnHostProcess: () => child, requestTimeoutMs: 100 });
  host.onLifecycleFailure((failure) => lifecycle.push(failure));
  const presentation = host.updatePresentation({
    documentEpoch: 2, revision: 3,
    parentHwnd: '42', parentPid: 9, loadedRequestId: 'native-load-1',
    mode: 'player-full', bounds: { x: 0, y: 0, width: 1, height: 1 },
  });
  await new Promise<void>((resolve) => setImmediate(resolve));
  const shown = child.writes[0] as { operationId: string };
  const replacement = host.execute({ ...loadCommand, requestId: 'native-load-after-stale-hide' });
  child.send({
    type: 'presentation.result', version: 1, operationId: shown.operationId,
    documentEpoch: 2, revision: 3, status: 'stale',
  });
  assert.deepEqual(await presentation, { ok: true, status: 'stale' });
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.deepEqual(child.writes[1], {
    type: 'command', requestId: 'native-load-after-stale-hide', command: 'load', payload: loadCommand.payload,
    parentHwnd: '42', parentPid: 9,
  });
  assert.equal(child.killed, false);
  assert.equal(lifecycle.length, 0);
  child.send({ type: 'result', requestId: 'native-load-after-stale-hide', ok: true, events: [] });
  assert.equal((await replacement).ok, true);
});

test('native host process drains a pending presentation and excludes new shows across the hide-to-load boundary', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({ spawnHostProcess: () => child, requestTimeoutMs: 100 });
  const current = {
    documentEpoch: 4, revision: 6,
    parentHwnd: '42', parentPid: 9, loadedRequestId: 'native-load-1',
    mode: 'player-full' as const, bounds: { x: 0, y: 0, width: 1, height: 1 },
  };
  const pendingShow = host.updatePresentation(current);
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(child.writes.length, 1);

  const replacement = host.execute({ ...loadCommand, requestId: 'native-load-after-pending-show' });
  const excludedShow = await host.updatePresentation({
    ...current, revision: 7,
  });
  assert.equal(excludedShow.ok, false);
  assert.equal(excludedShow.ok ? null : excludedShow.classification, 'pre-send-rejected');
  assert.equal(child.writes.length, 1);

  child.send({
    type: 'presentation.result', version: 1, operationId: (child.writes[0] as { operationId: string }).operationId,
    documentEpoch: current.documentEpoch, revision: current.revision, status: 'applied',
  });
  assert.equal((await pendingShow).ok, true);
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(child.writes.length, 2);
  const hidden = child.writes[1] as { operationId: string; documentEpoch: number; revision: number; mode: string };
  assert.equal(hidden.mode, 'hidden');

  child.send({
    type: 'presentation.result', version: 1, operationId: hidden.operationId,
    documentEpoch: hidden.documentEpoch, revision: hidden.revision, status: 'hidden',
  });
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(child.writes.length, 3);
  assert.deepEqual(child.writes[2], {
    type: 'command', requestId: 'native-load-after-pending-show', command: 'load', payload: loadCommand.payload,
    parentHwnd: '42', parentPid: 9,
  });
  child.send({ type: 'result', requestId: 'native-load-after-pending-show', ok: true, events: [] });
  assert.equal((await replacement).ok, true);
});

test('native host process drains and hides a pending presentation before cleanup', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({ spawnHostProcess: () => child, requestTimeoutMs: 100 });
  const current = {
    documentEpoch: 5, revision: 8,
    parentHwnd: '42', parentPid: 9, loadedRequestId: 'native-load-1',
    mode: 'player-full' as const, bounds: { x: 0, y: 0, width: 1, height: 1 },
  };
  const pendingShow = host.updatePresentation(current);
  await new Promise<void>((resolve) => setImmediate(resolve));
  const cleanup = host.cleanup('native-load-1');
  const excluded = await host.updatePresentation({ ...current, revision: 9 });
  assert.equal(excluded.ok, false);
  assert.equal(child.writes.length, 1);

  child.send({
    type: 'presentation.result', version: 1, operationId: (child.writes[0] as { operationId: string }).operationId,
    documentEpoch: current.documentEpoch, revision: current.revision, status: 'applied',
  });
  await pendingShow;
  await new Promise<void>((resolve) => setImmediate(resolve));
  const hidden = child.writes[1] as { operationId: string; documentEpoch: number; revision: number; mode: string };
  assert.equal(hidden.mode, 'hidden');
  child.send({
    type: 'presentation.result', version: 1, operationId: hidden.operationId,
    documentEpoch: hidden.documentEpoch, revision: hidden.revision, status: 'hidden',
  });
  await cleanup;
  assert.deepEqual(child.writes[2], { type: 'cleanup', requestId: 'native-load-1' });
});

test('native host process accepts a stale hide ACK and sends cleanup without quarantine', async () => {
  const child = new FakeHostChildProcess();
  const lifecycle: NativePlayerHostLifecycleFailure[] = [];
  const host = new NativePlayerHostProcess({ spawnHostProcess: () => child, requestTimeoutMs: 100 });
  host.onLifecycleFailure((failure) => lifecycle.push(failure));
  const presentation = host.updatePresentation({
    documentEpoch: 2, revision: 3,
    parentHwnd: '42', parentPid: 9, loadedRequestId: 'native-load-1',
    mode: 'player-full', bounds: { x: 0, y: 0, width: 1, height: 1 },
  });
  await new Promise<void>((resolve) => setImmediate(resolve));
  const shown = child.writes[0] as { operationId: string };
  child.send({
    type: 'presentation.result', version: 1, operationId: shown.operationId,
    documentEpoch: 2, revision: 3, status: 'applied',
  });
  await presentation;

  const cleanup = host.cleanup('native-load-1');
  await new Promise<void>((resolve) => setImmediate(resolve));
  const hidden = child.writes[1] as { operationId: string; documentEpoch: number; revision: number };
  child.send({
    type: 'presentation.result', version: 1, operationId: hidden.operationId,
    documentEpoch: hidden.documentEpoch, revision: hidden.revision, status: 'stale',
  });
  await cleanup;
  assert.deepEqual(child.writes[2], { type: 'cleanup', requestId: 'native-load-1' });
  assert.equal(lifecycle.length, 0);
});

test('native host process quarantines an applied ACK for a replacement-load hide barrier', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({ spawnHostProcess: () => child, requestTimeoutMs: 100 });
  const presentation = host.updatePresentation({
    documentEpoch: 2, revision: 3,
    parentHwnd: '42', parentPid: 9, loadedRequestId: 'native-load-1',
    mode: 'player-full', bounds: { x: 0, y: 0, width: 1, height: 1 },
  });
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.send({ type: 'presentation.result', version: 1, operationId: (child.writes[0] as { operationId: string }).operationId, documentEpoch: 2, revision: 3, status: 'applied' });
  await presentation;
  const replacement = host.execute({ ...loadCommand, requestId: 'native-load-blocked' });
  await new Promise<void>((resolve) => setImmediate(resolve));
  const hidden = child.writes[1] as { operationId: string; documentEpoch: number; revision: number };
  child.send({
    type: 'presentation.result', version: 1, operationId: hidden.operationId,
    documentEpoch: hidden.documentEpoch, revision: hidden.revision, status: 'applied',
  });
  const result = await replacement;
  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.code, 'PLAYER_HELPER_MALFORMED_OUTPUT');
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(child.writes.length, 2);
  assert.equal(child.killed, true);
});

test('native host process quarantines an applied ACK for a cleanup hide barrier', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({ spawnHostProcess: () => child, requestTimeoutMs: 100 });
  const presentation = host.updatePresentation({
    documentEpoch: 2, revision: 3,
    parentHwnd: '42', parentPid: 9, loadedRequestId: 'native-load-1',
    mode: 'player-full', bounds: { x: 0, y: 0, width: 1, height: 1 },
  });
  await new Promise<void>((resolve) => setImmediate(resolve));
  const shown = child.writes[0] as { operationId: string };
  child.send({
    type: 'presentation.result', version: 1, operationId: shown.operationId,
    documentEpoch: 2, revision: 3, status: 'applied',
  });
  await presentation;

  const cleanup = host.cleanup('native-load-1');
  await new Promise<void>((resolve) => setImmediate(resolve));
  const hidden = child.writes[1] as { operationId: string; documentEpoch: number; revision: number };
  child.send({
    type: 'presentation.result', version: 1, operationId: hidden.operationId,
    documentEpoch: hidden.documentEpoch, revision: hidden.revision, status: 'applied',
  });
  await assert.rejects(cleanup, /Native player presentation could not be hidden/u);
  assert.equal(child.writes.length, 2);
  assert.equal(child.killed, true);
});

test('native host process quarantines a post-send presentation rejection', async () => {
  const child = new FakeHostChildProcess();
  const lifecycle: NativePlayerHostLifecycleFailure[] = [];
  const host = new NativePlayerHostProcess({ spawnHostProcess: () => child, requestTimeoutMs: 100 });
  host.onLifecycleFailure((failure) => lifecycle.push(failure));
  const pending = host.updatePresentation({
    documentEpoch: 2, revision: 4,
    parentHwnd: '42', parentPid: 9, loadedRequestId: 'native-load-1',
    mode: 'hidden', bounds: null,
  });
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.send({ type: 'presentation.result', version: 1, operationId: (child.writes[0] as { operationId: string }).operationId, documentEpoch: 2, revision: 4, status: 'rejected' });
  assert.equal((await pending).ok, false);
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(child.killed, true);
  assert.equal(lifecycle.length, 1);
});

test('native host process correlates bounded audio output queries on the shared helper', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
  });

  const pending = host.queryAudioOutputs('audio-output-1');
  await new Promise<void>((resolve) => setImmediate(resolve));

  assert.deepEqual(child.writes[0], {
    type: 'audio-output.query',
    requestId: 'audio-output-1',
  });
  child.send({
    type: 'audio-output.result',
    requestId: 'audio-output-1',
    ok: true,
    outputs: [
      { nativeKey: 'wasapi/default', label: 'Speakers' },
      { nativeKey: 'wasapi/headphones', label: 'Headphones' },
    ],
  });

  assert.deepEqual(await pending, {
    ok: true,
    outputs: [
      { nativeKey: 'wasapi/default', label: 'Speakers' },
      { nativeKey: 'wasapi/headphones', label: 'Headphones' },
    ],
  });
  assert.equal(child.killed, false);
});

test('native host process reports one lifecycle failure when an active-playback audio query crashes', async () => {
  const child = new FakeHostChildProcess();
  const lifecycleFailures: NativePlayerHostLifecycleFailure[] = [];
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
  });
  host.onLifecycleFailure((failure) => lifecycleFailures.push(failure));

  await completeActiveLoad(host, child);

  const query = host.queryAudioOutputs('audio-output-active-crash');
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.emit('close', 1, null);

  const result = await query;
  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.code, 'PLAYER_HELPER_EXITED');
  assert.equal(lifecycleFailures.length, 1);
  assert.equal(lifecycleFailures[0]?.requestId, null);
  assert.equal(lifecycleFailures[0]?.error.code, 'PLAYER_HELPER_EXITED');
});

test('native host process reports one lifecycle failure when an audio query times out', async () => {
  const child = new FakeHostChildProcess();
  const lifecycleFailures: NativePlayerHostLifecycleFailure[] = [];
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 5,
  });
  host.onLifecycleFailure((failure) => lifecycleFailures.push(failure));

  await completeActiveLoad(host, child);
  const result = await host.queryAudioOutputs('audio-output-timeout');
  await new Promise<void>((resolve) => setImmediate(resolve));

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.code, 'PLAYER_HELPER_TIMEOUT');
  assert.equal(child.killed, true);
  assert.equal(lifecycleFailures.length, 1);
  assert.equal(lifecycleFailures[0]?.requestId, null);
  assert.equal(lifecycleFailures[0]?.error.code, 'PLAYER_HELPER_TIMEOUT');
});

test('native host process quarantines inexact or privileged audio result envelopes once', async () => {
  const malformedResults = [
    {
      type: 'audio-output.result',
      requestId: 'audio-output-malformed',
      ok: true,
      outputs: [],
      extra: true,
    },
    {
      type: 'audio-output.result',
      requestId: 'audio-output-malformed',
      ok: false,
      error: {},
      extra: true,
    },
    {
      type: 'audio-output.result',
      requestId: 'audio-output-malformed',
      ok: true,
      outputs: [],
      tokenizedUrl: 'private-audio-url',
    },
    {
      type: 'audio-output.result',
      requestId: 'audio-output-malformed',
      ok: false,
    },
  ];

  for (const malformed of malformedResults) {
    const child = new FakeHostChildProcess();
    const lifecycleFailures: NativePlayerHostLifecycleFailure[] = [];
    const host = new NativePlayerHostProcess({
      spawnHostProcess: () => child,
      requestTimeoutMs: 100,
    });
    host.onLifecycleFailure((failure) => lifecycleFailures.push(failure));

    await completeActiveLoad(host, child);
    const pending = host.queryAudioOutputs('audio-output-malformed');
    await new Promise<void>((resolve) => setImmediate(resolve));
    child.send(malformed);

    const result = await pending;
    assert.equal(result.ok, false);
    assert.equal(result.ok ? null : result.error.code, 'PLAYER_HELPER_MALFORMED_OUTPUT');
    assert.equal(child.killed, true);
    assert.equal(lifecycleFailures.length, 1);
    assert.equal(lifecycleFailures[0]?.error.code, 'PLAYER_HELPER_MALFORMED_OUTPUT');
    assertNoForbiddenKeys(lifecycleFailures);
  }
});

test('native host process keeps concurrent command failures on results with one audio-owned lifecycle callback', async () => {
  const child = new FakeHostChildProcess();
  const lifecycleFailures: NativePlayerHostLifecycleFailure[] = [];
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
  });
  host.onLifecycleFailure((failure) => lifecycleFailures.push(failure));

  await completeActiveLoad(host, child);
  const command = host.execute({
    command: 'pause',
    requestId: 'native-pause-concurrent-crash',
    payload: {},
  });
  const audio = host.queryAudioOutputs('audio-output-concurrent-crash');
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(child.writes.length, 3);
  child.emit('close', 1, null);

  const [commandResult, audioResult] = await Promise.all([command, audio]);
  assert.equal(commandResult.ok, false);
  assert.equal(commandResult.ok ? null : commandResult.error.code, 'PLAYER_HELPER_EXITED');
  assert.equal(audioResult.ok, false);
  assert.equal(audioResult.ok ? null : audioResult.error.code, 'PLAYER_HELPER_EXITED');
  assert.equal(lifecycleFailures.length, 1);
  assert.equal(lifecycleFailures[0]?.requestId, null);
  assert.equal(lifecycleFailures[0]?.error.code, 'PLAYER_HELPER_EXITED');
});

test('native host process quarantines command/audio result type mismatches', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
  });

  const pending = host.queryAudioOutputs('audio-output-mismatch');
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.send({
    type: 'result',
    requestId: 'audio-output-mismatch',
    ok: true,
    events: [],
  });

  const result = await pending;
  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.code, 'PLAYER_HELPER_MALFORMED_OUTPUT');
  assert.equal(child.killed, true);
});

test('native host process ignores late audio output results with fixed diagnostics', async () => {
  const child = new FakeHostChildProcess();
  const diagnostics = new DiagnosticEventStore({
    clock: () => 1_000,
    idGenerator: () => 'late-audio-result',
  });
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
    diagnosticEventStore: diagnostics,
  });

  const pending = host.queryAudioOutputs('audio-output-late');
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.send({
    type: 'audio-output.result',
    requestId: 'audio-output-late',
    ok: true,
    outputs: [],
  });
  assert.equal((await pending).ok, true);

  child.send({
    type: 'audio-output.result',
    requestId: 'audio-output-late',
    ok: true,
    outputs: [{ nativeKey: 'private-late-key', label: 'Private late label' }],
  });
  await new Promise<void>((resolve) => setImmediate(resolve));

  const record = diagnostics.getRecords().find(
    (candidate) => candidate.operation === 'helper.late-result',
  );
  assert.deepEqual(record?.context, { count: 1 });
  assertTextAbsent(diagnostics.getRecords(), 'private-late-key');
  assertTextAbsent(diagnostics.getRecords(), 'Private late label');
});

test('native host process transports opaque helper event payloads to the adapter seam', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
  });

  const malformedEvent = {
    type: 'time.updated',
    requestId: 'native-load-1',
    positionMs: -1,
    durationMs: 1_000,
    tokenizedUrl: 'opaque-privileged-marker',
  };
  const first = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.send({ type: 'event', event: malformedEvent });
  child.send({ type: 'result', requestId: 'native-load-1', ok: true });

  const firstResult = await first;
  assert.deepEqual(firstResult, { ok: true, events: [malformedEvent] });

  const second = host.execute({ ...loadCommand, requestId: 'native-load-2' });
  await new Promise<void>((resolve) => setImmediate(resolve));
  const malformedBatch = { event: malformedEvent };
  child.send({
    type: 'result',
    requestId: 'native-load-2',
    ok: true,
    events: malformedBatch,
  });

  const secondResult = await second;
  assert.deepEqual(secondResult, { ok: true, events: malformedBatch });
});

test('native host process delivers helper events emitted after command results out of band', async () => {
  const child = new FakeHostChildProcess();
  const asyncEvents: unknown[] = [];
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
  });
  host.onEvent((event) => asyncEvents.push(event));

  const pending = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.send({ type: 'result', requestId: 'native-load-1', ok: true, events: [] });
  const result = await pending;

  child.send({
    type: 'event',
    event: {
      type: 'time.updated',
      requestId: 'native-load-1',
      positionMs: 750,
      durationMs: 1_000,
    },
  });
  await new Promise<void>((resolve) => setImmediate(resolve));

  assert.equal(result.ok, true);
  assert.deepEqual(asyncEvents, [
    {
      type: 'time.updated',
      requestId: 'native-load-1',
      positionMs: 750,
      durationMs: 1_000,
    },
  ]);
  assertNoForbiddenKeys(asyncEvents);
});

test('native host process transports the safe helper end-file ERROR envelope out of band', async () => {
  const child = new FakeHostChildProcess();
  const asyncEvents: unknown[] = [];
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
  });
  host.onEvent((event) => asyncEvents.push(event));

  const pending = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.send({ type: 'result', requestId: 'native-load-1', ok: true, events: [] });
  await pending;
  child.send({
    type: 'event',
    event: {
      type: 'error',
      requestId: 'native-load-1',
      error: {
        code: 'PLAYER_HELPER_PLAYBACK_ENDED_WITH_ERROR',
        category: 'engine-failure',
        message: 'Native playback ended with a player engine error.',
        recoverable: true,
        retryable: true,
      },
    },
  });
  await new Promise<void>((resolve) => setImmediate(resolve));

  assert.deepEqual(asyncEvents, [
    {
      type: 'error',
      requestId: 'native-load-1',
      error: {
        code: 'PLAYER_HELPER_PLAYBACK_ENDED_WITH_ERROR',
        category: 'engine-failure',
        message: 'Native playback ended with a player engine error.',
        recoverable: true,
        retryable: true,
      },
    },
  ]);
  assertNoForbiddenKeys(asyncEvents);
});

test('native host process rejects duplicate in-flight request IDs without overwriting pending commands', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
  });

  const first = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));
  const duplicate = await host.execute({
    command: 'play',
    requestId: 'native-load-1',
    payload: {},
  });

  assert.equal(duplicate.ok, false);
  assert.equal(duplicate.ok ? null : duplicate.error.code, 'PLAYER_HELPER_DUPLICATE_REQUEST');
  assert.equal(child.writes.length, 1);

  child.send({ type: 'result', requestId: 'native-load-1', ok: true, events: [] });
  assert.equal((await first).ok, true);
});

test('native host process reports idle helper lifecycle failures to subscribers', async () => {
  const child = new FakeHostChildProcess();
  const lifecycleFailures: NativePlayerHostLifecycleFailure[] = [];
  const diagnostics = new DiagnosticEventStore({ clock: () => 1_000, idGenerator: () => 'idle-close' });
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
    diagnosticEventStore: diagnostics,
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
  assert.equal(diagnostics.getCrashRecoverySummary().helperCrashCount, 1);
  assert.equal(diagnostics.getRecords().some((record) => record.operation === 'helper.lifecycle'), true);
  assertNoForbiddenKeys(lifecycleFailures);
  unsubscribe();
});

test('native host process reports helper exit after an applied presentation with no pending operation', async () => {
  const child = new FakeHostChildProcess();
  const lifecycleFailures: NativePlayerHostLifecycleFailure[] = [];
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
  });
  host.onLifecycleFailure((failure) => lifecycleFailures.push(failure));
  await completeActiveLoad(host, child);

  const presentation = host.updatePresentation({
    documentEpoch: 2,
    revision: 3,
    parentHwnd: '42',
    parentPid: 9,
    loadedRequestId: 'native-load-1',
    mode: 'player-full',
    bounds: { x: 0, y: 0, width: 1, height: 1 },
  });
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.send({
    type: 'presentation.result',
    version: 1,
    operationId: 'presentation-1',
    documentEpoch: 2,
    revision: 3,
    status: 'applied',
  });
  assert.deepEqual(await presentation, { ok: true, status: 'applied' });

  child.emit('close', 1, null);
  assert.equal(lifecycleFailures.length, 1);
  assert.equal(lifecycleFailures[0]?.requestId, null);
  assert.equal(lifecycleFailures[0]?.error.code, 'PLAYER_HELPER_EXITED');
});

test('native host process clears partial frames after child error and close before replacement', async () => {
  for (const terminalEvent of ['error', 'close'] as const) {
    const failedChild = new FakeHostChildProcess();
    const replacementChild = new FakeHostChildProcess();
    const children = [failedChild, replacementChild];
    const diagnostics = new DiagnosticEventStore({
      clock: () => 1_500,
      idGenerator: () => `partial-frame-${terminalEvent}`,
    });
    const host = new NativePlayerHostProcess({
      spawnHostProcess: () => {
        const child = children.shift();
        assert.ok(child, 'expected a fake child process');
        return child;
      },
      requestTimeoutMs: 100,
      diagnosticEventStore: diagnostics,
    });

    const failed = host.execute(loadCommand);
    await new Promise<void>((resolve) => setImmediate(resolve));
    failedChild.stdout.write('{"type":"result"');
    failedChild.emit(terminalEvent, terminalEvent === 'error' ? new Error('private helper detail') : 1);
    assert.equal((await failed).ok, false);

    const replacementRequestId = `native-load-after-${terminalEvent}`;
    const replacement = host.execute({ ...loadCommand, requestId: replacementRequestId });
    await new Promise<void>((resolve) => setImmediate(resolve));
    replacementChild.send({ type: 'result', requestId: replacementRequestId, ok: true, events: [] });

    assert.equal((await replacement).ok, true);
    assert.equal(diagnostics.getCrashRecoverySummary().helperCrashCount, 1);
    assert.equal(diagnostics.getCrashRecoverySummary().helperRestartCount, 1);
    assertTextAbsent(diagnostics.getRecords(), 'private helper detail');
  }
});

test('native host process keeps active command close failures on the command result', async () => {
  const child = new FakeHostChildProcess();
  const lifecycleFailures: NativePlayerHostLifecycleFailure[] = [];
  const diagnostics = new DiagnosticEventStore({ clock: () => 2_000, idGenerator: () => 'pending-close' });
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
    diagnosticEventStore: diagnostics,
  });
  host.onLifecycleFailure((failure) => lifecycleFailures.push(failure));

  const pending = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.emit('close', 1, null);
  const result = await pending;

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.code, 'PLAYER_HELPER_EXITED');
  assert.equal(lifecycleFailures.length, 0);
  assert.equal(diagnostics.getRecords().some((record) => record.requestId === 'native-load-1'), true);
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
    assert.equal(result.ok && Array.isArray(result.events) ? result.events.length : 0, 3);
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
  const diagnostics = new DiagnosticEventStore({ clock: () => 3_000, idGenerator: () => 'malformed-output' });
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
    diagnosticEventStore: diagnostics,
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
  assertTextAbsent(diagnostics.getRecords(), 'native-secret');
  assertTextAbsent(diagnostics.getRecords(), 'do not expose this raw detail');
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
  const diagnostics = new DiagnosticEventStore({ clock: () => 4_000, idGenerator: () => 'oversized-output' });
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
    diagnosticEventStore: diagnostics,
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
  assert.equal(diagnostics.getCrashRecoverySummary().helperRestartCount, 1);
  assertTextAbsent(diagnostics.getCrashRecoverySummary(), 'x'.repeat(20));
  assert.deepEqual(replacementChild.writes[0], {
    type: 'command',
    requestId: 'native-load-after-oversized',
    command: 'load',
    payload: loadCommand.payload,
    parentHwnd: '42',
    parentPid: 9,
  });
});

test('native host process normalizes timeout, spawn failure, and exit failure', async () => {
  const diagnostics = new DiagnosticEventStore({ clock: () => 5_000, idGenerator: () => 'timeout-restart' });
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
    diagnosticEventStore: diagnostics,
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
    parentHwnd: '42',
    parentPid: 9,
  });

  const sensitiveHelperPath = ['', 'tmp', 'helper-secret'].join('/');
  const spawnHost = new NativePlayerHostProcess({
    spawnHostProcess: () => {
      throw new Error(`local path ${sensitiveHelperPath}`);
    },
    diagnosticEventStore: diagnostics,
  });
  const spawnResult = await spawnHost.execute(loadCommand);
  assert.equal(spawnResult.ok, false);
  assert.equal(spawnResult.ok ? null : spawnResult.error.code, 'PLAYER_HELPER_SPAWN_FAILED');
  assertTextAbsent(spawnResult, sensitiveHelperPath);
  assertTextAbsent(diagnostics.getRecords(), sensitiveHelperPath);
  assert.equal(diagnostics.getCrashRecoverySummary().helperRestartCount, 1);

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
  const diagnostics = new DiagnosticEventStore({ clock: () => 5_500, idGenerator: () => 'cleanup-aborted' });
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => {
      const child = children.shift();
      assert.ok(child, 'expected a fake child process');
      return child;
    },
    requestTimeoutMs: 100,
    cleanupGraceMs: 10,
    diagnosticEventStore: diagnostics,
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
  assert.equal(diagnostics.getCrashRecoverySummary().helperCrashCount, 0);
  assert.equal(diagnostics.getCrashRecoverySummary().cleanupFailureCount, 0);
  assert.deepEqual(
    diagnostics.getCrashRecoverySummary().events.map((event) => ({
      category: event.category,
      status: event.status,
      operation: event.operation,
      code: event.code,
    })),
    [
      {
        category: 'cleanup',
        status: 'cancelled',
        operation: 'helper.cleanup',
        code: 'PLAYER_HELPER_CLEANED_UP',
      },
    ],
  );
  assert.equal(firstChild.killSignals.includes('SIGTERM'), true);
  assert.deepEqual(firstChild.writes[1], { type: 'cleanup', requestId: 'native-load-1' });
  assertNoForbiddenKeys(result);

  const nextPending = host.execute({ ...loadCommand, requestId: 'native-load-2' });
  await new Promise<void>((resolve) => setImmediate(resolve));
  secondChild.send({ type: 'result', requestId: 'native-load-2', ok: true, events: [] });
  assert.equal((await nextPending).ok, true);
  assert.equal(diagnostics.getCrashRecoverySummary().helperRestartCount, 0);
  assert.deepEqual(secondChild.writes[0], {
    type: 'command',
    requestId: 'native-load-2',
    command: 'load',
    payload: loadCommand.payload,
    parentHwnd: '42',
    parentPid: 9,
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
  const diagnostics = new DiagnosticEventStore({ clock: () => 6_000, idGenerator: () => 'cleanup-failure' });
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
    cleanupGraceMs: 10,
    diagnosticEventStore: diagnostics,
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
  assert.equal(diagnostics.getCrashRecoverySummary().cleanupFailureCount, 1);
  assertNoForbiddenKeys(result);
});

test('native host process records quarantine reap failures safely', async () => {
  const child = new FakeHostChildProcess();
  child.autoCloseOnKill = false;
  const diagnostics = new DiagnosticEventStore({ clock: () => 8_000, idGenerator: () => 'quarantine-cleanup' });
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 1,
    cleanupGraceMs: 5,
    diagnosticEventStore: diagnostics,
  });

  const result = await host.execute(loadCommand);
  await delay(20);

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.category, 'timeout');
  assert.equal(diagnostics.getCrashRecoverySummary().cleanupFailureCount, 1);
  assert.equal(diagnostics.getRecords().some((record) => record.operation === 'helper.cleanup'), true);
  assertNoForbiddenKeys(diagnostics.getRecords());
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

test('native host process drops stderr content before diagnostics storage', async () => {
  const child = new FakeHostChildProcess();
  const diagnostics = new DiagnosticEventStore({ clock: () => 7_000, idGenerator: () => 'stderr-redacted' });
  const forbiddenUrl = ['https://', 'secret', '.example'].join('');
  const forbiddenHandle = ['native', 'Handle'].join('');
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
    diagnosticEventStore: diagnostics,
  });

  const pending = host.execute(loadCommand);
  await new Promise<void>((resolve) => setImmediate(resolve));
  child.stderr.write(`tokenizedUrl=${forbiddenUrl} ${forbiddenHandle}=12345`);
  child.send({ type: 'result', requestId: 'native-load-1', ok: true, events: [] });

  assert.equal((await pending).ok, true);
  assert.equal(diagnostics.getRecords().some((record) => record.operation === 'helper.output'), true);
  assertTextAbsent(diagnostics.getRecords(), forbiddenUrl);
  assertTextAbsent(diagnostics.getRecords(), forbiddenHandle);
});

test('native host process serializes private playback details correctly', async () => {
  const child = new FakeHostChildProcess();
  const privateParentPid = Number(['12', '34'].join(''));
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
    getNativeParentIdentity: () => ({ hwnd: '424242', pid: privateParentPid }),
  });

  const context = {
    privatePlayback: {
      requestId: 'native-load-1',
      decisionKind: 'direct-play' as const,
      playbackUrl: 'https://private.example/library/parts/main',
      credentialHeader: {
        name: 'X-Private-Header',
        value: 'private-value',
      },
      setup: {
        playbackMode: 'direct-play' as const,
        mediaPath: '/library/metadata/rating-1',
        variantId: 'plex-variant-main',
        partPath: '/library/parts/main',
        selectedTrackIds: { video: null, audio: null, subtitle: null },
        selectedPrivateTrackIds: { video: null, audio: null, subtitle: null },
        trackMap: { video: [], audio: [], subtitle: [] },
        audioOutputNativeKey: null,
        dtsPassthroughEnabled: false,
      },
      selectedConnection: {
        protocol: 'https' as const,
        address: 'private.example',
        port: 443,
        local: false,
        relay: false,
      },
      media: { id: 'media-1', title: 'Episode 1' },
    },
  };

  const pending = host.execute(loadCommand, context);
  await new Promise<void>((resolve) => setImmediate(resolve));

  assert.deepEqual(child.writes[0], {
    type: 'command',
    requestId: 'native-load-1',
    command: 'load',
    payload: loadCommand.payload,
    setup: context.privatePlayback.setup,
    playbackUrl: context.privatePlayback.playbackUrl,
    credentialHeader: context.privatePlayback.credentialHeader,
    parentHwnd: '424242',
    parentPid: privateParentPid,
  });

  child.send({ type: 'result', requestId: 'native-load-1', ok: true, events: [] });
  const result = await pending;
  assert.equal(result.ok, true);
});

test('native host process rejects an invalid private parent identity before spawning', async () => {
  let spawnCount = 0;
  const privateParentPid = Number(['12', '34'].join(''));
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => {
      spawnCount += 1;
      return new FakeHostChildProcess();
    },
    getNativeParentIdentity: () => ({ hwnd: ' ', pid: privateParentPid }),
  });

  const result = await host.execute(loadCommand);

  assert.equal(result.ok, false);
  assert.equal(spawnCount, 0);
});

test('native host process rejects oversized messages', async () => {
  const child = new FakeHostChildProcess();
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => child,
    requestTimeoutMs: 100,
  });

  // Create an oversized command by adding a huge payload
  const oversizedCommand = {
    ...loadCommand,
    payload: {
      ...loadCommand.payload,
      hugeField: 'x'.repeat(1024 * 1024 + 10),
    },
  };

  const result = await host.execute(oversizedCommand);
  assert.equal(result.ok, false);
  assert.equal(result.error.code, 'PLAYER_HELPER_MESSAGE_TOO_LARGE');
});
