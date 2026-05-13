import test from 'node:test';
import assert from 'node:assert/strict';

import {
  hasPlayerForbiddenPrivilegedField,
  type PlayerLoadCommandPayload,
} from '../../contracts/player.js';
import {
  mapPlexMediaDetailsToDesktopStreamCandidates,
  PlexStreamResolver,
  type PlexPrivilegedPlaybackDescriptor,
  type PlexStreamResolverAuthHeader,
  type PlexStreamResolverPmsSessionStartInput,
  type PlexStreamResolverResult,
} from '../../main/plex/streamResolver.js';
import type { PlexConnection } from '../../main/plex/discovery/types.js';
import type { PlexMediaItem } from '../../main/plex/library/types.js';
import type { DesktopStreamCapabilityProfile } from '../../main/player/streamPolicy/types.js';

const PUBLIC_FORBIDDEN_KEYS = [
  'uri',
  'url',
  'headers',
  'credentialHeader',
  'playbackUrl',
  'selectedConnection',
  'mediaPath',
  'partPath',
  'key',
  'file',
  'size',
] as const;

const RAW_PLEX_PRIVATE_VALUES = [
  'variant-main',
  'part-main',
  'video-main-h264',
  'audio-main-aac',
  'subtitle-main-embedded',
  'variant-rich',
  'part-rich',
  'video-rich-dovi',
  'audio-rich-truehd',
  'audio-rich-opus',
  'subtitle-rich-forced-pgs',
  'subtitle-rich-default-srt',
] as const;
const SECRET_SHAPED_THROWN_TEXT = 'sk_live_like_1234567890abcdef';

function assertPublicSafe(value: unknown, path = 'value'): void {
  assert.equal(hasPlayerForbiddenPrivilegedField(value), false, `${path} has player privileged fields`);
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertPublicSafe(item, `${path}[${index}]`));
    return;
  }
  if (value === null || typeof value !== 'object') {
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    const normalized = key.toLowerCase();
    assert.equal(
      PUBLIC_FORBIDDEN_KEYS.some((forbidden) => {
        const forbiddenKey = forbidden.toLowerCase();
        return (
          normalized === forbiddenKey ||
          normalized.endsWith(`${forbiddenKey}s`) ||
          (forbiddenKey === 'url' && normalized.includes(forbiddenKey))
        );
      }),
      false,
      `${path} exposes forbidden key ${key}`,
    );
    assertPublicSafe(child, `${path}.${key}`);
  }
}

function assertPublicOutputDoesNotContain(value: unknown, forbiddenValues: readonly string[], path = 'value'): void {
  if (typeof value === 'string') {
    for (const forbiddenValue of forbiddenValues) {
      assert.equal(value.includes(forbiddenValue), false, `${path} contains raw Plex value ${forbiddenValue}`);
    }
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertPublicOutputDoesNotContain(item, forbiddenValues, `${path}[${index}]`));
    return;
  }
  if (value === null || typeof value !== 'object') {
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    assertPublicOutputDoesNotContain(key, forbiddenValues, `${path}.${key}:key`);
    assertPublicOutputDoesNotContain(child, forbiddenValues, `${path}.${key}`);
  }
}

function assertFailureSafe(result: Extract<PlexStreamResolverResult, { ok: false }>): void {
  assertPublicSafe(result.error, 'error');
  assertPublicSafe(result.diagnostics, 'diagnostics');
  assertPublicOutputDoesNotContain(result.error, [SECRET_SHAPED_THROWN_TEXT], 'error');
  assertPublicOutputDoesNotContain(result.diagnostics, [SECRET_SHAPED_THROWN_TEXT], 'diagnostics');
  assertPublicOutputDoesNotContain(result.error, RAW_PLEX_PRIVATE_VALUES, 'error');
  assertPublicOutputDoesNotContain(result.diagnostics, RAW_PLEX_PRIVATE_VALUES, 'diagnostics');
  if (result.decision !== undefined) {
    assertPublicSafe(result.decision, 'decision');
    assertPublicOutputDoesNotContain(result.decision, RAW_PLEX_PRIVATE_VALUES, 'decision');
  }
}

