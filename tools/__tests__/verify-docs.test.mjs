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

test('verifyDocs reports broken markdown anchors', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'README.md'), '[Broken](./docs/AGENTIC_DEV_WORKFLOW.md#missing-anchor)\n');
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('broken anchor')));
});

test('verifyDocs reports broken same-page markdown anchors', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'README.md'), [
    '# Readme',
    '[Broken](#missing-anchor)',
  ].join('\n'));
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('broken anchor')));
});

test('verifyDocs requires raw run bundles to stay ignored', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, '.gitignore'), 'node_modules/\n');
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('local-only artifact marker: docs/runs/*')));
  assert(errors.some((error) => error.includes('local-only artifact marker: .codanna/')));
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
      lint: 'true',
      typecheck: 'true',
      test: 'true',
      'test:contracts': 'true',
      'test:harness-docs': 'true',
      'verify:architecture': 'true',
      'verify:docs': 'true',
      'verify:maintainability': 'true',
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
  assert(errors.some((error) => error.includes('missing ## Required Skills')));
  assert(errors.some((error) => error.includes('missing ## Evidence And Discovery')));
  assert(errors.some((error) => error.includes('missing ## Impact Snapshot')));
  assert(errors.some((error) => error.includes('missing ## Planner Self-Check')));
  assert(errors.some((error) => error.includes('missing ## Acceptance Criteria')));
  assert(errors.some((error) => error.includes('missing ## Rollback Notes')));
  assert(errors.some((error) => error.includes('missing ## Commit Checkpoints')));
  assert(errors.some((error) => error.includes('exactly one verification classification')));
});

test('verifyDocs requires active plan fields to be real markdown headings', () => {
  const root = makeFixture({ complete: true });
  const planPath = path.join(root, 'docs/plans/active.md');
  fs.writeFileSync(planPath, [
    '**Plan Status:** active',
    '**Task family:** feature/design',
    'new regression/contract test required',
    'This prose mentions `## Goal`, `## Non-Goals`, `## Parent Architecture Alignment`,',
    '`## Required Reading`, `## Required Skills`, `## Evidence And Discovery`,',
    '`## Impact Snapshot`, `## Files In Scope`, `## Files Out Of Scope`,',
    '`## Planner Self-Check`, `## Architecture Seam Decision Gate`,',
    '`## Verification Commands`, `## Acceptance Criteria`, `## Replan Triggers`,',
    '`## Rollback Notes`, and `## Commit Checkpoints` without declaring sections.',
  ].join('\n'));

  const errors = verifyDocs(root);

  assert(errors.some((error) => error.includes('missing ## Goal')));
  assert(errors.some((error) => error.includes('missing ## Commit Checkpoints')));
});

test('verifyDocs rejects active plans with late status marker or heading order drift', () => {
  const root = makeFixture({ complete: true });
  const planPath = path.join(root, 'docs/plans/active.md');
  fs.writeFileSync(planPath, [
    '# Active Plan',
    '## Goal',
    '**Plan Status:** active',
    '**Task family:** feature/design',
    'new regression/contract test required',
    '## Non-Goals',
    '## Parent Architecture Alignment',
    '## Required Reading',
    '## Required Skills',
    '## Evidence And Discovery',
    '## Impact Snapshot',
    '## Files In Scope',
    '## Files Out Of Scope',
    '## Architecture Seam Decision Gate',
    '## Planner Self-Check',
    '## Verification Commands',
    '## Acceptance Criteria',
    '## Replan Triggers',
    '## Rollback Notes',
    '## Commit Checkpoints',
  ].join('\n'));

  const errors = verifyDocs(root);

  assert(errors.some((error) => error.includes('status marker must appear before the first ## heading')));
  assert(errors.some((error) => error.includes('heading out of order: ## Architecture Seam Decision Gate')));
});

test('verifyDocs rejects Tier 3 active plans missing model and handoff shape', () => {
  const root = makeFixture({ complete: true });
  const planPath = path.join(root, 'docs/plans/active.md');
  fs.writeFileSync(planPath, [
    '# Active Plan',
    '**Plan Status:** active',
    '**Task family:** feature/design',
    '**Tier:** Tier 3',
    'new regression/contract test required',
    '## Goal',
    '## Non-Goals',
    '## Parent Architecture Alignment',
    '## Required Reading',
    '## Required Skills',
    '## Evidence And Discovery',
    '## Impact Snapshot',
    '## Files In Scope',
    '## Files Out Of Scope',
    '## Planner Self-Check',
    '## Architecture Seam Decision Gate',
    '## Verification Commands',
    '## Acceptance Criteria',
    '## Replan Triggers',
    '## Rollback Notes',
    '## Commit Checkpoints',
    'NEXT_SESSION_HANDOFF',
    'TASK: fixture',
  ].join('\n'));

  const errors = verifyDocs(root);

  assert(errors.some((error) => error.includes('missing MODEL_SUGGESTION')));
  assert(errors.some((error) => error.includes('missing ## Architecture Health or ## File Shape Preflight section')));
  assert(errors.some((error) => error.includes('NEXT_SESSION_HANDOFF missing field NEXT_SESSION_LAUNCHER:')));
  assert(errors.some((error) => error.includes('NEXT_SESSION_HANDOFF missing field MESSAGE:')));
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

test('verifyDocs rejects workflow docs missing feature-quality anchors', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'docs/agentic/plan-authoring-standard.md'), '# Missing required headings\n');
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('missing active-plan heading reference')));
});

