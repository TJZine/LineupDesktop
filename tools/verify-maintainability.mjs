import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const attentionLineLimit = 500;
const reviewLineLimit = 800;
const productionExtensions = new Set(['.ts', '.tsx', '.cts', '.mts', '.css', '.html']);

export function collectMaintainabilityEvidence(root = repoRoot) {
  return collectProductionFiles(root)
    .map((relativePath) => ({
      path: relativePath,
      lines: countLines(path.join(root, relativePath)),
    }))
    .filter(({ lines }) => lines > attentionLineLimit)
    .map((entry) => ({
      ...entry,
      review: entry.lines > reviewLineLimit ? 'fresh-review' : 'disposition',
    }));
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
    if (entry.isDirectory()) {
      if (entry.name !== '__tests__') {
        walk(absolute, root, files);
      }
      continue;
    }
    if (
      entry.isFile()
      && !entry.name.includes('.test.')
      && productionExtensions.has(path.extname(entry.name))
    ) {
      files.push(path.relative(root, absolute).split(path.sep).join('/'));
    }
  }
}

function countLines(filePath) {
  const content = fs.readFileSync(filePath, 'utf8').replace(/\r?\n$/u, '');
  return content === '' ? 0 : content.split(/\r?\n/u).length;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const evidence = collectMaintainabilityEvidence();
  for (const { path: relativePath, lines, review } of evidence) {
    console.log(`${review}\t${lines}\t${relativePath}`);
  }
  console.log(`Maintainability evidence: ${evidence.length} production file(s) over ${attentionLineLimit} lines.`);
}
