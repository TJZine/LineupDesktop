import test from 'node:test';
import assert from 'node:assert/strict';

import { PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS } from '../../../contracts/player.js';
import { decideDesktopStreamPolicy } from '../../../main/player/streamPolicy/desktopStreamPolicy.js';
import type {
  DesktopStreamPolicyDecision,
  DesktopStreamPolicyDecisionKind,
  DesktopStreamPolicyReasonCode,
  DesktopStreamPolicyUnknownCode,
} from '../../../main/player/streamPolicy/types.js';
import {
  audioFallbackCandidate,
  allDesktopStreamPolicyFixtureValues,
  desktopStreamPolicyInputs,
  windowsRd07CapabilityFacts,
  windowsStreamPolicyMatrixInputs,
} from './fixtures/desktopStreamPolicyFixtures.js';

const RD08_FORBIDDEN_FIELD_KEYS = [
  'url',
  'uri',
  'href',
  'origin',
  'host',
  'hostname',
  'headers',
  'requestHeaders',
  'token',
  'accessToken',
  'plexToken',
  'sourcePayload',
  'ratingKey',
  'mediaKey',
  'partId',
  'streamId',
  'nativeHandleId',
  'processId',
  'pid',
  'engineTrackId',
] as const;

const RD08_FORBIDDEN_TEXT = [
  'http://',
  'https://',
  'plex.direct',
  'X-Plex-Token',
  'Authorization',
  'Bearer ',
] as const;

function assertNoForbiddenFields(value: unknown, path = 'value'): void {
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertNoForbiddenFields(item, `${path}[${index}]`));
    return;
  }
  if (value === null || typeof value !== 'object') {
    return;
  }

  for (const [key, child] of Object.entries(value)) {
    assert.equal(
      PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS.includes(
        key as (typeof PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS)[number],
      ),
      false,
      `${path} contains player forbidden field ${key}`,
    );
    assert.equal(
      RD08_FORBIDDEN_FIELD_KEYS.includes(key as (typeof RD08_FORBIDDEN_FIELD_KEYS)[number]),
      false,
      `${path} contains RD-08 forbidden field ${key}`,
    );
    assertNoForbiddenFields(child, `${path}.${key}`);
  }
}

function assertNoForbiddenText(value: unknown): void {
  const serialized = JSON.stringify(value);
  for (const text of RD08_FORBIDDEN_TEXT) {
    assert.equal(serialized.includes(text), false, `RD-08 value contains forbidden text ${text}`);
  }
}

function decideFixture(name: keyof typeof desktopStreamPolicyInputs): DesktopStreamPolicyDecision {
  const decision = decideDesktopStreamPolicy(desktopStreamPolicyInputs[name]);
  assertNoForbiddenFields(decision, `decision.${name}`);
  assertNoForbiddenText(decision);
  assert.equal(decision.summary.action, decision.kind);
  assert.equal(Object.hasOwn(decision.summary, 'audioLanguage'), true);
  assert.equal(Object.hasOwn(decision.summary, 'subtitleLanguage'), true);
  assert.ok(decision.reasonCodes.length > 0, 'expected stable reason codes');
  assert.ok(
    decision.unknowns.includes('desktop-parity-unproven'),
    'expected explicit unproven desktop parity unknown',
  );
  return decision;
}

function assertHasUnknowns(
  decision: DesktopStreamPolicyDecision,
  unknowns: readonly DesktopStreamPolicyUnknownCode[],
): void {
  for (const unknown of unknowns) {
    assert.ok(decision.unknowns.includes(unknown), `expected unknown ${unknown}`);
  }
}

test('desktop stream policy chooses direct play for fully supported facts', () => {
  const decision = decideFixture('directPlay');

  assert.equal(decision.kind, 'direct-play');
  assert.equal(decision.candidateId, 'candidate-direct-play');
  assert.equal(decision.selectedTrackIds.audio, 'audio-track-en-aac');
  assert.equal(decision.selectedTrackIds.subtitle, 'subtitle-track-en-embedded');
  assert.deepEqual(decision.reasonCodes, ['direct-play-supported']);
  assert.equal(decision.summary.videoCodec, 'h264');
});