test('verifyDocs rejects missing fresh-chat and skill adaptation anchors', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'docs/AGENTIC_DEV_WORKFLOW.md'), [
    '# Fixture',
    'docs/agentic/external-guidance.md',
  ].join('\n'));
  fs.writeFileSync(path.join(root, 'docs/agentic/session-prompts/README.md'), '# Fixture\n');
  fs.writeFileSync(path.join(root, 'docs/agentic/skill-strategy.md'), '# Fixture\n');

  const errors = verifyDocs(root);

  assert(errors.some((error) => error.includes('missing fresh chat bootstrap marker')));
  assert(errors.some((error) => error.includes('missing launcher routing matrix marker')));
  assert(errors.some((error) => error.includes('missing Codex skill discovery policy marker')));
  assert(errors.some((error) => error.includes('missing legacy skill adaptation audit marker')));
});

test('verifyDocs rejects workflow skill-transfer sections missing semantic phrases', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'docs/AGENTIC_DEV_WORKFLOW.md'), [
    '# Fixture',
    '## Fresh Chat Bootstrap',
    'docs/agentic/external-guidance.md',
  ].join('\n'));
  fs.writeFileSync(path.join(root, 'docs/agentic/session-prompts/README.md'), [
    '# Fixture',
    '## Launcher Routing Matrix',
  ].join('\n'));
  fs.writeFileSync(path.join(root, 'docs/agentic/skill-strategy.md'), [
    '# Fixture',
    '## Codex Skill Discovery',
    '## Legacy Skill Adaptation Audit',
  ].join('\n'));

  const errors = verifyDocs(root);

  assert(errors.some((error) => error.includes('missing fresh chat bootstrap phrase')));
  assert(errors.some((error) => error.includes('missing default workflow phrase')));
  assert(errors.some((error) => error.includes('missing multi-agent usage phrase')));
  assert(errors.some((error) => error.includes('missing session handoff format phrase')));
  assert(errors.some((error) => error.includes('missing launcher routing matrix phrase')));
  assert(errors.some((error) => error.includes('missing Codex skill discovery policy phrase')));
  assert(errors.some((error) => error.includes('missing legacy skill adaptation audit phrase')));
});

test('verifyDocs rejects missing production engineering guardrails', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'docs/AGENTIC_DEV_WORKFLOW.md'), [
    '# Fixture',
    '## Fresh Chat Bootstrap',
    'docs/agentic/external-guidance.md',
    'Do not depend on the original Lineup repo',
    'Run `git status --short --branch` before planning edits',
    '## Default Workflow',
    'Plan explicitly before multi-step work',
    'Do not freeze a plan while ownership',
    '## Production Engineering Guardrails',
    '## Multi-Agent Usage',
    'Keep read-only roles read-only',
    'Do not let a worker invent architecture seams',
    '## Session Handoffs',
    'NEXT_SESSION_HANDOFF',
    'MODEL_SUGGESTION',
  ].join('\n'));

  const errors = verifyDocs(root);

  assert(errors.some((error) => error.includes('missing production engineering guardrails structure')));
});

test('verifyDocs rejects missing MVP fake-surface retirement policy', () => {
  const root = makeFixture({ complete: true });

  let workflow = fs.readFileSync(path.join(root, 'docs/AGENTIC_DEV_WORKFLOW.md'), 'utf8');
  workflow = workflow.replace(
    'Fake scaffold product UI in reachable app routes moves to tests, smoke harnesses, or dev-only fixtures.',
    'Scaffold policy omitted.',
  );
  fs.writeFileSync(path.join(root, 'docs/AGENTIC_DEV_WORKFLOW.md'), workflow);
  let errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('scaffold product-route retirement')));

  fs.writeFileSync(path.join(root, 'docs/AGENTIC_DEV_WORKFLOW.md'), fixtureContent('docs/AGENTIC_DEV_WORKFLOW.md'));
  let featureQualityLoop = fs.readFileSync(path.join(root, 'docs/agentic/session-prompts/feature-quality-loop.md'), 'utf8');
  featureQualityLoop = featureQualityLoop.replace(
    'fake app routes fake/scaffold UI in a reachable product route active product routes for the roadmap item no longer depend on fake controls',
    'fake route policy omitted',
  );
  fs.writeFileSync(path.join(root, 'docs/agentic/session-prompts/feature-quality-loop.md'), featureQualityLoop);
  errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('missing MVP fake-surface retirement marker')));

  fs.writeFileSync(
    path.join(root, 'docs/agentic/session-prompts/feature-quality-loop.md'),
    fixtureContent('docs/agentic/session-prompts/feature-quality-loop.md'),
  );
  let roadmap = fs.readFileSync(path.join(root, 'docs/roadmap/desktop-port-roadmap.md'), 'utf8');
  roadmap = roadmap.replace('## MVP Build Posture', '## Fixture Posture');
  fs.writeFileSync(path.join(root, 'docs/roadmap/desktop-port-roadmap.md'), roadmap);
  errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('MVP Build Posture missing required fake-surface retirement concepts')));
});

test('verifyDocs allows MVP build posture prose changes when scoped concepts remain', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'docs/roadmap/desktop-port-roadmap.md'), [
    '# Desktop Port Roadmap',
    '## MVP Build Posture',
    'A fake UI in a reachable app route is temporary proof only.',
    'The real product journey should drive each owned slice.',
    'Server/library selection should be part of that journey.',
    'Channel setup and channel creation surfaces must be replaced or isolated before closeout.',
    'The channel setup route must not keep a fake setup summary once live setup owns the route.',
  ].join('\n'));

  const errors = verifyDocs(root);

  assert(!errors.some((error) => error.includes('MVP Build Posture')));
});

