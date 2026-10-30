import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/plex/plex_transcode.dart';

const _session = '00000000-0000-4000-8000-000000000001';
final _server = Uri.parse('https://synthetic.invalid:32400');
const _master =
    '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=8000000\n'
    '/video/:/transcode/universal/session/synthetic/base/index.m3u8\n';
const _target =
    'add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mp4&videoCodec=hevc,h264&audioCodec=aac,ac3,eac3&replace=true)';
const _channels =
    'add-limitation(scope=videoAudioCodec&scopeName=*&type=upperBound&name=audio.channels&value=8&replace=true)';
const _desktopExtra =
    'add-direct-play-profile(type=videoProfile&container=*&videoCodec=*&audioCodec=*&subtitleCodec=*&replace=true)+$_target+$_channels';
const _fireVideo = [
  VideoDecoderCapabilities(
    codec: 'h264',
    profiles: ['high', 'high 10'],
    dolbyVisionProfiles: [9],
    maxWidth: 3840,
    maxHeight: 2160,
  ),
  VideoDecoderCapabilities(
    codec: 'hevc',
    profiles: ['main', 'main 10'],
    maxWidth: 3840,
    maxHeight: 2160,
    dolbyVisionProfiles: [4, 5, 8],
  ),
  VideoDecoderCapabilities(
    codec: 'av1',
    profiles: ['main', 'main 10'],
    maxWidth: 3840,
    maxHeight: 2160,
    dolbyVisionProfiles: [10],
  ),
];
const _fire = MediaCapabilities(
  videoDecoders: _fireVideo,
  audioDecoders: ['aac', 'ac3', 'eac3'],
  containers: ['mkv', 'mp4'],
);
const _firePassthrough = MediaCapabilities(
  videoDecoders: _fireVideo,
  audioDecoders: ['aac', 'ac3', 'eac3'],
  audioPassthrough: ['truehd', 'dts'],
  containers: ['mkv', 'mp4'],
);
const _phone = MediaCapabilities(
  videoDecoders: [
    VideoDecoderCapabilities(
      codec: 'h264',
      profiles: ['baseline', 'main', 'high'],
      maxWidth: 1920,
      maxHeight: 1080,
    ),
  ],
  audioDecoders: ['aac'],
  containers: ['mkv', 'mp4'],
);
const _fireLimitations =
    '+add-limitation(scope=videoCodec&scopeName=h264&type=upperBound&name=video.bitDepth&value=10&replace=true)'
    '+add-limitation(scope=videoCodec&scopeName=h264&type=upperBound&name=video.width&value=3840&replace=true)'
    '+add-limitation(scope=videoCodec&scopeName=h264&type=upperBound&name=video.height&value=2160&replace=true)'
    '+add-limitation(scope=videoCodec&scopeName=h264&type=match&name=video.profile&list=high|high 10&replace=true)'
    '+add-limitation(scope=videoCodec&scopeName=h264&type=match&name=video.DOVIProfile&list=9&isRequired=false&replace=true)'
    '+add-limitation(scope=videoCodec&scopeName=hevc&type=upperBound&name=video.bitDepth&value=10&replace=true)'
    '+add-limitation(scope=videoCodec&scopeName=hevc&type=upperBound&name=video.width&value=3840&replace=true)'
    '+add-limitation(scope=videoCodec&scopeName=hevc&type=upperBound&name=video.height&value=2160&replace=true)'
    '+add-limitation(scope=videoCodec&scopeName=hevc&type=match&name=video.profile&list=main|main 10&replace=true)'
    '+add-limitation(scope=videoCodec&scopeName=hevc&type=match&name=video.DOVIProfile&list=4|5|8&isRequired=false&replace=true)'
    '+add-limitation(scope=videoCodec&scopeName=av1&type=upperBound&name=video.bitDepth&value=10&replace=true)'
    '+add-limitation(scope=videoCodec&scopeName=av1&type=upperBound&name=video.width&value=3840&replace=true)'
    '+add-limitation(scope=videoCodec&scopeName=av1&type=upperBound&name=video.height&value=2160&replace=true)'
    '+add-limitation(scope=videoCodec&scopeName=av1&type=match&name=video.profile&list=main&replace=true)'
    '+add-limitation(scope=videoCodec&scopeName=av1&type=match&name=video.DOVIProfile&list=10&isRequired=false&replace=true)';

