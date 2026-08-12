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
  runCleanElectronBuild,
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

test('collectRuntimeVersions probes the bundled Electron runtime with a sanitized Node environment', () => {
  const root = path.join(path.sep, 'fixture-runtime-root');
  const electronDist = path.join(root, 'node_modules/electron/dist');
  const expectedVersions = {
    electron: '42.0.0',
    node: '24.15.0',
    chrome: '148.0.7778.96',
    v8: '14.8.178.14-electron.0',
    modules: '146',
    napi: '10',
  };
  const invocations = [];
  const spawnSyncForTest = (...args) => {
    invocations.push(args);
    return {
      error: undefined,
      signal: null,
      status: 0,
      stdout: `${JSON.stringify(expectedVersions)}\n`,
      stderr: '',
    };
  };

  withTemporaryEnvironmentVariables({
    NODE_OPTIONS: '--require /hostile-preload.cjs',
    Node_Options: '--require /duplicate-hostile-preload.cjs',
    npm_config_node_options: '--trace-warnings',
    NPM_CONFIG_NODE_OPTIONS: '--require /duplicate-hostile-npm-preload.cjs',
    npm_config_script_shell: '/hostile-script-shell',
    Npm_Config_Script_Shell: '/duplicate-hostile-script-shell',
    npm_execpath: '/hostile-npm-cli.js',
    NPM_EXECPATH: '/duplicate-hostile-npm-cli.js',
    npm_node_execpath: '/hostile-node',
    Npm_Node_ExecPath: '/duplicate-hostile-node',
  }, () => {
    assert.deepEqual(collectRuntimeVersions(root, { spawnSyncForTest }), expectedVersions);
    assert.deepEqual(
      collectRuntimeVersionsFromDir(electronDist, { spawnSyncForTest }),
      expectedVersions,
    );
  });

  assert.equal(invocations.length, 2);
  for (const [executable, args, options] of invocations) {
    assert.equal(executable, path.join(electronDist, 'electron.exe'));
    assert.equal(args[0], '-p');
    assert.match(args[1], /process\.versions\.electron/u);
    assert.deepEqual(options.stdio, ['ignore', 'pipe', 'pipe']);
    assert.equal(options.timeout, 15_000);
    assert.equal(options.maxBuffer, 64 * 1024);
    assert.equal(options.env.ELECTRON_RUN_AS_NODE, '1');
    assert.equal(
      readEnvironmentVariable(options.env, 'PATH'),
      readEnvironmentVariable(process.env, 'PATH'),
    );
    for (const key of [
      'NODE_OPTIONS',
      'npm_config_node_options',
      'npm_config_script_shell',
      'npm_execpath',
      'npm_node_execpath',
    ]) {
      assert.equal(hasEnvironmentVariable(options.env, key), false);
    }
  }
});

test('collectRuntimeVersions classifies nonzero probe failures without child output', () => {
  const sensitiveChildOutput = 'sensitive-runtime-probe-output';

  assert.throws(
    () => collectRuntimeVersionsFromDir('/sensitive-runtime-location', {
      spawnSyncForTest: () => ({
        error: undefined,
        signal: null,
        status: 7,
        stdout: sensitiveChildOutput,
        stderr: sensitiveChildOutput,
      }),
    }),
    (error) => {
      assert.equal(
        error.message,
        'Bundled Electron runtime version probe exited unsuccessfully (status=7).',
      );
      assert.equal(error.message.includes(sensitiveChildOutput), false);
      return true;
    },
  );
});

test('collectRuntimeVersions classifies launch failures without executable paths', () => {
  const runtimeDir = '/sensitive-runtime-location';
  assert.throws(
    () => collectRuntimeVersionsFromDir(runtimeDir, {
      spawnSyncForTest: () => ({
        error: Object.assign(new Error(runtimeDir), { code: 'ENOENT' }),
        signal: null,
        status: null,
        stdout: '',
        stderr: runtimeDir,
      }),
    }),
    (error) => {
      assert.equal(
        error.message,
        'Bundled Electron runtime version probe could not be started.',
      );
      assert.equal(error.message.includes(runtimeDir), false);
      return true;
    },
  );
});

test('collectRuntimeVersions classifies timeout without child output', () => {
  const sensitiveChildOutput = 'sensitive-timeout-output';

  assert.throws(
    () => collectRuntimeVersionsFromDir('/runtime', {
      timeout: 100,
      spawnSyncForTest: () => ({
        error: Object.assign(new Error(sensitiveChildOutput), { code: 'ETIMEDOUT' }),
        signal: 'SIGTERM',
        status: null,
        stdout: sensitiveChildOutput,
        stderr: sensitiveChildOutput,
      }),
    }),
    (error) => {
      assert.equal(error.message, 'Bundled Electron runtime version probe timed out.');
      assert.equal(error.message.includes(sensitiveChildOutput), false);
      return true;
    },
  );
});

