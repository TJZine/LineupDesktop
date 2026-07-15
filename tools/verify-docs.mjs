import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export const REQUIRED_FILES = [
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

export const REQUIRED_ROLES = {
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

export const REQUIRED_SKILLS = [
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

export const REQUIRED_SCRIPTS = [
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

export const REQUIRED_IGNORE_MARKERS = [
  'docs/runs/*',
  '!docs/runs/README.md',
  '.codanna/',
  '.codex/cache/',
  '.agent/',
  '.fastembed_cache',
  '.mcp_sequential_thinking/',
];

export const ACTIVE_PLAN_HEADINGS = [
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

export const ACTIVE_PLAN_VERIFICATION_MARKERS = [
  'new regression/contract test required',
  'existing coverage sufficient',
  'broader integration/manual proof required',
  'no new automated test needed',
];

export const LAUNCHER_WRAPPERS = {
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

const READ_ONLY_ROLES = new Set([
  'explorer',
  'explorer_fallback',
  'reviewer',
  'docs_researcher',
  'monitor',
  'monitor_fallback',
]);

export function verifyDocs(root = repoRoot) {
  const errors = [];
  checkRequiredFiles(root, errors);
  checkForbiddenArtifacts(root, errors);
  checkIgnorePolicy(root, errors);
  checkRoleConfiguration(root, errors);
  checkRoleDocumentation(root, errors);
  checkSkillMetadata(root, errors);
  checkPackageScripts(root, errors);
  checkActivePlans(root, errors);
  checkMarkdownLinks(root, errors);
  return errors;
}

function checkRoleDocumentation(root, errors) {
  for (const relativePath of [
    '.agents/skills/bounded-worker-execution/SKILL.md',
    '.agents/skills/model-selection/SKILL.md',
    'docs/AGENTIC_DEV_WORKFLOW.md',
  ]) {
    const filePath = path.join(root, relativePath);
    if (!fs.existsSync(filePath)) continue;
    if (readText(filePath).includes('.codex/agents/<role>.toml')) {
      errors.push(`${relativePath}: role config paths must come from .codex/config.toml config_file mappings`);
    }
  }
}

function checkRequiredFiles(root, errors) {
  for (const relativePath of REQUIRED_FILES) {
    if (!fs.existsSync(path.join(root, relativePath))) {
      errors.push(`Missing required file: ${relativePath}`);
    }
  }

  for (const configFile of Object.values(REQUIRED_ROLES)) {
    const relativePath = path.posix.join('.codex', configFile);
    if (!fs.existsSync(path.join(root, relativePath))) {
      errors.push(`Missing required role config: ${relativePath}`);
    }
  }
}

function checkForbiddenArtifacts(root, errors) {
  for (const relativePath of [
    'ARCHITECTURE_CLEANUP_CHECKLIST.md',
    'scorecard.png',
    'docs/agentic/evals/baselines',
  ]) {
    if (fs.existsSync(path.join(root, relativePath))) {
      errors.push(`Forbidden imported workflow artifact: ${relativePath}`);
    }
  }
}

function checkIgnorePolicy(root, errors) {
  const ignorePath = path.join(root, '.gitignore');
  if (!fs.existsSync(ignorePath)) return;
  const lines = new Set(readText(ignorePath).split(/\r?\n/u).map((line) => line.trim()));
  for (const marker of REQUIRED_IGNORE_MARKERS) {
    if (!lines.has(marker)) {
      errors.push(`Missing local-only artifact marker in .gitignore: ${marker}`);
    }
  }
}

function checkRoleConfiguration(root, errors) {
  const configPath = path.join(root, '.codex/config.toml');
  if (!fs.existsSync(configPath)) return;
  const sections = parseTomlSections(readText(configPath));
  const agents = sections.get('agents') ?? new Map();

  if (agents.get('max_threads') !== '6') {
    errors.push('.codex/config.toml must keep agents.max_threads = 6');
  }
  if (agents.get('max_depth') !== '1') {
    errors.push('.codex/config.toml must keep agents.max_depth = 1');
  }

  for (const [role, expectedConfig] of Object.entries(REQUIRED_ROLES)) {
    const roleSection = sections.get(`agents.${role}`);
    const configured = unquote(roleSection?.get('config_file'));
    if (configured !== expectedConfig) {
      errors.push(`Role ${role} must reference ${expectedConfig}`);
      continue;
    }

    const rolePath = path.join(root, '.codex', expectedConfig);
    if (!fs.existsSync(rolePath)) continue;
    const roleConfig = parseTomlSections(readText(rolePath)).get('') ?? new Map();
    for (const key of ['model', 'model_reasoning_effort', 'developer_instructions']) {
      if (!roleConfig.has(key)) errors.push(`${expectedConfig} is missing ${key}`);
    }
    if (READ_ONLY_ROLES.has(role) && unquote(roleConfig.get('sandbox_mode')) !== 'read-only') {
      errors.push(`${expectedConfig} must keep sandbox_mode = "read-only"`);
    }
  }
}

function checkSkillMetadata(root, errors) {
  const skillsRoot = path.join(root, '.agents/skills');
  if (!fs.existsSync(skillsRoot)) {
    errors.push('Missing required skill directory: .agents/skills');
    return;
  }

  const directories = fs.readdirSync(skillsRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name);
  const present = new Set(directories);
  for (const skill of REQUIRED_SKILLS) {
    if (!present.has(skill)) errors.push(`Missing required project skill: ${skill}`);
  }

  for (const directory of directories) {
    const skillPath = path.join(skillsRoot, directory, 'SKILL.md');
    if (!fs.existsSync(skillPath)) {
      errors.push(`Skill ${directory} is missing SKILL.md`);
      continue;
    }
    const metadata = parseFrontmatter(readText(skillPath));
    if (metadata.name !== directory) {
      errors.push(`Skill ${directory} frontmatter name must match its directory`);
    }
    if (!metadata.description) {
      errors.push(`Skill ${directory} must have a non-empty frontmatter description`);
    }
  }

  for (const [skill, wrapper] of Object.entries(LAUNCHER_WRAPPERS)) {
    const skillPath = path.join(skillsRoot, skill, 'SKILL.md');
    if (!fs.existsSync(skillPath)) continue;
    const content = readText(skillPath);
    for (const requiredTarget of [
      '../../../AGENTS.md',
      '../../../docs/AGENTIC_DEV_WORKFLOW.md',
      `../../../docs/agentic/session-prompts/${wrapper.launcher}`,
    ]) {
      if (!content.includes(`](${requiredTarget})`)) {
        errors.push(`Launcher wrapper ${skill} must route to ${requiredTarget}`);
      }
    }
    const actualBody = normalizeMarkdownBody(stripFrontmatter(content));
    const expectedBody = normalizeMarkdownBody(renderLauncherWrapperBody(wrapper));
    if (actualBody !== expectedBody) {
      errors.push(`Launcher wrapper ${skill} must match its canonical tracked-launcher router`);
    }
  }
}

function checkPackageScripts(root, errors) {
  const packagePath = path.join(root, 'package.json');
  if (!fs.existsSync(packagePath)) return;
  let packageJson;
  try {
    packageJson = JSON.parse(readText(packagePath));
  } catch (error) {
    errors.push(`package.json is invalid JSON: ${error.message}`);
    return;
  }

  for (const scriptName of REQUIRED_SCRIPTS) {
    const command = packageJson.scripts?.[scriptName];
    if (typeof command !== 'string' || command.trim() === '') {
      errors.push(`Missing required package script: ${scriptName}`);
    } else if (['true', ':', 'echo ok'].includes(command.trim().toLowerCase())) {
      errors.push(`Package script ${scriptName} is a placeholder`);
    }
  }
}

function checkActivePlans(root, errors) {
  const plansRoot = path.join(root, 'docs/plans');
  if (!fs.existsSync(plansRoot)) return;
  for (const filePath of walkFiles(plansRoot, (entry) => entry.endsWith('.md'))) {
    if (path.basename(filePath) === 'README.md') continue;
    const relativePath = relative(root, filePath);
    const content = readText(filePath);
    if (!/^\*\*Plan Status:\*\*\s*active\s*$/imu.test(content)) continue;

    const firstH2 = content.search(/^##\s+/mu);
    const preamble = firstH2 < 0 ? content : content.slice(0, firstH2);
    if (countExactLines(preamble, '**Plan Status:** active') !== 1) {
      errors.push(`${relativePath}: active status must appear exactly once before the first ## heading`);
    }
    if (countExactLines(preamble, '**Task family:** feature/design') !== 1) {
      errors.push(`${relativePath}: Task family must be exactly feature/design before the first ## heading`);
    }
    if (countMatchingLines(preamble, /^\*\*Tier:\*\*\s*Tier [123]$/u) !== 1) {
      errors.push(`${relativePath}: valid Tier metadata must appear exactly once before the first ## heading`);
    }
    for (const heading of ACTIVE_PLAN_HEADINGS) {
      if (!hasExactHeading(content, heading)) {
        errors.push(`${relativePath}: active plan is missing ${heading}`);
      }
    }
    const verificationSection = readH2Section(content, '## Verification Commands');
    if (verificationSection !== null) {
      const markers = verificationSection.split(/\r?\n/u)
        .map(readVerificationMarker)
        .filter((marker) => marker !== null);
      if (markers.length !== 1) {
        errors.push(`${relativePath}: ## Verification Commands must contain exactly one verification classification marker`);
      }
    }
  }
}

function checkMarkdownLinks(root, errors) {
  const roots = ['AGENTS.md', 'README.md', 'SECURITY.md', '.github', '.agents/skills', 'docs'];
  const markdownFiles = [];
  for (const relativeRoot of roots) {
    const absoluteRoot = path.join(root, relativeRoot);
    if (!fs.existsSync(absoluteRoot)) continue;
    if (fs.statSync(absoluteRoot).isFile()) markdownFiles.push(absoluteRoot);
    else markdownFiles.push(...walkFiles(absoluteRoot, (entry) => entry.endsWith('.md'), (directory) => {
      const rel = relative(root, directory);
      return rel === 'docs/runs' || rel.startsWith('docs/runs/');
    }));
  }

  for (const filePath of markdownFiles) {
    const content = readText(filePath);
    for (const target of markdownTargets(content)) {
      if (isExternalTarget(target)) continue;
      const [rawPath, rawFragment = ''] = target.split('#', 2);
      const decodedPath = safeDecode(rawPath);
      const targetPath = decodedPath === ''
        ? filePath
        : path.resolve(path.dirname(filePath), decodedPath);
      if (!isInside(root, targetPath) || !fs.existsSync(targetPath)) {
        errors.push(`${relative(root, filePath)}: broken link ${target}`);
        continue;
      }
      if (rawFragment && fs.statSync(targetPath).isFile() && targetPath.endsWith('.md')) {
        const anchors = markdownAnchors(readText(targetPath));
        const fragment = githubSlug(safeDecode(rawFragment));
        if (!anchors.has(fragment)) {
          errors.push(`${relative(root, filePath)}: broken anchor ${target}`);
        }
      }
    }
  }
}

function parseTomlSections(content) {
  const sections = new Map([['', new Map()]]);
  let section = '';
  for (const rawLine of content.split(/\r?\n/u)) {
    const line = rawLine.trim();
    if (line === '' || line.startsWith('#')) continue;
    const sectionMatch = line.match(/^\[([^\]]+)\]$/u);
    if (sectionMatch) {
      section = sectionMatch[1];
      if (!sections.has(section)) sections.set(section, new Map());
      continue;
    }
    const assignment = line.match(/^([A-Za-z0-9_]+)\s*=\s*(.+)$/u);
    if (assignment) sections.get(section).set(assignment[1], assignment[2].trim());
  }
  return sections;
}

function parseFrontmatter(content) {
  const match = content.match(/^---\s*\n([\s\S]*?)\n---(?:\s*\n|$)/u);
  if (!match) return {};
  const result = {};
  const lines = match[1].split(/\r?\n/u);
  for (let index = 0; index < lines.length; index += 1) {
    const field = lines[index].match(/^([A-Za-z0-9_-]+):\s*(.*)$/u);
    if (!field) continue;
    let value = field[2].trim();
    if (value === '>' || value === '|') {
      const block = [];
      while (index + 1 < lines.length && /^\s+/u.test(lines[index + 1])) {
        block.push(lines[index + 1].trim());
        index += 1;
      }
      value = block.join(' ');
    }
    result[field[1]] = unquote(value);
  }
  return result;
}

function stripFrontmatter(content) {
  return content.replace(/^---\s*\n[\s\S]*?\n---(?:\s*\n|$)/u, '');
}

function normalizeMarkdownBody(content) {
  return content.replace(/\s+/gu, ' ').trim();
}

function renderLauncherWrapperBody(wrapper) {
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

function countExactLines(content, expected) {
  return content.split(/\r?\n/u).filter((line) => line.trim() === expected).length;
}

function countMatchingLines(content, pattern) {
  return content.split(/\r?\n/u).filter((line) => pattern.test(line.trim())).length;
}

function readH2Section(content, heading) {
  const lines = content.split(/\r?\n/u);
  const start = lines.findIndex((line) => line.trim() === heading);
  if (start < 0) return null;
  const section = [];
  for (let index = start + 1; index < lines.length; index += 1) {
    if (/^##\s+/u.test(lines[index].trim())) break;
    section.push(lines[index]);
  }
  return section.join('\n');
}

function readVerificationMarker(line) {
  const normalized = line.trim()
    .replace(/^-\s+/u, '')
    .replace(/^\*\*Verification classification:\*\*\s*/u, '');
  return ACTIVE_PLAN_VERIFICATION_MARKERS.includes(normalized) ? normalized : null;
}

function markdownTargets(content) {
  const targets = [];
  const pattern = /!?\[[^\]]*\]\(([^)]+)\)/gu;
  for (const match of content.matchAll(pattern)) {
    let target = match[1].trim();
    if (target.startsWith('<')) target = target.slice(1, target.indexOf('>'));
    else target = target.replace(/\s+["'][^"']*["']\s*$/u, '');
    targets.push(target);
  }
  return targets;
}

function markdownAnchors(content) {
  const anchors = new Set();
  const counts = new Map();
  for (const match of content.matchAll(/^#{1,6}\s+(.+?)\s*#*\s*$/gmu)) {
    const base = githubSlug(match[1]);
    const count = counts.get(base) ?? 0;
    anchors.add(count === 0 ? base : `${base}-${count}`);
    counts.set(base, count + 1);
  }
  for (const match of content.matchAll(/<a\s+(?:name|id)=["']([^"']+)["']/giu)) {
    anchors.add(githubSlug(match[1]));
  }
  return anchors;
}

function githubSlug(value) {
  return value.toLowerCase()
    .replace(/<[^>]+>/gu, '')
    .replace(/[`*_~]/gu, '')
    .replace(/[^\p{L}\p{N}\s_-]/gu, '')
    .trim()
    .replace(/\s+/gu, '-')
    .replace(/-+/gu, '-');
}

function hasExactHeading(content, heading) {
  return content.split(/\r?\n/u).some((line) => line.trim() === heading);
}

function walkFiles(root, include, skipDirectory = () => false) {
  const files = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const entryPath = path.join(root, entry.name);
    if (entry.isDirectory()) {
      if (!skipDirectory(entryPath)) files.push(...walkFiles(entryPath, include, skipDirectory));
    } else if (entry.isFile() && include(entry.name)) {
      files.push(entryPath);
    }
  }
  return files;
}

function isExternalTarget(target) {
  return /^(?:[a-z][a-z0-9+.-]*:|\/\/)/iu.test(target);
}

function isInside(root, target) {
  const rel = path.relative(root, target);
  return rel === '' || (!rel.startsWith(`..${path.sep}`) && rel !== '..' && !path.isAbsolute(rel));
}

function safeDecode(value) {
  try { return decodeURIComponent(value); } catch { return value; }
}

function unquote(value) {
  if (typeof value !== 'string') return value;
  return value.replace(/^(?:"([\s\S]*)"|'([\s\S]*)')$/u, '$1$2');
}

function relative(root, filePath) {
  return path.relative(root, filePath).split(path.sep).join('/');
}

function readText(filePath) {
  return fs.readFileSync(filePath, 'utf8');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const errors = verifyDocs();
  if (errors.length > 0) {
    for (const error of errors) console.error(`- ${error}`);
    process.exitCode = 1;
  } else {
    console.log('Documentation structure verified.');
  }
}