test('plex stream resolver projects direct play to safe load payload and private setup separately', async () => {
  const pmsStarts: PlexStreamResolverPmsSessionStartInput[] = [];
  const result = await createResolver({
    mediaDetail: createMediaDetail(),
    pmsStarts,
  }).resolve({
    requestId: 'request-direct-play',
    mediaId: 'media-input-direct-play',
    capabilityProfile: directPlayProfile,
    startPositionMs: 12_000,
  });

  assertResolved(result, 'direct-play');
  assert.equal(result.load.media.id, 'plex-media-media-safe-main');
  assert.equal(result.load.media.title, 'Resolver Safe Episode');
  assert.equal(result.load.media.container, 'mkv');
  assert.equal(result.load.policy.autoplay, true);
  assert.equal(result.load.policy.startPositionMs, 12_000);
  assert.equal(result.load.policy.preferredAudioTrackId, 'plex-track-audio-1-1-1');
  assert.equal(result.load.policy.preferredSubtitleTrackId, 'plex-track-subtitle-1-1-1');
  assert.equal(result.load.capabilityProfileId, directPlayProfile.id);
  assertPrivateCarriesPrivilegedSetup(result.privatePlayback);
  assertPublicProjectionSafe(result);
  assert.equal(result.pmsSession?.id, 'lease-request-direct-play');
  assert.deepEqual(pmsStarts.map((start) => start.decisionKind), ['direct-play']);
});

test('plex stream resolver projects direct stream when policy requires remux', async () => {
  const directPlay = await createResolver({
    mediaDetail: createMediaDetail(),
  }).resolve({
    requestId: 'request-direct-play-compare',
    mediaId: 'media-input-direct-play-compare',
    capabilityProfile: directPlayProfile,
  });
  assertResolved(directPlay, 'direct-play');

  const result = await createResolver({
    mediaDetail: createMediaDetail({ container: 'avi' }),
  }).resolve({
    requestId: 'request-direct-stream',
    mediaId: 'media-input-direct-stream',
    capabilityProfile: directPlayProfile,
    preferredSubtitleTrackId: null,
  });

  assertResolved(result, 'direct-stream');
  assert.equal(result.load.media.container, 'avi');
  assert.equal(result.load.policy.preferredSubtitleTrackId, null);
  assert.equal(result.decision.reasonCodes.includes('direct-stream-container-remux'), true);
  assertPrivateCarriesPrivilegedSetup(result.privatePlayback, { subtitlePrivateTrackId: null });
  assert.notEqual(result.privatePlayback.playbackUrl, directPlay.privatePlayback.playbackUrl);
  assert.match(result.privatePlayback.playbackUrl, /transcode\/universal\/start/u);
  assert.equal(result.privatePlayback.setup.playbackMode, 'direct-stream');
  assert.equal(directPlay.privatePlayback.setup.playbackMode, 'direct-play');
  assert.notDeepEqual(result.privatePlayback.setup, directPlay.privatePlayback.setup);
  assertPublicProjectionSafe(result);
});

test('plex stream resolver projects transcode without leaking private descriptor fields', async () => {
  const result = await createResolver({
    mediaDetail: createMediaDetail({ videoCodec: 'vp9' }),
  }).resolve({
    requestId: 'request-transcode',
    mediaId: 'media-input-transcode',
    capabilityProfile: directPlayProfile,
    preferredSubtitleTrackId: null,
  });

  assertResolved(result, 'transcode');
  assert.equal(result.decision.reasonCodes.includes('transcode-video'), true);
  assert.match(result.privatePlayback.playbackUrl, /transcode\/universal\/start/u);
  assertPublicProjectionSafe(result);
});

