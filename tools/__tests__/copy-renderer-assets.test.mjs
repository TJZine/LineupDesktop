import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  copyRendererAssets,
  copyRendererChannelBuilderRuntime,
} from '../copy-renderer-assets.mjs';

test('renderer asset copy preserves recursive files and exact binary hashes', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-renderer-assets-'));
  const source = path.join(root, 'source');
  const target = path.join(root, 'target');
  try {
    fs.mkdirSync(path.join(source, 'styles'), { recursive: true });
    fs.mkdirSync(path.join(source, 'assets', 'nested'), { recursive: true });
    fs.writeFileSync(path.join(source, 'index.html'), '<!doctype html>');
    fs.writeFileSync(path.join(source, 'styles.css'), '@import "./styles/base.css";');
    fs.writeFileSync(path.join(source, 'styles', 'base.css'), ':root{}');
    fs.writeFileSync(path.join(source, 'assets', 'lineup-logo-mark.png'), new Uint8Array([0, 1, 2, 3]));
    fs.writeFileSync(path.join(source, 'assets', 'nested', 'proof.bin'), new Uint8Array([9, 8, 7, 6]));

    copyRendererAssets(source, target);

    for (const relativePath of [
      'index.html',
      'styles.css',
      path.join('styles', 'base.css'),
      path.join('assets', 'lineup-logo-mark.png'),
      path.join('assets', 'nested', 'proof.bin'),
    ]) {
      const sourceHash = sha256(path.join(source, relativePath));
      const targetHash = sha256(path.join(target, relativePath));
      assert.equal(targetHash, sourceHash, relativePath);
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('renderer runtime copy includes only byte-exact Channel Builder config dependencies', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-renderer-runtime-'));
  const compiled = path.join(root, 'dist', 'domain', 'channelBuilder');
  const renderer = path.join(root, 'dist', 'renderer');
  try {
    fs.mkdirSync(compiled, { recursive: true });
    for (const [fileName, bytes] of [
      ['config.js', new Uint8Array([1, 3, 5, 7])],
      ['constants.js', new Uint8Array([2, 4, 6, 8])],
      ['config.js.map', new Uint8Array([9])],
      ['index.js', new Uint8Array([10])],
      ['planner.js', new Uint8Array([11])],
    ]) {
      fs.writeFileSync(path.join(compiled, fileName), bytes);
    }

    copyRendererChannelBuilderRuntime(compiled, renderer);

    const served = path.join(renderer, 'domain', 'channelBuilder');
    for (const fileName of ['config.js', 'constants.js']) {
      assert.equal(
        sha256(path.join(served, fileName)),
        sha256(path.join(compiled, fileName)),
        fileName,
      );
    }
    for (const fileName of ['config.js.map', 'index.js', 'planner.js']) {
      assert.equal(fs.existsSync(path.join(served, fileName)), false, fileName);
    }
    assert.deepEqual(fs.readdirSync(served).sort(), ['config.js', 'constants.js']);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

function sha256(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}
