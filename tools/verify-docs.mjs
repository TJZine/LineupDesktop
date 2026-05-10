import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const requiredFiles = [
  '.codannaignore',
  '.codex/config.toml',
  '.codex/agents/docs-researcher.toml',
  '.codex/agents/explorer-fallback.toml',
  '.codex/agents/explorer.toml',
  '.codex/agents/monitor-fallback.toml',
  '.codex/agents/monitor.toml',
  '.codex/agents/planner.toml',
  '.codex/agents/reviewer.toml',
  '.codex/agents/worker.toml',
  '.github/CODEOWNERS',
  '.github/PULL_REQUEST_TEMPLATE.md',
  '.github/workflows/ci.yml',
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

const forbiddenPaths = [
  'ARCHITECTURE_CLEANUP_CHECKLIST.md',
  'scorecard.png',
];

const forbiddenPathPatterns = [
  /(^|\/)scorecard\.[^/]+$/iu,
  /(^|\/)docs\/agentic\/evals\/baselines\//u,
];

const forbiddenContentPatterns = [
  {
    label: 'upstream cleanup package token',
    pattern: /\b(?:FCP|DCR)-\d+\b/u,
  },
  {
    label: 'active cleanup-loop authority',
    pattern: /cleanup-loop/u,
  },
  {
    label: 'detector score-chasing tool reference',
    pattern: /Desloppify|score chasing/iu,
  },
  {
    label: 'detector issue id',
    pattern: /\b(?:smells|facade|god-class|large-file|duplicate|detector)::[A-Za-z0-9_.:-]+/u,
  },
  {
    label: 'upstream cleanup package field',
    pattern: /\b(?:slice_table|ready_now_execution_unit|coverage_ledger|execution_waves)\b/u,
  },
];

const expectedScripts = {
  lint: 'eslint .',
  typecheck: 'tsc --noEmit',
  test: 'npm run test:contracts && npm run test:harness-docs',
  'test:contracts': 'node --import tsx --test src/__tests__/*.test.ts',
  'test:harness-docs': 'node --test tools/__tests__/*.test.mjs',
  'verify:architecture': 'npm run lint',
  'verify:docs': 'node tools/verify-docs.mjs',
  'verify:redaction': 'node tools/verify-redaction.mjs',
  verify: 'npm run typecheck && npm run verify:architecture && npm run test && npm run verify:docs && npm run verify:redaction',
};

const requiredIgnoreMarkers = [
  'docs/runs/*',
  '!docs/runs/README.md',
  '.codanna/',
  '.codex/cache/',
  '.agent/',
  '.fastembed_cache',
  '.mcp_sequential_thinking/',
];

const localOnlyDirectoryNames = new Set([
  '.codanna',
  '.agent',
  '.fastembed_cache',
  '.mcp_sequential_thinking',
  'dist',
  'out',
  'coverage',
]);

const requiredCodexRoles = {
  explorer: 'agents/explorer.toml',
  explorer_fallback: 'agents/explorer-fallback.toml',
  reviewer: 'agents/reviewer.toml',
  docs_researcher: 'agents/docs-researcher.toml',
  planner: 'agents/planner.toml',
  worker: 'agents/worker.toml',
  monitor: 'agents/monitor.toml',
  monitor_fallback: 'agents/monitor-fallback.toml',
};

const verificationClassificationMarkers = [
  'new regression/contract test required',
  'existing coverage sufficient',
  'broader integration/manual proof required',
  'no new automated test needed',
];

const activePlanHeadings = [
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
];

const featureQualityLoopHeadings = [
  '## Controller State Machine',
  '## Phase Rules',
  '## Completion Gate',
];

const workflowAnchorMarkers = [
  {
    path: 'docs/AGENTIC_DEV_WORKFLOW.md',
    label: 'fresh chat bootstrap',
    marker: '## Fresh Chat Bootstrap',
    requiredPhrases: [
      'Do not depend on the original Lineup repo',
      'Run `git status --short --branch` before planning edits',
    ],
  },
  {
    path: 'docs/AGENTIC_DEV_WORKFLOW.md',
    label: 'default workflow',
    marker: '## Default Workflow',
    requiredPhrases: [
      'Plan explicitly before multi-step work',
      'Do not freeze a plan while ownership',
    ],
  },
  {
    path: 'docs/AGENTIC_DEV_WORKFLOW.md',
    label: 'production engineering guardrails',
    marker: '## Production Engineering Guardrails',
    requiredPhrases: [
      'Dependency changes must name the runtime owner',
      'Configuration, credentials, app paths, diagnostics, logs',
      'Keep every committed checkpoint buildable and reversible',
    ],
  },
  {
    path: 'docs/AGENTIC_DEV_WORKFLOW.md',
    label: 'multi-agent usage',
    marker: '## Multi-Agent Usage',
    requiredPhrases: [
      'Keep read-only roles read-only',
      'Do not let a worker invent architecture seams',
    ],
  },
  {
    path: 'docs/AGENTIC_DEV_WORKFLOW.md',
    label: 'session handoff format',
    marker: '## Session Handoffs',
    requiredPhrases: [
      'NEXT_SESSION_HANDOFF',
      'MODEL_SUGGESTION',
    ],
  },
  {
    path: '.github/PULL_REQUEST_TEMPLATE.md',
    label: 'PR code health checklist',
    marker: '## Code Health',
    requiredPhrases: [
      'Change is self-contained and reviewable',
      'New dependencies, build tools, config, diagnostics, or logging behavior are justified and verified',
      'Tests protect public seams or stable behavior',
    ],
  },
  {
    path: 'docs/agentic/session-prompts/README.md',
    label: 'launcher routing matrix',
    marker: '## Launcher Routing Matrix',
    requiredPhrases: [
      'lineup-desktop-feature-quality-loop',
      'lineup-desktop-workflow-harness-review',
    ],
  },
  {
    path: 'docs/agentic/skill-strategy.md',
    label: 'Codex skill discovery policy',
    marker: '## Codex Skill Discovery',
    requiredPhrases: [
      'Use `.agents/skills/` as the repository-scoped project skill home',
      'Do not create a parallel `.codex/skills/` tree unless',
    ],
  },
  {
    path: 'docs/agentic/skill-strategy.md',
    label: 'legacy skill adaptation audit',
    marker: '## Legacy Skill Adaptation Audit',
    requiredPhrases: [
      'The original Lineup repo',
      'maintenance-program mechanics',
    ],
  },
];

const upstreamBehaviorGuardrailPath = 'docs/architecture/upstream-behavior-guardrails.md';

const upstreamBehaviorGuardrailMarkers = [
  'Original Lineup behavior is reference evidence',
  'not Desktop architecture truth',
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
  'Source audits are temporary proof only until a Desktop owner exists',
  'convert source audits into Desktop tests or fixtures',
];

const requiredSkillTargets = {
  '.agents/skills/lineup-desktop-feature-plan/SKILL.md': 'docs/agentic/session-prompts/feature-plan.md',
  '.agents/skills/lineup-desktop-feature-implement/SKILL.md': 'docs/agentic/session-prompts/feature-implement.md',
  '.agents/skills/lineup-desktop-feature-review/SKILL.md': 'docs/agentic/session-prompts/feature-review.md',
  '.agents/skills/lineup-desktop-feature-quality-loop/SKILL.md': 'docs/agentic/session-prompts/feature-quality-loop.md',
  '.agents/skills/lineup-desktop-workflow-harness-review/SKILL.md': 'docs/agentic/session-prompts/workflow-harness-review.md',
};

const requiredSkillNames = {
  '.agents/skills/lineup-desktop-feature-plan/SKILL.md': 'lineup-desktop-feature-plan',
  '.agents/skills/lineup-desktop-feature-implement/SKILL.md': 'lineup-desktop-feature-implement',
  '.agents/skills/lineup-desktop-feature-review/SKILL.md': 'lineup-desktop-feature-review',
  '.agents/skills/lineup-desktop-feature-quality-loop/SKILL.md': 'lineup-desktop-feature-quality-loop',
  '.agents/skills/lineup-desktop-workflow-harness-review/SKILL.md': 'lineup-desktop-workflow-harness-review',
};

const requiredTransferredSkillNames = [
  'architecture-boundaries',
  'bounded-worker-execution',
  'closeout-verification',
  'debugging-remediation',
  'execution-plan-authoring',
  'model-selection',
  'parallel-sidecars',
  'persistence-boundaries',
  'plex-integration-boundaries',
  'review-adjudication',
  'review-request',
  'ui-composition-patterns',
  'verification-strategy',
];

export function verifyDocs(root = repoRoot) {
  const errors = [];
  checkRequiredFiles(root, errors);
  checkRunBundleIgnore(root, errors);
  checkCodexRoles(root, errors);
  checkForbiddenPaths(root, errors);
  checkMarkdownLinks(root, errors);
  checkActivePlanShape(root, errors);
  checkWorkflowAnchors(root, errors);
  checkUpstreamBehaviorGuardrails(root, errors);
  checkProjectSkills(root, errors);
  checkTransferredSkills(root, errors);
  checkForbiddenBaggage(root, errors);
  checkPackageScripts(root, errors);
  return errors;
}

function checkRequiredFiles(root, errors) {
  for (const relativePath of requiredFiles) {
    if (!fs.existsSync(path.join(root, relativePath))) {
      errors.push(`Missing required file: ${relativePath}`);
    }
  }
}

function checkForbiddenPaths(root, errors) {
  for (const relativePath of forbiddenPaths) {
    if (fs.existsSync(path.join(root, relativePath))) {
      errors.push(`Forbidden upstream cleanup artifact present: ${relativePath}`);
    }
  }
  for (const relativePath of collectAllFiles(root)) {
    for (const pattern of forbiddenPathPatterns) {
      if (pattern.test(relativePath)) {
        errors.push(`Forbidden upstream cleanup artifact path present: ${relativePath}`);
      }
    }
  }
}

function checkMarkdownLinks(root, errors) {
  for (const relativePath of collectMarkdownFiles(root)) {
    const content = fs.readFileSync(path.join(root, relativePath), 'utf8');
    const links = extractMarkdownLinks(content);
    for (const link of links) {
      if (/^[a-z][a-z0-9+.-]*:/iu.test(link)) {
        continue;
      }
      const target = link.split('#')[0];
      const fragment = link.includes('#') ? link.slice(link.indexOf('#') + 1) : '';
      const resolved = target
        ? path.resolve(path.dirname(path.join(root, relativePath)), target)
        : path.join(root, relativePath);
      if (!resolved.startsWith(root) || !fs.existsSync(resolved)) {
        errors.push(`${relativePath}: broken link ${link}`);
        continue;
      }
      if (fragment && !markdownAnchorExists(resolved, fragment)) {
        errors.push(`${relativePath}: broken anchor ${link}`);
      }
    }
  }
}

function checkRunBundleIgnore(root, errors) {
  const gitignorePath = path.join(root, '.gitignore');
  if (!fs.existsSync(gitignorePath)) {
    errors.push('.gitignore missing');
    return;
  }
  const gitignore = fs.readFileSync(gitignorePath, 'utf8');
  for (const marker of requiredIgnoreMarkers) {
    if (!gitignore.includes(marker)) {
      errors.push(`.gitignore missing local-only artifact marker: ${marker}`);
    }
  }
}

function checkCodexRoles(root, errors) {
  const configPath = path.join(root, '.codex/config.toml');
  if (!fs.existsSync(configPath)) {
    return;
  }
  const config = fs.readFileSync(configPath, 'utf8');
  if (config.includes('cleanup_worker')) {
    errors.push('.codex/config.toml must not declare a desktop cleanup-worker role before this repo owns that workflow');
  }
  for (const [role, configFile] of Object.entries(requiredCodexRoles)) {
    if (!config.includes(`[agents.${role}]`)) {
      errors.push(`.codex/config.toml missing role declaration: ${role}`);
    }
    if (!config.includes(`config_file = "${configFile}"`)) {
      errors.push(`.codex/config.toml missing config_file for role ${role}: ${configFile}`);
    }
    if (!fs.existsSync(path.join(root, '.codex', configFile))) {
      errors.push(`Missing Codex role config file: .codex/${configFile}`);
    }
  }
}

function checkActivePlanShape(root, errors) {
  const planDir = path.join(root, 'docs/plans');
  if (!fs.existsSync(planDir)) {
    return;
  }
  for (const relativePath of collectMarkdownFiles(root).filter((file) => file.startsWith('docs/plans/'))) {
    const content = fs.readFileSync(path.join(root, relativePath), 'utf8');
    if (!content.includes('**Plan Status:** active')) {
      continue;
    }
    const planStatusIndex = content.indexOf('**Plan Status:** active');
    const firstSectionIndex = content.indexOf('## ');
    if (firstSectionIndex !== -1 && planStatusIndex > firstSectionIndex) {
      errors.push(`${relativePath}: active plan status marker must appear before the first ## heading`);
    }
    let previousHeadingIndex = -1;
    for (const heading of activePlanHeadings) {
      const headingIndex = content.indexOf(heading);
      if (headingIndex === -1) {
        errors.push(`${relativePath}: active plan missing ${heading}`);
        continue;
      }
      if (headingIndex < previousHeadingIndex) {
        errors.push(`${relativePath}: active plan heading out of order: ${heading}`);
      }
      previousHeadingIndex = headingIndex;
    }
    if (!content.includes('**Task family:** feature/design')) {
      errors.push(`${relativePath}: active plan missing feature/design task family`);
    }
    if (content.includes('**Tier:** Tier 3')) {
      checkTier3Handoff(relativePath, content, errors);
    }
    const markerCount = verificationClassificationMarkers
      .filter((marker) => content.includes(marker))
      .length;
    if (markerCount !== 1) {
      errors.push(`${relativePath}: active plan must include exactly one verification classification marker`);
    }
  }
}

function checkTier3Handoff(relativePath, content, errors) {
  const modelIndex = content.indexOf('MODEL_SUGGESTION');
  const handoffIndex = content.indexOf('NEXT_SESSION_HANDOFF');
  if (modelIndex === -1) {
    errors.push(`${relativePath}: Tier 3 active plan missing MODEL_SUGGESTION`);
  }
  if (handoffIndex === -1) {
    errors.push(`${relativePath}: Tier 3 active plan missing NEXT_SESSION_HANDOFF`);
    return;
  }
  if (modelIndex !== -1 && modelIndex > handoffIndex) {
    errors.push(`${relativePath}: MODEL_SUGGESTION must appear before NEXT_SESSION_HANDOFF`);
  }
  for (const field of [
    'NEXT_SESSION_LAUNCHER:',
    'TASK:',
    'TASK_FAMILY:',
    'TIER:',
    'PLAN:',
    'ARTIFACT:',
    'FILES:',
    'BLOCKERS:',
    'MESSAGE:',
  ]) {
    if (!content.includes(field)) {
      errors.push(`${relativePath}: NEXT_SESSION_HANDOFF missing field ${field}`);
    }
  }
}

function checkWorkflowAnchors(root, errors) {
  const guidancePath = path.join(root, 'docs/agentic/external-guidance.md');
  const planStandardPath = path.join(root, 'docs/agentic/plan-authoring-standard.md');
  if (!fs.existsSync(guidancePath) || !fs.existsSync(planStandardPath)) {
    return;
  }

  for (const { path: relativePath, label, marker, requiredPhrases = [] } of workflowAnchorMarkers) {
    const absolutePath = path.join(root, relativePath);
    if (!fs.existsSync(absolutePath)) {
      continue;
    }
    const content = fs.readFileSync(absolutePath, 'utf8');
    if (!content.includes(marker)) {
      errors.push(`${relativePath}: missing ${label} marker ${marker}`);
    }
    for (const phrase of requiredPhrases) {
      if (!content.includes(phrase)) {
        errors.push(`${relativePath}: missing ${label} phrase: ${phrase}`);
      }
    }
  }

  const guidance = fs.readFileSync(guidancePath, 'utf8');
  for (const phrase of [
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
  ]) {
    if (!guidance.includes(phrase)) {
      errors.push(`docs/agentic/external-guidance.md: missing guidance source: ${phrase}`);
    }
  }

  const planStandard = fs.readFileSync(planStandardPath, 'utf8');
  for (const heading of activePlanHeadings) {
    if (!planStandard.includes(heading)) {
      errors.push(`docs/agentic/plan-authoring-standard.md: missing active-plan heading reference ${heading}`);
    }
  }
  for (const phrase of [
    'dependency, build-tool, configuration, or lockfile changes',
    'security/licensing/provenance considerations',
  ]) {
    if (!planStandard.includes(phrase)) {
      errors.push(`docs/agentic/plan-authoring-standard.md: missing production-engineering plan phrase ${phrase}`);
    }
  }

  const featureQualityLoopPath = path.join(root, 'docs/agentic/session-prompts/feature-quality-loop.md');
  if (fs.existsSync(featureQualityLoopPath)) {
    const featureQualityLoop = fs.readFileSync(featureQualityLoopPath, 'utf8');
    for (const heading of featureQualityLoopHeadings) {
      if (!featureQualityLoop.includes(heading)) {
        errors.push(`docs/agentic/session-prompts/feature-quality-loop.md: missing Tier 3 launcher heading ${heading}`);
      }
    }
  }
}

function checkUpstreamBehaviorGuardrails(root, errors) {
  const absolutePath = path.join(root, upstreamBehaviorGuardrailPath);
  if (!fs.existsSync(absolutePath)) {
    return;
  }
  const content = fs.readFileSync(absolutePath, 'utf8');
  const normalizedContent = content.replace(/\s+/gu, ' ');
  for (const marker of upstreamBehaviorGuardrailMarkers) {
    if (!normalizedContent.includes(marker)) {
      errors.push(`${upstreamBehaviorGuardrailPath}: missing upstream behavior guardrail marker: ${marker}`);
    }
  }
}

function checkProjectSkills(root, errors) {
  for (const [skillPath, targetPath] of Object.entries(requiredSkillTargets)) {
    const absolutePath = path.join(root, skillPath);
    if (!fs.existsSync(absolutePath)) {
      continue;
    }
    const content = fs.readFileSync(absolutePath, 'utf8');
    const frontmatter = parseFrontmatter(content);
    if (frontmatter.name !== requiredSkillNames[skillPath]) {
      errors.push(`${skillPath}: frontmatter name must be ${requiredSkillNames[skillPath]}`);
    }
    if (!frontmatter.description) {
      errors.push(`${skillPath}: frontmatter description is required`);
    }
    if (!content.includes('Use this only from the Lineup Desktop repo.')) {
      errors.push(`${skillPath}: missing repo-scope rule`);
    }
    for (const requiredRead of ['AGENTS.md', 'docs/AGENTIC_DEV_WORKFLOW.md', targetPath]) {
      if (!content.includes(requiredRead)) {
        errors.push(`${skillPath}: missing required read ${requiredRead}`);
      }
    }
    if (!content.includes(targetPath)) {
      errors.push(`${skillPath}: missing tracked launcher reference ${targetPath}`);
    }
    if (!content.includes('follow the tracked launcher exactly')) {
      errors.push(`${skillPath}: missing tracked-launcher delegation rule`);
    }
    if (content.split(/\r?\n/u).length > 28) {
      errors.push(`${skillPath}: project skill wrapper must stay thin`);
    }
  }
}

function checkTransferredSkills(root, errors) {
  for (const skillName of requiredTransferredSkillNames) {
    const skillPath = `.agents/skills/${skillName}/SKILL.md`;
    const absolutePath = path.join(root, skillPath);
    if (!fs.existsSync(absolutePath)) {
      errors.push(`Missing transferred Lineup skill adaptation: ${skillPath}`);
      continue;
    }
    const content = fs.readFileSync(absolutePath, 'utf8');
    const frontmatter = parseFrontmatter(content);
    if (frontmatter.name !== skillName) {
      errors.push(`${skillPath}: frontmatter name must be ${skillName}`);
    }
    if (!frontmatter.description) {
      errors.push(`${skillPath}: frontmatter description is required`);
    }
    if (!content.includes('Use this only from the Lineup Desktop repo.')) {
      errors.push(`${skillPath}: missing repo-scope rule`);
    }
    if (!content.includes('AGENTS.md')) {
      errors.push(`${skillPath}: missing AGENTS.md read`);
    }
    if (!content.includes('docs/AGENTIC_DEV_WORKFLOW.md')) {
      errors.push(`${skillPath}: missing workflow runbook read`);
    }
  }
}

function parseFrontmatter(content) {
  const match = /^---\r?\n([\s\S]*?)\r?\n---/u.exec(content);
  if (!match) {
    return {};
  }
  const fields = {};
  for (const line of match[1].split(/\r?\n/u)) {
    const fieldMatch = /^([A-Za-z0-9_-]+):\s*(.*)$/u.exec(line);
    if (fieldMatch) {
      fields[fieldMatch[1]] = fieldMatch[2].trim();
    }
  }
  return fields;
}

function markdownAnchorExists(filePath, fragment) {
  const content = fs.readFileSync(filePath, 'utf8');
  const expected = decodeURIComponent(fragment).toLowerCase();
  const anchors = new Set();
  for (const line of content.split(/\r?\n/u)) {
    const headingMatch = /^(#{1,6})\s+(.+)$/u.exec(line);
    if (headingMatch) {
      anchors.add(slugifyHeading(headingMatch[2]));
    }
    const idMatches = line.matchAll(/\bid=["']([^"']+)["']/gu);
    for (const idMatch of idMatches) {
      anchors.add(idMatch[1].toLowerCase());
    }
  }
  return anchors.has(expected);
}

function slugifyHeading(heading) {
  return heading
    .replace(/\s+#+\s*$/u, '')
    .replace(/`([^`]*)`/gu, '$1')
    .replace(/\[([^\]]+)\]\([^)]+\)/gu, '$1')
    .trim()
    .toLowerCase()
    .replace(/[^\p{Letter}\p{Number}\s-]/gu, '')
    .replace(/\s+/gu, '-');
}

function checkForbiddenBaggage(root, errors) {
  for (const relativePath of collectMarkdownFiles(root)) {
    const content = fs.readFileSync(path.join(root, relativePath), 'utf8');
    for (const { label, pattern } of forbiddenContentPatterns) {
      pattern.lastIndex = 0;
      if (pattern.test(content)) {
        errors.push(`${relativePath}: forbidden ${label}`);
      }
    }
  }
}

function checkPackageScripts(root, errors) {
  const packagePath = path.join(root, 'package.json');
  if (!fs.existsSync(packagePath)) {
    return;
  }
  const pkg = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
  for (const [script, expected] of Object.entries(expectedScripts)) {
    if (!pkg.scripts?.[script]) {
      errors.push(`package.json missing script: ${script}`);
      continue;
    }
    if (pkg.scripts[script] !== expected) {
      errors.push(`package.json script ${script} must be exactly: ${expected}`);
    }
  }
}

function collectAllFiles(root) {
  const files = [];
  walk(root, root, files, () => true);
  return files.sort();
}

function collectMarkdownFiles(root) {
  const files = [];
  walk(root, root, files, (entryName) => entryName.endsWith('.md'));
  return files.sort();
}

function walk(root, directory, files, includeFile) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    const nativeRelative = path.relative(root, absolute);
    const relative = nativeRelative.split(path.sep).join('/');
    if (
      entry.name === '.git' ||
      entry.name === 'node_modules' ||
      localOnlyDirectoryNames.has(entry.name) ||
      relative === '.codex/cache' ||
      relative.startsWith('.codex/cache/')
    ) {
      continue;
    }
    if (relative.startsWith('docs/runs/') && relative !== 'docs/runs/README.md') {
      continue;
    }
    if (entry.isDirectory()) {
      walk(root, absolute, files, includeFile);
    } else if (entry.isFile() && includeFile(entry.name)) {
      files.push(relative);
    }
  }
}

function extractMarkdownLinks(content) {
  const links = [];
  const regex = /\[[^\]]+\]\(([^)]+)\)/gu;
  let match = regex.exec(content);
  while (match !== null) {
    links.push(match[1].trim());
    match = regex.exec(content);
  }
  return links;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const errors = verifyDocs();
  if (errors.length > 0) {
    for (const error of errors) {
      console.error(error);
    }
    process.exit(1);
  }
  console.log('Documentation verification passed.');
}
