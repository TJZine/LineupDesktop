import test from 'node:test';
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  collectFiles,
  scanFileContent,
  scanRepo,
  scanSupportBundleDirectory,
} from '../verify-redaction.mjs';

const scannerLabels = [
  'token-query-parameter',
  'raw-auth-header',
  'credential-scheme',
  'header-map-credential',
  'secret-field-value',
  'privileged-diagnostic-field-value',
  'oauth-token-path-segment',
  'raw-filesystem-path',
  'raw-process-data',
  'native-handle',
  'raw-ipc-frame',
];

const plexTokenHeader = ['X-Plex', 'Token'].join('-');
const authorizationHeader = ['Authorization'].join('');
const bearerScheme = ['Bearer'].join('');

test('shared traversal preserves support-bundle filtering and directory skips', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-redaction-walk-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, 'nested'));
  fs.mkdirSync(path.join(root, 'node_modules'));
  fs.writeFileSync(path.join(root, 'nested', 'included.md'), 'safe');
  fs.writeFileSync(path.join(root, 'nested', 'excluded.html'), 'safe');
  fs.writeFileSync(
    path.join(root, 'node_modules', 'skipped.md'),
    `${authorizationHeader}: ${bearerScheme} ${['placeholder', 'secret'].join('-')}`,
  );

  assert.deepEqual(collectFiles(root), [path.join('nested', 'included.md')]);
  assert.deepEqual(scanRepo(root), []);
});
const basicScheme = ['Basic'].join('');
const tokenScheme = ['Token'].join('');
const headersKey = ['headers'].join('');
const authHeadersKey = ['auth', 'Headers'].join('');
const rawAuthHeadersKey = ['raw', 'Auth', 'Headers'].join('');
const tokenizedUrlKey = ['tokenized', 'Url'].join('');
const rawMediaUrlKey = ['raw', 'Media', 'Url'].join('');
const nativeHandleKey = ['native', 'Handle'].join('');
const rawPlexPayloadKey = ['raw', 'Plex', 'Payload'].join('');
const credentialMaterialKey = ['credential', 'Material'].join('');
const placeholderSecret = ['placeholder', 'secret'].join('-');
const alphabeticCredential = ['abcdefghijkl', 'mnop'].join('');
const mixedCaseAlphabeticCredential = ['AbCdEfGh', 'IjKlMnOp'].join('');

test('scanFileContent reports token query parameters without storing raw examples', () => {
  for (const queryKey of [plexTokenHeader, 'token', 'mediaToken']) {
    const content = `https://example.invalid/video?${queryKey}=placeholder-secret`;
    assert.deepEqual(scanFileContent(content), ['token-query-parameter']);
  }
});

test('scanFileContent reports mixed-case token query parameters', () => {
  const mixedCaseTokenKey = ['Account', 'ToKeN'].join('');
  const content = `https://example.invalid/video?${mixedCaseTokenKey}=placeholder-secret`;
  assert.deepEqual(scanFileContent(content), ['token-query-parameter']);
});

test('scanFileContent reports raw auth headers with credential values', () => {
  assert.deepEqual(
    scanFileContent(`${authorizationHeader}: ${bearerScheme} placeholder-secret`),
    ['raw-auth-header', 'credential-scheme'],
  );
  assert.deepEqual(
    scanFileContent(`${authorizationHeader}: ${basicScheme} placeholder-secret`),
    ['raw-auth-header', 'credential-scheme'],
  );
  assert.deepEqual(
    scanFileContent(`${authorizationHeader}: ${basicScheme} user:secret`),
    ['raw-auth-header', 'credential-scheme'],
  );
  assert.deepEqual(
    scanFileContent(`${authorizationHeader}: ${tokenScheme} abc:def`),
    ['raw-auth-header', 'credential-scheme'],
  );
  assert.deepEqual(
    scanFileContent(`${['authori', 'ZATION'].join('')}: ${['bA', 'sIc'].join('')} placeholder-secret`),
    ['raw-auth-header', 'credential-scheme'],
  );
  assert.deepEqual(scanFileContent(`${plexTokenHeader}: placeholder-secret`), [
    'raw-auth-header',
  ]);
  assert.deepEqual(scanFileContent(`${plexTokenHeader}: ${alphabeticCredential}`), [
    'raw-auth-header',
  ]);
  assert.deepEqual(scanFileContent(`${plexTokenHeader}: ${mixedCaseAlphabeticCredential}`), [
    'raw-auth-header',
  ]);
});

