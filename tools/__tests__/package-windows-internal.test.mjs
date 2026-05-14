import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  APP_PACKAGE_RELATIVE_PATH,
  CHECKSUMS_RELATIVE_PATH,
  MEDIA_BINARIES_BLOCKED_RELATIVE_PATH,
  NATIVE_HELPER_BLOCKED_RELATIVE_PATH,
  NOTICES_RELATIVE_PATH,
  PACKAGE_DIRECTORY_NAME,
  PROVENANCE_RELATIVE_PATH,
  assertWindowsX64Runtime,
  buildInputChecksumManifest,
  buildInternalPackagePaths,
  collectRuntimeVersions,
  collectRuntimeVersionsFromDir,
  computeArtifactChecksums,
  createStagedAppPackage,
  formatChecksumRows,
  parseChecksumRows,
  parsePackageArgs,
  packageWindowsInternal,
} from '../package-windows-internal.mjs';
import {
  parseVerifyArgs,
  verifyWindowsInternalPackage,
} from '../verify-windows-internal-package.mjs';

test('packaging CLI parser defaults to the reviewed RD-18 output root', () => {
  assert.deepEqual(parsePackageArgs([]), {
    outRoot: 'out/rd-18-windows-internal',
  });
  assert.deepEqual(parsePackageArgs(['--out', 'out/rd-18-windows-internal']), {
    outRoot: 'out/rd-18-windows-internal',
  });
  assert.throws(() => parsePackageArgs(['--out']), /--out out\/rd-18-windows-internal/u);
  assert.throws(
    () => parsePackageArgs(['--out', 'out/custom']),
    /output root must be exactly out\/rd-18-windows-internal/u,
  );
  assert.throws(
    () => buildInternalPackagePaths({ outRoot: '../rd-18-windows-internal' }),
    /output root must be exactly out\/rd-18-windows-internal/u,
  );
});

test('packaging CLI refuses to claim Windows x64 output off Windows x64', () => {
  assert.doesNotThrow(() => assertWindowsX64Runtime({ platform: 'win32', arch: 'x64' }));
  assert.throws(
    () => assertWindowsX64Runtime({ platform: 'darwin', arch: 'arm64' }),
    /Windows x64/u,
  );
});

test('packageWindowsInternal refuses real package generation off Windows x64 by default', async () => {
  await assert.rejects(
    () => packageWindowsInternal({ runtimePlatform: { platform: 'darwin', arch: 'arm64' } }),
    /Windows x64/u,
  );
});

test('staged app package manifest has only reviewed metadata and entrypoint', () => {
  const staged = createStagedAppPackage({
    app: {
      name: 'lineup-desktop',
      version: '0.0.0',
      license: 'Apache-2.0',
      type: 'module',
    },
  });

  assert.deepEqual(staged, {
    name: 'lineup-desktop',
    version: '0.0.0',
    license: 'Apache-2.0',
    type: 'module',
    main: 'dist/main/index.js',
  });
  assert.equal(Object.hasOwn(staged, 'dependencies'), false);
});

test('collectRuntimeVersions reads bundled Electron process versions', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-rd18-runtime-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));

  const electronDist = path.join(root, 'node_modules/electron/dist');
  const expectedVersions = {
    electron: '42.0.0',
    node: '24.15.0',
    chrome: '148.0.7778.96',
    v8: '14.8.178.14-electron.0',
    modules: '146',
    napi: '10',
  };
  const preloadPath = createNodeBackedElectronRuntime(electronDist, expectedVersions);

  withTemporaryNodeOptions(preloadPath, () => {
    assert.deepEqual(collectRuntimeVersions(root), expectedVersions);
    assert.deepEqual(collectRuntimeVersionsFromDir(electronDist), expectedVersions);
  });
});

test('collectRuntimeVersions includes child-process diagnostics on probe failures', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-rd18-runtime-failure-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));

  const runtimeDir = path.join(root, 'runtime');
  const preloadPath = createNodeBackedElectronRuntime(runtimeDir, undefined, [
    'console.error("runtime probe exploded");',
    'process.exit(7);',
  ]);

  withTemporaryNodeOptions(preloadPath, () => {
    assert.throws(
      () => collectRuntimeVersionsFromDir(runtimeDir),
      /Unable to collect bundled Electron runtime versions.*status=7.*stderrLastLine=runtime probe exploded/u,
    );
  });
});