test('verifyDocs requires upstream behavior guardrail document and slice coverage', () => {
  const root = makeFixture({ complete: true });
  fs.rmSync(path.join(root, 'docs/architecture/upstream-behavior-guardrails.md'));

  const missingErrors = verifyDocs(root);

  assert(missingErrors.some((error) => error.includes('Missing required file: docs/architecture/upstream-behavior-guardrails.md')));

  fs.writeFileSync(path.join(root, 'docs/architecture/upstream-behavior-guardrails.md'), [
    '# Upstream Behavior Guardrails',
    'Original Lineup behavior is reference evidence',
    'not Desktop architecture truth',
    '## Guardrail Matrix',
    'Preserved Behavior Evidence',
    'Required Desktop Proof Surface',
    'Intentional Divergence Policy',
    'Forbidden Shortcuts',
  ].join('\n'));

  const coverageErrors = verifyDocs(root);

  assert(coverageErrors.some((error) => error.includes('RD-07/RD-08 player and stream behavior')));
  assert(coverageErrors.some((error) => error.includes('RD-10 Plex auth/discovery/library')));
  assert(coverageErrors.some((error) => error.includes('RD-11 scheduler/channel/content')));
  assert(coverageErrors.some((error) => error.includes('RD-13 UI/navigation/settings')));
  assert(coverageErrors.some((error) => error.includes('RD-20 reference compatibility')));
});

test('verifyDocs requires RD-19 validation checklist safety sections', () => {
  const root = makeFixture({ complete: true });
  fs.rmSync(path.join(root, 'docs/development/rd-19-internal-validation-checklist.md'));

  const missingErrors = verifyDocs(root);

  assert(missingErrors.some((error) => error.includes('Missing RD-19 validation checklist')));

  fs.writeFileSync(path.join(root, 'docs/development/rd-19-internal-validation-checklist.md'), [
    '# RD-19 Internal Validation Checklist',
    '## Evidence Rules',
    'redacted summaries only',
    '## Redaction Gate',
    'tools/verify-redaction.mjs',
    '## Blocker Classifications',
    'release blocker beta blocker deferred',
  ].join('\n'));

  const driftErrors = verifyDocs(root);

  assert(driftErrors.some((error) => error.includes('missing RD-19 checklist heading ## Stop Conditions')));
  assert(driftErrors.some((error) => error.includes('missing RD-19 evidence rules required safety content')));
  assert(driftErrors.some((error) => error.includes('missing RD-19 redaction gate required safety content')));
  assert(driftErrors.some((error) => error.includes('missing RD-19 Windows x64 proof requirement')));
  assert(driftErrors.some((error) => error.includes('missing RD-19 validation matrix area: Auth')));
});

test('verifyDocs rejects RD-19 checklist matrix and template drift', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'docs/development/rd-19-internal-validation-checklist.md'), rd19ValidationChecklistFixture({
    omitLines: [
      '| Crash recovery | Redacted summary only. | not run | release blocker |',
      '- Redaction gate status:',
      '| RD19-BLOCK-001 | YYYY-MM-DD | <area> | <redacted summary only> | release blocker/beta blocker/deferred | <stop condition or none> | <command/status/counts only> | <owner or plan needed> | <specific trigger> | open |',
    ],
  }));

  const errors = verifyDocs(root);

  assert(errors.some((error) => error.includes('missing RD-19 validation matrix area: Crash recovery')));
  assert(errors.some((error) => error.includes('missing RD-19 scenario summary template required safety content')));
  assert(errors.some((error) => error.includes('missing RD-19 blocker log template required safety content')));
});

test('verifyDocs requires multi-token RD-19 Windows proof commands on one line', () => {
  const root = makeFixture({ complete: true });
  const checklistPath = path.join(root, 'docs/development/rd-19-internal-validation-checklist.md');
  const content = fs.readFileSync(checklistPath, 'utf8');
  fs.writeFileSync(
    checklistPath,
    content.replace(
      'node tools/verify-windows-internal-package.mjs --package <ignored-package-root> --manifest <ignored-provenance-manifest>',
      [
        'node tools/verify-windows-internal-package.mjs --package <ignored-package-root>',
        '--manifest <ignored-provenance-manifest>',
      ].join('\n'),
    ),
  );

  const errors = verifyDocs(root);

  assert(errors.some((error) => (
    error.includes('missing RD-19 Windows x64 proof requirement: internal Windows package verifier')
  )));
});

test('verifyDocs rejects plan standard missing dependency governance', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'docs/agentic/plan-authoring-standard.md'), [
    '# Fixture',
    '## Goal',
    '## Non-Goals',
    '## Parent Architecture Alignment',
    '## Required Reading',
    '## Required Skills',
    '## Evidence And Discovery',
    '## Impact Snapshot',
    '## Files In Scope',
    '## Files Out Of Scope',
    '## Planner Self-Check',
    '## Architecture Seam Decision Gate',
    '## Verification Commands',
    '## Acceptance Criteria',
    '## Replan Triggers',
    '## Rollback Notes',
    '## Commit Checkpoints',
  ].join('\n'));

  const errors = verifyDocs(root);

  assert(errors.some((error) => error.includes('missing production-engineering plan structure')));
});

test('verifyDocs rejects Tier 3 active plans missing Architecture Health section', () => {
  const root = makeFixture({ complete: true });
  const planPath = path.join(root, 'docs/plans/active.md');
  fs.writeFileSync(planPath, tier3Plan());

  const errors = verifyDocs(root);

  assert(errors.some((error) => error.includes('missing ## Architecture Health or ## File Shape Preflight section')));
});

