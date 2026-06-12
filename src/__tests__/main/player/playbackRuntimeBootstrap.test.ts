import test from 'node:test';
import assert from 'node:assert/strict';

import { getProductionCapabilityProfile } from '../../../main/player/playbackRuntimeBootstrap.js';

test('production playback capability profile advertises only proven conservative native-helper behaviors', () => {
  const profile = getProductionCapabilityProfile();

  assert.equal(profile.id, 'windows-native-production-conservative');
  assert.deepEqual(profile.directPlayContainers, ['mp4']);
  assert.deepEqual(profile.directPlayVideoCodecs, ['h264']);
  assert.deepEqual(profile.directPlayAudioCodecs, ['aac']);
  assert.deepEqual(profile.subtitleDeliveryModes, ['none']);
  assert.equal(profile.headerAuthSetup, 'supported');
  assert.equal(profile.audioTrackSwitching, 'unsupported');
  assert.equal(profile.subtitleTrackSwitching, 'unsupported');
  assert.equal(profile.hdr, 'unsupported');
  assert.equal(profile.dolbyVision, 'unsupported');
  assert.equal(profile.directStream.containerRemux, 'unsupported');
  assert.equal(profile.directStream.audioTranscode, 'unsupported');
  assert.equal(profile.directStream.subtitleConversion, 'unsupported');
  assert.equal(profile.transcode.video, 'unsupported');
  assert.equal(profile.transcode.audio, 'unsupported');
  assert.equal(profile.transcode.subtitles, 'unsupported');
  assert.equal(profile.transcode.hdr, 'unsupported');
});