test('plex stream resolver normalizes unsupported policy without private playback output', async () => {
  const result = await createResolver({
    mediaDetail: createMediaDetail({
      container: 'wmv',
      videoCodec: 'av1',
      audioCodec: 'truehd',
      subtitleCodec: 'dvdsub',
    }),
  }).resolve({
    requestId: 'request-unsupported',
    mediaId: 'media-input-unsupported',
    capabilityProfile: unsupportedProfile,
  });

  assert.equal(result.ok, false);
  assert.equal(result.error.category, 'unsupported-media');
  assert.equal(result.error.code, 'PLEX_STREAM_UNSUPPORTED_MEDIA');
  assert.equal(result.decision?.kind, 'unsupported');
  assertFailureSafe(result);
  assert.equal(Object.hasOwn(result, 'privatePlayback'), false);
});

test('plex stream resolver preserves language delivery default forced and HDR facts through safe decisions', async () => {
  const result = await createResolver({
    mediaDetail: createRichMediaDetail(),
  }).resolve({
    requestId: 'request-rich-facts',
    mediaId: 'media-input-rich-facts',
    capabilityProfile: {
      ...directPlayProfile,
      id: 'resolver-rich-facts-profile',
      directPlayVideoCodecs: ['hevc'],
      directPlayAudioCodecs: ['truehd', 'opus'],
      dolbyVision: 'supported',
    },
  });

  assertResolved(result, 'direct-play');
  assert.equal(result.load.policy.preferredAudioTrackId, 'plex-track-audio-1-1-2');
  assert.equal(result.load.policy.preferredSubtitleTrackId, 'plex-track-subtitle-1-1-1');
  assert.equal(result.decision.summary.audioCodec, 'opus');
  assert.equal(result.decision.summary.audioLanguage, 'en');
  assert.equal(result.decision.summary.subtitleDelivery, 'embedded');
  assert.equal(result.decision.summary.subtitleLanguage, 'es');
  assert.equal(result.decision.summary.dynamicRange, 'dolby-vision');
  assert.equal(result.decision.reasonCodes.includes('forced-subtitle-selected'), true);
  assert.equal(result.privatePlayback.setup.selectedPrivateTrackIds.audio, 'audio-rich-opus');
  assert.equal(result.privatePlayback.setup.selectedPrivateTrackIds.subtitle, 'subtitle-rich-forced-pgs');
  assertPublicProjectionSafe(result);
});

test('plex stream resolver normalizes missing selected connection safely', async () => {
  const result = await createResolver({
    selectedConnection: null,
    mediaDetail: createMediaDetail(),
  }).resolve({
    requestId: 'request-no-connection',
    mediaId: 'media-input-no-connection',
    capabilityProfile: directPlayProfile,
  });

  assert.equal(result.ok, false);
  assert.equal(result.error.code, 'PLEX_STREAM_CONNECTION_UNAVAILABLE');
  assertFailureSafe(result);
});

test('plex stream resolver normalizes thrown selected connection failures safely', async () => {
  const result = await createResolver({
    selectedConnectionError: new Error(`selected connection failed ${SECRET_SHAPED_THROWN_TEXT}`),
    mediaDetail: createMediaDetail(),
  }).resolve({
    requestId: 'request-thrown-connection',
    mediaId: 'media-input-thrown-connection',
    capabilityProfile: directPlayProfile,
  });

  assert.equal(result.ok, false);
  assert.equal(result.error.code, 'PLEX_STREAM_CONNECTION_UNAVAILABLE');
  assertFailureSafe(result);
});

test('plex stream resolver normalizes missing credential safely', async () => {
  const result = await createResolver({
    activeHeader: null,
    mediaDetail: createMediaDetail(),
  }).resolve({
    requestId: 'request-no-credential',
    mediaId: 'media-input-no-credential',
    capabilityProfile: directPlayProfile,
  });

  assert.equal(result.ok, false);
  assert.equal(result.error.category, 'authentication');
  assert.equal(result.error.code, 'PLEX_STREAM_CREDENTIAL_UNAVAILABLE');
  assertFailureSafe(result);
});

