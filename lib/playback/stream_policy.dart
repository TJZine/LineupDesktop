enum StreamDecisionKind { directPlay, directStream, transcode, unsupported }

enum DynamicRange { sdr, hdr10, hlg, dolbyVision, unknown }

enum SubtitleDelivery { embedded, sidecar, external, unknown }

class StreamFacts {
  const StreamFacts({
    required this.container,
    required this.videoCodec,
    required this.audioCodec,
    required this.dynamicRange,
    this.subtitleDelivery,
  });

  final String? container;
  final String? videoCodec;
  final String? audioCodec;
  final DynamicRange dynamicRange;
  final SubtitleDelivery? subtitleDelivery;
}

class StreamCapabilities {
  const StreamCapabilities({
    required this.containers,
    required this.videoCodecs,
    required this.audioCodecs,
    this.hdr10 = false,
    this.hlg = false,
    this.dolbyVision = false,
    this.remux = true,
    this.transcode = true,
    this.subtitleDeliveries = const {
      SubtitleDelivery.embedded,
      SubtitleDelivery.sidecar,
    },
  }) : _unrestricted = false;

  const StreamCapabilities.unrestricted({
    this.remux = true,
    this.transcode = true,
    this.subtitleDeliveries = const {
      SubtitleDelivery.embedded,
      SubtitleDelivery.sidecar,
      SubtitleDelivery.external,
      SubtitleDelivery.unknown,
    },
  }) : _unrestricted = true,
       containers = null,
       videoCodecs = null,
       audioCodecs = null,
       hdr10 = true,
       hlg = true,
       dolbyVision = true;

  // A null set accepts any reported value in that category.
  final Set<String>? containers;
  final Set<String>? videoCodecs;
  final Set<String>? audioCodecs;
  final Set<SubtitleDelivery> subtitleDeliveries;
  final bool hdr10;
  final bool hlg;
  final bool dolbyVision;
  final bool remux;
  final bool transcode;
  final bool _unrestricted;
}

class StreamDecision {
  const StreamDecision(this.kind, this.reasons, {this.unknowns = const []});

  final StreamDecisionKind kind;
  final List<String> reasons;
  final List<String> unknowns;
}

StreamDecision decideStream(
  StreamFacts facts,
  StreamCapabilities capabilities,
) {
  final unknowns = <String>[
    if (facts.container == null) 'container-unknown',
    if (facts.videoCodec == null) 'video-codec-unknown',
    if (facts.audioCodec == null) 'audio-codec-unknown',
    if (facts.dynamicRange == DynamicRange.unknown) 'dynamic-range-unknown',
    if (facts.subtitleDelivery == SubtitleDelivery.unknown)
      'subtitle-delivery-unknown',
  ];
  final unrestricted = capabilities._unrestricted;
  if (unknowns.isNotEmpty && !unrestricted) {
    return StreamDecision(StreamDecisionKind.unsupported, const [
      'candidate-facts-incomplete',
    ], unknowns: unknowns);
  }
  final container = capabilities.containers?.contains(facts.container) ?? true;
  final video = capabilities.videoCodecs?.contains(facts.videoCodec) ?? true;
  final audio = capabilities.audioCodecs?.contains(facts.audioCodec) ?? true;
  final subtitle =
      facts.subtitleDelivery == null ||
      capabilities.subtitleDeliveries.contains(facts.subtitleDelivery);
  final hdr = switch (facts.dynamicRange) {
    DynamicRange.sdr => true,
    DynamicRange.hdr10 => capabilities.hdr10,
    DynamicRange.hlg => capabilities.hlg,
    DynamicRange.dolbyVision => capabilities.dolbyVision,
    DynamicRange.unknown => unrestricted,
  };
  if (container && video && audio && subtitle && hdr) {
    return StreamDecision(StreamDecisionKind.directPlay, const [
      'direct-play-supported',
    ], unknowns: unknowns);
  }
  final incompatible = <String>[
    if (!container) 'container-incompatible',
    if (!video) 'video-incompatible',
    if (!audio) 'audio-incompatible',
    if (!subtitle) 'subtitle-incompatible',
    if (!hdr) 'dynamic-range-incompatible',
  ];
  if (capabilities.remux &&
      video &&
      hdr &&
      (!container || !audio || !subtitle)) {
    return StreamDecision(StreamDecisionKind.directStream, incompatible);
  }
  if (capabilities.transcode) {
    return StreamDecision(StreamDecisionKind.transcode, incompatible);
  }
  return StreamDecision(StreamDecisionKind.unsupported, incompatible);
}
