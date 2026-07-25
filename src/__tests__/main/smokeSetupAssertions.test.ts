import test from 'node:test';
import assert from 'node:assert/strict';

import {
  evaluateSetupSmokeProjection,
  type SetupSmokeProjection,
} from '../../main/smokeSetupAssertions.js';

test('setup smoke accepts signed-out auth and current staged library terminal projections', () => {
  assert.equal(evaluateSetupSmokeProjection(authProjection()).accepted, true);
  for (const status of ['loading', 'ready', 'empty'] as const) {
    assert.equal(evaluateSetupSmokeProjection(libraryProjection(status)).accepted, true);
  }
});

test('setup smoke rejects hidden, inert, wrong-owner, idle, error, and recovery projections', () => {
  const cases: SetupSmokeProjection[] = [
    { ...authProjection(), auth: { ...authProjection().auth, hostVisible: false } },
    { ...authProjection(), auth: { ...authProjection().auth, ownerVisible: false } },
    { ...authProjection(), auth: { ...authProjection().auth, owner: 'auth-error' } },
    libraryProjection('idle'),
    libraryProjection('error'),
    libraryProjection('recovery'),
    { ...libraryProjection('ready'), library: { ...libraryProjection('ready').library, workspaceVisible: false } },
    { ...libraryProjection('ready'), library: { ...libraryProjection('ready').library, ownerVisible: false } },
    { ...libraryProjection('ready'), library: { ...libraryProjection('ready').library, ownerActive: false } },
    { ...libraryProjection('ready'), library: { ...libraryProjection('ready').library, documentOwner: 'recovery-error' } },
  ];
  for (const projection of cases) {
    assert.equal(evaluateSetupSmokeProjection(projection).accepted, false);
  }
});

test('setup smoke rejects missing current flow controls and obsolete selectors', () => {
  for (const control of ['selectAllPresent', 'clearAllPresent', 'nextPresent', 'backPresent'] as const) {
    const valid = libraryProjection('ready');
    assert.equal(evaluateSetupSmokeProjection({
      ...valid,
      library: { ...valid.library, [control]: false },
    }).accepted, false);
  }
  const obsolete = authProjection();
  assert.deepEqual(evaluateSetupSmokeProjection({
    ...obsolete,
    obsoleteSelectorsPresent: true,
  }), {
    accepted: false,
    failures: ['obsolete selectors'],
  });
});

function authProjection(): SetupSmokeProjection {
  return {
    obsoleteSelectorsPresent: false,
    auth: {
      hostVisible: true,
      owner: 'auth-link-code',
      ownerVisible: true,
      requestPinControlPresent: true,
    },
    library: invalidLibrary('idle'),
  };
}

function libraryProjection(status: SetupSmokeProjection['library']['status']): SetupSmokeProjection {
  return {
    obsoleteSelectorsPresent: false,
    auth: {
      hostVisible: false,
      owner: null,
      ownerVisible: false,
      requestPinControlPresent: false,
    },
    library: {
      ...invalidLibrary(status),
      workspaceVisible: true,
      documentOwner: 'library',
      ownerVisible: true,
      ownerActive: true,
      sectionsPresent: true,
      selectAllPresent: true,
      clearAllPresent: true,
      nextPresent: true,
      backPresent: true,
    },
  };
}

function invalidLibrary(status: SetupSmokeProjection['library']['status']): SetupSmokeProjection['library'] {
  return {
    workspaceVisible: false,
    documentOwner: null,
    ownerVisible: false,
    ownerActive: false,
    status,
    sectionsPresent: false,
    selectAllPresent: false,
    clearAllPresent: false,
    nextPresent: false,
    backPresent: false,
  };
}
