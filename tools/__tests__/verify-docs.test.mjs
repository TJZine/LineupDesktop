import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  ACTIVE_PLAN_HEADINGS,
  ACTIVE_PLAN_VERIFICATION_MARKERS,
  LAUNCHER_WRAPPERS,
  REQUIRED_FILES,
  REQUIRED_IGNORE_MARKERS,
  REQUIRED_ROLES,
  REQUIRED_SCRIPTS,
  REQUIRED_SKILLS,
  verifyDocs,
} from '../verify-docs.mjs';

const TEST_REQUIRED_FILES = [
  '.gitignore',
  '.codex/config.toml',
  '.github/CODEOWNERS',
  '.github/PULL_REQUEST_TEMPLATE.md',
  '.github/workflows/ci.yml',
  'AGENTS.md',
  'README.md',
  'SECURITY.md',
  'package.json',
  'tsconfig.json',
  'docs/AGENTIC_DEV_WORKFLOW.md',
  'docs/architecture/CURRENT_STATE.md',
  'docs/architecture/file-shape-guardrails.md',
  'docs/architecture/security-and-secret-flow.md',
  'docs/agentic/plan-authoring-standard.md',
  'docs/agentic/skill-strategy.md',
  'docs/agentic/session-prompts/feature-quality-loop.md',
  'docs/plans/README.md',
  'docs/runs/README.md',
  'tools/verify-docs.mjs',
  'tools/verify-maintainability.mjs',
  'tools/verify-redaction.mjs',
];

const TEST_REQUIRED_ROLES = {
  explorer: 'agents/explorer.toml',
  explorer_fallback: 'agents/explorer-fallback.toml',
  reviewer: 'agents/reviewer.toml',
  docs_researcher: 'agents/docs-researcher.toml',
  planner: 'agents/planner.toml',
  worker: 'agents/worker.toml',
  worker_sol_low: 'agents/worker-sol-low.toml',
  worker_luna: 'agents/worker-luna.toml',
  monitor: 'agents/monitor.toml',
  monitor_fallback: 'agents/monitor-fallback.toml',
};

const TEST_REQUIRED_SKILLS = [
  'architecture-boundaries',
  'bounded-worker-execution',
  'closeout-verification',
  'debugging-remediation',
  'execution-plan-authoring',
  'large-task-orchestration',
  'lineup-desktop-feature-implement',
  'lineup-desktop-feature-plan',
  'lineup-desktop-feature-quality-loop',
  'lineup-desktop-feature-review',
  'lineup-desktop-workflow-harness-review',
  'model-selection',
  'parallel-sidecars',
  'persistence-boundaries',
  'plex-integration-boundaries',
  'repo-production-review',
  'review-adjudication',
  'review-request',
  'typescript-quality-boundaries',
  'typescript-test-design',
  'ui-composition-patterns',
  'verification-strategy',
];

const TEST_REQUIRED_SCRIPTS = [
  'lint',
  'typecheck',
  'test',
  'test:contracts',
  'test:harness-docs',
  'verify:architecture',
  'verify:docs',
  'verify:maintainability',
  'verify:redaction',
  'verify',
];

const TEST_REQUIRED_IGNORE_MARKERS = [
  'docs/runs/*',
  '!docs/runs/README.md',
  '.codanna/',
  '.codex/cache/',
  '.agent/',
  '.fastembed_cache',
  '.mcp_sequential_thinking/',
];

const TEST_ACTIVE_PLAN_HEADINGS = [
  '## Goal',
  '## Non-Goals',
  '## Architecture And Invariants',
  '## Files In Scope',
  '## Files Out Of Scope',
  '## Execution Packages',
  '## Verification Commands',
  '## Acceptance Criteria',
  '## Replan Triggers',
];

const TEST_ACTIVE_PLAN_VERIFICATION_MARKERS = [
  'new regression/contract test required',
  'existing coverage sufficient',
  'broader integration/manual proof required',
  'no new automated test needed',
];

