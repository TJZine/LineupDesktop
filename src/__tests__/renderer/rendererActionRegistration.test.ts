import assert from 'node:assert/strict';
import test from 'node:test';
import { registerRendererActions } from '../../renderer/rendererActionRegistration.js';

test('renderer action registration keeps one DOM/Document/handler entrypoint', () => {
  assert.equal(registerRendererActions.length, 3);
});
