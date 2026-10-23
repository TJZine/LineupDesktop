import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A node is either a list or a readable document. Resource paths never cross
/// back into a general filesystem operation: native reads use minted IDs only.
class LicenseItem {
  const LicenseItem.list(
    this.id,
    this.title,
    this.children, {
    this.subtitle = '',
  }) : read = null;
  const LicenseItem.document(
    this.id,
    this.title,
    this.read, {
    this.subtitle = '',
  }) : children = null;
  final String id;
  final String title;
  final String subtitle;
  final List<LicenseItem>? children;
  final Future<String> Function()? read;
}

class LicenseSource {
  const LicenseSource(this.title, this.load);
  final String title;
  final Future<List<LicenseItem>> Function() load;
}

enum _LicenseOperation { loadIndex, read }

class LicensesRepository {
  LicensesRepository({AssetBundle? assets, MethodChannel? channel})
    : _assets = assets ?? rootBundle,
      _channel = channel ?? const MethodChannel('lineup/platform');
  final AssetBundle _assets;
  final MethodChannel _channel;
  final bool _diagnosticsEnabled =
      Platform.environment['LINEUP_LICENSE_DIAGNOSTICS'] == '1';

  // Error values select fixed categories; raw codes/messages/details never
  // enter stderr. One record per failed index/read attempt, success is silent.
  void _reportFailure(_LicenseOperation operation, Object error) {
    if (!_diagnosticsEnabled) return;
    final category = switch (error) {
      MissingPluginException() => 'missing_plugin',
      PlatformException(code: 'license_resources_unavailable') =>
        'native_unavailable',
      PlatformException() => 'platform_other',
      FormatException() =>
        operation == _LicenseOperation.loadIndex
            ? 'invalid_index'
            : 'invalid_document',
      _ => 'other',
    };
    try {
      stderr.writeln(
        '[lineup-license-dart] operation=${operation == _LicenseOperation.loadIndex ? 'index' : 'read'} category=$category',
      );
    } catch (_) {
      // A diagnostic sink failure must not replace the original operation error.
    }
  }

  List<LicenseSource> get sources => [
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.android)
      LicenseSource('Native runtime', _native),
    LicenseSource('Flutter and packages', _packages),
    LicenseSource('Fonts and engine notices', _notices),
    if (defaultTargetPlatform == TargetPlatform.macOS)
      LicenseSource('Sources and rebuilding', _sources),
  ];

  Future<List<LicenseItem>> _native() async {
    try {
      return await _nativeIndex();
    } catch (error) {
      _reportFailure(_LicenseOperation.loadIndex, error);
      rethrow;
    }
  }

  Future<List<LicenseItem>> _nativeIndex() async {
    final entries = await _channel.invokeListMethod<Object?>(
      'listLicenseDocuments',
    );
    if (entries == null || entries.isEmpty || entries.length > 4096) {
      throw const FormatException('License resources unavailable');
    }
    final ids = <String>{};
    final paths = <String>{};
    final groups = <String, List<LicenseItem>>{};
    for (final value in entries) {
      if (value is! Map ||
          value['id'] is! String ||
          value['path'] is! String ||
          value['bytes'] is! int) {
        throw const FormatException('Invalid license index');
      }
      final id = value['id'] as String;
      final path = value['path'] as String;
      final parts = path.split('/');
      if (!ids.add(id) ||
          !paths.add(path) ||
          id.isEmpty ||
          parts.any((p) => p.isEmpty || p == '.' || p == '..') ||
          path.contains('\\') ||
          (value['bytes'] as int) <= 0 ||
          (value['bytes'] as int) > 2 * 1024 * 1024 ||
          !(path == 'BUILD-INFO.txt' ||
              parts.first == 'licenses' ||
              parts.first == 'patches')) {
        throw const FormatException('Invalid license index');
      }
      final group = parts.first == 'licenses' && parts.length >= 3
          ? parts[1]
          : parts.first == 'patches'
          ? 'Runtime patches'
          : 'Runtime information';
      (groups[group] ??= []).add(
        LicenseItem.document(
          id,
          parts.last,
          () => _nativeDocument(id),
          subtitle: path,
        ),
      );
    }
    if (!paths.contains('BUILD-INFO.txt') ||
        !paths.contains('licenses/NOTICES-SUMMARY.txt')) {
      throw const FormatException('Incomplete license index');
    }
    final names = groups.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [
      for (final name in names)
        LicenseItem.list(
          'native/$name',
          name,
          groups[name]!..sort((a, b) => a.subtitle.compareTo(b.subtitle)),
        ),
    ];
  }

  Future<String> _nativeDocument(String id) async {
    try {
      final text = await _channel.invokeMethod<String>('readLicenseDocument', {
        'id': id,
      });
      if (text == null || text.isEmpty) {
        throw const FormatException('Empty license');
      }
      return text;
    } catch (error) {
      _reportFailure(_LicenseOperation.read, error);
      rethrow;
    }
  }

  Future<List<LicenseItem>> _packages() async {
    final byPackage = <String, List<LicenseItem>>{};
    var number = 0;
    await for (final entry in LicenseRegistry.licenses) {
      final packages = entry.packages.toList()..sort();
      final paragraphs = entry.paragraphs.toList();
      final text = paragraphs
          .map((p) => '${p.indent > 0 ? ' ' * (p.indent * 2) : ''}${p.text}')
          .join('\n\n');
      final id = 'flutter/${number++}';
      for (final package in packages) {
        (byPackage[package] ??= []).add(
          LicenseItem.document(
            id,
            'License ${(byPackage[package]?.length ?? 0) + 1}',
            () async => text,
            subtitle: packages.join(', '),
          ),
        );
      }
    }
    if (byPackage.isEmpty) {
      throw const FormatException('Package licenses unavailable');
    }
    final names = byPackage.keys.toList()..sort();
    return [
      for (final name in names)
        LicenseItem.list('package/$name', name, byPackage[name]!),
    ];
  }

  Future<List<LicenseItem>> _notices() async => [
    _asset('Instrument Sans', 'assets/fonts/instrumentsans/OFL.txt'),
    _asset('Inter', 'assets/fonts/inter/OFL.txt'),
    if (defaultTargetPlatform == TargetPlatform.macOS)
      _asset('Engine notices', 'assets/licenses/engine-notices.txt'),
  ];

  Future<List<LicenseItem>> _sources() async {
    final text = await _assets.loadString('assets/licenses/index.txt');
    final items = <LicenseItem>[];
    for (final line in text.split('\n').where((line) => line.isNotEmpty)) {
      final fields = line.split('\t');
      if (fields.length != 2 ||
          fields[1].contains('/') ||
          fields[1].contains('..')) {
        throw const FormatException('Invalid source material index');
      }
      items.add(_asset(fields[0], 'assets/licenses/${fields[1]}'));
    }
    return [LicenseItem.list('sources', 'Sources and rebuilding', items)];
  }

  LicenseItem _asset(String title, String path) => LicenseItem.document(
    path,
    title,
    () => _assets.loadString(path),
    subtitle: title,
  );
}