const TEST_LAUNCHER_WRAPPERS = {
  'lineup-desktop-feature-implement': {
    title: 'Lineup Desktop Feature Implement',
    launcher: 'feature-implement.md',
    terminalInvariant: 'Keep repo-specific policy in tracked repo docs, not in this skill wrapper.',
  },
  'lineup-desktop-feature-plan': {
    title: 'Lineup Desktop Feature Plan',
    launcher: 'feature-plan.md',
    terminalInvariant: 'Keep repo-specific policy in tracked repo docs, not in this skill wrapper.',
  },
  'lineup-desktop-feature-quality-loop': {
    title: 'Lineup Desktop Feature Quality Loop',
    launcher: 'feature-quality-loop.md',
    terminalInvariant: 'Keep controller state in `update_plan` and keep write/review roles separated.',
  },
  'lineup-desktop-feature-review': {
    title: 'Lineup Desktop Feature Review',
    launcher: 'feature-review.md',
    terminalInvariant: 'Keep this review read-only unless the parent session explicitly starts a separate implementation pass.',
  },
  'lineup-desktop-workflow-harness-review': {
    title: 'Lineup Desktop Workflow Harness Review',
    launcher: 'workflow-harness-review.md',
    terminalInvariant: 'Keep this review read-only.',
  },
};

const fixtureRoots = new Set();

test.afterEach(() => {
  for (const root of fixtureRoots) fs.rmSync(root, { recursive: true, force: true });
  fixtureRoots.clear();
});

test('exported verifier policy matches the independent test canon', () => {
  assert.deepEqual(REQUIRED_FILES, TEST_REQUIRED_FILES);
  assert.deepEqual(REQUIRED_ROLES, TEST_REQUIRED_ROLES);
  assert.deepEqual(REQUIRED_SKILLS, TEST_REQUIRED_SKILLS);
  assert.deepEqual(REQUIRED_SCRIPTS, TEST_REQUIRED_SCRIPTS);
  assert.deepEqual(REQUIRED_IGNORE_MARKERS, TEST_REQUIRED_IGNORE_MARKERS);
  assert.deepEqual(ACTIVE_PLAN_HEADINGS, TEST_ACTIVE_PLAN_HEADINGS);
  assert.deepEqual(ACTIVE_PLAN_VERIFICATION_MARKERS, TEST_ACTIVE_PLAN_VERIFICATION_MARKERS);
  assert.deepEqual(LAUNCHER_WRAPPERS, TEST_LAUNCHER_WRAPPERS);
});

test('repository documentation satisfies structural policy', () => {
  assert.deepEqual(verifyDocs(), []);
});

test('missing required files are reported', () => {
  const root = makeFixture();
  fs.rmSync(path.join(root, 'AGENTS.md'));
  assert(verifyDocs(root).some((error) => error.includes('Missing required file: AGENTS.md')));
});

test('broken markdown paths and anchors are reported', () => {
  const root = makeFixture();
  fs.writeFileSync(path.join(root, 'README.md'), [
    '# Readme',
    '[Missing](docs/missing.md)',
    '[Bad anchor](docs/AGENTIC_DEV_WORKFLOW.md#missing)',
  ].join('\n'));
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('broken link')));
  assert(errors.some((error) => error.includes('broken anchor')));
});

test('local run and cache ignore markers are required', () => {
  const root = makeFixture();
  fs.writeFileSync(path.join(root, '.gitignore'), 'node_modules/\n');
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('docs/runs/*')));
  assert(errors.some((error) => error.includes('.codanna/')));
});

test('imported cleanup artifacts are rejected', () => {
  const root = makeFixture();
  fs.writeFileSync(path.join(root, 'ARCHITECTURE_CLEANUP_CHECKLIST.md'), '# Imported\n');
  assert(verifyDocs(root).some((error) => error.includes('Forbidden imported workflow artifact')));
});

test('role wiring and concurrency limits are checked', () => {
  const root = makeFixture();
  const configPath = path.join(root, '.codex/config.toml');
  const config = fs.readFileSync(configPath, 'utf8')
    .replace('max_threads = 6', 'max_threads = 8')
    .replace('config_file = "agents/worker.toml"', 'config_file = "agents/missing.toml"');
  fs.writeFileSync(configPath, config);
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('max_threads = 6')));
  assert(errors.some((error) => error.includes('Role worker must reference agents/worker.toml')));
});

test('role documentation must resolve config_file mappings instead of synthesizing paths', () => {
  const root = makeFixture();
  const workflowPath = path.join(root, 'docs/AGENTIC_DEV_WORKFLOW.md');
  fs.writeFileSync(workflowPath, '# Workflow\nUse `.codex/agents/<role>.toml`.\n');
  assert(verifyDocs(root).some((error) => error.includes('config_file mappings')));
});