test('collectRuntimeVersions includes stdout and stderr diagnostics on invalid JSON', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-rd18-runtime-json-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));

  const runtimeDir = path.join(root, 'runtime');
  const preloadPath = createNodeBackedElectronRuntime(runtimeDir, {
    electron: '42.0.0',
    node: '24.15.0',
    chrome: '148.0.7778.96',
    v8: '14.8.178.14-electron.0',
    modules: '146',
    napi: '10',
  }, [
    'console.error("json probe stderr context");',
    'JSON.stringify = () => "not-json";',
  ]);

  withTemporaryNodeOptions(preloadPath, () => {
    assert.throws(
      () => collectRuntimeVersionsFromDir(runtimeDir),
      /Bundled Electron runtime version output was not valid JSON.*stdout=.*not-json.*stderr=.*json probe stderr context/u,
    );
  });
});

test('packageWindowsInternal rejects Electron runtime version drift', async (t) => {
  const root = makeFixtureRepo(t);

  await assert.rejects(() => packageWindowsInternal({
    root,
    allowNonWindowsForTest: true,
    runtimeVersions: {
      electron: '41.0.0',
      node: '24.15.0',
      chrome: '148.0.7778.96',
      v8: '14.8.178.14-electron.0',
      modules: '146',
      napi: '10',
    },
  }), /does not match package-lock/u);
});

test('build input checksums include the packaging tool that defines provenance', () => {
  const manifest = buildInputChecksumManifest();
  assert(manifest.some((row) => row.path === 'tools/package-windows-internal.mjs'));
});

test('checksum parser and formatter keep deterministic normalized paths', () => {
  const rows = [
    { path: 'LineupDesktop.exe', sha256: 'a'.repeat(64) },
    { path: 'resources/app/package.json', sha256: 'b'.repeat(64) },
  ];

  assert.deepEqual(parseChecksumRows(formatChecksumRows(rows)), rows);
  assert.throws(
    () => parseChecksumRows(String.raw`${'a'.repeat(64)}  resources\app\package.json`),
    /Invalid checksum row/u,
  );
  assert.throws(
    () => parseChecksumRows(`${'a'.repeat(64)}  resources/../package.json`),
    /Invalid checksum row/u,
  );
  assert.throws(
    () => parseChecksumRows(`${'a'.repeat(64)}  C:/package.json`),
    /Invalid checksum row/u,
  );
});

