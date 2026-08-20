import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/form_error.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  test('safeFormError falls back only for missing or blank messages', () {
    const fallback = 'Try again.';

    expect(safeFormError(const FormatException(), fallback), fallback);
    expect(safeFormError(const FormatException('  '), fallback), fallback);
    expect(
      safeFormError(const PlexException('invalid', ''), fallback),
      fallback,
    );
    expect(
      safeFormError(const PlexException('invalid', '\t'), fallback),
      fallback,
    );
    expect(
      safeFormError(const FormatException('Invalid value'), fallback),
      'Invalid value',
    );
    expect(
      safeFormError(
        const PlexException('invalid', 'Server rejected the value.'),
        fallback,
      ),
      'Server rejected the value.',
    );
    expect(safeFormError(StateError('offline'), fallback), fallback);
  });
}