test('scanFileContent reports bearer basic and token credential schemes', () => {
  assert.deepEqual(scanFileContent(`${bearerScheme} placeholder-secret`), [
    'credential-scheme',
  ]);
  assert.deepEqual(scanFileContent(`${basicScheme} placeholder-secret`), [
    'credential-scheme',
  ]);
  assert.deepEqual(scanFileContent(`${basicScheme} user:secret`), [
    'credential-scheme',
  ]);
  assert.deepEqual(scanFileContent(`${bearerScheme} abc:def`), [
    'credential-scheme',
  ]);
  assert.deepEqual(scanFileContent(`${['bA', 'sIc'].join('')} placeholder-secret`), [
    'credential-scheme',
  ]);
  assert.deepEqual(scanFileContent(`${bearerScheme} ${alphabeticCredential}`), [
    'credential-scheme',
  ]);
  assert.deepEqual(scanFileContent(`${bearerScheme} ${mixedCaseAlphabeticCredential}`), [
    'credential-scheme',
  ]);
  assert.deepEqual(scanFileContent(`${tokenScheme} placeholder-secret`), [
    'credential-scheme',
  ]);
});

test('scanFileContent reports brace-delimited header maps', () => {
  assert.deepEqual(scanFileContent(`${headersKey}={${plexTokenHeader}: abc}`), [
    'header-map-credential',
  ]);
  assert.deepEqual(scanFileContent(`${headersKey}={"${plexTokenHeader}":"abc12345"}`), [
    'raw-auth-header',
    'header-map-credential',
  ]);
  assert.deepEqual(scanFileContent(`${headersKey}: {'${plexTokenHeader}': 'abc12345'}`), [
    'raw-auth-header',
    'header-map-credential',
  ]);
  assert.deepEqual(scanFileContent(`${headersKey}={${authorizationHeader}: ${bearerScheme} abc12345}`), [
    'raw-auth-header',
    'credential-scheme',
    'header-map-credential',
  ]);
  assert.deepEqual(scanFileContent(`${authHeadersKey}={${authorizationHeader}: ${basicScheme} abc12345}`), [
    'raw-auth-header',
    'credential-scheme',
    'header-map-credential',
  ]);
  assert.deepEqual(scanFileContent(`${rawAuthHeadersKey}={${plexTokenHeader}: abc12345}`), [
    'raw-auth-header',
    'header-map-credential',
  ]);
  assert.deepEqual(scanFileContent(`${['Hea', 'Ders'].join('')}={${plexTokenHeader}: abc12345}`), [
    'raw-auth-header',
    'header-map-credential',
  ]);
});

test('scanFileContent reports secret-shaped key-value fields', () => {
  const cases = [
    'authToken',
    'authenticationToken',
    'accountToken',
    'activeToken',
    'plexToken',
    'clientSecret',
    'credential',
    'password',
  ];

  for (const key of cases) {
    assert.deepEqual(scanFileContent(`${key}=placeholder-secret`), ['secret-field-value']);
    assert.deepEqual(scanFileContent(`${key.toUpperCase()}=placeholder-secret`), ['secret-field-value']);
    assert.deepEqual(scanFileContent(`{"${key}":"abc12345"}`), ['secret-field-value']);
    assert.deepEqual(scanFileContent(`{"${key.toUpperCase()}":"abc12345"}`), ['secret-field-value']);
    assert.deepEqual(scanFileContent(`${key}=${alphabeticCredential}`), ['secret-field-value']);
    assert.deepEqual(scanFileContent(`${key}=${mixedCaseAlphabeticCredential}`), [
      'secret-field-value',
    ]);
  }
});

test('scanFileContent reports formatted header maps', () => {
  assert.deepEqual(
    scanFileContent(`{
  "${headersKey}": {
    "${plexTokenHeader}": "abc12345"
  }
}`),
    ['raw-auth-header', 'header-map-credential'],
  );
  assert.deepEqual(
    scanFileContent(`{
  "${authHeadersKey}": {
    "${authorizationHeader}": "${basicScheme} abc12345"
  }
}`),
    ['raw-auth-header', 'credential-scheme', 'header-map-credential'],
  );
  assert.deepEqual(
    scanFileContent(`{
  "${rawAuthHeadersKey}": {
    "${plexTokenHeader}": "abc12345"
  }
}`),
    ['raw-auth-header', 'header-map-credential'],
  );
});

