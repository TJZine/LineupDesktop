import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { verifyMaintainability } from '../verify-maintainability.mjs';

test('verifyMaintainability rejects oversized production files without allowlist rows', () => {
  const root = makeFixture();
  writeLines(path.join(root, 'src/renderer/index.ts'), 501);

  const errors = verifyMaintainability(root);

  assert(errors.some((error) => error.includes('src/renderer/index.ts: 501 lines exceeds 500')));
});

test('verifyMaintainability accepts allowlisted oversized production files with triggers', () => {
  const root = makeFixture();
  writeLines(path.join(root, 'src/renderer/index.ts'), 801);
  writeGuardrail(root, [
    row(
      'src/renderer/index.ts',
      'Temporary RD-13 renderer composition root while route modules are split.',
      'Split before adding any RD-14 renderer input or fullscreen behavior.',
    ),
  ]);

  assert.deepEqual(verifyMaintainability(root), []);
});

test('verifyMaintainability accepts shrink below a reviewed baseline while the file remains oversized', () => {
  const root = makeFixture();
  writeLines(path.join(root, 'src/renderer/index.ts'), 760);
  writeGuardrail(root, [
    row(
      'src/renderer/index.ts',
      'Temporary RD-13 renderer composition root while route modules are split.',
      'Split before adding any RD-14 renderer input or fullscreen behavior.',
    ),
  ]);

  assert.deepEqual(verifyMaintainability(root), []);
});

test('verifyMaintainability rejects growth beyond the reviewed baseline', () => {
  const root = makeFixture();
  writeLines(path.join(root, 'src/renderer/index.ts'), 802);
  writeGuardrail(root, [
    row(
      'src/renderer/index.ts',
      'Temporary RD-13 renderer composition root while route modules are split.',
      'Split before adding any RD-14 renderer input or fullscreen behavior.',
    ),
  ]);

  const errors = verifyMaintainability(root);

  assert(errors.some((error) => error.includes('has 802 lines but its reviewed baseline is 801')));
});

test('verifyMaintainability rejects malformed and duplicate allowlist rows', () => {
  const root = makeFixture();
  writeLines(path.join(root, 'src/renderer/index.ts'), 801);
  const filePath = path.join(root, 'docs/architecture/file-shape-guardrails.md');
  fs.writeFileSync(filePath, [
    '# File Shape Guardrails',
    '',
    '| Path | Baseline lines | Rationale | Growth/decomposition trigger |',
    '| --- | ---: | --- | --- |',
    '| src/renderer/index.ts | unknown | Temporary RD-13 renderer composition root while route modules are split. | Split before adding any RD-14 renderer input or fullscreen behavior. |',
    '| src/renderer/index.ts | 801 | Temporary RD-13 renderer composition root while route modules are split. | Split before adding any RD-14 renderer input or fullscreen behavior. |',
    '',
  ].join('\n'));

  const errors = verifyMaintainability(root);

  assert(errors.some((error) => error.includes('duplicate allowlist row for src/renderer/index.ts')));
  assert(errors.some((error) => error.includes('allowlist row needs a numeric baseline line value')));
});

test('verifyMaintainability rejects malformed allowlist table headers', () => {
  const root = makeFixture();
  writeLines(path.join(root, 'src/renderer/index.ts'), 801);
  const filePath = path.join(root, 'docs/architecture/file-shape-guardrails.md');
  fs.writeFileSync(filePath, [
    '# File Shape Guardrails',
    '',
    '| Path | Rationale | Baseline lines | Growth/decomposition trigger |',
    '| --- | --- | ---: | --- |',
    '| src/renderer/index.ts | Temporary RD-13 renderer composition root while route modules are split. | 801 | Split before adding any RD-14 renderer input or fullscreen behavior. |',
    '',
  ].join('\n'));

  const errors = verifyMaintainability(root);

  assert(errors.some((error) => error.includes('allowlist table header must be Path | Baseline lines | Rationale | Growth/decomposition trigger')));
});

test('verifyMaintainability rejects stale and underspecified allowlist rows', () => {
  const root = makeFixture();
  writeLines(path.join(root, 'src/renderer/index.ts'), 20);
  writeLines(path.join(root, 'src/main/index.ts'), 801);
  writeGuardrail(root, [
    row('src/renderer/index.ts', 'Old reason that is now stale.', 'Remove after split is complete.'),
    row('src/main/index.ts', 'short', 'short'),
  ]);

  const errors = verifyMaintainability(root);

  assert(errors.some((error) => error.includes('src/renderer/index.ts is 20 lines')));
  assert(errors.some((error) => error.includes('src/main/index.ts allowlist row needs a specific rationale')));
  assert(errors.some((error) => error.includes('src/main/index.ts allowlist row needs a decomposition/revisit trigger')));
});

test('verifyMaintainability ignores test files', () => {
  const root = makeFixture();
  writeLines(path.join(root, 'src/__tests__/renderer/index.test.ts'), 900);

  assert.deepEqual(verifyMaintainability(root), []);
});

function makeFixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-maintainability-'));
  fs.mkdirSync(path.join(root, 'src/renderer'), { recursive: true });
  fs.mkdirSync(path.join(root, 'src/main'), { recursive: true });
  fs.mkdirSync(path.join(root, 'src/__tests__/renderer'), { recursive: true });
  writeGuardrail(root, []);
  return root;
}

function writeGuardrail(root, rows) {
  const filePath = path.join(root, 'docs/architecture/file-shape-guardrails.md');
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, [
    '# File Shape Guardrails',
    '',
    '| Path | Baseline lines | Rationale | Growth/decomposition trigger |',
    '| --- | ---: | --- | --- |',
    ...rows,
    '',
  ].join('\n'));
}

function row(filePath, reason, trigger) {
  return `| ${filePath} | 801 | ${reason} | ${trigger} |`;
}

function writeLines(filePath, lineCount) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, Array.from({ length: lineCount }, (_, index) => `line${index}`).join('\n'));
}
