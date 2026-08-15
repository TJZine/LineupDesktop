import '../plex/plex_models.dart';

String safeFormError(Object error, String fallback) => switch (error) {
  FormatException(:final message) => message.toString(),
  PlexException(:final message) => message,
  _ => fallback,
};
