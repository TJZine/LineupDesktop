import { Buffer } from 'node:buffer';
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const PACKAGE_OUTPUT_PARENT = 'out/rd-18-windows-internal';
export const PACKAGE_DIRECTORY_NAME = 'lineup-desktop-0.0.0-win32-x64';
export const PACKAGE_RELATIVE_PATH = `${PACKAGE_OUTPUT_PARENT}/${PACKAGE_DIRECTORY_NAME}`;
export const APP_PACKAGE_RELATIVE_PATH = 'resources/app/package.json';
export const PROVENANCE_RELATIVE_PATH = 'resources/lineup-desktop-provenance.json';
export const CHECKSUMS_RELATIVE_PATH = 'resources/checksums.sha256';
export const NOTICES_RELATIVE_PATH = 'resources/third-party-notices-internal.json';
export const NATIVE_HELPER_BLOCKED_RELATIVE_PATH =
  'resources/native-helper/PRODUCTION_HELPER_BLOCKED.txt';
export const MEDIA_BINARIES_BLOCKED_RELATIVE_PATH =
  'resources/media-binaries/REDISTRIBUTION_BLOCKED.txt';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export function parsePackageArgs(args) {
  const parsed = {
    outRoot: PACKAGE_OUTPUT_PARENT,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--out') {
      const value = args[index + 1];
      if (!value) {
        throw new Error('Usage: node tools/package-windows-internal.mjs --out out/rd-18-windows-internal');
      }
      assertApprovedOutRoot(value);
      parsed.outRoot = value;
      index += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  return parsed;
}

export function assertApprovedOutRoot(outRoot) {
  if (normalizeRelativePath(path.normalize(outRoot)) !== PACKAGE_OUTPUT_PARENT || path.isAbsolute(outRoot)) {
    throw new Error(`RD-18 internal packaging output root must be exactly ${PACKAGE_OUTPUT_PARENT}.`);
  }
}

export function assertWindowsX64Runtime({ platform = process.platform, arch = process.arch } = {}) {
  if (platform !== 'win32' || arch !== 'x64') {
    throw new Error('RD-18 internal packaging must be run on Windows x64 to create a Windows x64 artifact.');
  }
}

export function buildInternalPackagePaths({ root = repoRoot, outRoot = PACKAGE_OUTPUT_PARENT } = {}) {
  assertApprovedOutRoot(outRoot);
  const outputRoot = path.resolve(root, outRoot);
  return {
    outputRoot,
    packageRoot: path.join(outputRoot, PACKAGE_DIRECTORY_NAME),
  };
}

export function loadPackageMetadata(root = repoRoot) {
  const packageJson = readJson(path.join(root, 'package.json'));
  const lockfile = readJson(path.join(root, 'package-lock.json'));
  const electronPackage = lockfile.packages?.['node_modules/electron'];

  if (!electronPackage?.version) {
    throw new Error('package-lock.json must include locked node_modules/electron metadata.');
  }

  return {
    app: {
      name: packageJson.name,
      version: packageJson.version,
      license: packageJson.license,
      type: packageJson.type,
    },
    electronVersion: electronPackage.version,
    lockfilePackageCount: Object.keys(lockfile.packages ?? {}).length,
  };
}

export function createStagedAppPackage(metadata) {
  return {
    name: metadata.app.name,
    version: metadata.app.version,
    license: metadata.app.license,
    type: metadata.app.type,
    main: 'dist/main/index.js',
  };
}

export function createInternalNotices(metadata) {
  return {
    noticeFormat: 'rd-18-internal-notices-v1',
    packageName: metadata.app.name,
    packageVersion: metadata.app.version,
    packageLicense: metadata.app.license,
    auditStatus: {
      npmLockfilePackages: metadata.lockfilePackageCount,
      packageLicenseAudit: 'current-lockfile-internal-review-recorded',
      missingPackageLicenseFields: [],
      publicRelease: 'blocked',
    },
    blockedPublicReleaseObligations: [
      'native-media-redistribution-review',
      'installer-third-party-notices-review',
      'signing-and-update-release-review',
    ],
    nativeHelper: {
      status: 'blocked',
      marker: NATIVE_HELPER_BLOCKED_RELATIVE_PATH,
    },
    mediaBinaries: {
      status: 'blocked',
      marker: MEDIA_BINARIES_BLOCKED_RELATIVE_PATH,
    },
  };
}

export function createProvenanceManifest({
  metadata,
  runtimeVersions,
  buildInputChecksums,
  artifactFileChecksums,
}) {
  return {
    manifestFormat: 'rd-18-windows-internal-provenance-v1',
    packageLayout: {
      platform: 'win32',
      arch: 'x64',
      packageDirectoryName: PACKAGE_DIRECTORY_NAME,
      unpackedApp: true,
      asar: false,
      entrypoint: 'LineupDesktop.exe',
      appPackage: APP_PACKAGE_RELATIVE_PATH,
    },
    packageMetadata: metadata.app,
    runtime: {
      electron: metadata.electronVersion,
      node: runtimeVersions.node,
      chrome: runtimeVersions.chrome,
      v8: runtimeVersions.v8,
      modules: runtimeVersions.modules,
      napi: runtimeVersions.napi,
    },
    lockfile: {
      packageCount: metadata.lockfilePackageCount,
    },
    buildInputChecksums,
    artifactFileChecksums,
    licenseAndNoticeStatus: {
      internalNotices: NOTICES_RELATIVE_PATH,
      npmPackageLicenseAudit: 'current-lockfile-internal-review-recorded',
      publicRelease: 'blocked',
    },
    nativeHelperStatus: {
      status: 'blocked',
      marker: NATIVE_HELPER_BLOCKED_RELATIVE_PATH,
    },
    mediaBinariesStatus: {
      status: 'blocked',
      marker: MEDIA_BINARIES_BLOCKED_RELATIVE_PATH,
      rd06LocalPrerequisitesCopied: false,
    },
    supportBundleRedactionProof: {
      reference: 'rd-17-windows-smoke-support-bundle-redaction-report',
      status: 'recorded',
    },
    windowsProof: {
      status: 'required-before-closeout',
      reason: 'Package generation is only valid when observed on Windows x64.',
    },
  };
}

export function resolveElectronRuntimeDir(root = repoRoot) {
  return path.join(root, 'node_modules/electron/dist');
}

export function collectRuntimeVersions(root = repoRoot) {
  const electronDist = resolveElectronRuntimeDir(root);
  const electronExecutable = path.join(electronDist, 'electron.exe');
  const expression = [
    'JSON.stringify({',
    'electron:process.versions.electron,',
    'node:process.versions.node,',
    'chrome:process.versions.chrome,',
    'v8:process.versions.v8,',
    'modules:process.versions.modules,',
    'napi:process.versions.napi',
    '})',
  ].join('');
  const result = spawnSync(electronExecutable, ['-p', expression], {
    env: {
      ...process.env,
      ELECTRON_RUN_AS_NODE: '1',
    },
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  if (result.status !== 0) {
    throw new Error('Unable to collect bundled Electron runtime versions for RD-18 provenance.');
  }

  let versions;
  try {
    versions = JSON.parse(result.stdout.trim().split(/\r?\n/u).at(-1) ?? '');
  } catch {
    throw new Error('Bundled Electron runtime version output was not valid JSON.');
  }

  return {
    electron: assertRuntimeVersion(versions.electron, 'electron'),
    node: assertRuntimeVersion(versions.node, 'node'),
    chrome: assertRuntimeVersion(versions.chrome, 'chrome'),
    v8: assertRuntimeVersion(versions.v8, 'v8'),
    modules: assertRuntimeVersion(versions.modules, 'modules'),
    napi: assertRuntimeVersion(versions.napi, 'napi'),
  };
}

export async function packageWindowsInternal(options = {}) {
  if (options.allowNonWindowsForTest !== true) {
    assertWindowsX64Runtime(options.runtimePlatform);
  }

  const root = options.root ?? repoRoot;
  const metadata = loadPackageMetadata(root);
  const runtimeVersions = options.runtimeVersions ?? collectRuntimeVersions(root);
  if (runtimeVersions.electron !== undefined && runtimeVersions.electron !== metadata.electronVersion) {
    throw new Error('Bundled Electron runtime version does not match package-lock electron version.');
  }
  const runtimeDir = options.runtimeDir ?? resolveElectronRuntimeDir(root);
  const { packageRoot } = buildInternalPackagePaths({ root, outRoot: options.outRoot });

  await stagePackage({
    root,
    packageRoot,
    runtimeDir,
    metadata,
    runtimeVersions,
  });

  return {
    packageRoot,
    manifestPath: path.join(packageRoot, PROVENANCE_RELATIVE_PATH),
  };
}

export async function stagePackage({ root, packageRoot, runtimeDir, metadata, runtimeVersions }) {
  const distRoot = path.join(root, 'dist');
  assertDirectoryExists(runtimeDir, 'Electron runtime directory');
  assertDirectoryExists(distRoot, 'dist directory');
  assertFileExists(path.join(runtimeDir, 'electron.exe'), 'Electron Windows runtime executable');
  assertFileExists(path.join(distRoot, 'main/index.js'), 'Electron main build output');

  fs.rmSync(packageRoot, { recursive: true, force: true });
  fs.mkdirSync(packageRoot, { recursive: true });

  copyDirectory(runtimeDir, packageRoot, {
    renameFiles: new Map([['electron.exe', 'LineupDesktop.exe']]),
    skipFile: (relativePath) => relativePath.endsWith('.asar'),
  });

  const appRoot = path.join(packageRoot, 'resources/app');
  fs.mkdirSync(appRoot, { recursive: true });
  copyDirectory(distRoot, path.join(appRoot, 'dist'));

  writeJson(path.join(packageRoot, APP_PACKAGE_RELATIVE_PATH), createStagedAppPackage(metadata));
  writeText(path.join(packageRoot, NATIVE_HELPER_BLOCKED_RELATIVE_PATH), [
    'Production native helper packaging is blocked for RD-18 Unit 1.',
    'No local RD-06 prerequisite binaries are redistributed in this internal layout.',
    '',
  ].join('\n'));
  writeText(path.join(packageRoot, MEDIA_BINARIES_BLOCKED_RELATIVE_PATH), [
    'Media binary redistribution is blocked for RD-18 Unit 1.',
    'mpv and libmpv binaries are intentionally absent from this internal layout.',
    '',
  ].join('\n'));
  writeJson(path.join(packageRoot, NOTICES_RELATIVE_PATH), createInternalNotices(metadata));

  const buildInputChecksums = buildInputChecksumManifest(root);
  const preManifestArtifactChecksums = computeArtifactChecksums(packageRoot, {
    exclude: new Set([PROVENANCE_RELATIVE_PATH, CHECKSUMS_RELATIVE_PATH]),
  });
  writeJson(
    path.join(packageRoot, PROVENANCE_RELATIVE_PATH),
    createProvenanceManifest({
      metadata,
      runtimeVersions,
      buildInputChecksums,
      artifactFileChecksums: preManifestArtifactChecksums,
    }),
  );

  const checksumRows = computeArtifactChecksums(packageRoot, {
    exclude: new Set([CHECKSUMS_RELATIVE_PATH]),
  });
  writeText(path.join(packageRoot, CHECKSUMS_RELATIVE_PATH), formatChecksumRows(checksumRows));
}

export function buildInputChecksumManifest(root = repoRoot) {
  const files = [
    'package.json',
    'package-lock.json',
    'tsconfig.electron.json',
    'tools/clean-electron-build.mjs',
    'tools/copy-renderer-assets.mjs',
    'tools/smoke-electron.mjs',
  ];

  return files.map((relativePath) => ({
    path: normalizeRelativePath(relativePath),
    sha256: hashFile(path.join(root, relativePath)),
  }));
}

export function computeArtifactChecksums(packageRoot, options = {}) {
  const exclude = options.exclude ?? new Set();
  return listFiles(packageRoot)
    .filter((relativePath) => !exclude.has(relativePath))
    .map((relativePath) => ({
      path: relativePath,
      sha256: hashFile(path.join(packageRoot, relativePath)),
    }));
}

export function formatChecksumRows(rows) {
  return `${rows.map((row) => `${row.sha256}  ${row.path}`).join('\n')}\n`;
}

export function parseChecksumRows(content) {
  const rows = [];
  for (const line of content.split(/\r?\n/u)) {
    if (line.trim() === '') {
      continue;
    }
    const match = /^(?<sha256>[a-f0-9]{64})[ ]{2}(?<path>[^\r\n]+)$/u.exec(line);
    if (!match?.groups) {
      throw new Error(`Invalid checksum row: ${line}`);
    }
    if (
      path.isAbsolute(match.groups.path) ||
      match.groups.path.includes('\\') ||
      match.groups.path.includes('..')
    ) {
      throw new Error(`Invalid checksum row: ${line}`);
    }
    rows.push({
      path: match.groups.path,
      sha256: match.groups.sha256,
    });
  }
  return rows;
}

export function listFiles(root) {
  const files = [];
  walkFiles(root, root, files);
  return files.sort();
}

export function normalizeRelativePath(value) {
  return value.split(path.sep).join('/');
}

function copyDirectory(source, destination, options = {}, relativeRoot = '') {
  fs.mkdirSync(destination, { recursive: true });
  for (const entry of fs.readdirSync(source, { withFileTypes: true })) {
    if (entry.isSymbolicLink()) {
      throw new Error(`Refusing to stage symlink: ${entry.name}`);
    }
    const sourcePath = path.join(source, entry.name);
    const entryRelativePath = normalizeRelativePath(path.join(relativeRoot, entry.name));
    const destinationName = options.renameFiles?.get(entry.name) ?? entry.name;
    const destinationPath = path.join(destination, destinationName);
    if (entry.isDirectory()) {
      copyDirectory(sourcePath, destinationPath, options, entryRelativePath);
      continue;
    }
    if (entry.isFile()) {
      if (options.skipFile?.(entryRelativePath) === true) {
        continue;
      }
      fs.copyFileSync(sourcePath, destinationPath);
    }
  }
}

function walkFiles(root, directory, files) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (entry.isSymbolicLink()) {
      throw new Error(`Refusing to inspect symlink in package output: ${entry.name}`);
    }
    const absolutePath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      walkFiles(root, absolutePath, files);
      continue;
    }
    if (entry.isFile()) {
      files.push(normalizeRelativePath(path.relative(root, absolutePath)));
    }
  }
}

function hashFile(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function writeJson(filePath, value) {
  writeText(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function writeText(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, Buffer.from(content, 'utf8'));
}

function assertDirectoryExists(directoryPath, label) {
  if (!fs.statSync(directoryPath, { throwIfNoEntry: false })?.isDirectory()) {
    throw new Error(`${label} is missing: ${directoryPath}`);
  }
}

function assertFileExists(filePath, label) {
  if (!fs.statSync(filePath, { throwIfNoEntry: false })?.isFile()) {
    throw new Error(`${label} is missing: ${filePath}`);
  }
}

function assertRuntimeVersion(value, label) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`Bundled Electron runtime version is missing: ${label}`);
  }
  return value;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    assertWindowsX64Runtime();
    const { outRoot } = parsePackageArgs(process.argv.slice(2));
    const { packageRoot } = await packageWindowsInternal({ outRoot });
    console.log(`RD-18 internal Windows package staged: ${path.relative(repoRoot, packageRoot)}`);
  } catch (error) {
    console.error(error instanceof Error ? error.message : 'RD-18 internal packaging failed.');
    process.exit(1);
  }
}