test('packageWindowsInternal stages the reviewed layout with a fake Windows runtime', async (t) => {
  const root = makeFixtureRepo(t);
  const runtimeDir = path.join(root, 'fake-electron-runtime');
  fs.mkdirSync(path.join(runtimeDir, 'resources'), { recursive: true });
  fs.writeFileSync(path.join(runtimeDir, 'electron.exe'), 'fake exe');
  fs.writeFileSync(path.join(runtimeDir, 'version'), '42.0.0');
  fs.writeFileSync(path.join(runtimeDir, 'LICENSE'), 'runtime license');
  fs.writeFileSync(path.join(runtimeDir, 'resources/default_app.asar'), 'default app');

  const result = await packageWindowsInternal({
    root,
    allowNonWindowsForTest: true,
    outRoot: 'out/rd-18-windows-internal',
    runtimeDir,
    runtimeVersions: {
      node: '24.15.0',
      chrome: '148.0.7778.96',
      v8: '14.8.178.14-electron.0',
      modules: '146',
      napi: '10',
    },
  });

  const { packageRoot } = buildInternalPackagePaths({
    root,
    outRoot: 'out/rd-18-windows-internal',
  });
  assert.equal(result.packageRoot, packageRoot);
  assert.equal(path.basename(packageRoot), PACKAGE_DIRECTORY_NAME);
  assert.equal(fs.existsSync(path.join(packageRoot, 'LineupDesktop.exe')), true);
  assert.equal(fs.existsSync(path.join(packageRoot, 'electron.exe')), false);
  assert.equal(fs.existsSync(path.join(packageRoot, 'resources/default_app.asar')), false);
  assert.equal(fs.existsSync(path.join(packageRoot, 'resources/app/dist/main/index.js')), true);
  assert.equal(fs.existsSync(path.join(packageRoot, 'resources/app/dist/renderer/index.html')), true);
  assert.equal(fs.existsSync(path.join(packageRoot, NATIVE_HELPER_BLOCKED_RELATIVE_PATH)), true);
  assert.equal(fs.existsSync(path.join(packageRoot, MEDIA_BINARIES_BLOCKED_RELATIVE_PATH)), true);
  assert.equal(fs.existsSync(path.join(packageRoot, PROVENANCE_RELATIVE_PATH)), true);
  assert.equal(fs.existsSync(path.join(packageRoot, CHECKSUMS_RELATIVE_PATH)), true);
  assert.equal(fs.existsSync(path.join(packageRoot, NOTICES_RELATIVE_PATH)), true);

  const appPackage = readJson(path.join(packageRoot, 'resources/app/package.json'));
  assert.deepEqual(appPackage, {
    name: 'lineup-desktop',
    version: '0.0.0',
    license: 'Apache-2.0',
    type: 'module',
    main: 'dist/main/index.js',
  });

  const checksumRows = parseChecksumRows(fs.readFileSync(path.join(packageRoot, CHECKSUMS_RELATIVE_PATH), 'utf8'));
  assert.deepEqual(
    formatChecksumRows(checksumRows),
    formatChecksumRows(computeArtifactChecksums(packageRoot, { exclude: new Set([CHECKSUMS_RELATIVE_PATH]) })),
  );
  assert(checksumRows.every((row) => !path.isAbsolute(row.path) && !row.path.includes('\\')));

  const provenance = readJson(path.join(packageRoot, PROVENANCE_RELATIVE_PATH));
  assert.equal(provenance.runtime.electron, '42.0.0');
  assert.equal(provenance.lockfile.packageCount, 2);
  assert.equal(provenance.packageLayout.asar, false);
  assert.equal(provenance.mediaBinariesStatus.rd06LocalPrerequisitesCopied, false);
  assert(provenance.buildInputChecksums.some((row) => row.path === 'tools/package-windows-internal.mjs'));

  assert.deepEqual(verifyWindowsInternalPackage({
    root,
    packageRoot,
    manifestPath: path.join(packageRoot, PROVENANCE_RELATIVE_PATH),
  }), []);
});

test('verifier rejects package roots outside the reviewed RD-18 output path', async (t) => {
  const { root, packageRoot } = await makeVerifiedPackage(t);
  const unapprovedRoot = path.join(root, 'out/custom', PACKAGE_DIRECTORY_NAME);
  fs.cpSync(packageRoot, unapprovedRoot, { recursive: true });

  const errors = verifyWindowsInternalPackage({
    root,
    packageRoot: unapprovedRoot,
    manifestPath: path.join(unapprovedRoot, PROVENANCE_RELATIVE_PATH),
  });

  assert(errors.some((error) => error.includes('Package root must be exactly out/rd-18-windows-internal')));
});

test('verifier rejects alternate layouts app.asar and copied native/media binaries', async (t) => {
  const { root, packageRoot } = await makeVerifiedPackage(t);

  fs.writeFileSync(path.join(packageRoot, 'resources/app.asar'), 'blocked');
  fs.rmSync(path.join(packageRoot, NATIVE_HELPER_BLOCKED_RELATIVE_PATH));
  fs.writeFileSync(path.join(packageRoot, 'resources/native-helper/libmpv.dll'), 'blocked');
  fs.rmSync(path.join(packageRoot, MEDIA_BINARIES_BLOCKED_RELATIVE_PATH));
  fs.writeFileSync(path.join(packageRoot, 'resources/media-binaries/mpv.exe'), 'blocked');

  const errors = verifyWindowsInternalPackage({
    root,
    packageRoot,
    manifestPath: path.join(packageRoot, PROVENANCE_RELATIVE_PATH),
  });

  assert(errors.some((error) => error.includes('.asar')));
  assert(errors.some((error) => error.includes('resources/native-helper must contain only')));
  assert(errors.some((error) => error.includes('resources/media-binaries must contain only')));
  assert(errors.some((error) => error.includes('forbidden native/media binary-looking file')));
});

