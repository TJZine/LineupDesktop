import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { scanFileContent, scanRepo } from '../verify-redaction.mjs';

test('scanFileContent reports tokenized Plex URL without storing a raw example', () => {
  const content = `https://example.invalid/video?${['X-Plex', 'Token'].join('-')}=secret`;
  assert.deepEqual(scanFileContent(content), ['tokenized Plex URL']);
});

test('scanRepo reports raw auth headers in fixture content', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-desktop-redaction-'));
  fs.mkdirSync(path.join(root, 'docs'));
  fs.writeFileSync(path.join(root, 'docs/leak.md'), `${['Authorization'].join('')}: bad\n`);
  const findings = scanRepo(root);
  assert.equal(findings.length, 1);
  assert.equal(findings[0].reason, 'raw Authorization header');
});
