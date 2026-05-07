import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const forbiddenPatterns = [
  {
    label: 'tokenized Plex URL',
    pattern: new RegExp(`${['X-Plex', 'Token'].join('-')}\\s*=`, 'i'),
  },
  {
    label: 'raw Authorization header',
    pattern: new RegExp(`${['Authorization'].join('')}\\s*:`, 'i'),
  },
  {
    label: 'bearer credential',
    pattern: new RegExp(`\\b${['Bearer'].join('')}\\s+[A-Za-z0-9._~+/-]{12,}`, 'i'),
  },
];

const textFilePattern = /\.(md|ts|tsx|js|mjs|cjs|json|toml|yaml|yml|txt)$/u;

export function collectFiles(root = repoRoot) {
  const files = [];
  walkDirectory(root, root, files);
  return files.sort();
}

export function scanFileContent(content) {
  const findings = [];
  for (const { label, pattern } of forbiddenPatterns) {
    pattern.lastIndex = 0;
    if (pattern.test(content)) {
      findings.push(label);
    }
  }
  return findings;
}

export function scanRepo(root = repoRoot) {
  const findings = [];
  for (const relativePath of collectFiles(root)) {
    const absolutePath = path.join(root, relativePath);
    const stat = fs.statSync(absolutePath);
    if (!stat.isFile()) {
      continue;
    }
    const content = fs.readFileSync(absolutePath, 'utf8');
    for (const reason of scanFileContent(content)) {
      findings.push({ file: relativePath, reason });
    }
  }
  return findings;
}

function walkDirectory(root, directory, files) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      if (
        entry.name === 'node_modules' ||
        entry.name === '.git' ||
        entry.name === 'dist' ||
        entry.name === 'out' ||
        entry.name === 'coverage'
      ) {
        continue;
      }
      walkDirectory(root, absolute, files);
      continue;
    }
    if (entry.isFile() && textFilePattern.test(entry.name)) {
      files.push(path.relative(root, absolute));
    }
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const findings = scanRepo();
  if (findings.length > 0) {
    for (const finding of findings) {
      console.error(`${finding.file}: ${finding.reason}`);
    }
    process.exit(1);
  }
  console.log('Redaction verification passed.');
}