test('verifier rejects mpv and native media binaries anywhere in the package', async (t) => {
  const { root, packageRoot } = await makeVerifiedPackage(t);
  fs.mkdirSync(path.join(packageRoot, 'resources/app/dist/renderer/bin'), { recursive: true });
  fs.writeFileSync(path.join(packageRoot, 'resources/app/dist/renderer/bin/mpv.exe'), 'blocked');
  fs.writeFileSync(path.join(packageRoot, 'resources/app/dist/renderer/bin/libmpv.dll'), 'blocked');
  fs.writeFileSync(path.join(packageRoot, 'resources/app/dist/renderer/bin/native-media.node'), 'blocked');

  const errors = verifyWindowsInternalPackage({
    root,
    packageRoot,
    manifestPath: path.join(packageRoot, PROVENANCE_RELATIVE_PATH),
  });

  assert(errors.some((error) => error.includes('resources/app/dist/renderer/bin/mpv.exe')));
  assert(errors.some((error) => error.includes('resources/app/dist/renderer/bin/libmpv.dll')));
  assert(errors.some((error) => error.includes('resources/app/dist/renderer/bin/native-media.node')));
});

test('verifier rejects checksum drift and redaction-unsafe generated evidence', async (t) => {
  const { root, packageRoot } = await makeVerifiedPackage(t);
  fs.writeFileSync(
    path.join(packageRoot, NOTICES_RELATIVE_PATH),
    [
      '{',
      `  "${['client', 'Secret'].join('')}": "abc12345"`,
      '}',
      '',
    ].join('\n'),
  );

  const errors = verifyWindowsInternalPackage({
    root,
    packageRoot,
    manifestPath: path.join(packageRoot, PROVENANCE_RELATIVE_PATH),
  });

  assert(errors.some((error) => error.includes('checksums.sha256 must match')));
  assert(errors.some((error) => error.includes('redaction-safe')));
});

test('verifier validates provenance artifact checksums against staged files', async (t) => {
  const { root, packageRoot } = await makeVerifiedPackage(t);
  const provenancePath = path.join(packageRoot, PROVENANCE_RELATIVE_PATH);
  const provenance = readJson(provenancePath);
  provenance.artifactFileChecksums = [
    { path: 'LineupDesktop.exe', sha256: '0'.repeat(64) },
  ];
  fs.writeFileSync(provenancePath, `${JSON.stringify(provenance, null, 2)}\n`);
  rewriteChecksumManifest(packageRoot);

  const errors = verifyWindowsInternalPackage({
    root,
    packageRoot,
    manifestPath: path.join(packageRoot, PROVENANCE_RELATIVE_PATH),
  });

  assert(errors.some((error) => error.includes('Provenance artifactFileChecksums must match staged package files')));
  assert.equal(errors.some((error) => error.includes('checksums.sha256 must match')), false);
});

test('verifier reports package output symlinks without continuing checksum traversal', async (t) => {
  const { root, packageRoot } = await makeVerifiedPackage(t);
  const linkPath = path.join(packageRoot, 'linked-exe');
  try {
    fs.symlinkSync(path.join(packageRoot, 'LineupDesktop.exe'), linkPath, 'file');
  } catch (error) {
    t.skip(`symlink creation unavailable: ${error instanceof Error ? error.message : String(error)}`);
    return;
  }

  const errors = verifyWindowsInternalPackage({
    root,
    packageRoot,
    manifestPath: path.join(packageRoot, PROVENANCE_RELATIVE_PATH),
  });

  assert.deepEqual(errors, ['Refusing to inspect symlink in package output: linked-exe']);
});

test('packageWindowsInternal records runtime versions from the staged runtime directory', async (t) => {
  const root = makeFixtureRepo(t);
  const defaultRuntimeDir = path.join(root, 'node_modules/electron/dist');
  const stagedRuntimeDir = path.join(root, 'staged-electron-runtime');
  createNodeBackedElectronRuntime(defaultRuntimeDir);
  createNodeBackedElectronRuntime(stagedRuntimeDir);
  const preloadPath = path.join(root, 'runtime-version-router.cjs');
  fs.writeFileSync(preloadPath, [
    'const defaultVersions = {',
    '  electron: "41.0.0",',
    '  node: "23.0.0",',
    '  chrome: "147.0.0.0",',
    '  v8: "13.0.0",',
    '  modules: "145",',
    '  napi: "9",',
    '};',
    'const stagedVersions = {',
    '  electron: "42.0.0",',
    '  node: "24.15.0",',
    '  chrome: "148.0.7778.96",',
    '  v8: "14.8.178.14-electron.0",',
    '  modules: "146",',
    '  napi: "10",',
    '};',
    'const versions = process.execPath.includes("staged-electron-runtime") ? stagedVersions : defaultVersions;',
    'for (const [key, value] of Object.entries(versions)) {',
    '  Object.defineProperty(process.versions, key, {',
    '    value,',
    '    enumerable: true,',
    '    configurable: true,',
    '  });',
    '}',
    '',
  ].join('\n'));
  const stagedVersions = {
    electron: '42.0.0',
    node: '24.15.0',
    chrome: '148.0.7778.96',
    v8: '14.8.178.14-electron.0',
    modules: '146',
    napi: '10',
  };

  await withTemporaryNodeOptions(preloadPath, async () => {
    const result = await packageWindowsInternal({
      root,
      allowNonWindowsForTest: true,
      runtimeDir: stagedRuntimeDir,
    });

    const provenance = readJson(result.manifestPath);
    assert.deepEqual(provenance.runtime, stagedVersions);
  });
});

