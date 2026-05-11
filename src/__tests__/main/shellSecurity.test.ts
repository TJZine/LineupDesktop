import test from 'node:test';
import assert from 'node:assert/strict';

import { LINEUP_SHELL_URL } from '../../contracts/shell.js';
import {
  isAllowedShellOrigin,
  isAllowedShellUrl,
  isAuthorizedShellIpcRequest,
} from '../../main/shellSecurity.js';

test('shell URL and IPC authorization reject unexpected senders and origins', () => {
  assert.equal(isAllowedShellUrl(LINEUP_SHELL_URL), true);
  assert.equal(isAllowedShellUrl('lineup://shell/other.html'), false);
  assert.equal(isAllowedShellOrigin('lineup://shell/index.html'), true);
  assert.equal(isAllowedShellOrigin('https://example.com'), false);

  const authorized = {
    senderMatchesShell: true,
    senderDestroyed: false,
    senderUrl: LINEUP_SHELL_URL,
    frameUrl: LINEUP_SHELL_URL,
    frameIsMainFrame: true,
  };

  assert.equal(isAuthorizedShellIpcRequest(authorized), true);
  assert.equal(
    isAuthorizedShellIpcRequest({ ...authorized, senderMatchesShell: false }),
    false,
  );
  assert.equal(isAuthorizedShellIpcRequest({ ...authorized, senderDestroyed: true }), false);
  assert.equal(
    isAuthorizedShellIpcRequest({ ...authorized, senderUrl: 'lineup://shell/other.html' }),
    false,
  );
  assert.equal(
    isAuthorizedShellIpcRequest({ ...authorized, frameUrl: 'https://example.com' }),
    false,
  );
  assert.equal(isAuthorizedShellIpcRequest({ ...authorized, frameIsMainFrame: false }), false);
});
