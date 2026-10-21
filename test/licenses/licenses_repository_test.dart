import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/licenses/licenses_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lineup/platform');
  late List<Object?> index;
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls.clear();
    index = [
      {'id': 'a', 'path': 'BUILD-INFO.txt', 'bytes': 10},
      {'id': 'b', 'path': 'licenses/NOTICES-SUMMARY.txt', 'bytes': 10},
      {'id': 'c', 'path': 'licenses/new component/nested/COPYING', 'bytes': 20},
      {'id': 'd', 'path': 'patches/mpv/fix.patch', 'bytes': 10},
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'listLicenseDocuments') return index;
          return 'Copyright © fixture\n\n    Full unmodified notice.\n';
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'native hierarchy retains unknown nested files and reads only minted ID',
    () async {
      final groups = await LicensesRepository().sources.first.load();
      final group = groups.singleWhere((g) => g.title == 'new component');
      final file = group.children!.single;
      expect(file.title, 'COPYING');
      expect(file.subtitle, 'licenses/new component/nested/COPYING');
      expect(
        await file.read!(),
        'Copyright © fixture\n\n    Full unmodified notice.\n',
      );
      expect(calls.last.arguments, {'id': 'c'});
      expect(groups.expand((g) => g.children!).length, 4);
    },
  );

  test(
    'rejects duplicate IDs, paths, traversal, bad shape and missing tree',
    () async {
      final original = [...index];
      for (final bad in [
        [...original, original[0]],
        [
          ...original,
          {'id': 'a', 'path': 'licenses/extra', 'bytes': 5},
        ],
        [
          ...original,
          {'id': 'z', 'path': '../escape', 'bytes': 5},
        ],
        [
          ...original,
          {'id': 'z', 'path': '/etc/passwd', 'bytes': 5},
        ],
        [
          ...original,
          {'id': 'z', 'path': 'licenses/x', 'bytes': 3 * 1024 * 1024},
        ],
        [
          ...original,
          {'id': 'z', 'path': 'licenses/x', 'bytes': 0},
        ],
        [...original, 'invalid'],
        [original.first],
        <Object?>[],
      ]) {
        index = bad;
        await expectLater(
          LicensesRepository().sources.first.load(),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'all font, engine and source assets load without network or caches',
    () async {
      final sources = LicensesRepository().sources;
      for (final name in [
        'Fonts and engine notices',
        'Sources and rebuilding',
      ]) {
        final items = await sources.singleWhere((s) => s.title == name).load();
        expect(items, isNotEmpty);
        for (final parent in items) {
          for (final item in parent.children ?? [parent]) {
            expect(await item.read!(), isNotEmpty);
          }
        }
      }
      final notices = await sources
          .singleWhere((s) => s.title == 'Fonts and engine notices')
          .load();
      expect(await notices.first.read!(), contains('SIL OPEN FONT LICENSE'));
      expect(
        await notices.last.read!(),
        contains('Windows DirectComposition patch is not applied'),
      );
    },
  );

  test(
    'Flutter entries retain all package attribution and indentation',
    () async {
      LicenseRegistry.addLicense(
        () => Stream.value(
          LicenseEntryWithLineBreaks([
            'r03-package-a',
            'r03-package-b',
          ], 'Copyright test\n\n    indented notice'),
        ),
      );
      final packages = await LicensesRepository().sources
          .singleWhere((s) => s.title == 'Flutter and packages')
          .load();
      final item = packages
          .singleWhere((p) => p.title == 'r03-package-a')
          .children!
          .single;
      expect(item.subtitle, 'r03-package-a, r03-package-b');
      expect(await item.read!(), contains('Copyright test'));
      expect(await item.read!(), contains('indented notice'));
      final other = packages
          .singleWhere((p) => p.title == 'r03-package-b')
          .children!
          .single;
      expect(other.id, item.id);
    },
  );
}
