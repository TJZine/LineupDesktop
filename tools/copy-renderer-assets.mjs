import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sourceRoot = path.join(repoRoot, 'src', 'renderer');
const targetRoot = path.join(repoRoot, 'dist', 'renderer');

export function copyRendererAssets(sourceDirectory, targetDirectory) {
  fs.mkdirSync(targetDirectory, { recursive: true });

  for (const fileName of ['index.html', 'styles.css']) {
    fs.copyFileSync(path.join(sourceDirectory, fileName), path.join(targetDirectory, fileName));
  }

  fs.cpSync(path.join(sourceDirectory, 'styles'), path.join(targetDirectory, 'styles'), {
    recursive: true,
  });

  fs.cpSync(path.join(sourceDirectory, 'assets'), path.join(targetDirectory, 'assets'), {
    recursive: true,
  });
}

export function copyRendererChannelBuilderRuntime(
  compiledChannelBuilderDirectory,
  targetRendererDirectory,
) {
  const targetDirectory = path.join(
    targetRendererDirectory,
    'domain',
    'channelBuilder',
  );
  fs.mkdirSync(targetDirectory, { recursive: true });
  for (const fileName of ['config.js', 'constants.js']) {
    fs.copyFileSync(
      path.join(compiledChannelBuilderDirectory, fileName),
      path.join(targetDirectory, fileName),
    );
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  copyRendererAssets(sourceRoot, targetRoot);
  copyRendererChannelBuilderRuntime(
    path.join(repoRoot, 'dist', 'domain', 'channelBuilder'),
    targetRoot,
  );
  console.log('Renderer assets copied.');
}
