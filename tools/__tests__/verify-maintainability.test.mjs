import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { collectMaintainabilityEvidence } from '../verify-maintainability.mjs';

test('reports architecture-attention and fresh-review evidence without failing growth', () => {
  const root = makeFixture();
  writeLines(path.join(root, 'src/renderer/owner.ts'), 501);
  writeLines(path.join(root, 'src/main/composition.ts'), 801);

  assert.deepEqual(collectMaintainabilityEvidence(root), [
    { path: 'src/main/composition.ts', lines: 801, review: 'fresh-review' },
    { path: 'src/renderer/owner.ts', lines: 501, review: 'disposition' },
  ]);
});

test('ignores small production files and test files', () => {
  const root = makeFixture();
  writeLines(path.join(root, 'src/renderer/owner.ts'), 500);
  writeLines(path.join(root, 'src/__tests__/owner.test.ts'), 900);

  assert.deepEqual(collectMaintainabilityEvidence(root), []);
});

test('reports supported production source and style extensions deterministically', () => {
  const root = makeFixture();
  writeLines(path.join(root, 'src/renderer/z.css'), 520);
  writeLines(path.join(root, 'src/preload/a.cts'), 510);

  assert.deepEqual(collectMaintainabilityEvidence(root), [
    { path: 'src/preload/a.cts', lines: 510, review: 'disposition' },
    { path: 'src/renderer/z.css', lines: 520, review: 'disposition' },
  ]);
});

function makeFixture() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-maintainability-'));
}

function writeLines(filePath, lineCount) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, Array.from({ length: lineCount }, (_, index) => `line${index}`).join('\n'));
}
