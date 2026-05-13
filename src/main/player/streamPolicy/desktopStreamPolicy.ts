import type {
  DesktopStreamAudioCandidate,
  DesktopStreamCapabilityProfile,
  DesktopStreamMediaCandidate,
  DesktopStreamPolicyDecision,
  DesktopStreamPolicyInput,
  DesktopStreamPolicyReasonCode,
  DesktopStreamPolicyUnknownCode,
  DesktopStreamSubtitleCandidate,
} from './types.js';

type Evaluation = {
  decision: DesktopStreamPolicyDecision;
  rank: number;
};

type TrackSelection = {
  audio: DesktopStreamAudioCandidate | null;
  subtitle: DesktopStreamSubtitleCandidate | null;
  audioFallback: boolean;
  subtitleFallback: boolean;
  reasons: DesktopStreamPolicyReasonCode[];
  unknowns: DesktopStreamPolicyUnknownCode[];
};

const DECISION_RANK: Record<DesktopStreamPolicyDecision['kind'], number> = {
  'direct-play': 0,
  'direct-stream': 1,
  transcode: 2,
  unsupported: 3,
};

/** Fixture stream policy ranks deterministic decisions with explicit reasons/unknowns instead of treating candidate or profile unknowns as support. */ export function decideDesktopStreamPolicy(
  input: DesktopStreamPolicyInput,
): DesktopStreamPolicyDecision {
  const evaluations = input.candidates.map((candidate) => evaluateCandidate(input, candidate));
  if (evaluations.length === 0) {
    return unsupportedDecision(['candidate-facts-incomplete'], ['desktop-parity-unproven']);
  }

  const [best] = evaluations.sort((left, right) => left.rank - right.rank);
  return best.decision;
}

function evaluateCandidate(
  input: DesktopStreamPolicyInput,
  candidate: DesktopStreamMediaCandidate,
): Evaluation {
  const profile = input.capabilityProfile;
  const selection = selectTracks(input, candidate);
  const baseReasons = [...selection.reasons];
  const unknowns = collectUnknowns(profile, candidate, selection);
  const containerSupported = isKnownSupported(
    candidate.variant.container,
    profile.directPlayContainers,
  );
  const videoSupported = isKnownSupported(candidate.video.codec, profile.directPlayVideoCodecs);
  const audioSupported =
    selection.audio !== null &&
    isKnownSupported(selection.audio.codec, profile.directPlayAudioCodecs);
  const subtitleSupported =
    selection.subtitle === null ||
    (selection.subtitle.delivery !== 'unknown' &&
      profile.subtitleDeliveryModes.includes(selection.subtitle.delivery));
  const hdrSupported = isDynamicRangeSupported(profile, candidate.video.dynamicRange);

  const directPlayReasons = [...baseReasons];
  if (
    containerSupported &&
    videoSupported &&
    audioSupported &&
    subtitleSupported &&
    hdrSupported &&
    !selection.audioFallback &&
    !selection.subtitleFallback
  ) {
    directPlayReasons.unshift('direct-play-supported');
    return {
      decision: buildDecision('direct-play', candidate, selection, directPlayReasons, unknowns),
      rank: DECISION_RANK['direct-play'],
    };
  }

  const incompleteReasons = buildIncompleteFactReasons(unknowns);
  if (incompleteReasons.includes('candidate-facts-incomplete')) {
    return {
      decision: buildDecision(
        'unsupported',
        candidate,
        selection,
        [...incompleteReasons, ...baseReasons],
        unknowns,
      ),
      rank: DECISION_RANK.unsupported,
    };
  }

  const directStreamReasons = buildDirectStreamReasons({
    profile,
    containerSupported,
    videoSupported,
    audioSupported,
    subtitleSupported,
    hdrSupported,
    selection,
  });
  if (
    directStreamReasons.length > 0 &&
    canDirectStream({
      profile,
      containerSupported,
      videoSupported,
      audioSupported,
      subtitleSupported,
      hdrSupported,
    })
  ) {
    return {
      decision: buildDecision(
        'direct-stream',
        candidate,
        selection,
        [...directStreamReasons, ...baseReasons],
        unknowns,
      ),
      rank: DECISION_RANK['direct-stream'],
    };
  }

  const transcodeReasons = buildTranscodeReasons({
    profile,
    containerSupported,
    videoSupported,
    audioSupported,
    subtitleSupported,
    hdrSupported,
    dynamicRange: candidate.video.dynamicRange,
  });
  if (transcodeReasons.length > 0) {
    return {
      decision: buildDecision(
        'transcode',
        candidate,
        selection,
        [...transcodeReasons, ...baseReasons],
        unknowns,
      ),
      rank: DECISION_RANK.transcode,
    };
  }

  return {
    decision: buildDecision(
      'unsupported',
      candidate,
      selection,
      [
        ...incompleteReasons,
        ...buildUnsupportedReasons({
          containerSupported,
          videoSupported,
          audioSupported,
          subtitleSupported,
          hdrSupported,
          selection,
          dolbyVisionUnsupported: candidate.video.dynamicRange === 'dolby-vision',
        }),
        ...baseReasons,
      ],
      unknowns,
    ),
    rank: DECISION_RANK.unsupported,
  };
}