test('verifier rejects staged app package metadata drift after generated manifests are refreshed', async (t) => {
  const { root, packageRoot } = await makeVerifiedPackage(t);
  const appPackagePath = path.join(packageRoot, APP_PACKAGE_RELATIVE_PATH);
  const appPackage = readJson(appPackagePath);
  appPackage.version = '9.9.9';
  fs.writeFileSync(appPackagePath, `${JSON.stringify(appPackage, null, 2)}\n`);
  rewriteGeneratedManifests(packageRoot);

  const errors = verifyWindowsInternalPackage({
    root,
    packageRoot,
    manifestPath: path.join(packageRoot, PROVENANCE_RELATIVE_PATH),
  });

  assert(errors.some((error) => error.includes('resources/app/package.json version must match root package.json')));
  assert.equal(errors.some((error) => error.includes('checksums.sha256 must match')), false);
  assert.equal(errors.some((error) => error.includes('Provenance artifactFileChecksums must match')), false);
});

test('verifier rejects traversal paths in provenance checksum arrays', async (t) => {
  const { root, packageRoot } = await makeVerifiedPackage(t);
  const provenancePath = path.join(packageRoot, PROVENANCE_RELATIVE_PATH);
  const provenance = readJson(provenancePath);
  provenance.buildInputChecksums = [
    { path: 'tools/../package-windows-internal.mjs', sha256: 'a'.repeat(64) },
  ];
  provenance.artifactFileChecksums = [
    { path: 'resources/../LineupDesktop.exe', sha256: 'b'.repeat(64) },
  ];
  fs.writeFileSync(provenancePath, `${JSON.stringify(provenance, null, 2)}\n`);
  rewriteChecksumManifest(packageRoot);

  const errors = verifyWindowsInternalPackage({
    root,
    packageRoot,
    manifestPath: path.join(packageRoot, PROVENANCE_RELATIVE_PATH),
  });

  assert(errors.some((error) => (
    error.includes('Provenance buildInputChecksums paths must be normalized and relative.')
  )));
  assert(errors.some((error) => (
    error.includes('Provenance artifactFileChecksums paths must be normalized and relative.')
  )));
  assert.equal(errors.some((error) => error.includes('Unable to read provenance manifest.')), false);
});

test('verifier reports malformed provenance JSON once', async (t) => {
  const { root, packageRoot } = await makeVerifiedPackage(t);
  fs.writeFileSync(path.join(packageRoot, PROVENANCE_RELATIVE_PATH), '{not-json\n');

  const errors = verifyWindowsInternalPackage({
    root,
    packageRoot,
    manifestPath: path.join(packageRoot, PROVENANCE_RELATIVE_PATH),
  });

  assert.equal(errors.filter((error) => error === 'Unable to read provenance manifest.').length, 1);
});

test('verifier rejects signing certificate and private key material in generated evidence', async (t) => {
  const { root, packageRoot } = await makeVerifiedPackage(t);
  const provenancePath = path.join(packageRoot, PROVENANCE_RELATIVE_PATH);
  const provenance = readJson(provenancePath);
  provenance.publicReleaseBlockedProof = {
    signingPassword: 'not-for-rd18-unit1',
    certificatePath: 'C:\\Users\\example\\certificates\\release.pfx',
    privateKey: '-----BEGIN PRIVATE KEY-----',
  };
  fs.writeFileSync(provenancePath, `${JSON.stringify(provenance, null, 2)}\n`);
  rewriteChecksumManifest(packageRoot);

  const errors = verifyWindowsInternalPackage({
    root,
    packageRoot,
    manifestPath: path.join(packageRoot, PROVENANCE_RELATIVE_PATH),
  });

  assert(errors.some((error) => error.includes('Generated package evidence must not contain signing material')));
  assert.equal(errors.some((error) => error.includes('checksums.sha256 must match')), false);
});

