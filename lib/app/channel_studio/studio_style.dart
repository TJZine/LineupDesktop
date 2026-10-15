part of '../channel_studio_view.dart';

double _studioSize(BuildContext context, double wide, double compact) =>
    (LineupLayout.isCompactWidth(MediaQuery.sizeOf(context).width)
    ? compact
    : wide);

TextStyle _studioBodyStyle(
  BuildContext context, {
  Color? color,
  FontWeight? fontWeight,
}) =>
    Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontSize: 18, color: color, fontWeight: fontWeight) ??
    TextStyle(fontSize: 18, color: color, fontWeight: fontWeight);

TextStyle _studioSupportStyle(
  BuildContext context, {
  Color? color,
  FontWeight? fontWeight,
}) =>
    Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: 18,
      color: color ?? LineupTheme.of(context).secondaryText,
      fontWeight: fontWeight,
    ) ??
    TextStyle(
      fontSize: 18,
      color: color ?? LineupTheme.of(context).secondaryText,
      fontWeight: fontWeight,
    );

TextStyle _studioSectionHeadingStyle(BuildContext context) =>
    Theme.of(context).textTheme.titleLarge?.copyWith(
      fontSize: _studioSize(context, 24, 20),
      fontWeight: FontWeight.w600,
    ) ??
    TextStyle(
      fontSize: _studioSize(context, 24, 20),
      fontWeight: FontWeight.w600,
    );

Widget _studioSourceExplanation(BuildContext context, String? message) =>
    message == null
    ? const SizedBox.shrink()
    : Semantics(
        liveRegion: true,
        child: Text(message, style: _studioSupportStyle(context)),
      );

void _focusStudioNode(BuildContext owner, FocusNode node) {
  if (!owner.mounted) return;
  final focusContext = node.context;
  if (focusContext == null) return;
  node.requestFocus();
  unawaited(Scrollable.ensureVisible(focusContext, alignment: 0.35));
}
