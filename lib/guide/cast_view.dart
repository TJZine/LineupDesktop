import '../channels/channel.dart';
import '../plex/plex_models.dart';

/// Display data only; never copied back into catalog or schedule items.
class CastView {
  const CastView(this.cast);

  final List<ChannelCastMember> cast;
}

CastView mergeCast(
  List<ChannelCastMember> catalog,
  List<PlexCastMember> detail,
) {
  String key(String name) => name.trim().toLowerCase();
  final catalogByName = {
    for (final member in catalog) key(member.name): member,
  };
  final detailByName = {for (final member in detail) key(member.name): member};
  Uri? portrait(PlexCastMember? member) => canonicalPlexCastPortrait(
    member?.thumbPath == null ? null : Uri.tryParse(member!.thumbPath!),
  );
  // Empty detail cannot replace an empty catalog with useful information.
  final replace =
      detail.isNotEmpty && catalogByName.keys.every(detailByName.containsKey);
  return CastView(
    List.unmodifiable(
      replace
          ? detail
                .take(maxRichCastMembers)
                .map(
                  (member) => ChannelCastMember(
                    name: member.name,
                    role: member.role,
                    portrait:
                        catalogByName[key(member.name)]?.portrait ??
                        portrait(member),
                  ),
                )
          : catalog.map(
              (member) => ChannelCastMember(
                name: member.name,
                role: member.role,
                portrait:
                    member.portrait ?? portrait(detailByName[key(member.name)]),
              ),
            ),
    ),
  );
}