const _targetFixtures = [
  (
    name: 'desktop ignores Android probe availability',
    capabilities: MediaCapabilities.unknown,
    desktop: true,
    video: ['hevc', 'h264'],
    audio: ['aac', 'ac3', 'eac3'],
  ),
  (
    name: 'phone without HEVC',
    capabilities: _phone,
    desktop: false,
    video: ['h264'],
    audio: ['aac'],
  ),
  (
    name: 'HEVC only',
    capabilities: MediaCapabilities(
      videoDecoders: [VideoDecoderCapabilities(codec: 'hevc')],
      audioDecoders: ['ac3'],
    ),
    desktop: false,
    video: ['hevc'],
    audio: ['ac3'],
  ),
  (
    name: 'both in reverse order with duplicates',
    capabilities: MediaCapabilities(
      videoDecoders: [
        VideoDecoderCapabilities(codec: 'h264'),
        VideoDecoderCapabilities(codec: 'hevc'),
        VideoDecoderCapabilities(codec: 'h264'),
      ],
      audioDecoders: ['eac3', 'aac', 'aac', 'flac'],
    ),
    desktop: false,
    video: ['hevc', 'h264'],
    audio: ['aac', 'eac3'],
  ),
  (
    name: 'other video codecs are not HLS targets',
    capabilities: MediaCapabilities(
      videoDecoders: [
        VideoDecoderCapabilities(codec: 'av1'),
        VideoDecoderCapabilities(codec: 'h264'),
        VideoDecoderCapabilities(codec: 'vp9'),
        VideoDecoderCapabilities(codec: 'h265'),
      ],
      audioDecoders: ['aac'],
    ),
    desktop: false,
    video: ['h264'],
    audio: ['aac'],
  ),
  (
    name: 'unknown probe',
    capabilities: MediaCapabilities.unknown,
    desktop: false,
    video: <String>[],
    audio: <String>[],
  ),
  (
    name: 'unknown probe with untrusted populated lists',
    capabilities: MediaCapabilities(
      known: false,
      videoDecoders: [
        VideoDecoderCapabilities(codec: 'h264'),
        VideoDecoderCapabilities(codec: 'hevc'),
      ],
      audioDecoders: ['aac'],
    ),
    desktop: false,
    video: <String>[],
    audio: <String>[],
  ),
  (
    name: 'no video decoders',
    capabilities: MediaCapabilities(audioDecoders: ['aac']),
    desktop: false,
    video: <String>[],
    audio: <String>[],
  ),
  (
    name: 'AV1 only',
    capabilities: MediaCapabilities(
      videoDecoders: [VideoDecoderCapabilities(codec: 'av1')],
      audioDecoders: ['aac'],
    ),
    desktop: false,
    video: <String>[],
    audio: <String>[],
  ),
  (
    name: 'no audio decoders',
    capabilities: MediaCapabilities(
      videoDecoders: [VideoDecoderCapabilities(codec: 'h264')],
    ),
    desktop: false,
    video: <String>[],
    audio: <String>[],
  ),
  (
    name: 'no supported HLS audio target',
    capabilities: MediaCapabilities(
      videoDecoders: [VideoDecoderCapabilities(codec: 'h264')],
      audioDecoders: ['flac'],
    ),
    desktop: false,
    video: <String>[],
    audio: <String>[],
  ),
  (
    name: 'supported passthrough audio target',
    capabilities: MediaCapabilities(
      videoDecoders: [VideoDecoderCapabilities(codec: 'h264')],
      audioDecoders: ['flac'],
      audioPassthrough: ['eac3'],
    ),
    desktop: false,
    video: ['h264'],
    audio: ['eac3'],
  ),
];