test('plex stream resolver normalizes thrown credential failures safely', async () => {
  const result = await createResolver({
    activeHeaderError: new Error(`active credential failed ${SECRET_SHAPED_THROWN_TEXT}`),
    mediaDetail: createMediaDetail(),
  }).resolve({
    requestId: 'request-thrown-credential',
    mediaId: 'media-input-thrown-credential',
    capabilityProfile: directPlayProfile,
  });

  assert.equal(result.ok, false);
  assert.equal(result.error.category, 'authentication');
  assert.equal(result.error.code, 'PLEX_STREAM_CREDENTIAL_UNAVAILABLE');
  assertFailureSafe(result);
});

test('plex stream resolver normalizes missing media detail safely', async () => {
  const result = await createResolver({
    mediaDetail: null,
  }).resolve({
    requestId: 'request-no-media',
    mediaId: 'media-input-no-media',
    capabilityProfile: directPlayProfile,
  });

  assert.equal(result.ok, false);
  assert.equal(result.error.code, 'PLEX_STREAM_MEDIA_UNAVAILABLE');
  assertFailureSafe(result);
});

test('plex stream resolver normalizes thrown media detail failures safely', async () => {
  const result = await createResolver({
    mediaDetailError: new Error(`media detail failed ${SECRET_SHAPED_THROWN_TEXT}`),
    mediaDetail: createMediaDetail(),
  }).resolve({
    requestId: 'request-thrown-media-detail',
    mediaId: 'media-input-thrown-media-detail',
    capabilityProfile: directPlayProfile,
  });

  assert.equal(result.ok, false);
  assert.equal(result.error.code, 'PLEX_STREAM_MEDIA_UNAVAILABLE');
  assertFailureSafe(result);
});

test('plex stream resolver normalizes invalid media detail safely', async () => {
  const result = await createResolver({
    mediaDetail: createMediaDetail({ includeParts: false }),
  }).resolve({
    requestId: 'request-invalid-media',
    mediaId: 'media-input-invalid-media',
    capabilityProfile: directPlayProfile,
  });

  assert.equal(result.ok, false);
  assert.equal(result.error.code, 'PLEX_STREAM_UNSUPPORTED_MEDIA');
  assertFailureSafe(result);
});

test('plex media detail candidate mapping remains public-policy safe', () => {
  const candidates = mapPlexMediaDetailsToDesktopStreamCandidates(createMediaDetail());

  assert.equal(candidates.length, 1);
  assert.equal(candidates[0]?.video.codec, 'h264');
  assert.equal(candidates[0]?.video.id, 'plex-track-video-1-1-1');
  assert.equal(candidates[0]?.candidateId, 'plex-candidate-1-1');
  assert.equal(candidates[0]?.variant.id, 'plex-variant-1');
  assert.equal(candidates[0]?.part.id, 'plex-part-1');
  assert.equal(candidates[0]?.audioTracks[0]?.id, 'plex-track-audio-1-1-1');
  assert.equal(candidates[0]?.audioTracks[0]?.language, 'en');
  assert.equal(candidates[0]?.subtitleTracks[0]?.delivery, 'embedded');
  assert.equal(candidates[0]?.subtitleTracks[0]?.language, 'en');
  assertPublicSafe(candidates, 'candidates');
  assertPublicOutputDoesNotContain(candidates, RAW_PLEX_PRIVATE_VALUES, 'candidates');
});