test('scanFileContent reports privileged diagnostic field leaks', () => {
  const cases = [
    `${tokenizedUrlKey}=https://media.plex.direct/video`,
    `${rawMediaUrlKey}=https://media.plex.direct/video`,
    `${rawPlexPayloadKey}=payload12345`,
    `${credentialMaterialKey}=credential12345`,
  ];

  for (const content of cases) {
    assert.deepEqual(scanFileContent(content), ['privileged-diagnostic-field-value']);
  }
});

test('scanFileContent reports raw filesystem paths process data native handles and IPC frames', () => {
  const pathKey = ['file', 'Path'].join('');
  const processKey = ['p', 'id'].join('');
  const ipcKey = ['raw', 'Ipc'].join('');
  const keyedLogPath = ['/', 'Users/example/Lineup/private.log'].join('');
  const mediaPath = ['', 'Users/example/Library/Application', 'Support/Lineup/media.mkv'].join('/');

  assert.deepEqual(scanFileContent(`${pathKey}=${keyedLogPath}`), [
    'raw-filesystem-path',
  ]);
  assert.deepEqual(
    scanFileContent(`${['message'].join('')}=${mediaPath}`),
    ['raw-filesystem-path'],
  );
  assert.deepEqual(
    scanFileContent(mediaPath),
    ['raw-filesystem-path'],
  );
  for (const arbitraryPath of [
    ['', 'etc', 'passwd'].join('/'),
    ['', 'opt', 'Lineup Data', 'private-media-folder'].join('/'),
    ['', 'Médiathèque, 2026; (Director\'s Archive)', 'private-media-folder'].join('/'),
    ['D:', '\\', 'Media Library', '\\', 'private'].join(''),
    ['D:', '/', 'Media', '/', 'private.mkv'].join(''),
    ['\\\\', 'media-host', '\\', 'Shared Library', '\\', 'private'].join(''),
  ]) {
    assert.deepEqual(scanFileContent(arbitraryPath), ['raw-filesystem-path']);
  }
  assert.deepEqual(scanFileContent('src/contracts/diagnostics.ts'), []);
  assert.deepEqual(scanFileContent('1/2/3.14'), []);
  assert.deepEqual(scanFileContent(`${processKey}=12345`), ['raw-process-data']);
  assert.deepEqual(scanFileContent(`${processKey} 12345`), ['raw-process-data']);
  assert.deepEqual(scanFileContent(`${nativeHandleKey}=123456789`), ['native-handle']);
  assert.deepEqual(scanFileContent(`${nativeHandleKey} 123456789`), ['native-handle']);
  assert.deepEqual(scanFileContent(`${['Native', 'Handle'].join('')}=0x1234abcd`), [
    'native-handle',
  ]);
  assert.deepEqual(scanFileContent(`${ipcKey}={"channel":"lineup:private"}`), [
    'raw-ipc-frame',
  ]);
  assert.deepEqual(scanFileContent(`${ipcKey} channel lineup:private`), [
    'raw-ipc-frame',
  ]);
  assert.deepEqual(scanFileContent(`${['credential'].join('')} 12345`), [
    'secret-field-value',
  ]);
});

test('support bundle scanning rejects absolute paths under arbitrary JSON keys', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-support-scan-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const absolutePaths = [
    ['', 'opt', 'Lineup Data', 'private-media-folder'].join('/'),
    ['', 'Médiathèque, 2026; (Director\'s Archive)', 'private-media-folder'].join('/'),
    ['D:', '/', 'Media', '/', 'private.mkv'].join(''),
    ['\\\\', 'media-host', '\\', 'Shared Library', '\\', 'private'].join(''),
  ];
  absolutePaths.forEach((absolutePath, index) => {
    fs.writeFileSync(
      path.join(root, `environment-${index}.json`),
      JSON.stringify({ note: absolutePath }),
    );
  });

  const report = scanSupportBundleDirectory(root, {
    timestampMs: 1,
    truncatedRecordCount: 0,
    omittedFileCount: 0,
  });

  assert.equal(report.status, 'failed');
  assert.equal(report.findingsByLabel['raw-filesystem-path'], absolutePaths.length);
});

test('support bundle scanning permits relative paths and fractions', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-support-safe-scan-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.writeFileSync(
    path.join(root, 'environment.json'),
    JSON.stringify({
      source: 'src/contracts/diagnostics.ts',
      progress: '1/2/3.14',
    }),
  );

  const report = scanSupportBundleDirectory(root, { timestampMs: 1 });

  assert.equal(report.status, 'passed');
  assert.equal(report.findingsByLabel['raw-filesystem-path'], undefined);
});