function selectTracks(
  input: DesktopStreamPolicyInput,
  candidate: DesktopStreamMediaCandidate,
): TrackSelection {
  const reasons: DesktopStreamPolicyReasonCode[] = [];
  const unknowns: DesktopStreamPolicyUnknownCode[] = [];
  const audio = selectAudio(input, candidate, reasons, unknowns);
  const subtitle = selectSubtitle(input, candidate, reasons, unknowns);
  return {
    audio: audio.track,
    subtitle: subtitle.track,
    audioFallback: audio.fallback,
    subtitleFallback: subtitle.fallback,
    reasons,
    unknowns,
  };
}

function selectAudio(
  input: DesktopStreamPolicyInput,
  candidate: DesktopStreamMediaCandidate,
  reasons: DesktopStreamPolicyReasonCode[],
  unknowns: DesktopStreamPolicyUnknownCode[],
): { track: DesktopStreamAudioCandidate | null; fallback: boolean } {
  const preferredAudioTrackId = input.preferredAudioTrackId;
  const hasPreferredAudioTrack =
    preferredAudioTrackId !== undefined && preferredAudioTrackId !== null;
  const requested = hasPreferredAudioTrack
    ? candidate.audioTracks.find((track) => track.id === preferredAudioTrackId)
    : undefined;
  if (requested && isAudioSupported(input.capabilityProfile, requested)) {
    return { track: requested, fallback: false };
  }
  if (hasPreferredAudioTrack && !requested) {
    reasons.push('requested-audio-unavailable');
  }

  const defaultCompatible = candidate.audioTracks.find(
    (track) => track.default === true && isAudioSupported(input.capabilityProfile, track),
  );
  if (defaultCompatible && !hasPreferredAudioTrack) {
    return { track: defaultCompatible, fallback: false };
  }
  if (defaultCompatible && input.capabilityProfile.audioTrackSwitching === 'supported') {
    reasons.push('audio-fallback-selected');
    return { track: defaultCompatible, fallback: true };
  }

  const compatible = candidate.audioTracks.find((track) =>
    isAudioSupported(input.capabilityProfile, track),
  );
  if (compatible && input.capabilityProfile.audioTrackSwitching === 'supported') {
    reasons.push('audio-fallback-selected');
    return { track: compatible, fallback: true };
  }

  if (candidate.audioTracks.some((track) => !track.codec)) {
    unknowns.push('candidate-audio-codec-unknown');
  }
  if (requested) {
    return { track: requested, fallback: false };
  }
  reasons.push('no-audio-compatible');
  return { track: candidate.audioTracks[0] ?? null, fallback: false };
}