test('verifyDocs validates Tier 3 Architecture Health section semantically', () => {
  const root = makeFixture({ complete: true });
  const planPath = path.join(root, 'docs/plans/active.md');

  fs.writeFileSync(planPath, tier3Plan([
    '## Architecture Health',
    'General code health is noted.',
    'Verification route: npm run verify.',
    'Decision: split if this grows.',
  ]));
  const missingEvidence = verifyDocs(root);
  assert(missingEvidence.some((error) => error.includes('missing file-shape evidence')));

  fs.writeFileSync(planPath, tier3Plan([
    '## Architecture Health',
    'File-shape evidence uses docs/architecture/file-shape-guardrails.md.',
    'Decision: avoid guarded owner hotspots in this unit.',
  ]));
  const missingVerification = verifyDocs(root);
  assert(missingVerification.some((error) => error.includes('missing maintainability verification route')));

  fs.writeFileSync(planPath, tier3Plan([
    '## Architecture Health',
    'File-shape evidence uses docs/architecture/file-shape-guardrails.md.',
    'Verification route: npm run verify:architecture.',
    'Current hotspots are recorded for review.',
  ]));
  const missingDecision = verifyDocs(root);
  assert(missingDecision.some((error) => error.includes('missing decomposition, avoidance, or allowlist decision')));

  fs.writeFileSync(planPath, tier3Plan([
    '## Architecture Health',
    'File-shape evidence uses docs/architecture/file-shape-guardrails.md.',
    'Verification route: npm run verify:architecture.',
    'Before implementation, the current owner hotspots are recorded for review.',
  ]));
  const beforeOnlyDecision = verifyDocs(root);
  assert(beforeOnlyDecision.some((error) => error.includes('missing decomposition, avoidance, or allowlist decision')));

  fs.writeFileSync(planPath, tier3Plan([
    '## Architecture Health',
    'File-shape evidence uses docs/architecture/file-shape-guardrails.md.',
    'Verification route: npm run verify:architecture.',
    'Current hotspots are recorded with predecomposition notes for review.',
  ]));
  const partialDecision = verifyDocs(root);
  assert(partialDecision.some((error) => error.includes('missing decomposition, avoidance, or allowlist decision')));

  fs.writeFileSync(planPath, tier3Plan([
    '## Architecture Health Notes',
    'File-shape evidence uses docs/architecture/file-shape-guardrails.md.',
    'Verification route: npm run verify:architecture.',
    'Decision: avoid guarded owner hotspots in this unit.',
  ]));
  const wrongHeading = verifyDocs(root);
  assert(wrongHeading.some((error) => error.includes('missing ## Architecture Health or ## File Shape Preflight section')));
});

test('verifyDocs accepts Tier 3 Architecture Health without exact prose markers', () => {
  const root = makeFixture({ complete: true });
  const planPath = path.join(root, 'docs/plans/active.md');
  fs.writeFileSync(planPath, tier3Plan([
    '## Architecture Health',
    'Owner hotspot evidence comes from docs/architecture/file-shape-guardrails.md.',
    'Proof route is covered by npm run verify:architecture.',
    'Decision: avoid guarded renderer and preload files in the first unit.',
  ]));

  assert.deepEqual(verifyDocs(root), []);

  fs.writeFileSync(planPath, tier3Plan([
    '## Architecture Health',
    'Owner hotspot evidence comes from docs/architecture/file-shape-guardrails.md.',
    'Proof route is covered by npm run verify:architecture.',
    'Decision: use the temporary row because decomposition is deferred before this owner grows again.',
  ]));

  assert.deepEqual(verifyDocs(root), []);
});

test('verifyDocs accepts reworded production-engineering structures', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'docs/AGENTIC_DEV_WORKFLOW.md'), [
    '# Fixture',
    '## Fresh Chat Bootstrap',
    'docs/agentic/external-guidance.md',
    'Do not depend on the original Lineup repo',
    'Run `git status --short --branch` before planning edits',
    '## Default Workflow',
    'Plan explicitly before multi-step work',
    'Do not freeze a plan while ownership',
    '## Production Engineering Guardrails',
    'Dependency updates record the runtime owner and the verification that proves the change.',
    'Configuration, credentials, app paths, diagnostics, and logs are architecture surfaces.',
    'Architecture Health records file-shape evidence, owner hotspots, and the decomposition, avoidance, or allowlist decision.',
    'Each committed checkpoint must remain buildable and reversible.',
    'Fake scaffold product UI in reachable app routes moves to tests, smoke harnesses, or dev-only fixtures.',
    '## Multi-Agent Usage',
    'Keep read-only roles read-only',
    'Do not let a worker invent architecture seams',
    '## Session Handoffs',
    'NEXT_SESSION_HANDOFF',
    'MODEL_SUGGESTION',
    'feature-quality-loop.md',
    'Desktop Feature Quality Guardrails',
    'Feature-Quality Loop',
    'feature-plan -> feature-review -> feature-implement -> feature-review',
    'program state, score artifacts',
    'Keep renderer code unprivileged',
    'Record every copied/adapted upstream Lineup slice in the import ledger',
  ].join('\n'));

  assert.deepEqual(verifyDocs(root), []);
});

test('verifyDocs treats handoff TIER field as Tier 3 for active plan checks', () => {
  const root = makeFixture({ complete: true });
  const planPath = path.join(root, 'docs/plans/active.md');
  fs.writeFileSync(planPath, [
    '# Active Plan',
    '**Plan Status:** active',
    '**Task family:** feature/design',
    'new regression/contract test required',
    '## Goal',
    '## Non-Goals',
    '## Parent Architecture Alignment',
    '## Required Reading',
    '## Required Skills',
    '## Evidence And Discovery',
    '## Impact Snapshot',
    '## Files In Scope',
    '## Files Out Of Scope',
    '## Planner Self-Check',
    '## Architecture Seam Decision Gate',
    '## Verification Commands',
    '## Acceptance Criteria',
    '## Replan Triggers',
    '## Rollback Notes',
    '## Commit Checkpoints',
    'NEXT_SESSION_HANDOFF',
    'NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop',
    'TASK: fixture',
    'TASK_FAMILY: feature/design',
    'TIER: Tier 3',
    'PLAN: docs/plans/active.md',
    'ARTIFACT: docs/plans/active.md',
    'FILES:',
    'BLOCKERS: none',
    'MESSAGE:',
  ].join('\n'));

  const errors = verifyDocs(root);

  assert(errors.some((error) => error.includes('Tier 3 active plan missing MODEL_SUGGESTION')));
  assert(errors.some((error) => error.includes('missing ## Architecture Health or ## File Shape Preflight section')));
});

