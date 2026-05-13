import test from 'node:test';
import assert from 'node:assert/strict';

import {
  containsDiagnosticForbiddenField,
  redactDiagnosticText,
  sanitizeDiagnosticContext,
  sanitizeDiagnosticMessage,
  sanitizeDiagnosticOperation,
  sanitizeDiagnosticRequestId,
} from '../../../contracts/diagnostics.js';
import { DIAGNOSTIC_FORBIDDEN_FIELD_KEYS } from '../../../contracts/redaction.js';
import { redactMainProcessError } from '../../../main/redactedDiagnostics.js';

const localUserPath = '/Users/example/Library/Application Support/Lineup';

test('diagnostic forbidden field detection covers recursive RD-17 keys', () => {
  for (const key of [
    'path',
    'filePath',
    'env',
    'argv',
    'pid',
    'stderr',
    'stdout',
    'rawIpc',
    'privatePlaybackDescriptor',
    'connectionUri',
    'nativeHandle',
  ]) {
    assert.equal(
      DIAGNOSTIC_FORBIDDEN_FIELD_KEYS.includes(
        key as (typeof DIAGNOSTIC_FORBIDDEN_FIELD_KEYS)[number],
      ),
      true,
      `diagnostic forbidden field list contains ${key}`,
    );
    assert.equal(containsDiagnosticForbiddenField({ nested: { [key]: 'redacted-by-rejection' } }), true);
  }

  assert.equal(containsDiagnosticForbiddenField({ safe: { status: 'failed' } }), false);
});

test('diagnostic context sanitizer rejects forbidden keys and keeps flat values only', () => {
  const sanitized = sanitizeDiagnosticContext({
    status: 'failed',
    attempt: 2,
    retryable: true,
    none: null,
    path: localUserPath,
    nested: { status: 'unsafe-shape' },
    list: ['unsafe-shape'],
  });

  assert.deepEqual(sanitized.context, {
    status: 'failed',
    attempt: 2,
    retryable: true,
    none: null,
  });
  assert.deepEqual(sanitized.rejectedForbiddenKeys, ['path']);
});

test('diagnostic context sanitizer redacts unsafe free-form keys', () => {
  const unsafePathKey = ['/Users/example/Library/Application', 'Support/Lineup/media.mkv'].join(' ');
  const unsafeProcessKey = [['p', 'id'].join(''), '12345'].join(' ');
  const unsafeNativeKey = [['native', 'Handle'].join(''), '987654321'].join(' ');
  const unsafeIpcKey = [['raw', 'Ipc'].join(''), 'channel', 'lineup:private'].join(' ');
  const unsafeCredentialKey = [['credential'].join(''), '12345'].join('');
  const unsafeContext: Record<string, string> = {
    [unsafePathKey]: 'path-key',
    [unsafeProcessKey]: 'process-key',
    [unsafeNativeKey]: 'native-key',
    [unsafeIpcKey]: 'ipc-key',
    [unsafeCredentialKey]: 'credential-key',
  };
  const sanitized = sanitizeDiagnosticContext(unsafeContext);
  const serializedKeys = JSON.stringify(Object.keys(sanitized.context ?? {}));

  assert.equal(serializedKeys.includes('Support/Lineup/media.mkv'), false);
  assert.equal(serializedKeys.includes('12345'), false);
  assert.equal(serializedKeys.includes('987654321'), false);
  assert.equal(serializedKeys.includes('channel lineup:private'), false);
  assert.equal(serializedKeys.includes('credential12345'), false);
  assert.deepEqual(Object.keys(sanitized.context ?? {}), [
    'redacted-context-key',
    'redacted-context-key-2',
    'redacted-context-key-3',
    'redacted-context-key-4',
    'redacted-context-key-5',
  ]);
});