function selectSubtitle(
  input: DesktopStreamPolicyInput,
  candidate: DesktopStreamMediaCandidate,
  reasons: DesktopStreamPolicyReasonCode[],
  unknowns: DesktopStreamPolicyUnknownCode[],
): { track: DesktopStreamSubtitleCandidate | null; fallback: boolean } {
  if (input.preferredSubtitleTrackId === null) {
    reasons.push('no-subtitle-selected');
    return { track: null, fallback: false };
  }

  const requested = input.preferredSubtitleTrackId
    ? candidate.subtitleTracks.find((track) => track.id === input.preferredSubtitleTrackId)
    : undefined;
  const hasPreferredSubtitleTrack = input.preferredSubtitleTrackId !== undefined;
  if (requested && isSubtitleSupported(input.capabilityProfile, requested)) {
    return { track: requested, fallback: false };
  }
  if (input.preferredSubtitleTrackId && !requested) {
    reasons.push('requested-subtitle-unavailable');
  }

  const forcedCompatible = candidate.subtitleTracks.find(
    (track) => track.forced === true && isSubtitleSupported(input.capabilityProfile, track),
  );
  if (forcedCompatible && !hasPreferredSubtitleTrack) {
    reasons.push('forced-subtitle-selected');
    return { track: forcedCompatible, fallback: false };
  }
  if (forcedCompatible && input.capabilityProfile.subtitleTrackSwitching === 'supported') {
    reasons.push('forced-subtitle-selected', 'subtitle-fallback-selected');
    return { track: forcedCompatible, fallback: true };
  }

  const defaultCompatible = candidate.subtitleTracks.find(
    (track) => track.default === true && isSubtitleSupported(input.capabilityProfile, track),
  );
  if (defaultCompatible && !hasPreferredSubtitleTrack) {
    return { track: defaultCompatible, fallback: false };
  }
  if (defaultCompatible && input.capabilityProfile.subtitleTrackSwitching === 'supported') {
    reasons.push('subtitle-fallback-selected');
    return { track: defaultCompatible, fallback: true };
  }

  const compatible = candidate.subtitleTracks.find((track) =>
    isSubtitleSupported(input.capabilityProfile, track),
  );
  if (compatible && input.capabilityProfile.subtitleTrackSwitching === 'supported') {
    reasons.push('subtitle-fallback-selected');
    return { track: compatible, fallback: true };
  }

  if (candidate.subtitleTracks.some((track) => track.delivery === 'unknown')) {
    unknowns.push('candidate-subtitle-delivery-unknown');
  }
  if (candidate.subtitleTracks.length === 0) {
    reasons.push('no-subtitle-selected');
    return { track: null, fallback: false };
  }

  if (requested) {
    return { track: requested, fallback: false };
  }
  reasons.push('no-subtitle-compatible');
  return { track: candidate.subtitleTracks[0] ?? null, fallback: false };
}

function buildDirectStreamReasons(options: {
  profile: DesktopStreamCapabilityProfile;
  containerSupported: boolean;
  videoSupported: boolean;
  audioSupported: boolean;
  subtitleSupported: boolean;
  hdrSupported: boolean;
  selection: TrackSelection;
}): DesktopStreamPolicyReasonCode[] {
  const reasons: DesktopStreamPolicyReasonCode[] = [];
  if (!options.containerSupported && options.profile.directStream.containerRemux === 'supported') {
    reasons.push('direct-stream-container-remux');
  }
  if (!options.audioSupported && options.profile.directStream.audioTranscode === 'supported') {
    reasons.push('direct-stream-audio-transcode');
  }
  if (
    !options.subtitleSupported &&
    options.profile.directStream.subtitleConversion === 'supported'
  ) {
    reasons.push('direct-stream-subtitle-conversion');
  }
  if (
    options.selection.audioFallback &&
    options.profile.audioTrackSwitching === 'supported'
  ) {
    reasons.push('direct-stream-audio-fallback');
  }
  if (
    options.selection.subtitleFallback &&
    options.profile.subtitleTrackSwitching === 'supported'
  ) {
    reasons.push('direct-stream-subtitle-fallback');
  }
  if (!options.videoSupported || !options.hdrSupported) {
    return [];
  }
  return [...new Set(reasons)];
}

function canDirectStream(options: {
  profile: DesktopStreamCapabilityProfile;
  containerSupported: boolean;
  videoSupported: boolean;
  audioSupported: boolean;
  subtitleSupported: boolean;
  hdrSupported: boolean;
}): boolean {
  return (
    options.videoSupported &&
    options.hdrSupported &&
    (options.containerSupported || options.profile.directStream.containerRemux === 'supported') &&
    (options.audioSupported || options.profile.directStream.audioTranscode === 'supported') &&
    (options.subtitleSupported ||
      options.profile.directStream.subtitleConversion === 'supported')
  );
}

