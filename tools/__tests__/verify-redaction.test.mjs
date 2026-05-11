import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { scanFileContent, scanRepo } from '../verify-redaction.mjs';

const plexTokenHeader = ['X-Plex', 'Token'].join('-');
const authorizationHeader = ['Authorization'].join('');
const bearerScheme = ['Bearer'].join('');
const tokenScheme = ['Token'].join('');
const alphabeticCredential = ['abcdefghijkl', 'mnop'].join('');
const mixedCaseAlphabeticCredential = ['AbCdEfGh', 'IjKlMnOp'].join('');

test('scanFileContent reports token query parameters without storing raw examples', () => {
  for (const queryKey of [plexTokenHeader, 'token', 'mediaToken']) {
    const content = `https://example.invalid/video?${queryKey}=placeholder-secret`;
    assert.deepEqual(scanFileContent(content), ['token query parameter']);
  }
});

test('scanFileContent reports mixed-case token query parameters', () => {
  const mixedCaseTokenKey = ['Account', 'ToKeN'].join('');
  const content = `https://example.invalid/video?${mixedCaseTokenKey}=placeholder-secret`;
  assert.deepEqual(scanFileContent(content), ['token query parameter']);
});

test('scanFileContent reports raw auth headers with credential values', () => {
  assert.deepEqual(
    scanFileContent(`${authorizationHeader}: ${bearerScheme} placeholder-secret`),
    ['raw Authorization header', 'credential scheme'],
  );
  assert.deepEqual(scanFileContent(`${plexTokenHeader}: placeholder-secret`), [
    'raw Authorization header',
  ]);
  assert.deepEqual(scanFileContent(`${plexTokenHeader}: ${alphabeticCredential}`), [
    'raw Authorization header',
  ]);
  assert.deepEqual(scanFileContent(`${plexTokenHeader}: ${mixedCaseAlphabeticCredential}`), [
    'raw Authorization header',
  ]);
});

test('scanFileContent reports bearer and token credential schemes', () => {
  assert.deepEqual(scanFileContent(`${bearerScheme} placeholder-secret`), [
    'credential scheme',
  ]);
  assert.deepEqual(scanFileContent(`${bearerScheme} ${alphabeticCredential}`), [
    'credential scheme',
  ]);
  assert.deepEqual(scanFileContent(`${bearerScheme} ${mixedCaseAlphabeticCredential}`), [
    'credential scheme',
  ]);
  assert.deepEqual(scanFileContent(`${tokenScheme} placeholder-secret`), [
    'credential scheme',
  ]);
});

test('scanFileContent reports brace-delimited header maps', () => {
  assert.deepEqual(scanFileContent(`headers={${plexTokenHeader}: abc}`), [
    'header map credential',
  ]);
  assert.deepEqual(scanFileContent(`headers={"${plexTokenHeader}":"abc12345"}`), [
    'header map credential',
  ]);
  assert.deepEqual(scanFileContent(`headers: {'${plexTokenHeader}': 'abc12345'}`), [
    'header map credential',
  ]);
  assert.deepEqual(scanFileContent(`headers={${authorizationHeader}: ${bearerScheme} abc12345}`), [
    'raw Authorization header',
    'credential scheme',
    'header map credential',
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
    assert.deepEqual(scanFileContent(`${key}=placeholder-secret`), ['secret field value']);
    assert.deepEqual(scanFileContent(`${key}=${alphabeticCredential}`), ['secret field value']);
    assert.deepEqual(scanFileContent(`${key}=${mixedCaseAlphabeticCredential}`), [
      'secret field value',
    ]);
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
    'Bearer authentication remains a policy discussion.',
    'const authToken = readNullableString(payload.authToken)',
    'const authToken = placeholderAuthValue',
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
  assert.equal(findings[0].reason, 'raw Authorization header');
  assert.equal(findings[1].reason, 'credential scheme');
});
