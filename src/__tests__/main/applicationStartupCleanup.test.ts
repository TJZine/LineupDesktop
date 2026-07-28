import assert from 'node:assert/strict';
import test from 'node:test';

import {
  cleanupFailedApplicationStartup,
  type ApplicationStartupCleanupSteps,
} from '../../main/applicationStartupCleanup.js';

const cleanupOrder = [
  'settingsIpc',
  'diagnosticsIpc',
  'playerRecoveryIpc',
  'playbackTransitionOwner',
  'playerIpc',
  'playbackEventRouter',
  'playbackRuntime',
  'channelComposition',
  'plexComposition',
  'singleInstanceOwner',
] as const satisfies readonly (keyof ApplicationStartupCleanupSteps)[];

test('startup rollback runs every cleanup owner in deterministic dependency order', async () => {
  const observed: string[] = [];

  await cleanupFailedApplicationStartup(
    createCleanupSteps((name) => {
      observed.push(name);
    }),
    () => assert.fail('successful cleanup must not report a diagnostic'),
  );

  assert.deepEqual(observed, cleanupOrder);
});

test('startup rollback reports each failure and continues through later cleanup owners', async () => {
  const observed: string[] = [];
  const reported: string[] = [];
  const failures = new Set<keyof ApplicationStartupCleanupSteps>([
    'settingsIpc',
    'playerIpc',
    'playbackRuntime',
    'plexComposition',
  ]);

  await cleanupFailedApplicationStartup(
    createCleanupSteps((name) => {
      observed.push(name);
      if (failures.has(name)) {
        throw new Error(`failure:${name}`);
      }
    }),
    (message, error) => {
      assert.match(message, /failed during startup rollback$/u);
      assert.ok(error instanceof Error);
      reported.push(error.message);
    },
  );

  assert.deepEqual(observed, cleanupOrder);
  assert.deepEqual(
    reported,
    [...failures].map((name) => `failure:${name}`),
  );
});

test('startup rollback survives a failing diagnostic sink', async () => {
  const observed: string[] = [];

  await cleanupFailedApplicationStartup(
    createCleanupSteps((name) => {
      observed.push(name);
      if (name === 'diagnosticsIpc') {
        throw new Error('cleanup failed');
      }
    }),
    () => {
      throw new Error('diagnostic sink failed');
    },
  );

  assert.deepEqual(observed, cleanupOrder);
});

function createCleanupSteps(
  cleanup: (name: keyof ApplicationStartupCleanupSteps) => void,
): ApplicationStartupCleanupSteps {
  return {
    settingsIpc: () => cleanup('settingsIpc'),
    diagnosticsIpc: () => cleanup('diagnosticsIpc'),
    playerRecoveryIpc: () => cleanup('playerRecoveryIpc'),
    playbackTransitionOwner: {
      dispose: () => cleanup('playbackTransitionOwner'),
    },
    playerIpc: {
      teardown: async () => cleanup('playerIpc'),
    },
    playbackEventRouter: {
      dispose: () => cleanup('playbackEventRouter'),
    },
    playbackRuntime: {
      teardown: async () => cleanup('playbackRuntime'),
    },
    channelComposition: async () => cleanup('channelComposition'),
    plexComposition: async () => cleanup('plexComposition'),
    singleInstanceOwner: {
      teardown: () => cleanup('singleInstanceOwner'),
    },
  };
}
