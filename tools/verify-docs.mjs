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

export function verifyDocs(root = repoRoot) {
  const errors = [];
  checkRequiredFiles(root, errors);
  checkForbiddenPaths(root, errors);
  checkMarkdownLinks(root, errors);
  checkActivePlanShape(root, errors);
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
      if (/^[a-z][a-z0-9+.-]*:/iu.test(link) || link.startsWith('#')) {
        continue;
      }
      const target = link.split('#')[0];
      if (!target) {
        continue;
      }
      const resolved = path.resolve(path.dirname(path.join(root, relativePath)), target);
      if (!resolved.startsWith(root) || !fs.existsSync(resolved)) {
        errors.push(`${relativePath}: broken link ${link}`);
      }
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
    for (const heading of [
      '## Goal',
      '## Non-Goals',
      '## Parent Architecture Alignment',
      '## Required Reading',
      '## Files In Scope',
      '## Files Out Of Scope',
      '## Architecture Seam Decision Gate',
      '## Verification Commands',
      '## Replan Triggers',
      '## Rollback Notes',
    ]) {
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