test('verifyDocs rejects PR template missing code health checklist', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, '.github/PULL_REQUEST_TEMPLATE.md'), [
    '## Verification',
    '- [ ] `npm run verify`',
  ].join('\n'));

  const errors = verifyDocs(root);

  assert(errors.some((error) => error.includes('missing PR code health checklist marker')));
});

test('verifyDocs rejects Tier 3 launcher missing structural headings', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, 'docs/agentic/session-prompts/feature-quality-loop.md'), [
    '# Feature Quality Loop Launcher',
    '## Output Contract',
  ].join('\n'));
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('missing Tier 3 launcher heading ## Controller State Machine')));
  assert(errors.some((error) => error.includes('missing Tier 3 launcher heading ## Phase Rules')));
  assert(errors.some((error) => error.includes('missing Tier 3 launcher heading ## Completion Gate')));
});

test('verifyDocs ignores local run bundle contents', () => {
  const root = makeFixture({ complete: true });
  const runPath = path.join(root, 'docs/runs/local-bundle.md');
  fs.writeFileSync(runPath, [
    '# Local',
    '[Broken](./missing.md)',
    'smells::ignored-local-note',
  ].join('\n'));
  assert.deepEqual(verifyDocs(root), []);
});

test('verifyDocs rejects desktop Codex role drift', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, '.codex/config.toml'), [
    '[agents]',
    '[agents.cleanup_worker]',
    'config_file = "agents/cleanup-worker.toml"',
  ].join('\n'));
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('must not declare a desktop cleanup-worker role')));
  assert(errors.some((error) => error.includes('missing role declaration: explorer')));
});

test('verifyDocs rejects project skills that stop pointing at tracked launchers', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, '.agents/skills/lineup-desktop-feature-plan/SKILL.md'), [
    '---',
    'name: lineup-desktop-feature-plan',
    'description: broken',
    '---',
    '',
    'Use this only from the Lineup Desktop repo.',
  ].join('\n'));
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('missing tracked launcher reference')));
});

test('verifyDocs rejects project skills with wrong frontmatter or missing read order', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, '.agents/skills/lineup-desktop-feature-review/SKILL.md'), [
    '---',
    'name: wrong-name',
    'description: broken',
    '---',
    '',
    '# Broken',
    'Use this only from the Lineup Desktop repo.',
    'docs/agentic/session-prompts/feature-review.md',
    'follow the tracked launcher exactly',
  ].join('\n'));
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('frontmatter name must be lineup-desktop-feature-review')));
  assert(errors.some((error) => error.includes('missing required read AGENTS.md')));
});

test('verifyDocs accepts CRLF skill frontmatter and scans normalized plan paths', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, '.agents/skills/lineup-desktop-feature-plan/SKILL.md'), [
    '---',
    'name: lineup-desktop-feature-plan',
    'description: fixture',
    '---',
    '',
    '# Fixture',
    'Use this only from the Lineup Desktop repo.',
    'AGENTS.md',
    'docs/AGENTIC_DEV_WORKFLOW.md',
    'docs/agentic/session-prompts/feature-plan.md',
    'follow the tracked launcher exactly',
  ].join('\r\n'));
  fs.writeFileSync(path.join(root, 'docs/plans/active.md'), [
    '**Plan Status:** active',
    '**Task family:** feature/design',
    'new regression/contract test required',
    '## Goal',
    '## Non-Goals',
    '## Parent Architecture Alignment',
    '## Required Skills',
    '## Evidence And Discovery',
    '## Impact Snapshot',
    '## Files In Scope',
    '## Files Out Of Scope',
    '## Planner Self-Check',
    '## Architecture Seam Decision Gate',
    '## Verification Commands',
    '## Acceptance Criteria',
    '## Replan Triggers',
    '## Rollback Notes',
    '## Commit Checkpoints',
  ].join('\r\n'));

  const errors = verifyDocs(root);
  assert(!errors.some((error) => error.includes('frontmatter name must be lineup-desktop-feature-plan')));
  assert(!errors.some((error) => error.includes('frontmatter description is required')));
  assert(errors.some((error) => error.includes('docs/plans/active.md: active plan missing ## Required Reading')));
});

test('verifyDocs rejects missing transferred Lineup skill adaptations', () => {
  const root = makeFixture({ complete: true });
  fs.rmSync(path.join(root, '.agents/skills/debugging-remediation'), { recursive: true, force: true });

  const errors = verifyDocs(root);

  assert(errors.some((error) => error.includes('Missing transferred Lineup skill adaptation')));
});

test('verifyDocs rejects transferred Lineup skill adaptation drift', () => {
  const root = makeFixture({ complete: true });
  fs.writeFileSync(path.join(root, '.agents/skills/execution-plan-authoring/SKILL.md'), [
    '---',
    'name: wrong-name',
    'description: fixture',
    '---',
    '',
    '# Broken',
  ].join('\n'));

  const errors = verifyDocs(root);

  assert(errors.some((error) => error.includes('frontmatter name must be execution-plan-authoring')));
  assert(errors.some((error) => error.includes('missing repo-scope rule')));
  assert(errors.some((error) => error.includes('missing AGENTS.md read')));
  assert(errors.some((error) => error.includes('missing workflow runbook read')));
});

function tier3Plan(architectureHealthLines = []) {
  return [
    '# Active Plan',
    '**Plan Status:** active',
    '**Task family:** feature/design',
    '**Tier:** Tier 3',
    'new regression/contract test required',
    '## Goal',
    '## Non-Goals',
    '## Parent Architecture Alignment',
    '## Required Reading',
    '## Required Skills',
    '## Evidence And Discovery',
    '## Impact Snapshot',
    ...architectureHealthLines,
    '## Files In Scope',
    '## Files Out Of Scope',
    '## Planner Self-Check',
    '## Architecture Seam Decision Gate',
    '## Verification Commands',
    '## Acceptance Criteria',
    '## Replan Triggers',
    '## Rollback Notes',
    '## Commit Checkpoints',
    'MODEL_SUGGESTION',
    'NEXT_SESSION_HANDOFF',
    'NEXT_SESSION_LAUNCHER: lineup-desktop-feature-quality-loop',
    'TASK: fixture',
    'TASK_FAMILY: feature/design',
    'TIER: Tier 3',
    'PLAN: docs/plans/active.md',
    'ARTIFACT: docs/plans/active.md',
    'FILES:',
    'BLOCKERS: none',
    'MESSAGE:',
  ].join('\n');
}

