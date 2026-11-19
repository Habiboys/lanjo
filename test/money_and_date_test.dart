import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lanjo/core/money/money_formatter.dart';
import 'package:lanjo/core/utils/date_utils.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  group('MoneyFormatter', () {
    test('parses Indonesian amount shorthands deterministically', () {
      expect(MoneyFormatter.parseIndonesianAmount('25000'), 25000);
      expect(MoneyFormatter.parseIndonesianAmount('Rp 25.000'), 25000);
      expect(MoneyFormatter.parseIndonesianAmount('25k'), 25000);
      expect(MoneyFormatter.parseIndonesianAmount('25 rb'), 25000);
      expect(MoneyFormatter.parseIndonesianAmount('25 ribu'), 25000);
      expect(MoneyFormatter.parseIndonesianAmount('1,5 jt'), 1500000);
      expect(MoneyFormatter.parseIndonesianAmount('1.5 juta'), 1500000);
      expect(MoneyFormatter.parseIndonesianAmount('abc'), isNull);
    });

    test('splits Rupiah equally without losing remainder', () {
      final parts = MoneyFormatter.splitEqually(100000, 3);
      expect(parts, [33334, 33333, 33333]);
      expect(parts.reduce((a, b) => a + b), 100000);
    });

    test('allocates by weights deterministically', () {
      final parts = MoneyFormatter.allocateByWeights(100, [1, 1, 1]);
      expect(parts.reduce((a, b) => a + b), 100);
    });
  });

  group('ArusDateUtils', () {
    test('clamps day 31 to February last day (FR-10)', () {
      final nonLeap = ArusDateUtils.clampDayInMonth(2025, 2, 31);
      expect(nonLeap, DateTime(2025, 2, 28));

      final leap = ArusDateUtils.clampDayInMonth(2024, 2, 31);
      expect(leap, DateTime(2024, 2, 29));
    });

    test('computes financial period anchored to payday', () {
      final period = ArusDateUtils.currentFinancialPeriod(
        now: DateTime(2026, 11, 16),
        paydayDay: 25,
      );
      expect(period.start, DateTime(2026, 10, 25));
      expect(period.endExclusive, DateTime(2026, 11, 25));
      expect(period.remainingDays, 9);
    });
  });
}
