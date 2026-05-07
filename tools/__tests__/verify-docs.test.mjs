import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { verifyDocs } from '../verify-docs.mjs';

test('verifyDocs passes for the repository scaffold', () => {
  assert.deepEqual(verifyDocs(), []);
});

test('verifyDocs reports missing required files', () => {
  const root = makeFixture();
  fs.writeFileSync(path.join(root, 'README.md'), '# Missing scaffold\n');
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('Missing required file: AGENTS.md')));
});

test('verifyDocs reports broken markdown links', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'README.md'), '[Broken](./missing.md)\n');
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('broken link')));
});

test('verifyDocs rejects upstream cleanup baggage files', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'ARCHITECTURE_CLEANUP_CHECKLIST.md'), '# Not allowed\n');
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('Forbidden upstream cleanup artifact')));
});

test('verifyDocs rejects placeholder package scripts', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({
    scripts: {
      typecheck: 'true',
      test: 'true',
      'test:contracts': 'true',
      'test:harness-docs': 'true',
      'verify:docs': 'true',
      'verify:redaction': 'true',
      verify: 'true',
    },
  }));
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('script verify must be exactly')));
});

test('verifyDocs rejects active plans missing required standard fields', () => {
  const root = makeFixture({ complete: true });
  const planPath = path.join(root, 'docs/plans/active.md');
  fs.writeFileSync(planPath, [
    '**Plan Status:** active',
    '# Active Plan',
    '**Task family:** feature/design',
    '## Goal',
    '## Non-Goals',
    '## Parent Architecture Alignment',
    '## Files In Scope',
    '## Files Out Of Scope',
    '## Architecture Seam Decision Gate',
    '## Verification Commands',
    '## Replan Triggers',
  ].join('\n'));
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('missing ## Required Reading')));
  assert(errors.some((error) => error.includes('missing ## Rollback Notes')));
  assert(errors.some((error) => error.includes('exactly one verification classification')));
});

test('verifyDocs rejects detector ids and cleanup package fields', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'docs/plans/imported-detector.md'), [
    '# Imported Detector',
    'smells::runtime-ui-hotspot',
    'slice_table',
  ].join('\n'));
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('detector issue id')));
  assert(errors.some((error) => error.includes('cleanup package field')));
});

test('verifyDocs rejects score artifacts outside root scorecard image', () => {
  const root = makeFixture({ complete: true });
  const scorecardPath = path.join(root, 'docs/agentic/evals/baselines/scorecard.json');
  fs.mkdirSync(path.dirname(scorecardPath), { recursive: true });
  fs.writeFileSync(scorecardPath, '{}');
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('Forbidden upstream cleanup artifact path')));
});

function makeFixture(options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-desktop-docs-'));
  if (options.complete) {
    const required = [
      'AGENTS.md',
      'README.md',
      'package.json',
      'tsconfig.json',
      'docs/AGENTIC_DEV_WORKFLOW.md',
      'docs/architecture/README.md',
      'docs/architecture/CURRENT_STATE.md',
      'docs/architecture/desktop-repo-genesis-adr.md',
      'docs/architecture/import-ledger.md',
      'docs/architecture/security-and-secret-flow.md',
      'docs/architecture/playback-architecture.md',
      'docs/architecture/packaging-release-gates.md',
      'docs/agentic/plan-authoring-standard.md',
      'docs/agentic/session-prompts/README.md',
      'docs/agentic/session-prompts/feature-plan.md',
      'docs/agentic/session-prompts/feature-implement.md',
      'docs/agentic/session-prompts/feature-review.md',
      'docs/agentic/session-prompts/workflow-harness-review.md',
      'docs/plans/README.md',
      'docs/runs/README.md',
      'docs/development/testing.md',
      'tools/verify-docs.mjs',
      'tools/verify-redaction.mjs',
    ];
    for (const relativePath of required) {
      const absolute = path.join(root, relativePath);
      fs.mkdirSync(path.dirname(absolute), { recursive: true });
      fs.writeFileSync(absolute, relativePath === 'package.json'
        ? JSON.stringify({ scripts: {
          typecheck: 'tsc --noEmit',
          test: 'npm run test:contracts && npm run test:harness-docs',
          'test:contracts': 'tsx --test src/__tests__/*.test.ts',
          'test:harness-docs': 'node --test tools/__tests__/*.test.mjs',
          'verify:docs': 'node tools/verify-docs.mjs',
          'verify:redaction': 'node tools/verify-redaction.mjs',
          verify: 'npm run typecheck && npm run test && npm run verify:docs && npm run verify:redaction',
        } })
        : '# Fixture\n');
    }
  }
  return root;
}