test('plex media detail candidate mapping projects rich track facts without private ids', () => {
  const [candidate] = mapPlexMediaDetailsToDesktopStreamCandidates(createRichMediaDetail());

  assert.ok(candidate);
  assert.equal(candidate.video.codec, 'hevc');
  assert.equal(candidate.video.dynamicRange, 'dolby-vision');
  assert.equal(candidate.audioTracks[0]?.id, 'plex-track-audio-1-1-1');
  assert.equal(candidate.audioTracks[0]?.language, 'es');
  assert.equal(candidate.audioTracks[0]?.codec, 'truehd');
  assert.equal(candidate.audioTracks[0]?.channelCount, 8);
  assert.equal(candidate.audioTracks[0]?.default, false);
  assert.equal(candidate.audioTracks[1]?.id, 'plex-track-audio-1-1-2');
  assert.equal(candidate.audioTracks[1]?.language, 'en');
  assert.equal(candidate.audioTracks[1]?.codec, 'opus');
  assert.equal(candidate.audioTracks[1]?.default, true);
  assert.equal(candidate.subtitleTracks[0]?.id, 'plex-track-subtitle-1-1-1');
  assert.equal(candidate.subtitleTracks[0]?.language, 'es');
  assert.equal(candidate.subtitleTracks[0]?.delivery, 'embedded');
  assert.equal(candidate.subtitleTracks[0]?.format, 'pgs');
  assert.equal(candidate.subtitleTracks[0]?.forced, true);
  assert.equal(candidate.subtitleTracks[1]?.id, 'plex-track-subtitle-1-1-2');
  assert.equal(candidate.subtitleTracks[1]?.language, 'en');
  assert.equal(candidate.subtitleTracks[1]?.delivery, 'sidecar');
  assert.equal(candidate.subtitleTracks[1]?.format, 'srt');
  assert.equal(candidate.subtitleTracks[1]?.default, true);
  assertPublicSafe(candidate, 'candidate');
  assertPublicOutputDoesNotContain(candidate, RAW_PLEX_PRIVATE_VALUES, 'candidate');
});

function createResolver(options: {
  selectedConnection?: PlexConnection | null;
  selectedConnectionError?: Error;
  activeHeader?: PlexStreamResolverAuthHeader | null;
  activeHeaderError?: Error;
  mediaDetail: PlexMediaItem | null;
  mediaDetailError?: Error;
  pmsStarts?: PlexStreamResolverPmsSessionStartInput[];
}): PlexStreamResolver {
  const pmsStarts = options.pmsStarts ?? [];
  return new PlexStreamResolver({
    selectedConnection: {
      async getSelectedConnection() {
        if (options.selectedConnectionError !== undefined) {
          throw options.selectedConnectionError;
        }
        return options.selectedConnection === undefined ? selectedConnection : options.selectedConnection;
      },
    },
    activeCredential: {
      async getActiveAuthHeader() {
        if (options.activeHeaderError !== undefined) {
          throw options.activeHeaderError;
        }
        return options.activeHeader === undefined ? privateHeader : options.activeHeader;
      },
    },
    mediaDetail: {
      async getMediaDetail() {
        if (options.mediaDetailError !== undefined) {
          throw options.mediaDetailError;
        }
        return options.mediaDetail;
      },
    },
    pmsSession: {
      async startSession(input) {
        pmsStarts.push(input);
        return { id: `lease-${input.requestId}`, requestId: input.requestId };
      },
    },
  });
}

function assertResolved(
  result: PlexStreamResolverResult,
  kind: 'direct-play' | 'direct-stream' | 'transcode',
): asserts result is Extract<PlexStreamResolverResult, { ok: true }> {
  assert.equal(result.ok, true);
  assert.equal(result.decision.kind, kind);
}

function assertPublicProjectionSafe(result: Extract<PlexStreamResolverResult, { ok: true }>): void {
  assertSafeLoadPayload(result.load);
  assertPublicSafe(result.decision, 'decision');
  assertPublicSafe(result.diagnostics, 'diagnostics');
  assertPublicSafe(result.pmsSession, 'pmsSession');
  assertPublicOutputDoesNotContain(result.load, RAW_PLEX_PRIVATE_VALUES, 'load');
  assertPublicOutputDoesNotContain(result.decision, RAW_PLEX_PRIVATE_VALUES, 'decision');
  assertPublicOutputDoesNotContain(result.diagnostics, RAW_PLEX_PRIVATE_VALUES, 'diagnostics');
}

