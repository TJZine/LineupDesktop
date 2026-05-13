import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { scanFileContent, scanRepo } from '../verify-redaction.mjs';

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
  const mediaPath = ['/Users/example/Library/Application', 'Support/Lineup/media.mkv'].join(' ');

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

test('scanFileContent reports oauth2 token path segments', () => {
  assert.deepEqual(scanFileContent(`/oauth2/${placeholderSecret}/pin`), [
    'oauth-token-path-segment',
  ]);
  assert.deepEqual(scanFileContent(`/oauth2/${alphabeticCredential}`), [
    'oauth-token-path-segment',
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
    '/oauth2/ token paths are discussed without material.',
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