function buildTranscodeReasons(options: {
  profile: DesktopStreamCapabilityProfile;
  containerSupported: boolean;
  videoSupported: boolean;
  audioSupported: boolean;
  subtitleSupported: boolean;
  hdrSupported: boolean;
  dynamicRange: DesktopStreamMediaCandidate['video']['dynamicRange'];
}): DesktopStreamPolicyReasonCode[] {
  const reasons: DesktopStreamPolicyReasonCode[] = [];
  if (!options.videoSupported && options.profile.transcode.video === 'supported') {
    reasons.push('transcode-video');
  }
  if (!options.containerSupported && options.profile.transcode.video === 'supported') {
    reasons.push('transcode-container');
  }
  if (!options.audioSupported && options.profile.transcode.audio === 'supported') {
    reasons.push('transcode-audio');
  }
  if (!options.subtitleSupported && options.profile.transcode.subtitles === 'supported') {
    reasons.push('transcode-subtitle');
  }
  if (
    !options.hdrSupported &&
    options.dynamicRange === 'dolby-vision' &&
    options.profile.transcode.hdr === 'supported'
  ) {
    reasons.push('transcode-dolby-vision');
  } else if (!options.hdrSupported && options.profile.transcode.hdr === 'supported') {
    reasons.push('transcode-hdr');
  }
  return reasons;
}

function buildUnsupportedReasons(options: {
  containerSupported: boolean;
  videoSupported: boolean;
  audioSupported: boolean;
  subtitleSupported: boolean;
  hdrSupported: boolean;
  selection: TrackSelection;
  dolbyVisionUnsupported: boolean;
}): DesktopStreamPolicyReasonCode[] {
  const reasons: DesktopStreamPolicyReasonCode[] = [];
  if (!options.containerSupported) {
    reasons.push('unsupported-container');
  }
  if (!options.videoSupported) {
    reasons.push('unsupported-video-codec');
  }
  if (!options.audioSupported) {
    reasons.push('unsupported-audio-codec');
  }
  if (!options.subtitleSupported) {
    reasons.push('unsupported-subtitle-delivery');
  }
  if (!options.hdrSupported) {
    reasons.push('unsupported-hdr');
  }
  if (options.dolbyVisionUnsupported) {
    reasons.push('unsupported-dolby-vision');
  }
  if (options.selection.audio === null) {
    reasons.push('no-audio-compatible');
  }
  if (reasons.length === 0) {
    reasons.push('transcode-unavailable');
  }
  return [...new Set(reasons)];
}

function buildIncompleteFactReasons(
  unknowns: readonly DesktopStreamPolicyUnknownCode[],
): DesktopStreamPolicyReasonCode[] {
  const reasons: DesktopStreamPolicyReasonCode[] = [];
  if (unknowns.some((unknown) => unknown.startsWith('candidate-'))) {
    reasons.push('candidate-facts-incomplete');
  }
  if (unknowns.some((unknown) => unknown.startsWith('profile-'))) {
    reasons.push('profile-facts-incomplete');
  }
  return reasons;
}

function collectUnknowns(
  profile: DesktopStreamCapabilityProfile,
  candidate: DesktopStreamMediaCandidate,
  selection: TrackSelection,
): DesktopStreamPolicyUnknownCode[] {
  const unknowns: DesktopStreamPolicyUnknownCode[] = [
    ...(profile.unknowns ?? []),
    ...selection.unknowns,
  ];
  if (!candidate.variant.container) {
    unknowns.push('candidate-container-unknown');
  }
  if (!candidate.video.codec) {
    unknowns.push('candidate-video-codec-unknown');
  }
  if (!candidate.video.dynamicRange || candidate.video.dynamicRange === 'unknown') {
    unknowns.push('candidate-hdr-unknown');
  }
  if (candidate.audioTracks.some((track) => !track.codec)) {
    unknowns.push('candidate-audio-codec-unknown');
  }
  if (candidate.subtitleTracks.some((track) => track.delivery === 'unknown')) {
    unknowns.push('candidate-subtitle-delivery-unknown');
  }
  if (profile.directPlayContainers.length === 0) {
    unknowns.push('profile-container-support-unknown');
  }
  if (profile.directPlayVideoCodecs.length === 0) {
    unknowns.push('profile-video-support-unknown');
  }
  if (profile.directPlayAudioCodecs.length === 0) {
    unknowns.push('profile-audio-support-unknown');
  }
  if (profile.subtitleDeliveryModes.includes('unknown')) {
    unknowns.push('profile-subtitle-support-unknown');
  }
  if (profile.headerAuthSetup === 'unknown' || profile.headerAuthSetup === 'unproven') {
    unknowns.push('profile-header-auth-support-unknown');
  }
  if (
    profile.audioTrackSwitching === 'unknown' ||
    profile.audioTrackSwitching === 'unproven'
  ) {
    unknowns.push('profile-audio-switching-support-unknown');
  }
  if (
    profile.subtitleTrackSwitching === 'unknown' ||
    profile.subtitleTrackSwitching === 'unproven'
  ) {
    unknowns.push('profile-subtitle-switching-support-unknown');
  }
  if (
    profile.directStream.containerRemux === 'unknown' ||
    profile.directStream.containerRemux === 'unproven' ||
    profile.directStream.audioTranscode === 'unknown' ||
    profile.directStream.audioTranscode === 'unproven' ||
    profile.directStream.subtitleConversion === 'unknown' ||
    profile.directStream.subtitleConversion === 'unproven'
  ) {
    unknowns.push('profile-direct-stream-support-unknown');
  }
  if (
    profile.transcode.video === 'unknown' ||
    profile.transcode.video === 'unproven' ||
    profile.transcode.audio === 'unknown' ||
    profile.transcode.audio === 'unproven' ||
    profile.transcode.subtitles === 'unknown' ||
    profile.transcode.subtitles === 'unproven' ||
    profile.transcode.hdr === 'unknown' ||
    profile.transcode.hdr === 'unproven'
  ) {
    unknowns.push('profile-transcode-support-unknown');
  }
  if (profile.hdr === 'unknown' || profile.hdr === 'unproven') {
    unknowns.push('profile-hdr-support-unknown');
  }
  if (profile.dolbyVision === 'unknown' || profile.dolbyVision === 'unproven') {
    unknowns.push('profile-dolby-vision-support-unknown');
  }
  unknowns.push('desktop-parity-unproven');
  return [...new Set(unknowns)];
}

