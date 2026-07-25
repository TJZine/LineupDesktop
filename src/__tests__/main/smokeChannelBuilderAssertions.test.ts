import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import {
  CHANNEL_BUILDER_BRIDGE_ASSERTIONS_SOURCE,
  CHANNEL_BUILDER_FLOW_ASSERTIONS_SOURCE,
} from '../../main/smokeChannelBuilderAssertions.js';

test('smoke builder assertions pin the exact five-operation bridge and real route entry', () => {
  const source = `${CHANNEL_BUILDER_BRIDGE_ASSERTIONS_SOURCE}\n${CHANNEL_BUILDER_FLOW_ASSERTIONS_SOURCE}`;
  for (const method of ['getStatus', 'startReview', 'startApply', 'getOperation', 'cancel']) {
    assert.match(source, new RegExp(`'${method}'`, 'u'));
  }
  assert.match(source, /data-setup-flow-action="buildConfirm"/u);
  assert.match(source, /data-channel-commit-action/u);
  assert.match(source, /legacy channelSetup commit method/u);
});

test('smoke orchestration delegates builder logic to the focused owner', () => {
  const source = fs.readFileSync(
    new URL('../../main/smokeAssertions.ts', import.meta.url),
    'utf8',
  );
  assert.match(source, /CHANNEL_BUILDER_BRIDGE_ASSERTIONS_SOURCE/u);
  assert.match(source, /CHANNEL_BUILDER_FLOW_ASSERTIONS_SOURCE/u);
  assert.doesNotMatch(source, /channelCommitActionCount|channelSetupCommit/u);
});