test('desktop stream policy keeps direct play when unrelated remediation facts are unknown', () => {
  const decision = decideDesktopStreamPolicy({
    ...desktopStreamPolicyInputs.directPlay,
    capabilityProfile: {
      ...desktopStreamPolicyInputs.directPlay.capabilityProfile,
      directStream: {
        containerRemux: 'unknown',
        audioTranscode: 'unknown',
        subtitleConversion: 'unproven',
      },
      transcode: {
        video: 'unknown',
        audio: 'unknown',
        subtitles: 'unproven',
        hdr: 'unknown',
      },
    },
    preferredAudioTrackId: null,
  });

  assert.equal(decision.kind, 'direct-play');
  assert.equal(decision.selectedTrackIds.audio, 'audio-track-en-aac');
  assert.deepEqual(decision.reasonCodes, ['direct-play-supported']);
  assert.ok(decision.unknowns.includes('profile-direct-stream-support-unknown'));
  assert.ok(decision.unknowns.includes('profile-transcode-support-unknown'));
});

test('desktop stream policy treats null audio preference as default audio selection', () => {
  const decision = decideDesktopStreamPolicy({
    ...desktopStreamPolicyInputs.directPlay,
    preferredAudioTrackId: null,
  });

  assert.equal(decision.kind, 'direct-play');
  assert.equal(decision.selectedTrackIds.audio, 'audio-track-en-aac');
  assert.deepEqual(decision.reasonCodes, ['direct-play-supported']);
});

test('desktop stream policy chooses direct stream for supported container remux', () => {
  const decision = decideFixture('directStreamRemux');

  assert.equal(decision.kind, 'direct-stream');
  assert.equal(decision.candidateId, 'candidate-remux');
  assert.equal(decision.selectedTrackIds.subtitle, null);
  assert.deepEqual(decision.reasonCodes, [
    'direct-stream-container-remux',
    'no-subtitle-selected',
  ]);
});

test('desktop stream policy records audio fallback without exposing internals', () => {
  const decision = decideFixture('audioFallback');

  assert.equal(decision.kind, 'direct-stream');
  assert.equal(decision.selectedTrackIds.audio, 'audio-track-fallback-aac');
  assert.equal(decision.summary.audioCodec, 'aac');
  assert.deepEqual(decision.reasonCodes, [
    'direct-stream-audio-fallback',
    'requested-audio-unavailable',
    'audio-fallback-selected',
    'no-subtitle-selected',
  ]);
});

test('desktop stream policy falls back when requested audio exists but is incompatible', () => {
  const decision = decideDesktopStreamPolicy({
    ...desktopStreamPolicyInputs.audioFallback,
    preferredAudioTrackId: 'audio-track-requested-flac',
  });

  assert.equal(decision.kind, 'direct-stream');
  assert.equal(decision.selectedTrackIds.audio, 'audio-track-fallback-aac');
  assert.equal(decision.summary.audioCodec, 'aac');
  assert.deepEqual(decision.reasonCodes, [
    'direct-stream-audio-fallback',
    'audio-fallback-selected',
    'no-subtitle-selected',
  ]);
  assert.equal(decision.reasonCodes.includes('direct-stream-audio-transcode'), false);
  assert.equal(decision.reasonCodes.includes('requested-audio-unavailable'), false);
});

test('desktop stream policy records subtitle fallback through supported delivery', () => {
  const decision = decideFixture('subtitleFallback');

  assert.equal(decision.kind, 'direct-stream');
  assert.equal(decision.selectedTrackIds.subtitle, 'subtitle-track-sidecar');
  assert.equal(decision.summary.subtitleDelivery, 'sidecar');
  assert.deepEqual(decision.reasonCodes, [
    'direct-stream-subtitle-fallback',
    'requested-subtitle-unavailable',
    'subtitle-fallback-selected',
  ]);
});

test('desktop stream policy prefers forced subtitles over default subtitles without language matching', () => {
  const decision = decideFixture('forcedSubtitle');

  assert.equal(decision.kind, 'direct-play');
  assert.equal(decision.selectedTrackIds.subtitle, 'subtitle-track-es-forced');
  assert.equal(decision.summary.subtitleLanguage, 'es');
  assert.deepEqual(decision.reasonCodes, [
    'direct-play-supported',
    'forced-subtitle-selected',
  ]);
});

test('desktop stream policy selects default subtitles and preserves selected languages', () => {
  const decision = decideFixture('defaultSubtitle');

  assert.equal(decision.kind, 'direct-play');
  assert.equal(decision.selectedTrackIds.audio, 'audio-track-fr-aac-default');
  assert.equal(decision.selectedTrackIds.subtitle, 'subtitle-track-de-default');
  assert.equal(decision.summary.audioLanguage, 'fr');
  assert.equal(decision.summary.subtitleLanguage, 'de');
  assert.deepEqual(decision.reasonCodes, ['direct-play-supported']);
});