test('diagnostic text sanitizers redact raw values before storage', () => {
  const tokenKey = ['to', 'ken'].join('');
  const authHeader = ['Authoriza', 'tion'].join('');
  const bearer = ['Bear', 'er'].join('');
  const pathKey = ['media', 'Path'].join('');
  const rawUrl = `https://media.example.invalid/video?${tokenKey}=placeholder-secret`;
  const rawPath = '/Users/example/Library/Application Support/Lineup/media.mkv';
  const rawProcessId = '12345';
  const rawHandle = '987654321';
  const rawIpcChannel = 'lineup:private';
  const unsafeText = [
    rawUrl,
    `${authHeader}: ${bearer} placeholder-secret`,
    `${pathKey}=${rawPath}`,
    `${['p', 'id'].join('')}=${rawProcessId}`,
    `${['native', 'Handle'].join('')}=${rawHandle}`,
    `${['raw', 'Ipc'].join('')}={"channel":"${rawIpcChannel}"}`,
  ].join(' ');
  const redactedText = redactDiagnosticText(unsafeText);
  const operation = sanitizeDiagnosticOperation(`load ${unsafeText}`);
  const message = sanitizeDiagnosticMessage(`failed ${unsafeText}`);
  const requestId = sanitizeDiagnosticRequestId(`request ${unsafeText}`);
  const context = sanitizeDiagnosticContext({
    safeValue: unsafeText,
    path: rawPath,
    count: 1,
  });

  for (const safeText of [
    redactedText,
    operation.operation,
    message.message,
    String(requestId.requestId),
    String(context.context?.safeValue),
  ]) {
    assert.equal(safeText.includes('placeholder-secret'), false);
    assert.equal(safeText.includes(rawPath), false);
    assert.equal(safeText.includes(rawProcessId), false);
    assert.equal(safeText.includes(rawHandle), false);
    assert.equal(safeText.includes(rawIpcChannel), false);
  }
  assert.deepEqual(context.rejectedForbiddenKeys, ['path']);
  assert.equal(context.context?.count, 1);
});

test('diagnostic request ids redact raw diagnostic material before storage', () => {
  const tokenKey = ['media', 'Token'].join('');
  const pathKey = ['file', 'Path'].join('');
  const credentialKey = ['credential'].join('');
  const nativeHandleKey = ['native', 'Handle'].join('');
  const ipcKey = ['raw', 'Ipc'].join('');
  const unsafeRequestId = [
    `https://media.example.invalid/video?${tokenKey}=placeholder-secret`,
    `${pathKey}=/Users/example/Lineup/private.mkv`,
    `${credentialKey}=credential12345`,
    `${['p', 'id'].join('')}=12345`,
    `${nativeHandleKey}=987654321`,
    `${ipcKey}={"channel":"lineup:private"}`,
  ].join(' ');
  const requestId = sanitizeDiagnosticRequestId(unsafeRequestId);

  assert.equal(requestId.requestId?.includes('placeholder-secret'), false);
  assert.equal(requestId.requestId?.includes('/Users/example/Lineup/private.mkv'), false);
  assert.equal(requestId.requestId?.includes('credential12345'), false);
  assert.equal(requestId.requestId?.includes('12345'), false);
  assert.equal(requestId.requestId?.includes('987654321'), false);
  assert.equal(requestId.requestId?.includes('lineup:private'), false);
  assert.match(requestId.requestId ?? '', /\[redacted\]/u);
});

test('diagnostic text sanitizers redact free-form unsafe tails', () => {
  const unsafeText = [
    '/Users/example/Library/Application Support/Lineup/media.mkv',
    'pid-12345',
    [['p', 'id'].join(''), '12345'].join(' '),
    'nativeHandle-987654321',
    [['native', 'Handle'].join(''), '987654321'].join(' '),
    'rawIpc-channel-lineup:private',
    [['raw', 'Ipc'].join(''), 'channel', 'lineup:private'].join(' '),
    'credential12345',
    [['credential'].join(''), '12345'].join(' '),
  ].join(' ');
  const operation = sanitizeDiagnosticOperation(`operation ${unsafeText}`);
  const message = sanitizeDiagnosticMessage(`message ${unsafeText}`);
  const requestId = sanitizeDiagnosticRequestId(`request ${unsafeText}`);
  const context = sanitizeDiagnosticContext({ safeValue: unsafeText });

  for (const safeText of [
    operation.operation,
    message.message,
    String(requestId.requestId),
    String(context.context?.safeValue),
  ]) {
    assert.equal(safeText.includes('Support/Lineup/media.mkv'), false);
    assert.equal(safeText.includes('12345'), false);
    assert.equal(safeText.includes('987654321'), false);
    assert.equal(safeText.includes('channel-lineup:private'), false);
    assert.equal(safeText.includes('channel lineup:private'), false);
    assert.equal(safeText.includes('credential12345'), false);
    assert.match(safeText, /\[redacted\]/u);
  }
});