function buildDecision(
  kind: DesktopStreamPolicyDecision['kind'],
  candidate: DesktopStreamMediaCandidate,
  selection: TrackSelection,
  reasonCodes: DesktopStreamPolicyReasonCode[],
  unknowns: DesktopStreamPolicyUnknownCode[],
): DesktopStreamPolicyDecision {
  return {
    kind,
    candidateId: candidate.candidateId,
    selectedTrackIds: {
      video: candidate.video.id,
      audio: selection.audio?.id ?? null,
      subtitle: selection.subtitle?.id ?? null,
    },
    summary: {
      media: {
        id: candidate.media.id,
        title: candidate.media.title,
      },
      container: candidate.variant.container ?? null,
      videoCodec: candidate.video.codec ?? null,
      audioCodec: selection.audio?.codec ?? null,
      subtitleDelivery: selection.subtitle?.delivery ?? null,
      dynamicRange: candidate.video.dynamicRange ?? null,
      action: kind,
    },
    reasonCodes: [...new Set(reasonCodes)],
    unknowns: [...new Set(unknowns)],
  };
}

function unsupportedDecision(
  reasonCodes: DesktopStreamPolicyReasonCode[],
  unknowns: DesktopStreamPolicyUnknownCode[],
): DesktopStreamPolicyDecision {
  return {
    kind: 'unsupported',
    candidateId: null,
    selectedTrackIds: {
      video: null,
      audio: null,
      subtitle: null,
    },
    summary: {
      media: null,
      container: null,
      videoCodec: null,
      audioCodec: null,
      subtitleDelivery: null,
      dynamicRange: null,
      action: 'unsupported',
    },
    reasonCodes,
    unknowns,
  };
}

function isKnownSupported(value: string | null | undefined, supported: readonly string[]): boolean {
  return Boolean(value && supported.includes(value));
}

function isAudioSupported(
  profile: DesktopStreamCapabilityProfile,
  track: DesktopStreamAudioCandidate,
): boolean {
  return isKnownSupported(track.codec, profile.directPlayAudioCodecs);
}

function isSubtitleSupported(
  profile: DesktopStreamCapabilityProfile,
  track: DesktopStreamSubtitleCandidate,
): boolean {
  return track.delivery !== 'unknown' && profile.subtitleDeliveryModes.includes(track.delivery);
}

function isDynamicRangeSupported(
  profile: DesktopStreamCapabilityProfile,
  dynamicRange: DesktopStreamMediaCandidate['video']['dynamicRange'],
): boolean {
  if (!dynamicRange || dynamicRange === 'unknown') {
    return false;
  }
  if (dynamicRange === 'dolby-vision') {
    return profile.dolbyVision === 'supported';
  }
  if (dynamicRange === 'hdr10') {
    return profile.hdr === 'supported';
  }
  return true;
}