test('desktop stream policy does not use language mismatch alone to replace requested tracks', () => {
  const decision = decideFixture('languageMismatch');

  assert.equal(decision.kind, 'direct-play');
  assert.equal(decision.selectedTrackIds.audio, 'audio-track-ja-opus');
  assert.equal(decision.selectedTrackIds.subtitle, 'subtitle-track-it-sidecar');
  assert.equal(decision.summary.audioCodec, 'opus');
  assert.equal(decision.summary.audioLanguage, 'ja');
  assert.equal(decision.summary.subtitleDelivery, 'sidecar');
  assert.equal(decision.summary.subtitleLanguage, 'it');
  assert.deepEqual(decision.reasonCodes, ['direct-play-supported']);
});

test('desktop stream policy falls back when requested subtitle exists but has unsupported delivery', () => {
  const decision = decideDesktopStreamPolicy({
    ...desktopStreamPolicyInputs.subtitleFallback,
    preferredSubtitleTrackId: 'subtitle-track-requested-burn',
  });

  assert.equal(decision.kind, 'direct-stream');
  assert.equal(decision.selectedTrackIds.subtitle, 'subtitle-track-sidecar');
  assert.equal(decision.summary.subtitleDelivery, 'sidecar');
  assert.deepEqual(decision.reasonCodes, [
    'direct-stream-subtitle-fallback',
    'subtitle-fallback-selected',
  ]);
  assert.equal(decision.reasonCodes.includes('direct-stream-subtitle-conversion'), false);
  assert.equal(decision.reasonCodes.includes('requested-subtitle-unavailable'), false);
});

test('desktop stream policy converts requested incompatible subtitles when conversion is supported', () => {
  const decision = decideFixture('subtitleConversion');

  assert.equal(decision.kind, 'direct-stream');
  assert.equal(decision.selectedTrackIds.subtitle, 'subtitle-track-image-burn');
  assert.equal(decision.summary.subtitleDelivery, 'burn-in');
  assert.equal(decision.summary.subtitleLanguage, 'en');
  assert.deepEqual(decision.reasonCodes, ['direct-stream-subtitle-conversion']);
});

test('desktop stream policy does not use audio fallback when switching is unsupported', () => {
  const decision = decideDesktopStreamPolicy({
    ...desktopStreamPolicyInputs.audioFallback,
    capabilityProfile: {
      ...desktopStreamPolicyInputs.audioFallback.capabilityProfile,
      audioTrackSwitching: 'unsupported',
      directStream: {
        ...desktopStreamPolicyInputs.audioFallback.capabilityProfile.directStream,
        audioTranscode: 'unsupported',
      },
    },
  });

  assert.equal(decision.kind, 'transcode');
  assert.equal(decision.selectedTrackIds.audio, 'audio-track-requested-flac');
  assert.deepEqual(decision.reasonCodes, [
    'transcode-audio',
    'requested-audio-unavailable',
    'no-audio-compatible',
    'no-subtitle-selected',
  ]);
});

test('desktop stream policy does not let one direct stream remediation mask another failure', () => {
  const decision = decideDesktopStreamPolicy({
    ...desktopStreamPolicyInputs.audioFallback,
    capabilityProfile: {
      ...desktopStreamPolicyInputs.audioFallback.capabilityProfile,
      audioTrackSwitching: 'unsupported',
      directStream: {
        ...desktopStreamPolicyInputs.audioFallback.capabilityProfile.directStream,
        containerRemux: 'supported',
        audioTranscode: 'unsupported',
      },
    },
    candidates: [
      {
        ...audioFallbackCandidate,
        variant: {
          ...audioFallbackCandidate.variant,
          container: 'avi',
        },
      },
    ],
  });

  assert.equal(decision.kind, 'transcode');
  assert.deepEqual(decision.reasonCodes, [
    'transcode-container',
    'transcode-audio',
    'requested-audio-unavailable',
    'no-audio-compatible',
    'no-subtitle-selected',
  ]);
});

test('desktop stream policy does not use subtitle fallback when switching is unsupported', () => {
  const decision = decideDesktopStreamPolicy({
    ...desktopStreamPolicyInputs.subtitleFallback,
    capabilityProfile: {
      ...desktopStreamPolicyInputs.subtitleFallback.capabilityProfile,
      subtitleTrackSwitching: 'unsupported',
      directStream: {
        ...desktopStreamPolicyInputs.subtitleFallback.capabilityProfile.directStream,
        subtitleConversion: 'unsupported',
      },
    },
  });

  assert.equal(decision.kind, 'transcode');
  assert.equal(decision.selectedTrackIds.subtitle, 'subtitle-track-requested-burn');
  assert.deepEqual(decision.reasonCodes, [
    'transcode-subtitle',
    'requested-subtitle-unavailable',
    'no-subtitle-compatible',
  ]);
});

