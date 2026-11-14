import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/persistence/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const credentials = KeychainCredentialStore();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    test(
      '$platform profile deletion addresses one key and preserves options',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final values = <String, String>{};
        final calls = <MethodCall>[];
        var failDelete = false;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final arguments = Map<Object?, Object?>.from(call.arguments as Map);
          final options = Map<Object?, Object?>.from(
            arguments['options']! as Map,
          );
          if (platform == TargetPlatform.android) {
            expect(options['resetOnError'], 'false');
          }
          if (platform == TargetPlatform.macOS) {
            expect(options['usesDataProtectionKeychain'], 'false');
          }
          final key = arguments['key'] as String?;
          switch (call.method) {
            case 'write':
              values[key!] = arguments['value']! as String;
              return null;
            case 'read':
              return values[key];
            case 'delete':
              if (failDelete) {
                throw PlatformException(code: 'synthetic-storage-error');
              }
              values.remove(key);
              return null;
            default:
              fail('Unexpected broad credential operation ${call.method}');
          }
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        await credentials.writeAccountToken('synthetic-account');
        await credentials.writeProfileToken('target', 'synthetic-target');
        await credentials.writeProfileToken('target.other', 'synthetic-other');
        await credentials.deleteProfileToken('target');
        expect(await credentials.readProfileToken('target'), isNull);
        expect(
          await credentials.readProfileToken('target.other'),
          'synthetic-other',
        );
        expect(await credentials.readAccountToken(), 'synthetic-account');
        expect(
          values.keys,
          unorderedEquals([
            'plex.account-token',
            'plex.profile-token.target.other',
          ]),
        );
        expect(calls.where((call) => call.method == 'delete'), hasLength(1));
        final deletion = calls.singleWhere((call) => call.method == 'delete');
        expect((deletion.arguments as Map)['key'], 'plex.profile-token.target');

        failDelete = true;
        await expectLater(
          credentials.deleteProfileToken('target.other'),
          throwsA(isA<PlatformException>()),
        );
        expect(
          await credentials.readProfileToken('target.other'),
          'synthetic-other',
        );
        expect(await credentials.readAccountToken(), 'synthetic-account');
      },
    );
  }
}
