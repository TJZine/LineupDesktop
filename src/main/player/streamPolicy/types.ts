import type {
  PlayerCapabilitySupport,
  PlayerMediaSummary,
  PlayerSubtitleDeliveryMode,
  PlayerTrackId,
} from '../../../contracts/player.js';

export type DesktopStreamPolicyDecisionKind =
  | 'direct-play'
  | 'direct-stream'
  | 'transcode'
  | 'unsupported';

export type DesktopStreamPolicyReasonCode =
  | 'direct-play-supported'
  | 'direct-stream-container-remux'
  | 'direct-stream-audio-transcode'
  | 'direct-stream-audio-fallback'
  | 'direct-stream-subtitle-conversion'
  | 'direct-stream-subtitle-fallback'
  | 'transcode-video'
  | 'transcode-container'
  | 'transcode-audio'
  | 'transcode-subtitle'
  | 'transcode-hdr'
  | 'transcode-dolby-vision'
  | 'unsupported-container'
  | 'unsupported-video-codec'
  | 'unsupported-audio-codec'
  | 'unsupported-subtitle-delivery'
  | 'unsupported-hdr'
  | 'unsupported-dolby-vision'
  | 'audio-fallback-selected'
  | 'subtitle-fallback-selected'
  | 'no-audio-compatible'
  | 'no-subtitle-compatible'
  | 'requested-audio-unavailable'
  | 'requested-subtitle-unavailable'
  | 'forced-subtitle-selected'
  | 'no-subtitle-selected'
  | 'candidate-facts-incomplete'
  | 'profile-facts-incomplete'
  | 'transcode-unavailable';

export type DesktopStreamPolicyUnknownCode =
  | 'profile-container-support-unknown'
  | 'profile-video-support-unknown'
  | 'profile-audio-support-unknown'
  | 'profile-subtitle-support-unknown'
  | 'profile-header-auth-support-unknown'
  | 'profile-audio-switching-support-unknown'
  | 'profile-subtitle-switching-support-unknown'
  | 'profile-direct-stream-support-unknown'
  | 'profile-transcode-support-unknown'
  | 'profile-hdr-support-unknown'
  | 'profile-dolby-vision-support-unknown'
  | 'candidate-container-unknown'
  | 'candidate-video-codec-unknown'
  | 'candidate-audio-codec-unknown'
  | 'candidate-subtitle-delivery-unknown'
  | 'candidate-hdr-unknown'
  | 'desktop-parity-unproven';

export type DesktopStreamDynamicRange = 'sdr' | 'hdr10' | 'dolby-vision' | 'unknown';

export interface DesktopStreamCapabilityProfile {
  id: string;
  directPlayContainers: readonly string[];
  directPlayVideoCodecs: readonly string[];
  directPlayAudioCodecs: readonly string[];
  subtitleDeliveryModes: readonly PlayerSubtitleDeliveryMode[];
  headerAuthSetup: PlayerCapabilitySupport;
  audioTrackSwitching: PlayerCapabilitySupport;
  subtitleTrackSwitching: PlayerCapabilitySupport;
  hdr: PlayerCapabilitySupport;
  dolbyVision: PlayerCapabilitySupport;
  directStream: {
    containerRemux: PlayerCapabilitySupport;
    audioTranscode: PlayerCapabilitySupport;
    subtitleConversion: PlayerCapabilitySupport;
  };
  transcode: {
    video: PlayerCapabilitySupport;
    audio: PlayerCapabilitySupport;
    subtitles: PlayerCapabilitySupport;
    hdr: PlayerCapabilitySupport;
  };
  unknowns?: readonly DesktopStreamPolicyUnknownCode[];
}

export interface DesktopStreamMediaCandidate {
  candidateId: string;
  media: PlayerMediaSummary;
  variant: {
    id: string;
    container?: string | null;
    durationMs?: number | null;
  };
  part: {
    id: string;
    durationMs?: number | null;
  };
  video: {
    id: PlayerTrackId;
    codec?: string | null;
    dynamicRange?: DesktopStreamDynamicRange | null;
    width?: number;
    height?: number;
  };
  audioTracks: readonly DesktopStreamAudioCandidate[];
  subtitleTracks: readonly DesktopStreamSubtitleCandidate[];
}

export interface DesktopStreamAudioCandidate {
  id: PlayerTrackId;
  label: string;
  language?: string;
  codec?: string | null;
  channelCount?: number;
  default?: boolean;
}

export interface DesktopStreamSubtitleCandidate {
  id: PlayerTrackId;
  label: string;
  language?: string;
  delivery: PlayerSubtitleDeliveryMode;
  format?: string;
  forced?: boolean;
  default?: boolean;
}

export interface DesktopStreamPolicyInput {
  capabilityProfile: DesktopStreamCapabilityProfile;
  candidates: readonly DesktopStreamMediaCandidate[];
  preferredAudioTrackId?: PlayerTrackId | null;
  preferredSubtitleTrackId?: PlayerTrackId | null;
}

export interface DesktopStreamPolicyDecision {
  kind: DesktopStreamPolicyDecisionKind;
  candidateId: string | null;
  selectedTrackIds: {
    video: PlayerTrackId | null;
    audio: PlayerTrackId | null;
    subtitle: PlayerTrackId | null;
  };
  summary: {
    media: Pick<PlayerMediaSummary, 'id' | 'title'> | null;
    container: string | null;
    videoCodec: string | null;
    audioCodec: string | null;
    subtitleDelivery: PlayerSubtitleDeliveryMode | null;
    dynamicRange: DesktopStreamDynamicRange | null;
    action: DesktopStreamPolicyDecisionKind;
  };
  reasonCodes: readonly DesktopStreamPolicyReasonCode[];
  unknowns: readonly DesktopStreamPolicyUnknownCode[];
}