test('read-only roles must remain sandboxed', () => {
  const root = makeFixture();
  const reviewerPath = path.join(root, '.codex/agents/reviewer.toml');
  fs.writeFileSync(reviewerPath, roleToml(false));
  assert(verifyDocs(root).some((error) => error.includes('reviewer.toml must keep sandbox_mode')));
});

test('skills require matching names and descriptions', () => {
  const root = makeFixture();
  const skillPath = path.join(root, '.agents/skills/review-request/SKILL.md');
  fs.writeFileSync(skillPath, '---\nname: wrong\ndescription:\n---\n');
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('frontmatter name must match')));
  assert(errors.some((error) => error.includes('non-empty frontmatter description')));
});

test('skill frontmatter supports Windows CRLF checkouts', () => {
  const root = makeFixture();
  for (const skill of TEST_REQUIRED_SKILLS) {
    const skillPath = path.join(root, '.agents/skills', skill, 'SKILL.md');
    const content = fs.readFileSync(skillPath, 'utf8');
    fs.writeFileSync(skillPath, content.replace(/\n/gu, '\r\n'));
  }
  assert.deepEqual(verifyDocs(root), []);
});

test('launcher wrappers must match their canonical routers', () => {
  const root = makeFixture();
  const skill = 'lineup-desktop-feature-review';
  const skillPath = path.join(root, '.agents/skills', skill, 'SKILL.md');
  fs.writeFileSync(skillPath, `---\nname: ${skill}\ndescription: Fixture.\n---\n\nNo routing.\n`);
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes(`Launcher wrapper ${skill} must route`)));
  assert(errors.some((error) => error.includes('canonical tracked-launcher router')));
});

test('launcher wrappers reject extra local policy even when routing is intact', () => {
  const root = makeFixture();
  const skill = 'lineup-desktop-feature-review';
  const skillPath = path.join(root, '.agents/skills', skill, 'SKILL.md');
  fs.appendFileSync(skillPath, '\nAlways use a hard-coded reviewer model.\n');
  assert(verifyDocs(root).some((error) => error.includes('canonical tracked-launcher router')));
});

test('active plans require compact execution headings and early metadata', () => {
  const root = makeFixture();
  const planPath = path.join(root, 'docs/plans/active.md');
  fs.writeFileSync(planPath, [
    '# Active',
    '## Goal',
    '**Plan Status:** active',
    '**Task family:** feature/design',
    '**Tier:** Tier 3',
  ].join('\n'));
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('status must appear exactly once before')));
  assert(errors.some((error) => error.includes('missing ## Replan Triggers')));
});

test('active plan metadata uses exact preamble vocabulary', () => {
  const root = makeFixture();
  const planPath = path.join(root, 'docs/plans/active.md');
  fs.writeFileSync(planPath, activePlanContent()
    .replace('**Task family:** feature/design', '**Task family:** feature')
    .replace('**Tier:** Tier 3', '')
    .replace('## Goal', '## Goal\n**Tier:** Tier 3'));
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('Task family must be exactly feature/design')));
  assert(errors.some((error) => error.includes('valid Tier metadata must appear exactly once')));
});

test('active plans require exactly one verification marker in the verification section', () => {
  const root = makeFixture();
  const planPath = path.join(root, 'docs/plans/active.md');
  fs.writeFileSync(planPath, activePlanContent().replace(
    '**Verification classification:** existing coverage sufficient',
    [
      '**Verification classification:** existing coverage sufficient',
      '**Verification classification:** no new automated test needed',
    ].join('\n'),
  ));
  assert(verifyDocs(root).some((error) => error.includes('exactly one verification classification marker')));

  fs.writeFileSync(planPath, activePlanContent().replace(
    '**Verification classification:** existing coverage sufficient',
    'Run the usual checks.',
  ));
  assert(verifyDocs(root).some((error) => error.includes('exactly one verification classification marker')));
});

test('required scripts must be real commands', () => {
  const root = makeFixture();
  const packagePath = path.join(root, 'package.json');
  const packageJson = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
  packageJson.scripts.verify = 'true';
  delete packageJson.scripts.typecheck;
  fs.writeFileSync(packagePath, JSON.stringify(packageJson));
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes('verify is a placeholder')));
  assert(errors.some((error) => error.includes('Missing required package script: typecheck')));
});

function makeFixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-desktop-docs-'));
  fixtureRoots.add(root);
  for (const relativePath of TEST_REQUIRED_FILES) {
    const filePath = path.join(root, relativePath);
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, fixtureContent(relativePath));
  }

  fs.writeFileSync(path.join(root, '.gitignore'), `${TEST_REQUIRED_IGNORE_MARKERS.join('\n')}\n`);
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({
    scripts: Object.fromEntries(TEST_REQUIRED_SCRIPTS.map((name) => [name, `node ${name}.mjs`])),
  }));
  fs.writeFileSync(path.join(root, '.codex/config.toml'), configToml());

  for (const [role, configFile] of Object.entries(TEST_REQUIRED_ROLES)) {
    const rolePath = path.join(root, '.codex', configFile);
    fs.mkdirSync(path.dirname(rolePath), { recursive: true });
    fs.writeFileSync(rolePath, roleToml(['explorer', 'explorer_fallback', 'reviewer', 'docs_researcher', 'monitor', 'monitor_fallback'].includes(role)));
  }

  for (const { launcher } of Object.values(TEST_LAUNCHER_WRAPPERS)) {
    const launcherPath = path.join(root, 'docs/agentic/session-prompts', launcher);
    fs.mkdirSync(path.dirname(launcherPath), { recursive: true });
    fs.writeFileSync(launcherPath, `# ${launcher}\n`);
  }

  for (const skill of TEST_REQUIRED_SKILLS) {
    const skillPath = path.join(root, '.agents/skills', skill, 'SKILL.md');
    fs.mkdirSync(path.dirname(skillPath), { recursive: true });
    const wrapper = TEST_LAUNCHER_WRAPPERS[skill];
    const body = wrapper ? renderTestLauncherWrapper(wrapper) : `# ${skill}\n`;
    fs.writeFileSync(skillPath, `---\nname: ${skill}\ndescription: Fixture skill.\n---\n\n${body}`);
  }

  const planPath = path.join(root, 'docs/plans/active.md');
  fs.writeFileSync(planPath, activePlanContent());
  return root;
}

function activePlanContent() {
  const lines = [
    '# Active',
    '**Plan Status:** active',
    '**Task family:** feature/design',
    '**Tier:** Tier 3',
  ];
  for (const heading of TEST_ACTIVE_PLAN_HEADINGS) {
    lines.push(heading);
    if (heading === '## Verification Commands') {
      lines.push('**Verification classification:** existing coverage sufficient');
    }
  }
  return `${lines.join('\n')}\n`;
}

function renderTestLauncherWrapper(wrapper) {
  return [
    `# ${wrapper.title}`,
    '',
    'Use this only from the Lineup Desktop repo.',
    '',
    'Read these files in order:',
    '',
    '1. [`AGENTS.md`](../../../AGENTS.md)',
    '2. [`docs/AGENTIC_DEV_WORKFLOW.md`](../../../docs/AGENTIC_DEV_WORKFLOW.md)',
    `3. [\`docs/agentic/session-prompts/${wrapper.launcher}\`](../../../docs/agentic/session-prompts/${wrapper.launcher})`,
    '',
    `Then follow the tracked launcher exactly. ${wrapper.terminalInvariant}`,
    '',
  ].join('\n');
}

function fixtureContent(relativePath) {
  if (relativePath.endsWith('.md')) return `# ${path.basename(relativePath, '.md')}\n`;
  if (relativePath === 'package.json') return '{}\n';
  if (relativePath.endsWith('.json')) return '{}\n';
  return '\n';
}

function configToml() {
  return [
    '[agents]',
    'max_threads = 6',
    'max_depth = 1',
    ...Object.entries(TEST_REQUIRED_ROLES).flatMap(([role, configFile]) => [
      '',
      `[agents.${role}]`,
      `config_file = "${configFile}"`,
    ]),
    '',
  ].join('\n');
}

function roleToml(readOnly) {
  return [
    'model = "fixture-model"',
    'model_reasoning_effort = "medium"',
    ...(readOnly ? ['sandbox_mode = "read-only"'] : []),
    'developer_instructions = "fixture"',
    '',
  ].join('\n');
}