function makeFixture(options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-desktop-docs-'));
  if (options.complete) {
    const required = [
      '.editorconfig',
      '.codannaignore',
      '.coderabbit.yaml',
      '.github/CODEOWNERS',
      '.github/PULL_REQUEST_TEMPLATE.md',
      '.github/ISSUE_TEMPLATE/bug_report.md',
      '.github/ISSUE_TEMPLATE/config.yml',
      '.github/ISSUE_TEMPLATE/feature_request.md',
      '.github/workflows/ci.yml',
      '.codex/config.toml',
      '.codex/agents/docs-researcher.toml',
      '.codex/agents/explorer-fallback.toml',
      '.codex/agents/explorer.toml',
      '.codex/agents/monitor-fallback.toml',
      '.codex/agents/monitor.toml',
      '.codex/agents/planner.toml',
      '.codex/agents/reviewer.toml',
      '.codex/agents/worker.toml',
      'AGENTS.md',
      'LICENSE',
      'README.md',
      'SECURITY.md',
      'package.json',
      'tsconfig.json',
      'docs/AGENTIC_DEV_WORKFLOW.md',
      'docs/roadmap/desktop-port-roadmap.md',
      'docs/architecture/README.md',
      'docs/architecture/CURRENT_STATE.md',
      'docs/architecture/desktop-repo-genesis-adr.md',
      'docs/architecture/upstream-behavior-guardrails.md',
      'docs/architecture/import-ledger.md',
      'docs/architecture/file-shape-guardrails.md',
      'docs/architecture/security-and-secret-flow.md',
      'docs/architecture/playback-architecture.md',
      'docs/architecture/packaging-release-gates.md',
      'docs/agentic/external-guidance.md',
      'docs/agentic/codanna-playbook.md',
      'docs/agentic/plan-authoring-standard.md',
      'docs/agentic/skill-strategy.md',
      'docs/agentic/session-prompts/README.md',
      'docs/agentic/session-prompts/feature-plan.md',
      'docs/agentic/session-prompts/feature-implement.md',
      'docs/agentic/session-prompts/feature-review.md',
      'docs/agentic/session-prompts/feature-quality-loop.md',
      'docs/agentic/session-prompts/workflow-harness-review.md',
      '.agents/skills/lineup-desktop-feature-plan/SKILL.md',
      '.agents/skills/lineup-desktop-feature-implement/SKILL.md',
      '.agents/skills/lineup-desktop-feature-review/SKILL.md',
      '.agents/skills/lineup-desktop-feature-quality-loop/SKILL.md',
      '.agents/skills/lineup-desktop-workflow-harness-review/SKILL.md',
      '.agents/skills/architecture-boundaries/SKILL.md',
      '.agents/skills/bounded-worker-execution/SKILL.md',
      '.agents/skills/closeout-verification/SKILL.md',
      '.agents/skills/debugging-remediation/SKILL.md',
      '.agents/skills/execution-plan-authoring/SKILL.md',
      '.agents/skills/model-selection/SKILL.md',
      '.agents/skills/parallel-sidecars/SKILL.md',
      '.agents/skills/persistence-boundaries/SKILL.md',
      '.agents/skills/plex-integration-boundaries/SKILL.md',
      '.agents/skills/repo-production-review/SKILL.md',
      '.agents/skills/review-adjudication/SKILL.md',
      '.agents/skills/review-request/SKILL.md',
      '.agents/skills/ui-composition-patterns/SKILL.md',
      '.agents/skills/verification-strategy/SKILL.md',
      'docs/plans/README.md',
      'docs/runs/README.md',
      'docs/development/testing.md',
      'docs/development/rd-19-internal-validation-checklist.md',
      'tools/architecture-rules/buildEslintArchitectureRules.mjs',
      'tools/architecture-rules/desktopArchitectureRules.mjs',
      'tools/verify-docs.mjs',
      'tools/verify-maintainability.mjs',
      'tools/verify-redaction.mjs',
    ];
    fs.writeFileSync(path.join(root, '.gitignore'), [
      'node_modules/',
      'docs/runs/*',
      '!docs/runs/README.md',
      '.codanna/',
      '.codex/cache/',
      '.agent/',
      '.fastembed_cache',
      '.mcp_sequential_thinking/',
    ].join('\n'));
    for (const relativePath of required) {
      const absolute = path.join(root, relativePath);
      fs.mkdirSync(path.dirname(absolute), { recursive: true });
      fs.writeFileSync(absolute, fixtureContent(relativePath));
    }
  }
  return root;
}

