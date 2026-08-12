import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import process from 'node:process';
import {
  createProductionNativeHostFactory,
  getProductionHelperPath,
  resolveLocalProductionHelperPath,
} from '../../../main/player/productionNativeHostFactory.js';
import { NativePlayerHostProcess } from '../../../main/player/nativePlayerHostProcess.js';

const getNativeParentIdentity = () => ({ hwnd: '42', pid: 9 });

test('productionNativeHostFactory returns null on non-Windows platforms', () => {
  if (process.platform !== 'win32') {
    const factory = createProductionNativeHostFactory({ getNativeParentIdentity });
    assert.equal(factory, null);

    const path = getProductionHelperPath();
    assert.equal(path, null);
  }
});

test('productionNativeHostFactory creates NativePlayerHostProcess when helper is available on Windows', () => {
  if (process.platform === 'win32') {
    const helperPath = getProductionHelperPath();
    const factory = createProductionNativeHostFactory({ getNativeParentIdentity });
    if (helperPath === null) {
      assert.equal(factory, null);
    } else {
      assert.ok(factory);
      const host = factory();
      assert.ok(host instanceof NativePlayerHostProcess);
    }
  }
});

test('production helper path resolves a local dist main app path to the repo Release helper only', () => {
  const appPath = path.resolve('repo', 'dist', 'main');
  const expected = path.join(
    path.resolve(appPath, '..', '..'),
    'src',
    'native-helper',
    'Lineup.NativePlayerHost',
    'bin',
    'Release',
    'net8.0',
    'Lineup.NativePlayerHost.exe',
  );
  const resolved = resolveLocalProductionHelperPath(appPath);

  assert.equal(resolved, expected);
  assert.equal(resolved.includes(`${path.sep}Debug${path.sep}`), false);
});
