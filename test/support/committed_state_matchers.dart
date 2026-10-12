import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

/// Publication detaches caller-owned values; these assertions retain every
/// durable channel field and ordering without requiring the input object's alias.
Matcher channelValues(Iterable<Channel> expected) =>
    isA<Iterable<Channel>>().having(
      (actual) => actual.map((channel) => channel.toJson()).toList(),
      'channel values',
      expected.map((channel) => channel.toJson()).toList(),
    );

Matcher channelValue(Channel expected) => isA<Channel>().having(
  (actual) => actual.toJson(),
  'channel value',
  expected.toJson(),
);

Matcher serverValue(PlexServer expected) => isA<PlexServer>().having(
  _serverFields,
  'server value',
  _serverFields(expected),
);

Object _serverFields(PlexServer server) => {
  'id': server.id,
  'name': server.name,
  'owned': server.owned,
  'connections': [
    for (final connection in server.connections)
      {
        'uri': connection.uri.toString(),
        'local': connection.local,
        'relay': connection.relay,
        'latency': connection.latency,
      },
  ],
};
