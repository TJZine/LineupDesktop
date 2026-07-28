import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { initSync, parse } from 'es-module-lexer';

initSync();

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
  const sourceRoot = fs.realpathSync(path.resolve(compiledChannelBuilderDirectory));
  const targetDirectory = path.join(
    targetRendererDirectory,
    'domain',
    'channelBuilder',
  );
  fs.mkdirSync(targetDirectory, { recursive: true });

  const pendingFiles = [
    {
      fileName: 'config.js',
      importedBy: null,
      specifier: 'config.js',
    },
  ];
  const runtimeFiles = new Map();
  while (pendingFiles.length > 0) {
    const { fileName, importedBy, specifier } = pendingFiles.pop();
    if (runtimeFiles.has(fileName)) continue;

    const sourcePath = path.resolve(sourceRoot, fileName);
    assertPathInsideDirectory(sourcePath, sourceRoot, specifier);
    if (!fs.existsSync(sourcePath)) {
      const dependencyContext =
        importedBy === null
          ? `entry module ${JSON.stringify(specifier)}`
          : `${JSON.stringify(specifier)} imported by ${JSON.stringify(importedBy)}`;
      throw new Error(
        `Renderer Channel Builder runtime dependency could not be resolved: ${dependencyContext}`,
      );
    }
    const canonicalSourcePath = fs.realpathSync(sourcePath);
    assertPathInsideDirectory(canonicalSourcePath, sourceRoot, specifier);
    const source = fs.readFileSync(canonicalSourcePath, 'utf8');
    runtimeFiles.set(fileName, canonicalSourcePath);

    for (const dependencySpecifier of findRelativeModuleSpecifiers(source)) {
      const dependencyPath = path.resolve(path.dirname(sourcePath), dependencySpecifier);
      assertPathInsideDirectory(dependencyPath, sourceRoot, dependencySpecifier);
      if (path.extname(dependencyPath) !== '.js') {
        throw new Error(
          `Renderer Channel Builder runtime dependency must be JavaScript: ${dependencySpecifier}`,
        );
      }
      pendingFiles.push({
        fileName: path.relative(sourceRoot, dependencyPath),
        importedBy: fileName,
        specifier: dependencySpecifier,
      });
    }
  }

  for (const [fileName, canonicalSourcePath] of runtimeFiles) {
    const targetPath = path.join(targetDirectory, fileName);
    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    fs.copyFileSync(canonicalSourcePath, targetPath);
  }
}

function findRelativeModuleSpecifiers(source) {
  const specifiers = new Set();
  const [imports] = parse(source);
  for (const imported of imports) {
    if (imported.n?.startsWith('.')) specifiers.add(imported.n);
  }
  return specifiers;
}

function assertPathInsideDirectory(filePath, directory, specifier) {
  const relativePath = path.relative(directory, filePath);
  if (
    relativePath === '' ||
    relativePath === '..' ||
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
