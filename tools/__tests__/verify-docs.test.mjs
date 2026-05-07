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
  assert(errors.some((error) => error.includes('missing ## Evidence And Discovery')));
  assert(errors.some((error) => error.includes('missing ## Acceptance Criteria')));
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
  assert(errors.some((error) => error.includes('missing launcher routing matrix phrase')));
  assert(errors.some((error) => error.includes('missing Codex skill discovery policy phrase')));
  assert(errors.some((error) => error.includes('missing legacy skill adaptation audit phrase')));
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
      'docs/architecture/README.md',
      'docs/architecture/CURRENT_STATE.md',
      'docs/architecture/desktop-repo-genesis-adr.md',
      'docs/architecture/import-ledger.md',
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
      'docs/plans/README.md',
      'docs/runs/README.md',
      'docs/development/testing.md',
      'tools/architecture-rules/buildEslintArchitectureRules.mjs',
      'tools/architecture-rules/desktopArchitectureRules.mjs',
      'tools/verify-docs.mjs',
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
      'test:contracts': 'tsx --test src/__tests__/*.test.ts',
      'test:harness-docs': 'node --test tools/__tests__/*.test.mjs',
      'verify:architecture': 'npm run lint',
      'verify:docs': 'node tools/verify-docs.mjs',
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

  if (relativePath === 'docs/AGENTIC_DEV_WORKFLOW.md') {
    return [
      '# Fixture',
      '## Fresh Chat Bootstrap',
      'docs/agentic/external-guidance.md',
      'Do not depend on the original Lineup repo',
      'Run `git status --short --branch` before planning edits',
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
      'historical maintenance-program mechanics',
    ].join('\n');
  }

  if (relativePath === 'docs/agentic/external-guidance.md') {
    return [
      '# Fixture',
      'Codex best practices',
      'Building effective agents',
      'Claude Code subagents',
      'Using PLANS.md for multi-hour problem solving',
    ].join('\n');
  }

  if (relativePath === 'docs/agentic/plan-authoring-standard.md') {
    return [
      '# Fixture',
      '## Goal',
      '## Non-Goals',
      '## Parent Architecture Alignment',
      '## Required Reading',
      '## Evidence And Discovery',
      '## Files In Scope',
      '## Files Out Of Scope',
      '## Architecture Seam Decision Gate',
      '## Verification Commands',
      '## Acceptance Criteria',
      '## Replan Triggers',
      '## Rollback Notes',
    ].join('\n');
  }

  if (relativePath === 'docs/agentic/session-prompts/feature-quality-loop.md') {
    return [
      '# Feature Quality Loop Launcher',
      '## Controller State Machine',
      '## Phase Rules',
      '## Completion Gate',
    ].join('\n');
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

  return '# Fixture\n';
}
