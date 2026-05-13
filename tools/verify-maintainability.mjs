import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const guardrailPath = 'docs/architecture/file-shape-guardrails.md';
const attentionLineLimit = 500;
const hardLineLimit = 800;
const productionExtensions = new Set(['.ts', '.tsx', '.cts', '.mts', '.css', '.html']);

export function verifyMaintainability(root = repoRoot) {
  const errors = [];
  const allowlist = readFileShapeAllowlist(root, errors);
  const productionFiles = collectProductionFiles(root);
  const productionFileSet = new Set(productionFiles);

  for (const relativePath of productionFiles) {
    const lines = countLines(path.join(root, relativePath));
    if (lines <= attentionLineLimit) {
      continue;
    }

    const entry = allowlist.get(relativePath);
    if (!entry) {
      errors.push(
        `${relativePath}: ${lines} lines exceeds ${attentionLineLimit}; add a temporary row to ${guardrailPath} with rationale and decomposition trigger`,
      );
      continue;
    }

    if (!Number.isInteger(entry.lines)) {
      errors.push(`${guardrailPath}: ${relativePath} allowlist row needs a numeric baseline line value`);
    } else if (lines > entry.lines) {
      errors.push(
        `${guardrailPath}: ${relativePath} has ${lines} lines but its reviewed baseline is ${entry.lines}; update the file-shape decision before landing growth`,
      );
    }
    if (entry.reason.length < 20) {
      errors.push(`${guardrailPath}: ${relativePath} allowlist row needs a specific rationale`);
    }
    if (entry.trigger.length < 20) {
      errors.push(`${guardrailPath}: ${relativePath} allowlist row needs a decomposition/revisit trigger`);
    }
    if (lines > hardLineLimit && !/\b(?:decompose|split|extract|revisit|before)\b/iu.test(entry.trigger)) {
      errors.push(
        `${guardrailPath}: ${relativePath} exceeds ${hardLineLimit} lines and needs an explicit decomposition trigger`,
      );
    }
  }

  for (const [relativePath] of allowlist) {
    if (!productionFileSet.has(relativePath)) {
      errors.push(`${guardrailPath}: allowlist path does not match a production file: ${relativePath}`);
      continue;
    }
    const lines = countLines(path.join(root, relativePath));
    if (lines <= attentionLineLimit) {
      errors.push(
        `${guardrailPath}: ${relativePath} is ${lines} lines and no longer needs a file-shape allowlist row`,
      );
    }
  }

  return errors;
}

function readFileShapeAllowlist(root, errors) {
  const absolutePath = path.join(root, guardrailPath);
  const allowlist = new Map();
  if (!fs.existsSync(absolutePath)) {
    errors.push(`Missing required file: ${guardrailPath}`);
    return allowlist;
  }

  const content = fs.readFileSync(absolutePath, 'utf8');
  let sawHeader = false;
  let headerIsValid = false;
  let reportedHeaderError = false;
  for (const line of content.split(/\r?\n/u)) {
    const trimmed = line.trim();
    if (!trimmed.startsWith('|') || !trimmed.endsWith('|')) {
      continue;
    }
    const cells = trimmed
      .slice(1, -1)
      .split('|')
      .map((cell) => cell.trim());
    if (cells[0] === 'Path') {
      sawHeader = true;
      headerIsValid =
        cells[1] === 'Baseline lines' &&
        cells[2] === 'Rationale' &&
        cells[3] === 'Growth/decomposition trigger';
      if (!headerIsValid && !reportedHeaderError) {
        errors.push(
          `${guardrailPath}: allowlist table header must be Path | Baseline lines | Rationale | Growth/decomposition trigger`,
        );
        reportedHeaderError = true;
      }
      continue;
    }
    if (/^-+$/u.test(cells[0]) || !cells[0].startsWith('src/')) {
      continue;
    }
    if (cells.length !== 4) {
      errors.push(`${guardrailPath}: ${cells[0]} allowlist row must have exactly four columns`);
      continue;
    }
    if (!sawHeader && !reportedHeaderError) {
      errors.push(`${guardrailPath}: allowlist row appears before the expected table header`);
      reportedHeaderError = true;
    } else if (!headerIsValid && !reportedHeaderError) {
      errors.push(
        `${guardrailPath}: allowlist table header must be Path | Baseline lines | Rationale | Growth/decomposition trigger`,
      );
      reportedHeaderError = true;
    }

    if (allowlist.has(cells[0])) {
      errors.push(`${guardrailPath}: duplicate allowlist row for ${cells[0]}`);
    }
    const recordedLines = /^\d+$/u.test(cells[1] ?? '') ? Number.parseInt(cells[1], 10) : NaN;
    if (!Number.isInteger(recordedLines)) {
      errors.push(`${guardrailPath}: ${cells[0]} allowlist row needs a numeric baseline line value`);
    }

    allowlist.set(cells[0], {
      lines: recordedLines,
      reason: cells[2] ?? '',
      trigger: cells[3] ?? '',
    });
  }

  return allowlist;
}

function collectProductionFiles(root) {
  const files = [];
  walk(path.join(root, 'src'), root, files);
  return files.sort();
}

function walk(directory, root, files) {
  if (!fs.existsSync(directory)) {
    return;
  }
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    const relative = path.relative(root, absolute).split(path.sep).join('/');
    if (entry.isDirectory()) {
      if (entry.name === '__tests__') {
        continue;
      }
      walk(absolute, root, files);
      continue;
    }
    if (!entry.isFile()) {
      continue;
    }
    if (entry.name.includes('.test.')) {
      continue;
    }
    if (productionExtensions.has(path.extname(entry.name))) {
      files.push(relative);
    }
  }
}

function countLines(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const normalized = content.replace(/\r?\n$/u, '');
  return normalized === '' ? 0 : normalized.split(/\r?\n/u).length;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const errors = verifyMaintainability();
  if (errors.length > 0) {
    for (const error of errors) {
      console.error(error);
    }
    process.exit(1);
  }
  console.log('Maintainability verification passed.');
}