function assertSafeLoadPayload(load: PlayerLoadCommandPayload): void {
  assertPublicSafe(load, 'load');
  const serialized = JSON.stringify(load);
  assert.equal(serialized.includes(privateHeader.value), false, 'load leaked private header value');
  assert.equal(serialized.includes(selectedConnection.uri), false, 'load leaked selected connection');
}

function assertPrivateCarriesPrivilegedSetup(
  descriptor: PlexPrivilegedPlaybackDescriptor,
  expected: { subtitlePrivateTrackId?: string | null } = {},
): void {
  assert.equal(descriptor.credentialHeader.value, privateHeader.value);
  assert.equal(descriptor.selectedConnection.address, selectedConnection.address);
  assert.equal(descriptor.playbackUrl.startsWith(selectedConnection.uri), true);
  assert.equal(descriptor.setup.partPath, '/library/parts/safe-main');
  assert.equal(descriptor.setup.selectedPrivateTrackIds.video, 'video-main-h264');
  assert.equal(descriptor.setup.selectedPrivateTrackIds.audio, 'audio-main-aac');
  assert.equal(
    descriptor.setup.selectedPrivateTrackIds.subtitle,
    expected.subtitlePrivateTrackId === undefined ? 'subtitle-main-embedded' : expected.subtitlePrivateTrackId,
  );
}

function createMediaDetail(options: {
  container?: string;
  videoCodec?: string;
  audioCodec?: string;
  subtitleCodec?: string;
  includeParts?: boolean;
} = {}): PlexMediaItem {
  const includeParts = options.includeParts ?? true;
  return {
    ratingKey: 'media-safe-main',
    key: '/library/metadata/safe-main',
    type: 'episode',
    title: 'Resolver Safe Episode',
    sortTitle: 'Resolver Safe Episode',
    summary: 'Safe summary',
    year: 2026,
    durationMs: 1_800_000,
    addedAt: new Date('2026-01-01T00:00:00.000Z'),
    updatedAt: new Date('2026-01-01T00:00:00.000Z'),
    thumb: null,
    art: null,
    parentTitle: 'Resolver Safe Show',
    media: [
      {
        id: 'variant-main',
        duration: 1_800_000,
        bitrate: 4_000,
        width: 1920,
        height: 1080,
        aspectRatio: 1.78,
        videoCodec: options.videoCodec ?? 'h264',
        audioCodec: options.audioCodec ?? 'aac',
        audioChannels: 2,
        container: options.container ?? 'mkv',
        videoResolution: '1080',
        parts: includeParts
          ? [
              {
                id: 'part-main',
                key: '/library/parts/safe-main',
                duration: 1_800_000,
                file: 'safe-main.mkv',
                size: 123_456,
                container: options.container ?? 'mkv',
                streams: [
                  {
                    id: 'video-main-h264',
                    streamType: 1,
                    codec: options.videoCodec ?? 'h264',
                    width: 1920,
                    height: 1080,
                    dynamicRange: 'sdr',
                  },
                  {
                    id: 'audio-main-aac',
                    streamType: 2,
                    codec: options.audioCodec ?? 'aac',
                    language: 'English',
                    languageCode: 'en',
                    displayTitle: 'English AAC',
                    channels: 2,
                    default: true,
                  },
                  {
                    id: 'subtitle-main-embedded',
                    streamType: 3,
                    codec: options.subtitleCodec ?? 'srt',
                    language: 'English',
                    languageCode: 'en',
                    displayTitle: 'English Embedded',
                    default: true,
                  },
                ],
              },
            ]
          : [],
      },
    ],
  };
}

