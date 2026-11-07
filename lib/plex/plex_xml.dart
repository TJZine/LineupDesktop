import 'package:xml/xml.dart';

Map<String, Object?> plexXmlRecord(
  XmlElement element, {
  bool videoAsMetadata = false,
}) {
  final record = <String, Object?>{
    for (final attribute in element.attributes)
      attribute.name.local: attribute.value,
  };
  final groups = <String, List<Map<String, Object?>>>{};
  for (final child in element.childElements) {
    groups
        .putIfAbsent(child.name.local, () => [])
        .add(plexXmlRecord(child, videoAsMetadata: videoAsMetadata));
  }
  for (final entry in groups.entries) {
    final key = videoAsMetadata && entry.key == 'Video'
        ? 'Metadata'
        : entry.key;
    record[key] = entry.value;
  }
  return record;
}