test('diagnostic text sanitizers redact whitespace-separated free-form unsafe values', () => {
  const processProbe = [['p', 'id'].join(''), '12345'].join(' ');
  const nativeProbe = [['native', 'Handle'].join(''), '987654321'].join(' ');
  const ipcProbe = [['raw', 'Ipc'].join(''), 'channel', 'lineup:private'].join(' ');
  const credentialProbe = [['credential'].join(''), '12345'].join(' ');
  const unsafeText = [processProbe, nativeProbe, ipcProbe, credentialProbe].join(' ');
  const operation = sanitizeDiagnosticOperation(`operation ${unsafeText}`);
  const message = sanitizeDiagnosticMessage(`message ${unsafeText}`);
  const requestId = sanitizeDiagnosticRequestId(`request ${unsafeText}`);
  const context = sanitizeDiagnosticContext({ safeValue: unsafeText });

  for (const safeText of [
    operation.operation,
    message.message,
    String(requestId.requestId),
    String(context.context?.safeValue),
  ]) {
    assert.equal(safeText.includes('12345'), false);
    assert.equal(safeText.includes('987654321'), false);
    assert.equal(safeText.includes('channel lineup:private'), false);
    assert.match(safeText, /\[redacted\]/u);
  }
});

test('diagnostic string sanitizers apply Unit 1 truncation limits', () => {
  const operation = sanitizeDiagnosticOperation(` ${'o'.repeat(90)} `);
  const message = sanitizeDiagnosticMessage('m'.repeat(600));
  const requestId = sanitizeDiagnosticRequestId(` ${'r'.repeat(130)} `);

  assert.equal(operation.operation.length, 80);
  assert.equal(operation.truncation?.operationCharacters, 10);
  assert.equal(message.message.length, 512);
  assert.equal(message.truncation?.messageCharacters, 88);
  assert.equal(requestId.requestId?.length, 120);
  assert.equal(requestId.truncation?.requestIdCharacters, 10);
});

test('main diagnostic redaction removes raw path process native IPC and URL material', () => {
  const tokenKey = ['to', 'ken'].join('');
  const filePathKey = ['file', 'Path'].join('');
  const processIdKey = ['p', 'id'].join('');
  const helperOutputKey = ['std', 'err'].join('');
  const nativeHandleKey = ['native', 'Handle'].join('');
  const ipcKey = ['raw', 'Ipc'].join('');
  const rawUrl = `https://media.example.invalid/video?${tokenKey}=placeholder-secret`;
  const redacted = redactMainProcessError(
    new Error(
      [
        `url=${rawUrl}`,
        `${filePathKey}=${localUserPath}`,
        `${processIdKey}=12345`,
        `${helperOutputKey}="helper failed with private details"`,
        `${nativeHandleKey}=987654321`,
        `${ipcKey}={"channel":"lineup:private","payload":"unsafe"}`,
      ].join(' '),
    ),
  );

  assert.equal(redacted.includes('placeholder-secret'), false);
  assert.equal(redacted.includes(localUserPath), false);
  assert.equal(redacted.includes('12345'), false);
  assert.equal(redacted.includes('987654321'), false);
  assert.equal(redacted.includes('lineup:private'), false);
  assert.match(redacted, /\[redacted\]/u);
});