function fixtureContent(relativePath) {
  if (relativePath === 'package.json') {
    return JSON.stringify({ scripts: {
      lint: 'eslint .',
      typecheck: 'tsc --noEmit',
      test: 'npm run test:contracts && npm run test:harness-docs',
      'test:contracts': 'node --import tsx --test "src/__tests__/**/*.test.ts"',
      'test:harness-docs': 'node --test tools/__tests__/*.test.mjs',
      'verify:architecture': 'npm run lint && npm run verify:maintainability',
      'verify:docs': 'node tools/verify-docs.mjs',
      'verify:maintainability': 'node tools/verify-maintainability.mjs',
      'verify:redaction': 'node tools/verify-redaction.mjs',
      verify: 'npm run typecheck && npm run verify:architecture && npm run test && npm run verify:docs && npm run verify:redaction',
    } });
  }

  if (relativePath === '.codex/config.toml') {
    return [
      '[agents.explorer]',
      'config_file = "agents/explorer.toml"',
      '[agents.explorer_fallback]',
      'config_file = "agents/explorer-fallback.toml"',
      '[agents.reviewer]',
      'config_file = "agents/reviewer.toml"',
      '[agents.docs_researcher]',
      'config_file = "agents/docs-researcher.toml"',
      '[agents.planner]',
      'config_file = "agents/planner.toml"',
      '[agents.worker]',
      'config_file = "agents/worker.toml"',
      '[agents.monitor]',
      'config_file = "agents/monitor.toml"',
      '[agents.monitor_fallback]',
      'config_file = "agents/monitor-fallback.toml"',
    ].join('\n');
  }

  if (relativePath === '.github/PULL_REQUEST_TEMPLATE.md') {
    return [
      '## Code Health',
      'Change is self-contained and reviewable',
      'New dependencies, build tools, config, diagnostics, or logging behavior are justified and verified',
      'Tests protect public seams or stable behavior',
    ].join('\n');
  }

  if (relativePath === 'docs/AGENTIC_DEV_WORKFLOW.md') {
    return [
      '# Fixture',
      '## Fresh Chat Bootstrap',
      'docs/agentic/external-guidance.md',
      'Do not depend on the original Lineup repo',
      'Run `git status --short --branch` before planning edits',
      '## Default Workflow',
      'Plan explicitly before multi-step work',
      'Do not freeze a plan while ownership',
      '## Production Engineering Guardrails',
      'Dependency changes must name the runtime owner and verification route',
      'Configuration, credentials, app paths, diagnostics, logs',
      'Architecture Health file-shape owner hotspots decomposition avoidance allowlist',
      'Keep every committed checkpoint buildable and reversible',
      'Fake scaffold product UI in reachable app routes moves to tests, smoke harnesses, or dev-only fixtures.',
      '## Multi-Agent Usage',
      'Keep read-only roles read-only',
      'Do not let a worker invent architecture seams',
      '## Session Handoffs',
      'NEXT_SESSION_HANDOFF',
      'MODEL_SUGGESTION',
      'feature-quality-loop.md',
      'Desktop Feature Quality Guardrails',
      'Feature-Quality Loop',
      'feature-plan -> feature-review -> feature-implement -> feature-review',
      'program state, score artifacts',
      'Keep renderer code unprivileged',
      'Record every copied/adapted upstream Lineup slice in the import ledger',
    ].join('\n');
  }

  if (relativePath === 'docs/agentic/session-prompts/README.md') {
    return [
      '# Fixture',
      '## Launcher Routing Matrix',
      'lineup-desktop-feature-quality-loop',
      'lineup-desktop-workflow-harness-review',
    ].join('\n');
  }

  if (relativePath === 'docs/agentic/skill-strategy.md') {
    return [
      '# Fixture',
      '## Codex Skill Discovery',
      'Use `.agents/skills/` as the repository-scoped project skill home',
      'Do not create a parallel `.codex/skills/` tree unless',
      '## Legacy Skill Adaptation Audit',
      'The original Lineup repo',
      'maintenance-program mechanics',
    ].join('\n');
  }

  if (relativePath === 'docs/agentic/external-guidance.md') {
    return [
      '# Fixture',
      'How OpenAI uses Codex',
      'Evaluation best practices',
      'Safety in building agents',
      'Agents SDK',
      'Building effective agents',
      'Claude Code subagents',
      'Claude Code memory',
      'Claude Code hooks',
      'Electron',
      'Process model',
      'Process sandboxing',
      'Google Engineering Practices',
      'OWASP Developer Guide',
      'Twelve-Factor App',
      'Checked on',
      'renderer sandboxing',
      'context isolation',
      'IPC sender/origin validation',
      'production code health',
      'dependency, build-tool, configuration, diagnostics, and logging changes',
    ].join('\n');
  }

  if (relativePath === 'docs/agentic/plan-authoring-standard.md') {
    return [
      '# Fixture',
      '## Goal',
      '## Non-Goals',
      '## Parent Architecture Alignment',
      '## Required Reading',
      '## Required Skills',
      '## Evidence And Discovery',
      '## Impact Snapshot',
      'dependency, build-tool, configuration, or lockfile changes',
      '## Architecture Health',
      'file-shape evidence owner hotspots decomposition avoidance allowlist decision',
      'pre-authorize future growth',
      '## Files In Scope',
      '## Files Out Of Scope',
      '## Planner Self-Check',
      '## Architecture Seam Decision Gate',
      'security/licensing/provenance considerations',
      '## Invariants And Scope Rules',
      'dependency build-tool security licensing provenance',
      '## Verification Commands',
      '## Acceptance Criteria',
      '## Replan Triggers',
      '## Rollback Notes',
      '## Commit Checkpoints',
    ].join('\n');
  }

  if (relativePath === 'docs/agentic/session-prompts/feature-quality-loop.md') {
    return [
      '# Feature Quality Loop Launcher',
      '## Controller State Machine',
      '## Phase Rules',
      '## Completion Gate',
      '## Architecture Health',
      'fake app routes fake/scaffold UI in a reachable product route active product routes for the roadmap item no longer depend on fake controls',
    ].join('\n');
  }

  if (relativePath === 'docs/roadmap/desktop-port-roadmap.md') {
    return [
      '# Desktop Port Roadmap',
      '## MVP Build Posture',
      'fake UI in a reachable app route',
      'real webOS-informed product journey with server/library selection and channel setup',
    ].join('\n');
  }

  if (relativePath === 'docs/architecture/upstream-behavior-guardrails.md') {
    return [
      '# Upstream Behavior Guardrails',
      'Original Lineup behavior is reference evidence, not Desktop architecture truth.',
      'Source audits are temporary proof only until a Desktop owner exists.',
      'Future plans should convert source audits into Desktop tests or fixtures.',
      '## Guardrail Matrix',
      'Preserved Behavior Evidence',
      'Required Desktop Proof Surface',
      'Intentional Divergence Policy',
      'Forbidden Shortcuts',
      'RD-07/RD-08 player and stream behavior',
      'RD-10 Plex auth/discovery/library',
      'RD-11 scheduler/channel/content',
      'RD-13 UI/navigation/settings',
      'RD-20 reference compatibility',
    ].join('\n');
  }

  if (relativePath === 'docs/development/rd-19-internal-validation-checklist.md') {
    return rd19ValidationChecklistFixture();
  }

  const skillTargets = {
    '.agents/skills/lineup-desktop-feature-plan/SKILL.md': 'docs/agentic/session-prompts/feature-plan.md',
    '.agents/skills/lineup-desktop-feature-implement/SKILL.md': 'docs/agentic/session-prompts/feature-implement.md',
    '.agents/skills/lineup-desktop-feature-review/SKILL.md': 'docs/agentic/session-prompts/feature-review.md',
    '.agents/skills/lineup-desktop-feature-quality-loop/SKILL.md': 'docs/agentic/session-prompts/feature-quality-loop.md',
    '.agents/skills/lineup-desktop-workflow-harness-review/SKILL.md': 'docs/agentic/session-prompts/workflow-harness-review.md',
  };

  if (skillTargets[relativePath]) {
    const skillName = path.basename(path.dirname(relativePath));
    return [
      '---',
      `name: ${skillName}`,
      'description: fixture',
      '---',
      '',
      '# Fixture',
      'Use this only from the Lineup Desktop repo.',
      'AGENTS.md',
      'docs/AGENTIC_DEV_WORKFLOW.md',
      skillTargets[relativePath],
      'follow the tracked launcher exactly',
    ].join('\n');
  }

  if (relativePath.startsWith('.agents/skills/') && relativePath.endsWith('/SKILL.md')) {
    const skillName = path.basename(path.dirname(relativePath));
    return [
      '---',
      `name: ${skillName}`,
      'description: fixture',
      '---',
      '',
      '# Fixture',
      'Use this only from the Lineup Desktop repo.',
      'AGENTS.md',
      'docs/AGENTIC_DEV_WORKFLOW.md',
    ].join('\n');
  }

  return '# Fixture\n';
}

