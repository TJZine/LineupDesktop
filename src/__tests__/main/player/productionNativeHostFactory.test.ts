import test from 'node:test';
import assert from 'node:assert/strict';
import process from 'node:process';
import {
  createProductionNativeHostFactory,
  getProductionHelperPath,
} from '../../../main/player/productionNativeHostFactory.js';
import { NativePlayerHostProcess } from '../../../main/player/nativePlayerHostProcess.js';

test('productionNativeHostFactory returns null on non-Windows platforms', () => {
  if (process.platform !== 'win32') {
    const factory = createProductionNativeHostFactory();
    assert.equal(factory, null);

    const path = getProductionHelperPath();
    assert.equal(path, null);
  }
});

test('productionNativeHostFactory creates NativePlayerHostProcess when helper is available on Windows', () => {
  if (process.platform === 'win32') {
    const helperPath = getProductionHelperPath();
    const factory = createProductionNativeHostFactory();
    if (helperPath === null) {
      assert.equal(factory, null);
    } else {
      assert.ok(factory);
      const host = factory();
      assert.ok(host instanceof NativePlayerHostProcess);
    }
  }
});