test('collectRuntimeVersions classifies output overflow without child output', () => {
  const sensitiveChildOutput = 'sensitive-overflow-output';

  assert.throws(
    () => collectRuntimeVersionsFromDir('/runtime', {
      maxBuffer: 256,
      spawnSyncForTest: () => ({
        error: Object.assign(new Error(sensitiveChildOutput), { code: 'ENOBUFS' }),
        signal: 'SIGTERM',
        status: null,
        stdout: sensitiveChildOutput,
        stderr: sensitiveChildOutput,
      }),
    }),
    (error) => {
      assert.equal(
        error.message,
        'Bundled Electron runtime version probe exceeded its output limit.',
      );
      assert.equal(error.message.includes(sensitiveChildOutput), false);
      return true;
    },
  );
});

test('collectRuntimeVersions rejects invalid JSON without child output', () => {
  const sensitiveChildOutput = 'sensitive-json-probe-output';

  assert.throws(
    () => collectRuntimeVersionsFromDir('/runtime', {
      spawnSyncForTest: () => ({
        error: undefined,
        signal: null,
        status: 0,
        stdout: 'not-json',
        stderr: sensitiveChildOutput,
      }),
    }),
    (error) => {
      assert.equal(error.message, 'Bundled Electron runtime version output was not valid JSON.');
      assert.equal(error.message.includes(sensitiveChildOutput), false);
      return true;
    },
  );
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

test('clean Electron build runner invokes bounded npm CLI without a shell', () => {
  let invocation;
  withTemporaryEnvironmentVariables({
    NODE_OPTIONS: '--require /hostile-preload.cjs',
    Node_Options: '--require /duplicate-hostile-preload.cjs',
    npm_config_node_options: '--trace-warnings',
    NPM_CONFIG_NODE_OPTIONS: '--require /duplicate-hostile-npm-preload.cjs',
    npm_config_script_shell: '/hostile-script-shell',
    Npm_Config_Script_Shell: '/duplicate-hostile-script-shell',
    npm_execpath: '/hostile-npm-cli.js',
    NPM_EXECPATH: '/duplicate-hostile-npm-cli.js',
    npm_node_execpath: '/hostile-node',
    Npm_Node_ExecPath: '/duplicate-hostile-node',
  }, () => {
    runCleanElectronBuild('/fixture-root', {
      nodeExecutableForTest: '/fixture-node',
      npmCliPathForTest: '/fixture-npm-cli.js',
      spawnSyncForTest: (...args) => {
        invocation = args;
        return { error: undefined, signal: null, status: 0 };
      },
    });
  });

  assert.deepEqual(invocation.slice(0, 2), [
    '/fixture-node',
    ['/fixture-npm-cli.js', 'run', 'build:electron'],
  ]);
  const { env, ...spawnOptions } = invocation[2];
  assert.deepEqual(spawnOptions, {
    cwd: '/fixture-root',
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: 180_000,
    maxBuffer: 1024 * 1024,
    shell: false,
  });
  assert.equal(
    readEnvironmentVariable(env, 'PATH'),
    readEnvironmentVariable(process.env, 'PATH'),
  );
  for (const key of [
    'NODE_OPTIONS',
    'npm_config_node_options',
    'npm_config_script_shell',
    'npm_execpath',
    'npm_node_execpath',
  ]) {
    assert.equal(hasEnvironmentVariable(env, key), false);
  }
});

test('clean Electron build runner classifies failures without child output or paths', () => {
  const sensitiveChildOutput = 'sensitive-build-child-output';
  const cases = [
    {
      result: {
        error: Object.assign(new Error(sensitiveChildOutput), { code: 'ETIMEDOUT' }),
        signal: 'SIGTERM',
        status: null,
      },
      expected: 'Electron clean build timed out.',
    },
    {
      result: {
        error: Object.assign(new Error(sensitiveChildOutput), { code: 'ENOBUFS' }),
        signal: 'SIGTERM',
        status: null,
      },
      expected: 'Electron clean build exceeded its output limit.',
    },
    {
      result: {
        error: Object.assign(new Error(sensitiveChildOutput), { code: 'ENOENT' }),
        signal: null,
        status: null,
      },
      expected: 'Electron clean build could not be started.',
    },
    {
      result: { error: undefined, signal: 'SIGTERM', status: null },
      expected: 'Electron clean build was terminated by a signal.',
    },
    {
      result: { error: undefined, signal: null, status: 9 },
      expected: 'Electron clean build exited unsuccessfully (status=9).',
    },
  ];

  for (const { result, expected } of cases) {
    assert.throws(
      () => runCleanElectronBuild('/sensitive-build-root', {
        nodeExecutableForTest: '/sensitive-node-path',
        npmCliPathForTest: '/sensitive-npm-cli-path',
        spawnSyncForTest: () => ({
          ...result,
          stdout: sensitiveChildOutput,
          stderr: sensitiveChildOutput,
        }),
      }),
      (error) => {
        assert.equal(error.message, expected);
        assert.equal(error.message.includes(sensitiveChildOutput), false);
        assert.equal(error.message.includes('/sensitive'), false);
        return true;
      },
    );
  }
});

test('packageWindowsInternal packages only bytes produced by its owned clean build', async (t) => {
  const root = makeFixtureRepo(t);
  const runtimeDir = makeFakeElectronRuntime(root);
  fs.writeFileSync(path.join(root, 'dist/main/index.js'), 'stale main bytes\n');
  fs.writeFileSync(path.join(root, 'dist/stale-only.js'), 'stale only bytes\n');

  const result = await packageWindowsInternal({
    root,
    allowNonWindowsForTest: true,
    runtimeDir,
    runtimeVersions: fixtureRuntimeVersions(),
    unsupportedCallerOption: 'ignored',
  });

  assert.equal(
    fs.readFileSync(path.join(result.packageRoot, 'resources/app/dist/main/index.js'), 'utf8'),
    'fresh fixture main bytes\n',
  );
  assert.equal(
    fs.existsSync(path.join(result.packageRoot, 'resources/app/dist/stale-only.js')),
    false,
  );
});

test('packageWindowsInternal ignores hostile npm executable and Node option environment', async (t) => {
  const root = makeFixtureRepo(t);
  const runtimeDir = makeFakeElectronRuntime(root);
  const hostileRoot = path.join(root, 'hostile-environment');
  fs.mkdirSync(hostileRoot);
  const hostileNpmMarker = path.join(hostileRoot, 'npm-cli-executed');
  const hostilePreloadMarker = path.join(hostileRoot, 'node-options-executed');
  const hostileNpmCliPath = path.join(hostileRoot, 'npm-cli.js');
  const hostilePreloadPath = path.join(hostileRoot, 'preload.cjs');
  fs.writeFileSync(hostileNpmCliPath, [
    "const fs = require('node:fs');",
    `fs.writeFileSync(${JSON.stringify(hostileNpmMarker)}, 'executed');`,
    'process.exit(0);',
    '',
  ].join('\n'));
  fs.writeFileSync(hostilePreloadPath, [
    "const fs = require('node:fs');",
    `fs.writeFileSync(${JSON.stringify(hostilePreloadMarker)}, 'executed');`,
    '',
  ].join('\n'));
  fs.writeFileSync(path.join(root, 'dist/main/index.js'), 'hostile environment stale bytes\n');

  const result = await withTemporaryEnvironmentVariables({
    NODE_OPTIONS: `--require ${JSON.stringify(hostilePreloadPath)}`,
    npm_execpath: hostileNpmCliPath,
    npm_node_execpath: path.join(hostileRoot, 'hostile-node'),
  }, () => packageWindowsInternal({
    root,
    allowNonWindowsForTest: true,
    runtimeDir,
    runtimeVersions: fixtureRuntimeVersions(),
  }));

  assert.equal(fs.existsSync(hostileNpmMarker), false);
  assert.equal(fs.existsSync(hostilePreloadMarker), false);
  assert.equal(
    fs.readFileSync(path.join(result.packageRoot, 'resources/app/dist/main/index.js'), 'utf8'),
    'fresh fixture main bytes\n',
  );
});

test('packageWindowsInternal preserves an existing package when its clean build fails', async (t) => {
  const root = makeFixtureRepo(t);
  const { packageRoot } = buildInternalPackagePaths({ root });
  fs.mkdirSync(packageRoot, { recursive: true });
  const sentinelPath = path.join(packageRoot, 'existing-package-sentinel.txt');
  fs.writeFileSync(sentinelPath, 'existing package bytes\n');
  setFixtureBuildMode(root, 'fail');

  await assert.rejects(
    () => packageWindowsInternal({
      root,
      allowNonWindowsForTest: true,
      runtimeVersions: fixtureRuntimeVersions(),
    }),
    /Electron clean build exited unsuccessfully \(status=9\)/u,
  );

  assert.equal(fs.readFileSync(sentinelPath, 'utf8'), 'existing package bytes\n');
  assert.deepEqual(fs.readdirSync(packageRoot), ['existing-package-sentinel.txt']);
});

test('packageWindowsInternal runs its clean build before runtime and fails closed on no-op build', async (t) => {
  const root = makeFixtureRepo(t);
  const { packageRoot } = buildInternalPackagePaths({ root });
  fs.writeFileSync(path.join(root, 'dist/main/index.js'), 'stale before runtime validation\n');

  await assert.rejects(
    () => packageWindowsInternal({
      root,
      allowNonWindowsForTest: true,
      runtimeDir: path.join(root, 'missing-runtime'),
      runtimeVersions: fixtureRuntimeVersions(),
    }),
    /Electron runtime directory is missing/u,
  );

  assert.equal(
    fs.readFileSync(path.join(root, 'dist/main/index.js'), 'utf8'),
    'fresh fixture main bytes\n',
  );
  assert.equal(fs.existsSync(packageRoot), false);

  const runtimeDir = makeFakeElectronRuntime(root);
  fs.writeFileSync(path.join(root, 'dist/main/index.js'), 'stale before no-op build\n');
  setFixtureBuildMode(root, 'noop');
  await assert.rejects(
    () => packageWindowsInternal({
      root,
      allowNonWindowsForTest: true,
      runtimeDir,
      runtimeVersions: fixtureRuntimeVersions(),
    }),
    /dist directory is missing/u,
  );

  assert.equal(fs.existsSync(path.join(root, 'dist')), false);
  assert.equal(fs.existsSync(packageRoot), false);
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
    () => parseChecksumRows(`${'a'.repeat(64)}  ${['C:', 'package.json'].join('/')}`),
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
  assert.equal(
    fs.existsSync(
      path.join(
        packageRoot,
        'resources/app/dist/main/channel/channelBuilderPlanningWorkerEntry.js',
      ),
    ),
    true,
  );
  assert.equal(fs.existsSync(path.join(packageRoot, 'resources/app/dist/renderer/index.html')), true);
  const rendererChannelBuilderRoot = path.join(
    packageRoot,
    'resources/app/dist/renderer/domain/channelBuilder',
  );
  assert.equal(fs.existsSync(path.join(rendererChannelBuilderRoot, 'config.js')), true);
  assert.equal(fs.existsSync(path.join(rendererChannelBuilderRoot, 'constants.js')), true);
  assert.equal(fs.existsSync(path.join(rendererChannelBuilderRoot, 'config.js.map')), false);
  assert.equal(fs.existsSync(path.join(rendererChannelBuilderRoot, 'index.js')), false);
  assert.equal(fs.existsSync(path.join(rendererChannelBuilderRoot, 'planner.js')), false);
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
  assert.deepEqual(provenance.build, {
    strategy: 'package-time-clean-build',
    command: 'npm run build:electron',
  });
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

test('verifier requires truthful package-owned clean-build provenance', async (t) => {
  const { root, packageRoot } = await makeVerifiedPackage(t);
  const provenancePath = path.join(packageRoot, PROVENANCE_RELATIVE_PATH);
  const provenance = readJson(provenancePath);
  provenance.build = {
    strategy: 'caller-prebuilt-dist',
    command: 'npm run build:electron',
  };
  fs.writeFileSync(provenancePath, `${JSON.stringify(provenance, null, 2)}\n`);
  rewriteChecksumManifest(packageRoot);

  const errors = verifyWindowsInternalPackage({
    root,
    packageRoot,
    manifestPath: provenancePath,
  });

  assert(errors.some((error) => (
    error.includes('Provenance build must record package-time-clean-build')
  )));
  assert.equal(errors.some((error) => error.includes('checksums.sha256 must match')), false);
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

test('runtime version collection probes the explicitly selected staged runtime directory', (t) => {
  const root = makeFixtureRepo(t);
  const stagedRuntimeDir = path.join(root, 'staged-electron-runtime');
  fs.mkdirSync(stagedRuntimeDir);
  fs.writeFileSync(path.join(stagedRuntimeDir, 'electron.exe'), 'fake exe');
  const stagedVersions = {
    electron: '42.0.0',
    node: '24.15.0',
    chrome: '148.0.7778.96',
    v8: '14.8.178.14-electron.0',
    modules: '146',
    napi: '10',
  };
  let probedExecutable;

  const result = collectRuntimeVersionsFromDir(stagedRuntimeDir, {
    spawnSyncForTest: (executable) => {
      probedExecutable = executable;
      return {
        error: undefined,
        signal: null,
        status: 0,
        stdout: `${JSON.stringify(stagedVersions)}\n`,
        stderr: '',
      };
    },
  });

  assert.equal(probedExecutable, path.join(stagedRuntimeDir, 'electron.exe'));
  assert.deepEqual(result, stagedVersions);
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
    certificatePath: ['C:', 'Users', 'example', 'certificates', 'release.pfx'].join('\\'),
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
    scripts: {
      'build:electron': 'node fixture-build.mjs',
    },
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
  writeFixtureDist(root, 'stale fixture main bytes\n');
  writeFixtureDist(path.join(root, 'fixture-build-output'), 'fresh fixture main bytes\n');
  fs.writeFileSync(path.join(root, 'fixture-build.mjs'), [
    "import fs from 'node:fs';",
    "import path from 'node:path';",
    '',
    'const root = process.cwd();',
    "const modePath = path.join(root, 'fixture-build-mode.txt');",
    "const mode = fs.existsSync(modePath) ? fs.readFileSync(modePath, 'utf8').trim() : 'success';",
    "const distRoot = path.join(root, 'dist');",
    "if (mode === 'fail') process.exit(9);",
    "if (mode === 'noop') process.exit(0);",
    'fs.rmSync(distRoot, { recursive: true, force: true });',
    "if (mode !== 'missing-dist') {",
    "  fs.cpSync(path.join(root, 'fixture-build-output', 'dist'), distRoot, { recursive: true });",
    '}',
    '',
  ].join('\n'));

  return root;
}

function writeFixtureDist(root, mainIndexContent = 'console.log("main");\n') {
  fs.mkdirSync(path.join(root, 'dist/main'), { recursive: true });
  fs.mkdirSync(path.join(root, 'dist/main/channel'), { recursive: true });
  fs.mkdirSync(path.join(root, 'dist/renderer/styles'), { recursive: true });
  fs.mkdirSync(path.join(root, 'dist/renderer/domain/channelBuilder'), { recursive: true });
  fs.writeFileSync(path.join(root, 'dist/main/index.js'), mainIndexContent);
  fs.writeFileSync(
    path.join(root, 'dist/main/channel/channelBuilderPlanningWorkerEntry.js'),
    'console.log("worker");\n',
  );
  fs.writeFileSync(path.join(root, 'dist/renderer/index.html'), '<!doctype html>\n');
  fs.writeFileSync(path.join(root, 'dist/renderer/styles.css'), '@import "./styles/base.css";\n');
  fs.writeFileSync(path.join(root, 'dist/renderer/styles/base.css'), ':root { color: white; }\n');
  fs.writeFileSync(
    path.join(root, 'dist/renderer/domain/channelBuilder/config.js'),
    'export const config = true;\n',
  );
  fs.writeFileSync(
    path.join(root, 'dist/renderer/domain/channelBuilder/constants.js'),
    'export const constants = true;\n',
  );

}

function makeFakeElectronRuntime(root) {
  const runtimeDir = path.join(root, 'runtime');
  fs.mkdirSync(runtimeDir, { recursive: true });
  fs.writeFileSync(path.join(runtimeDir, 'electron.exe'), 'fake exe');
  fs.writeFileSync(path.join(runtimeDir, 'version'), '42.0.0');
  return runtimeDir;
}

function fixtureRuntimeVersions() {
  return {
    node: '24.15.0',
    chrome: '148.0.7778.96',
    v8: '14.8.178.14-electron.0',
    modules: '146',
    napi: '10',
  };
}

function setFixtureBuildMode(root, mode) {
  fs.writeFileSync(path.join(root, 'fixture-build-mode.txt'), `${mode}\n`);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function withTemporaryEnvironmentVariables(values, callback) {
  const previousValues = new Map(
    Object.keys(values).map((key) => [key, process.env[key]]),
  );
  for (const [key, value] of Object.entries(values)) {
    process.env[key] = value;
  }

  const restore = () => {
    for (const [key, previous] of previousValues) {
      if (previous === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = previous;
      }
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

function readEnvironmentVariable(environment, name) {
  const normalizedName = name.toLowerCase();
  return Object.entries(environment).find(
    ([key]) => key.toLowerCase() === normalizedName,
  )?.[1];
}

function hasEnvironmentVariable(environment, name) {
  const normalizedName = name.toLowerCase();
  return Object.keys(environment).some(
    (key) => key.toLowerCase() === normalizedName,
  );
}