test('desktop stream policy records unknown direct stream capability without defaulting to direct stream', () => {
  const decision = decideDesktopStreamPolicy({
    ...desktopStreamPolicyInputs.directStreamRemux,
    capabilityProfile: {
      ...desktopStreamPolicyInputs.directStreamRemux.capabilityProfile,
      directStream: {
        ...desktopStreamPolicyInputs.directStreamRemux.capabilityProfile.directStream,
        containerRemux: 'unknown',
      },
    },
  });

  assert.equal(decision.kind, 'transcode');
  assert.deepEqual(decision.reasonCodes, ['transcode-container', 'no-subtitle-selected']);
  assert.ok(decision.unknowns.includes('profile-direct-stream-support-unknown'));
});

test('desktop stream policy chooses transcode for unsupported video with allowed transcode', () => {
  const decision = decideFixture('transcode');

  assert.equal(decision.kind, 'transcode');
  assert.equal(decision.candidateId, 'candidate-transcode');
  assert.deepEqual(decision.reasonCodes, ['transcode-video', 'no-subtitle-selected']);
  assert.equal(decision.summary.videoCodec, 'vp9');
});

test('desktop stream policy returns unsupported with stable reasons when no mode is allowed', () => {
  const decision = decideFixture('unsupported');

  assert.equal(decision.kind, 'unsupported');
  assert.equal(decision.candidateId, 'candidate-unsupported');
  assert.deepEqual(decision.reasonCodes, [
    'unsupported-container',
    'unsupported-video-codec',
    'unsupported-audio-codec',
    'unsupported-subtitle-delivery',
    'unsupported-hdr',
    'unsupported-dolby-vision',
  ]);
});

test('desktop stream policy preserves HDR only when profile explicitly supports it', () => {
  const decision = decideFixture('hdr');

  assert.equal(decision.kind, 'direct-play');
  assert.equal(decision.summary.dynamicRange, 'hdr10');
  assert.deepEqual(decision.reasonCodes, ['direct-play-supported', 'no-subtitle-selected']);
});

test('desktop stream policy transcodes Dolby Vision when preservation is unsupported', () => {
  const decision = decideFixture('dolbyVision');

  assert.equal(decision.kind, 'transcode');
  assert.equal(decision.summary.dynamicRange, 'dolby-vision');
  assert.deepEqual(decision.reasonCodes, ['transcode-dolby-vision', 'no-subtitle-selected']);
});

test('desktop stream policy returns explicit unknowns for incomplete profile and candidate facts', () => {
  const decision = decideFixture('unknownFacts');

  assert.equal(decision.kind, 'unsupported');
  assert.deepEqual(decision.reasonCodes, [
    'candidate-facts-incomplete',
    'profile-facts-incomplete',
  ]);
  assert.deepEqual([...decision.unknowns].sort(), [
    'candidate-audio-codec-unknown',
    'candidate-container-unknown',
    'candidate-hdr-unknown',
    'candidate-subtitle-delivery-unknown',
    'candidate-video-codec-unknown',
    'desktop-parity-unproven',
    'profile-audio-support-unknown',
    'profile-audio-switching-support-unknown',
    'profile-container-support-unknown',
    'profile-direct-stream-support-unknown',
    'profile-dolby-vision-support-unknown',
    'profile-hdr-support-unknown',
    'profile-header-auth-support-unknown',
    'profile-subtitle-switching-support-unknown',
    'profile-transcode-support-unknown',
    'profile-video-support-unknown',
  ]);
});

test('desktop stream policy treats unknown dynamic range as incomplete candidate HDR facts', () => {
  const decision = decideFixture('unknownDynamicRange');

  assert.equal(decision.kind, 'unsupported');
  assert.equal(decision.summary.dynamicRange, 'unknown');
  assert.deepEqual(decision.reasonCodes, ['candidate-facts-incomplete']);
  assertHasUnknowns(decision, ['candidate-hdr-unknown']);
});

