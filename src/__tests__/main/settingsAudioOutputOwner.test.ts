import test from 'node:test';
import assert from 'node:assert/strict';

import { DiagnosticEventStore } from '../../main/diagnostics/diagnosticEventStore.js';
import {
  SettingsAudioOutputOwner,
  createAudioOutputDeviceId,
  type SettingsAudioOutputOwnerOptions,
} from '../../main/settings/settingsAudioOutputOwner.js';
import type {
  NativeAudioOutput,
  NativePlayerHostAudioOutputResult,
  NativePlayerHostPort,
} from '../../main/player/nativePlayerHostPort.js';

class AudioHost implements NativePlayerHostPort {
  queries: string[] = [];
  result: NativePlayerHostAudioOutputResult = { ok: true, outputs: [] };
  async queryAudioOutputs(requestId: string) {
    this.queries.push(requestId);
    return this.result;
  }
  async execute() { return { ok: true as const }; }
  async cleanup() {}
}

test('audio output owner checks platform/helper before querying and always returns system default', async () => {
  const host = new AudioHost();
  const offWindows = owner({ platform: 'darwin', host });
  assert.deepEqual(await offWindows.getAudioOutputs(), unavailable('platform-unsupported'));
  assert.deepEqual(host.queries, []);
  assert.deepEqual(await owner({ platform: 'win32', host: null }).getAudioOutputs(),
    unavailable('helper-unavailable'));
});

test('audio output owner hashes private keys, sanitizes labels, sorts, and resolves fresh selections', async () => {
  const host = new AudioHost();
  host.result = {
    ok: true,
    outputs: [
      { nativeKey: 'synthetic-key-b', label: '  Zebra\u0007 Device  ' },
      { nativeKey: 'synthetic-key-a', label: 'Alpha\u00a0Device' },
    ],
  };
  const audioOwner = owner({ platform: 'win32', host });
  const list = await audioOwner.getAudioOutputs();
  assert.deepEqual(list, {
    status: 'ready',
    reason: 'available',
    outputs: [
      { kind: 'system-default', id: 'system-default', label: 'System default' },
      {
        kind: 'device',
        id: createAudioOutputDeviceId('synthetic-key-a'),
        label: 'Alpha Device',
      },
      {
        kind: 'device',
        id: createAudioOutputDeviceId('synthetic-key-b'),
        label: 'Zebra Device',
      },
    ],
  });
  assert.doesNotMatch(JSON.stringify(list), /synthetic-key/u);
  const resolved = await audioOwner.resolveSelectedOutput(
    createAudioOutputDeviceId('synthetic-key-a'),
  );
  assert.deepEqual(resolved, { audioOutputNativeKey: 'synthetic-key-a', matched: true });
  assert.equal(host.queries.length, 2);
});

test('audio output owner reports bounded partial lists and fails closed on collisions or stale ids', async () => {
  const host = new AudioHost();
  host.result = {
    ok: true,
    outputs: [
      { nativeKey: 'synthetic-duplicate', label: 'First' },
      { nativeKey: 'synthetic-duplicate', label: 'Second' },
      ...outputs(40),
    ],
  };
  const list = await owner({ platform: 'win32', host }).getAudioOutputs();
  assert.equal(list.status, 'partial');
  assert.equal(list.reason, 'device-list-sanitized');
  assert.equal(list.outputs.length, 33);

  const diagnostics = new DiagnosticEventStore();
  const collided = owner({
    platform: 'win32',
    host: hostWith([
      { nativeKey: 'synthetic-one', label: 'One' },
      { nativeKey: 'synthetic-two', label: 'Two' },
    ]),
    diagnostics,
    createOpaqueId: () => `audio_${'C'.repeat(43)}`,
  });
  assert.deepEqual(await collided.getAudioOutputs(), unavailable('enumeration-failed'));
  assert.match(JSON.stringify(diagnostics.getRecords()), /audio-output-id-collision/u);
  assert.doesNotMatch(JSON.stringify(diagnostics.getRecords()), /synthetic-one|synthetic-two/u);

  const stale = await owner({ platform: 'win32', host: hostWith([]) })
    .resolveSelectedOutput(`audio_${'Z'.repeat(43)}`);
  assert.deepEqual(stale, { audioOutputNativeKey: null, matched: false });
});

function owner(input: {
  platform: SettingsAudioOutputOwnerOptions['platform'];
  host: NativePlayerHostPort | null;
  diagnostics?: DiagnosticEventStore;
  createOpaqueId?: () => `audio_${string}`;
}) {
  let request = 0;
  return new SettingsAudioOutputOwner({
    platform: input.platform,
    nativeHost: input.host,
    createRequestId: (prefix) => `${prefix}-${++request}`,
    diagnosticEventStore: input.diagnostics,
    createOpaqueId: input.createOpaqueId,
  });
}

function hostWith(rows: NativeAudioOutput[]): AudioHost {
  const host = new AudioHost();
  host.result = { ok: true, outputs: rows };
  return host;
}

function outputs(count: number): NativeAudioOutput[] {
  return Array.from({ length: count }, (_, index) => ({
    nativeKey: `synthetic-key-${index}`,
    label: `Device ${String(index).padStart(2, '0')}`,
  }));
}

function unavailable(reason: 'platform-unsupported' | 'helper-unavailable' | 'enumeration-failed') {
  return {
    status: 'unavailable',
    reason,
    outputs: [{ kind: 'system-default', id: 'system-default', label: 'System default' }],
  };
}
