import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sourceRoot = path.join(repoRoot, 'src', 'renderer');
const targetRoot = path.join(repoRoot, 'dist', 'renderer');

fs.mkdirSync(targetRoot, { recursive: true });

for (const fileName of ['index.html', 'styles.css']) {
  fs.copyFileSync(path.join(sourceRoot, fileName), path.join(targetRoot, fileName));
}

fs.cpSync(path.join(sourceRoot, 'styles'), path.join(targetRoot, 'styles'), {
  recursive: true,
});

console.log('Renderer assets copied.');
