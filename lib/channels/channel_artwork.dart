import 'channel.dart';

/// Episodes prefer their series poster, falling back to the item's poster
/// when the series path is absent or cannot be parsed.
Uri? posterPath(ChannelItem item) =>
    item.showThumb == null || item.showThumb!.isEmpty
    ? item.poster
    : Uri.tryParse(item.showThumb!) ?? item.poster;
