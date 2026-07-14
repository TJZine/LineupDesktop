import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  ACTIVE_PLAN_HEADINGS,
  LAUNCHER_WRAPPERS,
  REQUIRED_FILES,
  REQUIRED_IGNORE_MARKERS,
  REQUIRED_ROLES,
  REQUIRED_SCRIPTS,
  REQUIRED_SKILLS,
  verifyDocs,
} from '../verify-docs.mjs';

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

test('launcher wrappers must retain tracked launcher routing', () => {
  const root = makeFixture();
  const skill = 'lineup-desktop-feature-review';
  const skillPath = path.join(root, '.agents/skills', skill, 'SKILL.md');
  fs.writeFileSync(skillPath, `---\nname: ${skill}\ndescription: Fixture.\n---\n\nNo routing.\n`);
  const errors = verifyDocs(root);
  assert(errors.some((error) => error.includes(`Launcher wrapper ${skill} must route`)));
  assert(errors.some((error) => error.includes('thin tracked-launcher router')));
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
  assert(errors.some((error) => error.includes('status must appear before')));
  assert(errors.some((error) => error.includes('missing ## Replan Triggers')));
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
  for (const relativePath of REQUIRED_FILES) {
    const filePath = path.join(root, relativePath);
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, fixtureContent(relativePath));
  }

  fs.writeFileSync(path.join(root, '.gitignore'), `${REQUIRED_IGNORE_MARKERS.join('\n')}\n`);
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({
    scripts: Object.fromEntries(REQUIRED_SCRIPTS.map((name) => [name, `node ${name}.mjs`])),
  }));
  fs.writeFileSync(path.join(root, '.codex/config.toml'), configToml());

  for (const [role, configFile] of Object.entries(REQUIRED_ROLES)) {
    const rolePath = path.join(root, '.codex', configFile);
    fs.mkdirSync(path.dirname(rolePath), { recursive: true });
    fs.writeFileSync(rolePath, roleToml(['explorer', 'explorer_fallback', 'reviewer', 'docs_researcher', 'monitor', 'monitor_fallback'].includes(role)));
  }

  for (const skill of REQUIRED_SKILLS) {
    const skillPath = path.join(root, '.agents/skills', skill, 'SKILL.md');
    fs.mkdirSync(path.dirname(skillPath), { recursive: true });
    const launcher = LAUNCHER_WRAPPERS[skill];
    const routing = launcher ? [
      '[Agents](../../../AGENTS.md)',
      '[Workflow](../../../docs/AGENTIC_DEV_WORKFLOW.md)',
      `[Launcher](../../../docs/agentic/session-prompts/${launcher})`,
      'Then follow the tracked launcher exactly.',
    ].join('\n') : '';
    fs.writeFileSync(skillPath, `---\nname: ${skill}\ndescription: Fixture skill.\n---\n\n# ${skill}\n${routing}\n`);
  }

  const planPath = path.join(root, 'docs/plans/active.md');
  fs.writeFileSync(planPath, [
    '# Active',
    '**Plan Status:** active',
    '**Task family:** feature/design',
    '**Tier:** Tier 3',
    ...ACTIVE_PLAN_HEADINGS,
  ].join('\n'));
  return root;
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
    ...Object.entries(REQUIRED_ROLES).flatMap(([role, configFile]) => [
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