test('verifier rejects certificate PEM material in refreshed generated provenance', async (t) => {
  const { root, packageRoot } = await makeVerifiedPackage(t);
  const provenancePath = path.join(packageRoot, PROVENANCE_RELATIVE_PATH);
  const provenance = readJson(provenancePath);
  provenance.publicReleaseBlockedProof = {
    certificatePem: [
      '-----BEGIN CERTIFICATE-----',
      'MIIFakeCertificateMaterialForRd18VerifierCoverage=',
      '-----END CERTIFICATE-----',
    ].join('\n'),
  };
  fs.writeFileSync(provenancePath, `${JSON.stringify(provenance, null, 2)}\n`);
  rewriteChecksumManifest(packageRoot);

  const errors = verifyWindowsInternalPackage({
    root,
    packageRoot,
    manifestPath: path.join(packageRoot, PROVENANCE_RELATIVE_PATH),
  });

  const signingMaterialError = errors.find((error) => (
    error.includes('Generated package evidence must not contain signing material') &&
    error.includes(PROVENANCE_RELATIVE_PATH)
  ));
  assert(signingMaterialError);
  assert.match(signingMaterialError, /certificate-field/u);
  assert.match(signingMaterialError, /certificate-pem-block/u);
  assert.equal(errors.some((error) => error.includes('checksums.sha256 must match')), false);
  assert.equal(errors.some((error) => error.includes('Provenance artifactFileChecksums must match')), false);
});

test('verifier rejects encrypted private-key PEM material in refreshed generated provenance', async (t) => {
  const { root, packageRoot } = await makeVerifiedPackage(t);
  const provenancePath = path.join(packageRoot, PROVENANCE_RELATIVE_PATH);
  const provenance = readJson(provenancePath);
  provenance.publicReleaseBlockedProof = {
    releaseAuditNote: [
      '-----BEGIN ENCRYPTED PRIVATE KEY-----',
      'MIIFakeEncryptedPrivateKeyMaterialForRd18VerifierCoverage=',
      '-----END ENCRYPTED PRIVATE KEY-----',
    ].join('\n'),
  };
  fs.writeFileSync(provenancePath, `${JSON.stringify(provenance, null, 2)}\n`);
  rewriteGeneratedManifests(packageRoot);

  const errors = verifyWindowsInternalPackage({
    root,
    packageRoot,
    manifestPath: path.join(packageRoot, PROVENANCE_RELATIVE_PATH),
  });

  const signingMaterialError = errors.find((error) => (
    error.includes('Generated package evidence must not contain signing material') &&
    error.includes(PROVENANCE_RELATIVE_PATH)
  ));
  assert(signingMaterialError);
  assert.match(signingMaterialError, /private-key-field/u);
  assert.equal(errors.some((error) => error.includes('checksums.sha256 must match')), false);
  assert.equal(errors.some((error) => error.includes('Provenance artifactFileChecksums must match')), false);
});

test('verifier CLI parser requires package and manifest arguments', () => {
  assert.deepEqual(parseVerifyArgs(['--package', 'pkg', '--manifest', 'pkg/resources/provenance.json']), {
    packageRoot: 'pkg',
    manifestPath: 'pkg/resources/provenance.json',
  });
  assert.throws(() => parseVerifyArgs(['--package', 'pkg']), /--package <package-root>/u);
});

async function makeVerifiedPackage(t) {
  const root = makeFixtureRepo(t);
  const runtimeDir = path.join(root, 'runtime');
  fs.mkdirSync(runtimeDir, { recursive: true });
  fs.writeFileSync(path.join(runtimeDir, 'electron.exe'), 'fake exe');
  fs.writeFileSync(path.join(runtimeDir, 'version'), '42.0.0');

  const packageResult = await packageWindowsInternal({
    root,
    allowNonWindowsForTest: true,
    runtimeDir,
    runtimeVersions: {
      node: '24.15.0',
      chrome: '148.0.7778.96',
      v8: '14.8.178.14-electron.0',
      modules: '146',
      napi: '10',
    },
  });
  return {
    root,
    ...packageResult,
  };
}

