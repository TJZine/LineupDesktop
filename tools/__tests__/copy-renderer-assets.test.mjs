import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { copyRendererAssets } from '../copy-renderer-assets.mjs';

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

    for (const relativePath of ['lineup-logo-mark.png', path.join('nested', 'proof.bin')]) {
      const sourceHash = sha256(path.join(source, 'assets', relativePath));
      const targetHash = sha256(path.join(target, 'assets', relativePath));
      assert.equal(targetHash, sourceHash, relativePath);
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

function sha256(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}