void main() {
  group('confirmed session targets', () {
    for (final fixture in _targetFixtures) {
      test('${fixture.name}: declaration and immutable target facts agree', () {
        final profile = buildProfile(
          fixture.capabilities,
          desktop: fixture.desktop,
        );
        final target = profile.transcodeTarget;
        final directives = profile.profileExtra
            .split('+')
            .where(
              (directive) => directive.startsWith('add-transcode-target('),
            );
        if (fixture.video.isEmpty) {
          expect(target, isNull);
          expect(directives, isEmpty);
        } else {
          expect(target, isNotNull);
          expect(target!.videoCodecs, fixture.video);
          expect(target.audioCodecs, fixture.audio);
          expect(directives, [
            'add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mp4&videoCodec=${fixture.video.join(',')}&audioCodec=${fixture.audio.join(',')}&replace=true)',
          ]);
          expect(target.videoCodecs.clear, throwsUnsupportedError);
          expect(target.audioCodecs.clear, throwsUnsupportedError);
        }
        if (!fixture.desktop && !fixture.capabilities.known) {
          expect(
            profile.eligible(
              const PlexMediaFacts(
                container: 'mkv',
                videoCodec: 'h264',
                videoProfile: 'high',
                bitDepth: 8,
                width: 1920,
                height: 1080,
                audioCodec: 'aac',
              ),
            ),
            isFalse,
          );
        }
      });

      test(
        '${fixture.name}: decision allowed, start requires a declared target',
        () async {
          final profile = buildProfile(
            fixture.capabilities,
            desktop: fixture.desktop,
          );
          final request = PlexSessionRequest(
            ratingKey: '42',
            sessionId: _session,
            profile: profile,
          );
          final requests = <http.Request>[];
          final client = PlexClient(
            clientIdentifier: 'synthetic-client',
            httpClient: MockClient((request) async {
              requests.add(request);
              if (requests.length == 1 &&
                  request.url.path == '/video/:/transcode/universal/decision') {
                return http.Response(
                  '{"MediaContainer":{"generalDecisionCode":1001,"directPlayDecisionCode":3001}}',
                  200,
                );
              }
              if (fixture.video.isNotEmpty &&
                  requests.length == 2 &&
                  request.url.path ==
                      '/video/:/transcode/universal/start.m3u8') {
                return http.Response(_master, 200);
              }
              fail('Unexpected request');
            }),
          );
          addTearDown(client.close);
          expect(
            (await client.transcodeDecision(
              _server,
              request,
              'synthetic-token',
            )).method,
            PlexPlaybackMethod.directStream,
          );
          if (fixture.video.isEmpty) {
            await expectLater(
              client.startTranscodeSession(_server, request, 'synthetic-token'),
              throwsA(
                isA<PlexException>()
                    .having(
                      (error) => error.code,
                      'code',
                      'session-unsupported',
                    )
                    .having(
                      (error) => error.message,
                      'message',
                      'This device has no supported Plex session target.',
                    ),
              ),
            );
            expect(
              requests,
              hasLength(1),
              reason: 'An undeclared target must be refused before HTTP',
            );
            expect(
              requests.single.headers['X-Plex-Client-Profile-Extra'],
              isNot(contains('add-transcode-target(')),
            );
          } else {
            await client.startTranscodeSession(
              _server,
              request,
              'synthetic-token',
            );
            expect(requests, hasLength(2));
          }
          expect(
            requests.map(
              (request) => request.url.queryParameters['directPlay'],
            ),
            fixture.video.isEmpty ? ['1'] : ['1', '0'],
          );
          for (final request in requests) {
            expect(
              request.headers['X-Plex-Client-Profile-Extra'],
              profile.profileExtra,
            );
            expect(request.headers['X-Plex-Client-Profile-Name'], 'Generic');
            expect(request.headers['X-Plex-Token'], 'synthetic-token');
            expect(request.followRedirects, isFalse);
            expect(request.url.toString(), isNot(contains('synthetic-token')));
            expect(
              request.url.queryParameters.keys.map((key) => key.toLowerCase()),
              isNot(contains('x-plex-token')),
            );
          }
        },
      );
    }
  });

  group('session HTTP boundary', () {
    test('decision, start, ping, stop and PUT have exact shapes and header-only token', () async {
      final extra = buildProfile(MediaCapabilities.desktop, desktop: true);
      final request = PlexSessionRequest(
        ratingKey: '42',
        sessionId: _session,
        profile: extra,
        partIndex: 2,
        offset: const Duration(milliseconds: 600999),
        location: PlexTranscodeLocation.wan,
        subtitles: PlexSessionSubtitles.burn,
        maxVideoBitrateKbps: 8000,
        videoWidth: 1920,
        videoHeight: 1080,
      );
      final pending =
          <
            ({
              String method,
              String path,
              Map<String, String> query,
              String body,
              int status,
            })
          >[
            (
              method: 'GET',
              path: '/video/:/transcode/universal/decision',
              query: _expectedQuery('1'),
              body: '{"MediaContainer":{"generalDecisionCode":1000,"directPlayDecisionCode":1000}}',
              status: 200,
            ),
            (
              method: 'GET',
              path: '/video/:/transcode/universal/start.m3u8',
              query: _expectedQuery('0'),
              body: _master,
              status: 200,
            ),
            (
              method: 'GET',
              path: '/video/:/transcode/universal/ping',
              query: {'session': _session},
              body: '',
              status: 200,
            ),
            (
              method: 'GET',
              path: '/video/:/transcode/universal/stop',
              query: {'session': _session},
              body: '',
              status: 200,
            ),
            (
              method: 'PUT',
              path: '/library/parts/7',
              query: {
                'audioStreamID': '9',
                'subtitleStreamID': '0',
                'allParts': '1',
              },
              body: '',
              status: 200,
            ),
          ];
      final boundaryFailures = <Object>[];
      final client = PlexClient(
        clientIdentifier: 'synthetic-client',
        httpClient: MockClient((request) async {
          try {
            if (pending.isEmpty) fail('Unexpected request');
            final expected = pending.removeAt(0);
            expect(request.method, expected.method);
            expect(request.url.origin, _server.origin);
            expect(request.url.path, expected.path);
            expect(request.url.queryParameters, expected.query);
            expect(request.followRedirects, isFalse);
            expect(request.headers['X-Plex-Token'], 'synthetic-token');
            expect(request.url.toString(), isNot(contains('synthetic-token')));
            expect(
              request.url.queryParameters.keys.map((key) => key.toLowerCase()),
              isNot(contains('x-plex-token')),
            );
            expect(request.headers['X-Plex-Client-Profile-Name'], 'Generic');
            expect(
              request.headers['X-Plex-Client-Profile-Extra'],
              _desktopExtra,
            );
            if (expected.path.endsWith('decision') ||
                expected.path.endsWith('m3u8') ||
                expected.path.endsWith('ping')) {
              expect(request.headers['X-Plex-Session-Identifier'], _session);
            }
            return http.Response(expected.body, expected.status);
          } catch (error) {
            boundaryFailures.add(error);
            rethrow;
          }
        }),
      );
      addTearDown(client.close);
      expect(
        (await client.transcodeDecision(
          _server,
          request,
          'synthetic-token',
        )).method,
        PlexPlaybackMethod.directPlay,
      );
      final start = await client.startTranscodeSession(
        _server,
        request,
        'synthetic-token',
      );
      expect(
        start.variant.path,
        '/video/:/transcode/universal/session/synthetic/base/index.m3u8',
      );
      expect(start.sessionId, _session);
      expect(start.toString(), isNot(contains(_session)));
      await client.pingTranscodeSession(_server, _session, 'synthetic-token');
      await client.stopTranscodeSession(_server, _session, 'synthetic-token');
      await client.selectPartStreams(
        _server,
        '7',
        audioStreamId: '9',
        subtitleStreamId: '0',
        token: 'synthetic-token',
      );
      expect(pending, isEmpty);
      expect(
        boundaryFailures,
        isEmpty,
        reason: 'Best-effort stop must not hide a fake assertion',
      );
    });

    test(
      'Original omits ceiling and start validation never fetches children',
      () async {
        var calls = 0;
        final client = PlexClient(
          clientIdentifier: 'synthetic',
          httpClient: MockClient((request) async {
            calls++;
            expect(
              calls,
              1,
              reason: 'No child playlist request belongs to the Dart client',
            );
            expect(
              request.url.queryParameters.keys,
              isNot(contains('maxVideoBitrate')),
            );
            expect(
              request.url.queryParameters.keys,
              isNot(contains('videoBitrate')),
            );
            expect(
              request.url.queryParameters.keys,
              isNot(contains('videoResolution')),
            );
            return http.Response(_master, 200);
          }),
        );
        addTearDown(client.close);
        await client.startTranscodeSession(
          _server,
          _request(),
          'synthetic-token',
        );
        expect(calls, 1);
      },
    );

    for (final status in [200, 404, 500]) {
      test('stop is nonthrowing at HTTP $status', () async {
        final failures = <String>[];
        var calls = 0;
        Uri? calledUri;
        final client = PlexClient(
          clientIdentifier: 'synthetic',
          onTranscodeStopFailure: failures.add,
          httpClient: MockClient((request) async {
            expect(++calls, 1);
            calledUri = request.url;
            return http.Response('', status);
          }),
        );
        addTearDown(client.close);
        await client.stopTranscodeSession(_server, _session, 'synthetic-token');
        expect(failures, status == 500 ? ['server-unreachable'] : isEmpty);
        expect(calls, 1);
        expect(calledUri?.path, '/video/:/transcode/universal/stop');
      });
    }

    test('stop contains exceptions from a diagnostic consumer too', () async {
      final client = PlexClient(
        clientIdentifier: 'synthetic',
        onTranscodeStopFailure: (_) => throw StateError('consumer'),
        httpClient: MockClient(
          (_) async => throw http.ClientException('synthetic'),
        ),
      );
      addTearDown(client.close);
      await client.stopTranscodeSession(_server, _session, 'synthetic-token');
    });

    for (final status in [401, 403, 302]) {
      test(
        'decision/start preserve authorization and refuse redirect HTTP $status',
        () async {
          var calls = 0;
          final client = PlexClient(
            clientIdentifier: 'synthetic',
            httpClient: MockClient((_) async {
              calls++;
              return http.Response(
                '',
                status,
                headers: {'location': 'https://elsewhere.invalid/'},
              );
            }),
          );
          addTearDown(client.close);
          final code = status == 401
              ? 'auth-invalid'
              : status == 403
              ? 'access-denied'
              : 'server-unreachable';
          await expectLater(
            client.transcodeDecision(_server, _request(), 'synthetic-token'),
            _error(code),
          );
          await expectLater(
            client.startTranscodeSession(
              _server,
              _request(),
              'synthetic-token',
            ),
            _error(code),
          );
          expect(calls, 2);
        },
      );
    }

    test(
      'master byte limit is enforced at transport before buffering',
      () async {
        var calls = 0;
        final client = PlexClient(
          clientIdentifier: 'synthetic',
          httpClient: MockClient((_) async {
            expect(++calls, 1);
            return http.Response('x' * (maximumPlexMasterBytes + 1), 200);
          }),
        );
        addTearDown(client.close);
        await expectLater(
          client.startTranscodeSession(_server, _request(), 'synthetic-token'),
          _error('session-invalid'),
        );
      },
    );
  });

  group('master validation', () {
    final start = _server.resolve('/video/:/transcode/universal/start.m3u8');
    test('accepts P0-shaped one-variant master and resolves relative URI', () {
      expect(
        validatePlexSessionMaster(
          _master,
          server: _server,
          start: start,
        ).origin,
        _server.origin,
      );
      expect(
        validatePlexSessionMaster(
          _master.replaceFirst('/video/:/transcode/universal/', ''),
          server: _server,
          start: start,
        ).path,
        '/video/:/transcode/universal/session/synthetic/base/index.m3u8',
      );
    });
    final variants = <String, String>{
      'two variants':
          '$_master#EXT-X-STREAM-INF:BANDWIDTH=1\n/video/:/transcode/universal/session/second/base/index.m3u8',
      'rendition': '$_master#EXT-X-MEDIA:TYPE=AUDIO,URI="audio.m3u8"',
      'I-frame': '$_master#EXT-X-I-FRAME-STREAM-INF:URI="iframe.m3u8"',
      'session data URI':
          '$_master#EXT-X-SESSION-DATA:DATA-ID="x",URI="data.json"',
      'session key': '$_master#EXT-X-SESSION-KEY:METHOD=AES-128,URI="key"',
      'off origin': _master.replaceFirst(
        '/video/:',
        'https://elsewhere.invalid/video/:',
      ),
      'HTTP': _master.replaceFirst(
        '/video/:',
        'http://synthetic.invalid:32400/video/:',
      ),
      'userinfo': _master.replaceFirst(
        '/video/:',
        'https://user@synthetic.invalid:32400/video/:',
      ),
      'token query': _master.replaceFirst(
        'index.m3u8',
        'index.m3u8?x-pLeX-ToKeN=synthetic',
      ),
      'encoded token query': _master.replaceFirst(
        'index.m3u8',
        'index.m3u8?%58-Plex-Token=synthetic',
      ),
      'wrong path': _master.replaceFirst(
        '/base/index.m3u8',
        '/other/index.m3u8',
      ),
      'malformed authority': _master.replaceFirst(
        '/video/:',
        'https://[bad/video/:',
      ),
      'malformed query encoding': _master.replaceFirst(
        'index.m3u8',
        'index.m3u8?%FF=value',
      ),
      'no header': _master.replaceFirst('#EXTM3U', '#NO'),
      'no stream': '#EXTM3U\n',
      'missing variant': '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1',
      'loose URI': '$_master stray.m3u8',
      'oversize': '$_master${' ' * maximumPlexMasterBytes}',
    };
    for (final entry in variants.entries) {
      test('refuses ${entry.key}', () {
        expect(
          () => validatePlexSessionMaster(
            entry.value,
            server: _server,
            start: start,
          ),
          _error('session-invalid'),
        );
      });
    }
  });

  group('decision parsing', () {
    for (final fixture in [
      (1000, 1000, 1000, 'copy', PlexPlaybackMethod.directPlay),
      (1001, 3001, 1000, 'copy', PlexPlaybackMethod.directStream),
      (1001, 3000, 1000, 'transcode', PlexPlaybackMethod.transcode),
      (2000, 3000, 2000, 'copy', PlexPlaybackMethod.directStream),
      (2002, 3000, 2002, 'copy', PlexPlaybackMethod.directStream),
      (4999, 4999, 4999, 'burn', PlexPlaybackMethod.transcode),
    ]) {
      for (final xml in [false, true]) {
        test(
          '${fixture.$1}/${fixture.$2} ${xml ? 'XML' : 'JSON'} preserves codes, streams, sanitized texts',
          () {
            final body = xml
                ? '<MediaContainer generalDecisionCode="${fixture.$1}" directPlayDecisionCode="${fixture.$2}" transcodeDecisionCode="${fixture.$3}" generalDecisionText="Unsafe https://synthetic.invalid/private/file /private/file C:\\private\\file"><Video><Media decision="transcode"><Part decision="transcode"><Stream id="1" streamType="1" decision="${fixture.$4}" location="segments" codec="hevc" width="1920" height="1080" bitrate="8000" colorTrc="smpte2084"/><Stream id="2" streamType="3" decision="burn"/></Part></Media></Video></MediaContainer>'
                : jsonEncode({
                    'MediaContainer': {
                      'generalDecisionCode': fixture.$1,
                      'directPlayDecisionCode': fixture.$2,
                      'transcodeDecisionCode': fixture.$3,
                      'generalDecisionText': r'Unsafe https://synthetic.invalid/private/file /private/file C:\private\file',
                      'Metadata': [
                        {
                          'Media': [
                            {
                              'decision': 'transcode',
                              'Part': [
                                {
                                  'decision': 'transcode',
                                  'Stream': [
                                    {
                                      'id': '1',
                                      'streamType': 1,
                                      'decision': fixture.$4,
                                      'location': 'segments',
                                      'codec': 'hevc',
                                      'width': 1920,
                                      'height': 1080,
                                      'bitrate': 8000,
                                      'colorTrc': 'smpte2084',
                                    },
                                    {
                                      'id': '2',
                                      'streamType': 3,
                                      'decision': 'burn',
                                    },
                                  ],
                                },
                              ],
                            },
                          ],
                        },
                      ],
                    },
                  });
            final decision = parsePlexDecision(body);
            expect(decision.generalDecisionCode, fixture.$1);
            expect(decision.directPlayDecisionCode, fixture.$2);
            expect(decision.transcodeDecisionCode, fixture.$3);
            expect(decision.method, fixture.$5);
            expect(decision.generalDecisionText, 'Unsafe <redacted>');
            expect(decision.mediaDecision, 'transcode');
            expect(decision.partDecision, 'transcode');
            final video = decision.streams.first;
            expect(video.id, '1');
            expect(video.codec, 'hevc');
            expect(video.width, 1920);
            expect(video.height, 1080);
            expect(video.bitrate, 8000);
            expect(video.colorTrc, 'smpte2084');
            expect(video.location, 'segments');
            expect(decision.streams.last.decision, 'burn');
          },
        );
      }
    }
    test('spaced paths and URLs cannot leave private filename suffixes', () {
      for (final path in [
        '/media/Private Movie Title.mkv',
        r'C:\Media\Private Movie Title.mkv',
        r'\\synthetic\Media\Private Movie Title.mkv',
        'https://synthetic.invalid/Private Movie Title.mkv',
      ]) {
        expect(
          sanitizePlexDecisionText('Cannot open $path: failure'),
          'Cannot open <redacted>',
        );
        expect(
          sanitizePlexDecisionText('Cannot open "$path": failure'),
          'Cannot open <redacted>: failure',
        );
        expect(
          sanitizePlexDecisionText("Cannot open '$path': failure"),
          'Cannot open <redacted>: failure',
        );
      }
    });
    test('texts strip token fields, controls, UUID and bound length', () {
      expect(
        sanitizePlexDecisionText(
          'X-Plex-Token=synthetic $_session\n${'x' * 300}',
        ),
        hasLength(200),
      );
      expect(
        sanitizePlexDecisionText('X-Plex-Token=synthetic $_session'),
        '<redacted> <redacted>',
      );
    });
    test('invalid envelope fails without including source response', () {
      expect(() => parsePlexDecision('private invalid'), _error('parse-error'));
    });
  });

  group('profile builder', () {
    test(
      'desktop declaration is broad and local eligibility always passes',
      () {
        final profile = buildProfile(MediaCapabilities.desktop, desktop: true);
        expect(profile.profileExtra, _desktopExtra);
        expect(profile.eligible(const PlexMediaFacts()), isTrue);
      },
    );
    test('Fire TV without passthrough exact profile', () {
      expect(
        buildProfile(_fire, desktop: false).profileExtra,
        'add-direct-play-profile(type=videoProfile&container=mkv,mp4&videoCodec=av1,h264,hevc&audioCodec=aac,ac3,eac3&protocol=http&replace=true)+$_target+$_channels$_fireLimitations',
      );
    });
    test('Fire TV with TrueHD and DTS passthrough exact profile', () {
      expect(
        buildProfile(_firePassthrough, desktop: false).profileExtra,
        'add-direct-play-profile(type=videoProfile&container=mkv,mp4&videoCodec=av1,h264,hevc&audioCodec=aac,ac3,dca,eac3,truehd&protocol=http&replace=true)+$_target+$_channels$_fireLimitations',
      );
    });
    test(
      'AV1 Main10 capability matches Main source metadata with bounded depth',
      () {
        const capabilities = MediaCapabilities(
          videoDecoders: [
            VideoDecoderCapabilities(
              codec: 'av1',
              profiles: ['main 10'],
              maxWidth: 3840,
              maxHeight: 2160,
            ),
          ],
          audioDecoders: ['aac'],
          containers: ['mkv'],
        );
        final profile = buildProfile(capabilities, desktop: false);
        expect(
          profile.profileExtra,
          contains('name=video.profile&list=main&replace=true'),
        );
        expect(
          profile.profileExtra,
          contains(
            'scopeName=av1&type=upperBound&name=video.bitDepth&value=10&replace=true',
          ),
        );
        for (final depth in [8, 10, 12]) {
          expect(
            profile.eligible(
              PlexMediaFacts(
                container: 'mkv',
                videoCodec: 'av1',
                videoProfile: 'main',
                bitDepth: depth,
                width: 1920,
                height: 1080,
                audioCodec: 'aac',
              ),
            ),
            depth <= 10,
          );
        }
      },
    );
    test(
      'VP9 numeric capability matches FFmpeg profile names and caps depth',
      () {
        const capabilities = MediaCapabilities(
          videoDecoders: [
            VideoDecoderCapabilities(
              codec: 'vp9',
              profiles: ['0', '2'],
              maxWidth: 3840,
              maxHeight: 2160,
            ),
          ],
          audioDecoders: ['aac'],
          containers: ['mkv'],
        );
        final profile = buildProfile(capabilities, desktop: false);
        expect(
          profile.profileExtra,
          contains('name=video.profile&list=profile 0|profile 2&replace=true'),
        );
        expect(
          profile.profileExtra,
          contains(
            'scopeName=vp9&type=upperBound&name=video.bitDepth&value=10&replace=true',
          ),
        );
        expect(
          profile.eligible(
            const PlexMediaFacts(
              container: 'mkv',
              videoCodec: 'vp9',
              videoProfile: 'profile 2',
              bitDepth: 10,
              width: 1920,
              height: 1080,
              audioCodec: 'aac',
            ),
          ),
          isTrue,
        );
        expect(
          profile.eligible(
            const PlexMediaFacts(
              container: 'mkv',
              videoCodec: 'vp9',
              videoProfile: 'profile 2',
              bitDepth: 12,
              width: 1920,
              height: 1080,
              audioCodec: 'aac',
            ),
          ),
          isFalse,
        );
      },
    );
    test('DV limitations and eligibility apply to their H264 and AV1 codecs', () {
      final profile = buildProfile(_fire, desktop: false);
      for (final source in [('h264', 'high', 9), ('av1', 'main', 10)]) {
        expect(
          profile.profileExtra,
          contains(
            'scopeName=${source.$1}&type=match&name=video.DOVIProfile&list=${source.$3}&isRequired=false',
          ),
        );
        for (final dv in [source.$3, 7]) {
          expect(
            profile.eligible(
              PlexMediaFacts(
                container: 'mkv',
                videoCodec: source.$1,
                videoProfile: source.$2,
                bitDepth: 8,
                width: 1920,
                height: 1080,
                audioCodec: 'aac',
                dolbyVisionProfile: dv,
              ),
            ),
            dv == source.$3,
          );
        }
      }
      final noDv = buildProfile(_phone, desktop: false);
      expect(
        noDv.profileExtra,
        contains(
          'scopeName=h264&type=match&name=video.DOVIProfile&list=&isRequired=false',
        ),
      );
      expect(
        noDv.eligible(
          const PlexMediaFacts(
            container: 'mkv',
            videoCodec: 'h264',
            videoProfile: 'high',
            bitDepth: 8,
            width: 1920,
            height: 1080,
            audioCodec: 'aac',
            dolbyVisionProfile: 9,
          ),
        ),
        isFalse,
      );
    });
    test('phone without HEVC exact profile', () {
      expect(
        buildProfile(_phone, desktop: false).profileExtra,
        'add-direct-play-profile(type=videoProfile&container=mkv,mp4&videoCodec=h264&audioCodec=aac&protocol=http&replace=true)'
        '+add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mp4&videoCodec=h264&audioCodec=aac&replace=true)+$_channels'
        '+add-limitation(scope=videoCodec&scopeName=h264&type=upperBound&name=video.bitDepth&value=8&replace=true)'
        '+add-limitation(scope=videoCodec&scopeName=h264&type=upperBound&name=video.width&value=1920&replace=true)'
        '+add-limitation(scope=videoCodec&scopeName=h264&type=upperBound&name=video.height&value=1080&replace=true)'
        '+add-limitation(scope=videoCodec&scopeName=h264&type=match&name=video.profile&list=baseline|main|high&replace=true)'
        '+add-limitation(scope=videoCodec&scopeName=h264&type=match&name=video.DOVIProfile&list=&isRequired=false&replace=true)',
      );
    });
    final facts = [
      const PlexMediaFacts(
        container: 'mkv',
        videoCodec: 'h264',
        videoProfile: 'high',
        bitDepth: 8,
        width: 1920,
        height: 1080,
        audioCodec: 'aac',
      ),
      const PlexMediaFacts(
        container: 'mkv',
        videoCodec: 'hevc',
        videoProfile: 'main 10',
        bitDepth: 10,
        width: 3840,
        height: 2160,
        audioCodec: 'truehd',
      ),
      const PlexMediaFacts(
        container: 'mkv',
        videoCodec: 'hevc',
        videoProfile: 'main 10',
        bitDepth: 10,
        width: 3840,
        height: 2160,
        dolbyVisionProfile: 7,
        audioCodec: 'aac',
      ),
      const PlexMediaFacts(
        container: 'mkv',
        videoCodec: 'hevc',
        videoProfile: 'main 10',
        bitDepth: 10,
        width: 3840,
        height: 2160,
        dolbyVisionProfile: 8,
        audioCodec: 'aac',
      ),
      const PlexMediaFacts(
        container: 'mkv',
        videoCodec: 'av1',
        videoProfile: 'main',
        bitDepth: 8,
        width: 1920,
        height: 1080,
        audioCodec: 'aac',
      ),
      const PlexMediaFacts(
        container: 'mkv',
        videoCodec: 'h264',
        videoProfile: 'high',
        width: 1920,
        height: 1080,
        audioCodec: 'aac',
      ),
    ];
    for (final fixture in [
      (
        'desktop',
        MediaCapabilities.desktop,
        true,
        [true, true, true, true, true, true],
      ),
      ('Fire TV', _fire, false, [true, false, false, true, true, false]),
      (
        'Fire TV passthrough',
        _firePassthrough,
        false,
        [true, true, false, true, true, false],
      ),
      ('phone', _phone, false, [true, false, false, false, false, false]),
      (
        'unknown',
        MediaCapabilities.unknown,
        false,
        [false, false, false, false, false, false],
      ),
    ]) {
      test(
        '${fixture.$1} eligibility for H264, HEVC/TrueHD, DV7, DV8.1, AV1, missing depth',
        () {
          final profile = buildProfile(fixture.$2, desktop: fixture.$3);
          expect(facts.map(profile.eligible), fixture.$4);
        },
      );
    }
    test(
      'unknown profile, resolution, container and audio never bypass decision',
      () {
        final profile = buildProfile(_fire, desktop: false);
        for (final source in [
          const PlexMediaFacts(
            container: 'mkv',
            videoCodec: 'h264',
            videoProfile: 'unsupported',
            bitDepth: 8,
            width: 1920,
            height: 1080,
            audioCodec: 'aac',
          ),
          const PlexMediaFacts(
            container: 'mkv',
            videoCodec: 'h264',
            videoProfile: 'high',
            bitDepth: 8,
            width: 8000,
            height: 1080,
            audioCodec: 'aac',
          ),
          const PlexMediaFacts(
            container: 'unknown',
            videoCodec: 'h264',
            videoProfile: 'high',
            bitDepth: 8,
            width: 1920,
            height: 1080,
            audioCodec: 'aac',
          ),
          const PlexMediaFacts(
            container: 'mkv',
            videoCodec: 'h264',
            videoProfile: 'high',
            bitDepth: 12,
            width: 1920,
            height: 1080,
            audioCodec: 'aac',
          ),
          const PlexMediaFacts(
            container: 'mkv',
            videoCodec: 'h264',
            videoProfile: 'high',
            bitDepth: 8,
            width: 1920,
            height: 1080,
          ),
        ]) {
          expect(profile.eligible(source), isFalse);
        }
      },
    );
  });
}

PlexSessionRequest _request() => PlexSessionRequest(
  ratingKey: '42',
  sessionId: _session,
  profile: buildProfile(MediaCapabilities.desktop, desktop: true),
);
Matcher _error(String code) =>
    throwsA(isA<PlexException>().having((error) => error.code, 'code', code));
Map<String, String> _expectedQuery(String directPlay) => {
  'path': '/library/metadata/42',
  'mediaIndex': '0',
  'partIndex': '2',
  'offset': '600',
  'session': _session,
  'protocol': 'hls',
  'fastSeek': '1',
  'directPlay': directPlay,
  'directStream': '1',
  'directStreamAudio': '1',
  'videoQuality': '100',
  'maxVideoBitrate': '8000',
  'videoBitrate': '8000',
  'videoResolution': '1920x1080',
  'location': 'wan',
  'autoAdjustQuality': '0',
  'subtitles': 'burn',
  'subtitleSize': '100',
  'audioBoost': '100',
  'audioChannelCount': '8',
};