function rewriteChecksumManifest(packageRoot) {
  const checksumRows = computeArtifactChecksums(packageRoot, {
    exclude: new Set([CHECKSUMS_RELATIVE_PATH]),
  });
  fs.writeFileSync(path.join(packageRoot, CHECKSUMS_RELATIVE_PATH), formatChecksumRows(checksumRows));
}

function rewriteGeneratedManifests(packageRoot) {
  const provenancePath = path.join(packageRoot, PROVENANCE_RELATIVE_PATH);
  const provenance = readJson(provenancePath);
  provenance.artifactFileChecksums = computeArtifactChecksums(packageRoot, {
    exclude: new Set([PROVENANCE_RELATIVE_PATH, CHECKSUMS_RELATIVE_PATH]),
  });
  fs.writeFileSync(provenancePath, `${JSON.stringify(provenance, null, 2)}\n`);
  rewriteChecksumManifest(packageRoot);
}

function makeFixtureRepo(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-rd18-package-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));

  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({
    name: 'lineup-desktop',
    version: '0.0.0',
    license: 'Apache-2.0',
    type: 'module',
  }));
  fs.writeFileSync(path.join(root, 'package-lock.json'), JSON.stringify({
    lockfileVersion: 3,
    packages: {
      '': {},
      'node_modules/electron': {
        version: '42.0.0',
      },
    },
  }));
  fs.writeFileSync(path.join(root, 'tsconfig.electron.json'), '{}');
  fs.mkdirSync(path.join(root, 'tools'), { recursive: true });
  for (const tool of [
    'package-windows-internal.mjs',
    'clean-electron-build.mjs',
    'copy-renderer-assets.mjs',
    'smoke-electron.mjs',
  ]) {
    fs.writeFileSync(path.join(root, 'tools', tool), `// ${tool}\n`);
  }
  fs.mkdirSync(path.join(root, 'dist/main'), { recursive: true });
  fs.mkdirSync(path.join(root, 'dist/renderer/styles'), { recursive: true });
  fs.writeFileSync(path.join(root, 'dist/main/index.js'), 'console.log("main");\n');
  fs.writeFileSync(path.join(root, 'dist/renderer/index.html'), '<!doctype html>\n');
  fs.writeFileSync(path.join(root, 'dist/renderer/styles.css'), '@import "./styles/base.css";\n');
  fs.writeFileSync(path.join(root, 'dist/renderer/styles/base.css'), ':root { color: white; }\n');

  return root;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function createNodeBackedElectronRuntime(runtimeDir, versions, extraPreloadLines = []) {
  fs.mkdirSync(runtimeDir, { recursive: true });
  const executablePath = path.join(runtimeDir, 'electron.exe');
  fs.copyFileSync(process.execPath, executablePath);
  fs.chmodSync(executablePath, 0o755);

  const preloadPath = path.join(runtimeDir, 'electron-runtime-preload.cjs');
  const versionLines = versions
    ? [
        `const versions = ${JSON.stringify(versions)};`,
        'for (const [key, value] of Object.entries(versions)) {',
        '  Object.defineProperty(process.versions, key, {',
        '    value,',
        '    enumerable: true,',
        '    configurable: true,',
        '  });',
        '}',
      ]
    : [];
  fs.writeFileSync(preloadPath, [
    ...versionLines,
    ...extraPreloadLines,
    '',
  ].join('\n'));

  return preloadPath;
}

function withTemporaryNodeOptions(preloadPaths, callback) {
  const previous = process.env.NODE_OPTIONS;
  const paths = Array.isArray(preloadPaths) ? preloadPaths : [preloadPaths];
  const preloadOptions = paths.map((preloadPath) => `--require ${JSON.stringify(preloadPath)}`).join(' ');
  process.env.NODE_OPTIONS = previous ? `${previous} ${preloadOptions}` : preloadOptions;

  const restore = () => {
    if (previous === undefined) {
      delete process.env.NODE_OPTIONS;
    } else {
      process.env.NODE_OPTIONS = previous;
    }
  };

  try {
    const result = callback();
    if (result && typeof result.then === 'function') {
      return result.finally(restore);
    }
    restore();
    return result;
  } catch (error) {
    restore();
    throw error;
  }
}
