import type {
  DesktopStreamCapabilityProfile,
  DesktopStreamMediaCandidate,
  DesktopStreamPolicyInput,
} from '../../../../main/player/streamPolicy/types.js';
import type { PlaybackCapabilityProfile } from '../../../../contracts/player.js';

export const desktopPolicyProfile: DesktopStreamCapabilityProfile = {
  id: 'desktop-policy-safe-profile',
  directPlayContainers: ['mp4', 'mkv'],
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

export const windowsRd07CapabilityFacts: PlaybackCapabilityProfile = {
  id: 'windows-rd07-native-presentation-facts',
  containerFormats: [],
  videoCodecs: [],
  audioCodecs: [],
  subtitleDeliveryModes: ['unknown'],
  headerAuthSetup: 'supported',
  seek: 'supported',
  volume: 'supported',
  audioTrackSwitching: 'unknown',
  subtitleTrackSwitching: 'unknown',
  overlayComposition: 'unproven',
  fullscreenHandling: 'supported',
  livePlayback: 'unsupported',
  diagnostics: 'supported',
};

export const windowsNativePresentationPolicyProfile: DesktopStreamCapabilityProfile = {
  id: 'windows-rd08-native-presentation-policy',
  directPlayContainers: windowsRd07CapabilityFacts.containerFormats,
  directPlayVideoCodecs: windowsRd07CapabilityFacts.videoCodecs,
  directPlayAudioCodecs: windowsRd07CapabilityFacts.audioCodecs,
  subtitleDeliveryModes: windowsRd07CapabilityFacts.subtitleDeliveryModes,
  headerAuthSetup: windowsRd07CapabilityFacts.headerAuthSetup,
  audioTrackSwitching: windowsRd07CapabilityFacts.audioTrackSwitching,
  subtitleTrackSwitching: windowsRd07CapabilityFacts.subtitleTrackSwitching,
  hdr: 'unproven',
  dolbyVision: 'unproven',
  directStream: {
    containerRemux: 'unknown',
    audioTranscode: 'unknown',
    subtitleConversion: 'unknown',
  },
  transcode: {
    video: 'unknown',
    audio: 'unknown',
    subtitles: 'unknown',
    hdr: 'unknown',
  },
  unknowns: ['desktop-parity-unproven'],
};

export const directPlayCandidate: DesktopStreamMediaCandidate = {
  candidateId: 'candidate-direct-play',
  media: {
    id: 'media-safe-episode',
    title: 'Safe Fixture Episode',
    durationMs: 1_800_000,
    container: 'mkv',
  },
  variant: {
    id: 'variant-main',
    container: 'mkv',
    durationMs: 1_800_000,
  },
  part: {
    id: 'safe-part-main',
    durationMs: 1_800_000,
  },
  video: {
    id: 'video-track-main',
    codec: 'h264',
    dynamicRange: 'sdr',
    width: 1920,
    height: 1080,
  },
  audioTracks: [
    {
      id: 'audio-track-en-aac',
      label: 'English AAC',
      language: 'en',
      codec: 'aac',
      channelCount: 2,
      default: true,
    },
  ],
  subtitleTracks: [
    {
      id: 'subtitle-track-en-embedded',
      label: 'English Embedded',
      language: 'en',
      delivery: 'embedded',
      format: 'srt',
      default: true,
    },
  ],
};

export const remuxCandidate: DesktopStreamMediaCandidate = {
  ...directPlayCandidate,
  candidateId: 'candidate-remux',
  variant: {
    id: 'variant-remux',
    container: 'avi',
    durationMs: 1_800_000,
  },
  part: {
    id: 'safe-part-remux',
    durationMs: 1_800_000,
  },
  media: {
    ...directPlayCandidate.media,
    id: 'media-safe-remux',
    container: 'avi',
  },
};

export const audioFallbackCandidate: DesktopStreamMediaCandidate = {
  ...directPlayCandidate,
  candidateId: 'candidate-audio-fallback',
  media: {
    ...directPlayCandidate.media,
    id: 'media-safe-audio-fallback',
  },
  audioTracks: [
    {
      id: 'audio-track-requested-flac',
      label: 'Requested FLAC',
      language: 'en',
      codec: 'flac',
      channelCount: 6,
      default: true,
    },
    {
      id: 'audio-track-fallback-aac',
      label: 'Fallback AAC',
      language: 'en',
      codec: 'aac',
      channelCount: 2,
    },
  ],
};

export const subtitleFallbackCandidate: DesktopStreamMediaCandidate = {
  ...directPlayCandidate,
  candidateId: 'candidate-subtitle-fallback',
  media: {
    ...directPlayCandidate.media,
    id: 'media-safe-subtitle-fallback',
  },
  subtitleTracks: [
    {
      id: 'subtitle-track-requested-burn',
      label: 'Requested Burn In',
      language: 'en',
      delivery: 'burn-in',
      format: 'image',
      default: true,
    },
    {
      id: 'subtitle-track-sidecar',
      label: 'Sidecar English',
      language: 'en',
      delivery: 'sidecar',
      format: 'srt',
    },
  ],
};

export const transcodeCandidate: DesktopStreamMediaCandidate = {
  ...directPlayCandidate,
  candidateId: 'candidate-transcode',
  media: {
    ...directPlayCandidate.media,
    id: 'media-safe-transcode',
  },
  video: {
    ...directPlayCandidate.video,
    codec: 'vp9',
  },
};

export const unsupportedCandidate: DesktopStreamMediaCandidate = {
  ...directPlayCandidate,
  candidateId: 'candidate-unsupported',
  media: {
    ...directPlayCandidate.media,
    id: 'media-safe-unsupported',
  },
  variant: {
    id: 'variant-unsupported',
    container: 'wmv',
    durationMs: 1_800_000,
  },
  part: {
    id: 'safe-part-unsupported',
    durationMs: 1_800_000,
  },
  video: {
    ...directPlayCandidate.video,
    codec: 'av1',
    dynamicRange: 'dolby-vision',
  },
  audioTracks: [
    {
      id: 'audio-track-unsupported',
      label: 'Unsupported Audio',
      language: 'en',
      codec: 'truehd',
      channelCount: 8,
      default: true,
    },
  ],
  subtitleTracks: [
    {
      id: 'subtitle-track-unsupported',
      label: 'Unsupported Subtitle',
      language: 'en',
      delivery: 'burn-in',
      format: 'image',
      default: true,
    },
  ],
};

export const hdrCandidate: DesktopStreamMediaCandidate = {
  ...directPlayCandidate,
  candidateId: 'candidate-hdr',
  media: {
    ...directPlayCandidate.media,
    id: 'media-safe-hdr',
  },
  video: {
    ...directPlayCandidate.video,
    codec: 'hevc',
    dynamicRange: 'hdr10',
  },
};

export const dolbyVisionCandidate: DesktopStreamMediaCandidate = {
  ...hdrCandidate,
  candidateId: 'candidate-dolby-vision',
  media: {
    ...directPlayCandidate.media,
    id: 'media-safe-dolby-vision',
  },
  video: {
    ...directPlayCandidate.video,
    codec: 'hevc',
    dynamicRange: 'dolby-vision',
  },
};

export const unknownFactsCandidate: DesktopStreamMediaCandidate = {
  ...directPlayCandidate,
  candidateId: 'candidate-unknown-facts',
  media: {
    ...directPlayCandidate.media,
    id: 'media-safe-unknown-facts',
    container: undefined,
  },
  variant: {
    id: 'variant-unknown-facts',
    container: null,
    durationMs: 1_800_000,
  },
  part: {
    id: 'safe-part-unknown-facts',
    durationMs: 1_800_000,
  },
  video: {
    id: 'video-track-unknown',
    codec: null,
    dynamicRange: 'unknown',
  },
  audioTracks: [
    {
      id: 'audio-track-unknown',
      label: 'Unknown Audio',
      language: 'en',
      codec: null,
      default: true,
    },
  ],
  subtitleTracks: [
    {
      id: 'subtitle-track-unknown',
      label: 'Unknown Subtitle',
      language: 'en',
      delivery: 'unknown',
      default: true,
    },
  ],
};

export const desktopStreamPolicyInputs: Record<string, DesktopStreamPolicyInput> = {
  directPlay: {
    capabilityProfile: desktopPolicyProfile,
    candidates: [directPlayCandidate],
    preferredAudioTrackId: 'audio-track-en-aac',
    preferredSubtitleTrackId: 'subtitle-track-en-embedded',
  },
  directStreamRemux: {
    capabilityProfile: desktopPolicyProfile,
    candidates: [remuxCandidate],
    preferredAudioTrackId: 'audio-track-en-aac',
    preferredSubtitleTrackId: null,
  },
  audioFallback: {
    capabilityProfile: desktopPolicyProfile,
    candidates: [audioFallbackCandidate],
    preferredAudioTrackId: 'audio-track-missing',
    preferredSubtitleTrackId: null,
  },
  subtitleFallback: {
    capabilityProfile: desktopPolicyProfile,
    candidates: [subtitleFallbackCandidate],
    preferredAudioTrackId: 'audio-track-en-aac',
    preferredSubtitleTrackId: 'subtitle-track-missing',
  },
  transcode: {
    capabilityProfile: desktopPolicyProfile,
    candidates: [transcodeCandidate],
    preferredAudioTrackId: 'audio-track-en-aac',
    preferredSubtitleTrackId: null,
  },
  unsupported: {
    capabilityProfile: {
      ...desktopPolicyProfile,
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
    },
    candidates: [unsupportedCandidate],
    preferredAudioTrackId: 'audio-track-unsupported',
    preferredSubtitleTrackId: 'subtitle-track-unsupported',
  },
  hdr: {
    capabilityProfile: desktopPolicyProfile,
    candidates: [hdrCandidate],
    preferredAudioTrackId: 'audio-track-en-aac',
    preferredSubtitleTrackId: null,
  },
  dolbyVision: {
    capabilityProfile: desktopPolicyProfile,
    candidates: [dolbyVisionCandidate],
    preferredAudioTrackId: 'audio-track-en-aac',
    preferredSubtitleTrackId: null,
  },
  unknownFacts: {
    capabilityProfile: {
      ...desktopPolicyProfile,
      directPlayContainers: [],
      directPlayVideoCodecs: [],
      directPlayAudioCodecs: [],
      headerAuthSetup: 'unproven',
      audioTrackSwitching: 'unknown',
      subtitleTrackSwitching: 'unproven',
      hdr: 'unknown',
      dolbyVision: 'unproven',
      directStream: {
        containerRemux: 'unknown',
        audioTranscode: 'unproven',
        subtitleConversion: 'unknown',
      },
      transcode: {
        video: 'unknown',
        audio: 'unproven',
        subtitles: 'unknown',
        hdr: 'unproven',
      },
    },
    candidates: [unknownFactsCandidate],
    preferredAudioTrackId: 'audio-track-unknown',
    preferredSubtitleTrackId: 'subtitle-track-unknown',
  },
};

export const windowsStreamPolicyMatrixInputs: Record<string, DesktopStreamPolicyInput> = {
  directPlay: {
    capabilityProfile: windowsNativePresentationPolicyProfile,
    candidates: [directPlayCandidate],
    preferredAudioTrackId: 'audio-track-en-aac',
    preferredSubtitleTrackId: null,
  },
  remuxUnproven: {
    capabilityProfile: windowsNativePresentationPolicyProfile,
    candidates: [remuxCandidate],
    preferredAudioTrackId: 'audio-track-en-aac',
    preferredSubtitleTrackId: null,
  },
  audioFallbackUnproven: {
    capabilityProfile: windowsNativePresentationPolicyProfile,
    candidates: [audioFallbackCandidate],
    preferredAudioTrackId: 'audio-track-missing',
    preferredSubtitleTrackId: null,
  },
  subtitleFallbackUnproven: {
    capabilityProfile: windowsNativePresentationPolicyProfile,
    candidates: [subtitleFallbackCandidate],
    preferredAudioTrackId: 'audio-track-en-aac',
    preferredSubtitleTrackId: 'subtitle-track-missing',
  },
  videoTranscodeUnproven: {
    capabilityProfile: windowsNativePresentationPolicyProfile,
    candidates: [transcodeCandidate],
    preferredAudioTrackId: 'audio-track-en-aac',
    preferredSubtitleTrackId: null,
  },
  hdrUnproven: {
    capabilityProfile: windowsNativePresentationPolicyProfile,
    candidates: [hdrCandidate],
    preferredAudioTrackId: 'audio-track-en-aac',
    preferredSubtitleTrackId: null,
  },
  dolbyVisionUnproven: {
    capabilityProfile: windowsNativePresentationPolicyProfile,
    candidates: [dolbyVisionCandidate],
    preferredAudioTrackId: 'audio-track-en-aac',
    preferredSubtitleTrackId: null,
  },
};

export const allDesktopStreamPolicyFixtureValues = [
  desktopPolicyProfile,
  windowsRd07CapabilityFacts,
  windowsNativePresentationPolicyProfile,
  directPlayCandidate,
  remuxCandidate,
  audioFallbackCandidate,
  subtitleFallbackCandidate,
  transcodeCandidate,
  unsupportedCandidate,
  hdrCandidate,
  dolbyVisionCandidate,
  unknownFactsCandidate,
  desktopStreamPolicyInputs,
  windowsStreamPolicyMatrixInputs,
] as const;
