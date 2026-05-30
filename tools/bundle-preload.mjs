import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import esbuild from 'esbuild';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outputPath = path.join(repoRoot, 'dist', 'preload', 'index.cjs');
const splitOutputPath = path.join(repoRoot, 'dist', 'preload', 'channelBridgeGuards.cjs');

await esbuild.build({
  entryPoints: [path.join(repoRoot, 'src', 'preload', 'index.cts')],
  outfile: outputPath,
  bundle: true,
  platform: 'node',
  format: 'cjs',
  target: 'node22',
  external: ['electron'],
  sourcemap: true,
  logLevel: 'silent',
});

fs.rmSync(splitOutputPath, { force: true });
fs.rmSync(`${splitOutputPath}.map`, { force: true });
console.log('Preload bundle written.');