test('scanFileContent reports oauth2 token path segments', () => {
  assert.deepEqual(scanFileContent(`/oauth2/${placeholderSecret}/pin`), [
    'oauth-token-path-segment',
    'raw-filesystem-path',
  ]);
  assert.deepEqual(scanFileContent(`/oauth2/${alphabeticCredential}`), [
    'oauth-token-path-segment',
    'raw-filesystem-path',
  ]);
});

test('scanFileContent labels are aligned with the diagnostics scan contract', () => {
  const observedLabels = new Set([
    ...scanFileContent(`https://example.invalid/video?${['media', 'Token'].join('')}=placeholder-secret`),
    ...scanFileContent(`${authorizationHeader}: ${bearerScheme} placeholder-secret`),
    ...scanFileContent(`${headersKey}={${plexTokenHeader}: abc}`),
    ...scanFileContent(`${credentialMaterialKey}=credential12345`),
    ...scanFileContent(`/oauth2/${placeholderSecret}/pin`),
    ...scanFileContent(`${['file', 'Path'].join('')}=${['/', 'Users/example/private.log'].join('')}`),
    ...scanFileContent(`${['p', 'id'].join('')}=12345`),
    ...scanFileContent(`${['p', 'id'].join('')} 12345`),
    ...scanFileContent(`${nativeHandleKey}=123456789`),
    ...scanFileContent(`${nativeHandleKey} 123456789`),
    ...scanFileContent(`${['raw', 'Ipc'].join('')}={"channel":"lineup:private"}`),
    ...scanFileContent(`${['raw', 'Ipc'].join('')} channel lineup:private`),
    ...scanFileContent(`${['credential'].join('')} 12345`),
  ]);

  for (const label of observedLabels) {
    assert.equal(scannerLabels.includes(label), true, `scanner label is in contract: ${label}`);
  }
});

test('scanFileContent does not report safe policy prose', () => {
  const content = [
    'authorization flow',
    'token policy',
    'client secret policy',
    'Architecture docs discuss secret handling without values.',
    `${authorizationHeader}: header requirements are documented here.`,
    `${plexTokenHeader}: header name appears without credential material.`,
    'Token handling remains a policy discussion.',
    'Basic authentication remains a policy discussion.',
    'Bearer authentication remains a policy discussion.',
    'const authToken = readNullableString(payload.authToken)',
    'const authToken = placeholderAuthValue',
    'tokenized URL fields are forbidden in diagnostics.',
    'native handle values must stay inside main.',
    'raw auth header maps are never renderer safe.',
    'oauth2 token paths are discussed without material.',
  ].join('\n');

  assert.deepEqual(scanFileContent(content), []);
});

test('scanRepo reports raw auth headers in fixture content', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-desktop-redaction-'));
  fs.mkdirSync(path.join(root, 'docs'));
  fs.writeFileSync(
    path.join(root, 'docs/leak.md'),
    `${authorizationHeader}: ${bearerScheme} placeholder-secret\n`,
  );
  const findings = scanRepo(root);
  assert.equal(findings.length, 2);
  assert.equal(findings[0].reason, 'raw-auth-header');
  assert.equal(findings[1].reason, 'credential-scheme');
});

test('scanRepo applies shared absolute-path recognition to filesystem fields', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-desktop-path-scan-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.writeFileSync(
    path.join(root, 'safe.ts'),
    [
      'const source = "src/contracts/diagnostics.ts";',
      'const progress = "1/2/3.14";',
      'const pathPolicyPattern = /^[/]private/u;',
    ].join('\n'),
  );
  fs.writeFileSync(
    path.join(root, 'safe.json'),
    JSON.stringify({
      filePath: 'src/contracts/diagnostics.ts',
      progress: '1/2/3.14',
    }),
  );
  fs.writeFileSync(
    path.join(root, 'unix-leak.json'),
    JSON.stringify({
      filePath: ['', 'Médiathèque, 2026', 'private'].join('/'),
    }),
  );
  fs.writeFileSync(
    path.join(root, 'windows-leak.json'),
    JSON.stringify({
      filePath: ['D:', '/', 'Media', '/', 'private.mkv'].join(''),
    }),
  );

  assert.deepEqual(scanRepo(root), [
    { file: 'unix-leak.json', reason: 'raw-filesystem-path' },
    { file: 'windows-leak.json', reason: 'raw-filesystem-path' },
  ]);
});

