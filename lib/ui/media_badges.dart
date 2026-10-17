import '../channels/channel.dart';

enum MediaBadgeSurface { guide, nowPlaying }

/// Catalog facts retain each surface's established badge set. The Player may
/// supply its formatted runtime codec and observed HDR transfer independently.
List<String> mediaBadges(
  ChannelItem item, {
  required MediaBadgeSurface surface,
  bool runtimeHdr = false,
  String? effectiveVideoCodec,
}) => [
  ?item.contentRating,
  ?item.resolution?.toUpperCase(),
  ?_dynamicRange(item.dynamicRange, surface, runtimeHdr),
  if (surface == MediaBadgeSurface.nowPlaying) ?effectiveVideoCodec,
  ?item.audioCodec?.toUpperCase(),
  if (item.audioChannels case final channels?)
    switch (channels) {
      1 => 'MONO',
      2 => 'STEREO',
      6 => '5.1',
      8 => '7.1',
      _ => '$channels CH',
    },
];

String? _dynamicRange(
  String? value,
  MediaBadgeSurface surface,
  bool runtimeHdr,
) {
  if (surface == MediaBadgeSurface.guide) {
    return switch (value) {
      'hdr10' => 'HDR10',
      'hlg' => 'HLG',
      'dolbyVision' => 'DOLBY VISION',
      _ => null,
    };
  }
  final catalog = switch (value?.toLowerCase()) {
    'unknown' => null,
    'sdr' => 'SDR',
    'hdr' => 'HDR',
    'hdr10' => 'HDR10',
    'hlg' => 'HLG',
    'dolbyvision' || 'dolby vision' => 'DOLBY VISION',
    final value? when value.trim().isNotEmpty => value.toUpperCase(),
    _ => null,
  };
  if (!runtimeHdr) return catalog;
  return switch (catalog) {
    'HDR10' || 'HLG' || 'DOLBY VISION' => catalog,
    _ => 'HDR',
  };
}