function rd19ValidationChecklistFixture(options = {}) {
  const omitLines = new Set(options.omitLines ?? []);
  const lines = [
    '# RD-19 Internal Validation Checklist',
    'Tracked material uses redacted summaries only. Status may be `passed`, `failed`, `blocked`, or `not run`.',
    '## Evidence Rules',
    'Tracked material is limited to redacted summaries.',
    'Raw evidence must never be tracked in this file or any tracked doc.',
    'Raw local evidence must stay ignored under `docs/runs/**` or `out/**`.',
    '## Redaction Gate',
    'Confirm every diagnostics result passed `tools/verify-redaction.mjs` before readiness evidence is used.',
    'If forbidden material appears, stop and classify it as a release blocker.',
    '## Blocker Classifications',
    '`release blocker`, `beta blocker`, and `deferred` are the only classifications.',
    '## Stop Conditions',
    'Stop if validation requires live Plex auth or real Plex credentials.',
    'Stop if validation requires production native helper playback or new preload APIs.',
    'Stop if any summary contains forbidden material or fails redaction scanning.',
    '## Required Windows x64 Proof Commands',
    '```sh',
    'git status --short --branch',
    'npm run verify:docs',
    'npm run verify:redaction',
    'npm run build:electron',
    'node tools/package-windows-internal.mjs --out <ignored-package-output>',
    'node tools/verify-windows-internal-package.mjs --package <ignored-package-root> --manifest <ignored-provenance-manifest>',
    'node tools/rd17-diagnostics-smoke.mjs --out <ignored-evidence-root>',
    '```',
    '## Validation Matrix',
    '| Area | Checklist | Status | Classification rule |',
    '| --- | --- | --- | --- |',
    '| Auth | Redacted summary only. | not run | beta blocker |',
    '| Server selection | Redacted summary only. | not run | beta blocker |',
    '| Channel creation | Redacted summary only. | not run | beta blocker |',
    '| Playback | Redacted summary only. | not run | release blocker |',
    '| Switching | Redacted summary only. | not run | beta blocker |',
    '| Subtitles/audio | Redacted summary only. | not run | release blocker |',
    '| EPG | Redacted summary only. | not run | beta blocker |',
    '| Settings | Redacted summary only. | not run | deferred |',
    '| Sleep/wake | Redacted summary only. | not run | beta blocker |',
    '| Fullscreen | Redacted summary only. | not run | beta blocker |',
    '| Multi-monitor | Redacted summary only. | not run | deferred |',
    '| Crash recovery | Redacted summary only. | not run | release blocker |',
    '| Diagnostics export | Redacted summary only. | not run | release blocker |',
    '| Install/delete of unpacked package | Redacted summary only. | not run | deferred |',
    '| Long playback | Redacted summary only. | not run | beta blocker |',
    '## Scenario Summary Template',
    '### Scenario RD19-<area>-<nn>',
    '- Area:',
    '- Status:',
    '- Blocker classification:',
    '- Redaction gate status:',
    '## Blocker Log Template',
    '| ID | Date | Area | Summary | Classification | Stop condition hit | Safe evidence | Owner for next enabling plan | Revisit trigger | Status |',
    '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
    '| RD19-BLOCK-001 | YYYY-MM-DD | <area> | <redacted summary only> | release blocker/beta blocker/deferred | <stop condition or none> | <command/status/counts only> | <owner or plan needed> | <specific trigger> | open |',
  ];
  return lines
    .filter((line) => !omitLines.has(line))
    .join('\n');
}