test('scanRepo reports repository paths across prose arbitrary fields and source types', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-desktop-source-path-scan-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const unixPath = ['', 'Users', 'example', 'Lineup Data', 'private.log'].join('/');
  const windowsPath = ['D:', '\\', 'Media Library', '\\', 'private.mkv'].join('');
  const uncPath = ['\\\\', 'media-host', '\\', 'Shared Library', '\\', 'private'].join('');
  const servicePath = ['', 'srv', 'lineup', 'private.log'].join('/');
  const localizedPath = ['', 'Médiathèque', 'private'].join('/');
  const dataPath = ['', 'data', 'private.log'].join('/');
  const mountPath = ['', 'mnt', 'private'].join('/');
  const workspacePath = ['', 'workspace', 'private'].join('/');
  const fixtures = new Map([
    ['NOTICE', `Generated from ${unixPath}\n`],
    ['config.json', JSON.stringify({ workspaceLocation: unixPath })],
    ['helper.cs', `// Local helper output: ${windowsPath}\n`],
    ['page.html', `<!-- Local preview source: ${unixPath} -->\n`],
    ['project.csproj', `<PropertyGroup><LocalCache>${windowsPath}</LocalCache></PropertyGroup>\n`],
    ['script.ps1', `# Copied from ${uncPath}\n`],
    ['styles.css', `/* Screenshot source: ${unixPath} */\n`],
    ['service.log', `Output retained at ${servicePath}\n`],
    ['localized.txt', `Archive root: ${localizedPath}\n`],
    ['data.txt', `Filesystem path: ${dataPath}\n`],
    ['mount.txt', `Mounted folder: ${mountPath}\n`],
    ['workspace.txt', `Workspace output: ${workspacePath}\n`],
  ]);
  for (const [file, content] of fixtures) {
    fs.writeFileSync(path.join(root, file), content);
  }

  assert.deepEqual(
    scanRepo(root),
    [...fixtures.keys()].sort().map((file) => ({ file, reason: 'raw-filesystem-path' })),
  );
});

test('scanRepo permits regexes URLs relative paths and intentional fixture construction', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-desktop-safe-source-scan-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const unixPath = ['', 'Users', 'example', 'private.log'].join('/');
  fs.writeFileSync(
    path.join(root, 'safe.ts'),
    [
      'const pathPattern = /^[/]private/u;',
      String.raw`const escapedPathPattern = /^\/Users\/[^/]+/u;`,
      String.raw`const attrRegex = new RegExp(key + '\\s*=\\s*(["\'])([\\s\\S]*?)\\1', 'gi');`,
      String.raw`assert.match(source, /buffer\.split\(\/\\r\?\\n\/u\)/u);`,
      "const fixturePath = ['', 'Users', 'example', 'private.log'].join('/');",
      'const relativePath = "src/contracts/diagnostics.ts";',
      'const ratio = "1/2/3.14";',
    ].join('\n'),
  );
  fs.writeFileSync(
    path.join(root, 'safe.html'),
    [
      '<a href="https://example.invalid/Users/example/private.log">remote</a>',
      '<img src="/assets/private.png">',
    ].join('\n'),
  );
  fs.writeFileSync(
    path.join(root, 'binary.dat'),
    Buffer.concat([Buffer.from(`embedded ${unixPath}`), Buffer.from([0, 1, 2])]),
  );

  assert.deepEqual(scanRepo(root), []);
});

test('scanRepo reports absolute filesystem paths embedded in file URLs', (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-desktop-file-url-scan-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const unixPath = ['', 'srv', 'lineup', 'private.log'].join('/');
  const hostPath = ['media-host', 'private-share', 'private.log'].join('/');
  fs.writeFileSync(
    path.join(root, 'preview.html'),
    [
      `<a href="file://${unixPath}">local</a>`,
      `<a href="file://${hostPath}">network</a>`,
    ].join('\n'),
  );

  assert.deepEqual(scanRepo(root), [
    { file: 'preview.html', reason: 'raw-filesystem-path' },
  ]);
});

test('scanRepo inspects symlink targets without dereferencing them', (t) => {
  if (process.platform === 'win32') {
    t.skip('Creating symlinks requires privileges that are not guaranteed on Windows CI.');
    return;
  }
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-desktop-symlink-scan-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const absoluteTarget = ['', 'Users', 'example', 'private.log'].join('/');
  fs.symlinkSync(absoluteTarget, path.join(root, 'local-output'));

  assert.deepEqual(scanRepo(root), [
    { file: 'local-output', reason: 'raw-filesystem-path' },
  ]);
});