function createRichMediaDetail(): PlexMediaItem {
  return {
    ...createMediaDetail(),
    ratingKey: 'media-rich-main',
    media: [
      {
        id: 'variant-rich',
        duration: 1_800_000,
        bitrate: 9_000,
        width: 3840,
        height: 2160,
        aspectRatio: 1.78,
        videoCodec: 'hevc',
        audioCodec: 'opus',
        audioChannels: 6,
        container: 'mkv',
        videoResolution: '4k',
        parts: [
          {
            id: 'part-rich',
            key: '/library/parts/rich-main',
            duration: 1_800_000,
            file: 'rich-main.mkv',
            size: 654_321,
            container: 'mkv',
            streams: [
              {
                id: 'video-rich-dovi',
                streamType: 1,
                codec: 'hevc',
                width: 3840,
                height: 2160,
                doviProfile: '8',
                dynamicRange: 'Dolby Vision',
              },
              {
                id: 'audio-rich-truehd',
                streamType: 2,
                codec: 'truehd',
                language: 'Spanish',
                languageCode: 'es',
                displayTitle: 'Spanish TrueHD',
                channels: 8,
                default: true,
              },
              {
                id: 'audio-rich-opus',
                streamType: 2,
                codec: 'opus',
                language: 'English',
                languageCode: 'en',
                displayTitle: 'English Opus',
                channels: 6,
                selected: true,
              },
              {
                id: 'subtitle-rich-forced-pgs',
                streamType: 3,
                codec: 'pgs',
                format: 'pgs',
                language: 'Spanish',
                languageCode: 'es',
                displayTitle: 'Spanish Forced PGS',
                forced: true,
              },
              {
                id: 'subtitle-rich-default-srt',
                streamType: 3,
                codec: 'srt',
                format: 'srt',
                key: '/library/streams/rich-default-srt',
                language: 'English',
                languageCode: 'en',
                displayTitle: 'English Sidecar SRT',
                default: true,
              },
            ],
          },
        ],
      },
    ],
  };
}

const selectedConnection: PlexConnection = {
  uri: 'https://secret.example',
  protocol: 'https',
  address: 'secret.example',
  port: 443,
  local: false,
  relay: false,
  latencyMs: 8,
};

const privateHeader: PlexStreamResolverAuthHeader = {
  name: 'X-Lineup-Private-Setup',
  value: 'setup-private-value',
};

const directPlayProfile: DesktopStreamCapabilityProfile = {
  id: 'resolver-policy-profile',
  directPlayContainers: ['mkv', 'mp4'],
  directPlayVideoCodecs: ['h264', 'hevc'],
  directPlayAudioCodecs: ['aac', 'opus'],
  subtitleDeliveryModes: ['embedded', 'sidecar', 'external', 'none'],
  headerAuthSetup: 'supported',
  audioTrackSwitching: 'supported',
  subtitleTrackSwitching: 'supported',
  hdr: 'supported',
  dolbyVision: 'unsupported',
  directStream: {
    containerRemux: 'supported',
    audioTranscode: 'supported',
    subtitleConversion: 'supported',
  },
  transcode: {
    video: 'supported',
    audio: 'supported',
    subtitles: 'supported',
    hdr: 'supported',
  },
  unknowns: ['desktop-parity-unproven'],
};

const unsupportedProfile: DesktopStreamCapabilityProfile = {
  ...directPlayProfile,
  id: 'resolver-unsupported-profile',
  directPlayContainers: ['mkv'],
  directPlayVideoCodecs: ['h264'],
  directPlayAudioCodecs: ['aac'],
  subtitleDeliveryModes: ['embedded'],
  directStream: {
    containerRemux: 'unsupported',
    audioTranscode: 'unsupported',
    subtitleConversion: 'unsupported',
  },
  transcode: {
    video: 'unsupported',
    audio: 'unsupported',
    subtitles: 'unsupported',
    hdr: 'unsupported',
  },
};