test('desktop stream policy does not promote Windows RD-06/RD-07 sample facts to codec parity', () => {
  assert.equal(windowsRd07CapabilityFacts.headerAuthSetup, 'supported');
  assert.equal(windowsRd07CapabilityFacts.livePlayback, 'unsupported');
  assert.equal(windowsRd07CapabilityFacts.audioTrackSwitching, 'unknown');
  assert.equal(windowsRd07CapabilityFacts.subtitleTrackSwitching, 'unknown');
  assert.deepEqual(windowsRd07CapabilityFacts.containerFormats, []);
  assert.deepEqual(windowsRd07CapabilityFacts.videoCodecs, []);
  assert.deepEqual(windowsRd07CapabilityFacts.audioCodecs, []);
  assert.deepEqual(windowsRd07CapabilityFacts.subtitleDeliveryModes, ['unknown']);

  const profileUnknowns = [
    'desktop-parity-unproven',
    'profile-container-support-unknown',
    'profile-video-support-unknown',
    'profile-audio-support-unknown',
    'profile-subtitle-support-unknown',
    'profile-audio-switching-support-unknown',
    'profile-subtitle-switching-support-unknown',
    'profile-direct-stream-support-unknown',
    'profile-transcode-support-unknown',
    'profile-hdr-support-unknown',
    'profile-dolby-vision-support-unknown',
  ] as const satisfies readonly DesktopStreamPolicyUnknownCode[];
  const cases = [
    {
      name: 'directPlay',
      kind: 'unsupported',
      reasonCodes: [
        'profile-facts-incomplete',
        'unsupported-container',
        'unsupported-video-codec',
        'unsupported-audio-codec',
        'no-subtitle-selected',
      ],
    },
    {
      name: 'remuxUnproven',
      kind: 'unsupported',
      reasonCodes: [
        'profile-facts-incomplete',
        'unsupported-container',
        'unsupported-video-codec',
        'unsupported-audio-codec',
        'no-subtitle-selected',
      ],
    },
    {
      name: 'audioFallbackUnproven',
      kind: 'unsupported',
      reasonCodes: [
        'profile-facts-incomplete',
        'unsupported-container',
        'unsupported-video-codec',
        'unsupported-audio-codec',
        'requested-audio-unavailable',
        'no-audio-compatible',
        'no-subtitle-selected',
      ],
    },
    {
      name: 'subtitleFallbackUnproven',
      kind: 'unsupported',
      reasonCodes: [
        'profile-facts-incomplete',
        'unsupported-container',
        'unsupported-video-codec',
        'unsupported-audio-codec',
        'unsupported-subtitle-delivery',
        'requested-subtitle-unavailable',
        'no-subtitle-compatible',
      ],
    },
    {
      name: 'videoTranscodeUnproven',
      kind: 'unsupported',
      reasonCodes: [
        'profile-facts-incomplete',
        'unsupported-container',
        'unsupported-video-codec',
        'unsupported-audio-codec',
        'no-subtitle-selected',
      ],
    },
    {
      name: 'hdrUnproven',
      kind: 'unsupported',
      reasonCodes: [
        'profile-facts-incomplete',
        'unsupported-container',
        'unsupported-video-codec',
        'unsupported-audio-codec',
        'unsupported-hdr',
        'no-subtitle-selected',
      ],
    },
    {
      name: 'dolbyVisionUnproven',
      kind: 'unsupported',
      reasonCodes: [
        'profile-facts-incomplete',
        'unsupported-container',
        'unsupported-video-codec',
        'unsupported-audio-codec',
        'unsupported-hdr',
        'unsupported-dolby-vision',
        'no-subtitle-selected',
      ],
    },
  ] as const satisfies readonly {
    name: keyof typeof windowsStreamPolicyMatrixInputs;
    kind: DesktopStreamPolicyDecisionKind;
    reasonCodes: readonly DesktopStreamPolicyReasonCode[];
  }[];

  for (const matrixCase of cases) {
    const decision = decideDesktopStreamPolicy(windowsStreamPolicyMatrixInputs[matrixCase.name]);

    assert.equal(decision.kind, matrixCase.kind, matrixCase.name);
    assert.deepEqual(decision.reasonCodes, matrixCase.reasonCodes, matrixCase.name);
    assertHasUnknowns(decision, profileUnknowns);
    assertNoForbiddenFields(decision, `windowsMatrix.${matrixCase.name}`);
    assertNoForbiddenText(decision);
  }
});

test('desktop stream policy fixture inputs and outputs exclude forbidden fields recursively', () => {
  const decisions = Object.values(desktopStreamPolicyInputs).map((input) =>
    decideDesktopStreamPolicy(input),
  );
  const values = [
    ...allDesktopStreamPolicyFixtureValues,
    desktopStreamPolicyInputs,
    ...decisions,
  ];

  for (const [index, value] of values.entries()) {
    assertNoForbiddenFields(value, `rd08[${index}]`);
    assertNoForbiddenText(value);
  }
});
