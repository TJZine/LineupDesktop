import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const requiredFiles = [
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
  'docs/agentic/external-guidance.md',
  'docs/agentic/plan-authoring-standard.md',
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
  typecheck: 'tsc --noEmit',
  test: 'npm run test:contracts && npm run test:harness-docs',
  'test:contracts': 'tsx --test src/__tests__/*.test.ts',
  'test:harness-docs': 'node --test tools/__tests__/*.test.mjs',
  'verify:docs': 'node tools/verify-docs.mjs',
  'verify:redaction': 'node tools/verify-redaction.mjs',
  verify: 'npm run typecheck && npm run test && npm run verify:docs && npm run verify:redaction',
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
  '## Evidence And Discovery',
  '## Files In Scope',
  '## Files Out Of Scope',
  '## Architecture Seam Decision Gate',
  '## Verification Commands',
  '## Acceptance Criteria',
  '## Replan Triggers',
  '## Rollback Notes',
];

const featureQualityLoopHeadings = [
  '## Controller State Machine',
  '## Phase Rules',
  '## Completion Gate',
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

export function verifyDocs(root = repoRoot) {
  const errors = [];
  checkRequiredFiles(root, errors);
  checkRunBundleIgnore(root, errors);
  checkForbiddenPaths(root, errors);
  checkMarkdownLinks(root, errors);
  checkActivePlanShape(root, errors);
  checkWorkflowAnchors(root, errors);
  checkProjectSkills(root, errors);
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
  if (!gitignore.includes('docs/runs/*') || !gitignore.includes('!docs/runs/README.md')) {
    errors.push('.gitignore must ignore raw docs/runs bundles while keeping docs/runs/README.md tracked');
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
    for (const heading of activePlanHeadings) {
      if (!content.includes(heading)) {
        errors.push(`${relativePath}: active plan missing ${heading}`);
      }
    }
    if (!content.includes('**Task family:** feature/design')) {
      errors.push(`${relativePath}: active plan missing feature/design task family`);
    }
    const markerCount = verificationClassificationMarkers
      .filter((marker) => content.includes(marker))
      .length;
    if (markerCount !== 1) {
      errors.push(`${relativePath}: active plan must include exactly one verification classification marker`);
    }
  }
}

function checkWorkflowAnchors(root, errors) {
  const guidancePath = path.join(root, 'docs/agentic/external-guidance.md');
  const planStandardPath = path.join(root, 'docs/agentic/plan-authoring-standard.md');
  if (!fs.existsSync(guidancePath) || !fs.existsSync(planStandardPath)) {
    return;
  }

  const guidance = fs.readFileSync(guidancePath, 'utf8');
  for (const phrase of [
    'Codex best practices',
    'Building effective agents',
    'Claude Code subagents',
    'Using PLANS.md for multi-hour problem solving',
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

function parseFrontmatter(content) {
  const match = /^---\n([\s\S]*?)\n---/u.exec(content);
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
    if (entry.name === '.git' || entry.name === 'node_modules') {
      continue;
    }
    const absolute = path.join(directory, entry.name);
    const relative = path.relative(root, absolute);
    if (relative.startsWith(`docs${path.sep}runs${path.sep}`) && relative !== path.join('docs', 'runs', 'README.md')) {
      continue;
    }
    if (entry.isDirectory()) {
      walk(root, absolute, files, includeFile);
    } else if (entry.isFile() && includeFile(entry.name)) {
      files.push(path.relative(root, absolute));
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
