import '../plex/plex_models.dart';

String safeFormError(Object error, String fallback) => switch (error) {
  FormatException(:final message) when message.trim().isNotEmpty => message,
  PlexException(:final message) when message.trim().isNotEmpty => message,
  _ => fallback,
};
