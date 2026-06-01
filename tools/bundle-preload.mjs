import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import esbuild from 'esbuild';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outputPath = path.join(repoRoot, 'dist', 'preload', 'index.cjs');
const legacySplitOutputPath = path.join(repoRoot, 'dist', 'preload', 'channelBridgeGuards.cjs');

try {
  await esbuild.build({
    entryPoints: [path.join(repoRoot, 'src', 'preload', 'index.cts')],
    outfile: outputPath,
    bundle: true,
    platform: 'node',
    format: 'cjs',
    target: 'node22',
    external: ['electron'],
    sourcemap: true,
    logLevel: 'warning',
  });
  console.log('Preload bundle written.');
} catch (error) {
  console.error(`Failed to bundle preload to ${outputPath}`);
  console.error(error instanceof Error ? error.stack ?? error.message : error);
  process.exitCode = 1;
} finally {
  fs.rmSync(legacySplitOutputPath, { force: true });
  fs.rmSync(`${legacySplitOutputPath}.map`, { force: true });
}
