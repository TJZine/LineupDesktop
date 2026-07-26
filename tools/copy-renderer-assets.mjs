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
  const sourceRoot = path.resolve(compiledChannelBuilderDirectory);
  const targetDirectory = path.join(
    targetRendererDirectory,
    'domain',
    'channelBuilder',
  );
  fs.mkdirSync(targetDirectory, { recursive: true });

  const pendingFiles = ['config.js'];
  const runtimeFiles = new Set();
  while (pendingFiles.length > 0) {
    const fileName = pendingFiles.pop();
    if (runtimeFiles.has(fileName)) continue;

    const sourcePath = path.resolve(sourceRoot, fileName);
    assertPathInsideDirectory(sourcePath, sourceRoot, fileName);
    const source = fs.readFileSync(sourcePath, 'utf8');
    runtimeFiles.add(fileName);

    for (const specifier of findRelativeModuleSpecifiers(source)) {
      const dependencyPath = path.resolve(path.dirname(sourcePath), specifier);
      assertPathInsideDirectory(dependencyPath, sourceRoot, specifier);
      if (path.extname(dependencyPath) !== '.js') {
        throw new Error(
          `Renderer Channel Builder runtime dependency must be JavaScript: ${specifier}`,
        );
      }
      pendingFiles.push(path.relative(sourceRoot, dependencyPath));
    }
  }

  for (const fileName of runtimeFiles) {
    const targetPath = path.join(targetDirectory, fileName);
    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    fs.copyFileSync(path.join(sourceRoot, fileName), targetPath);
  }
}

function findRelativeModuleSpecifiers(source) {
  const specifiers = new Set();
  const patterns = [
    /\b(?:import|export)\s+[^;]*?\s+from\s+(['"])([^'"]+)\1/gu,
    /\bimport\s+(['"])([^'"]+)\1/gu,
    /\bimport\s*\(\s*(['"])([^'"]+)\1\s*\)/gu,
  ];
  for (const pattern of patterns) {
    for (const match of source.matchAll(pattern)) {
      if (match[2].startsWith('.')) specifiers.add(match[2]);
    }
  }
  return specifiers;
}

function assertPathInsideDirectory(filePath, directory, specifier) {
  const relativePath = path.relative(directory, filePath);
  if (
    relativePath === '' ||
    relativePath.startsWith(`..${path.sep}`) ||
    path.isAbsolute(relativePath)
  ) {
    throw new Error(
      `Renderer Channel Builder runtime dependency escapes its allowed directory: ${specifier}`,
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
