import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/domain/filter_helpers.dart';

void main() {
  test('date-only end filter includes the entire selected day', () {
    final end = parseFilterEndDate('2026-06-30');

    expect(end, DateTime(2026, 6, 30, 23, 59, 59, 999, 999));
  });

  test('text filters match band and mode case-insensitively', () {
    expect(matchesFilterText('20m', '20M'), isTrue);
    expect(matchesFilterText('SSB', 'ssb'), isTrue);
    expect(matchesFilterText('40m', '20m'), isFalse);
  });
}
