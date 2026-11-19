import 'package:intl/intl.dart';

/// Deterministic integer-Rupiah formatting, parsing, and split utilities (BR-01).
abstract final class MoneyFormatter {
  static final NumberFormat _idrFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  static final NumberFormat _plainNumber = NumberFormat.decimalPattern('id_ID');

  /// Formats an integer Rupiah amount, e.g. `Rp25.000` or `-Rp25.000`.
  static String format(int amount, {bool hidden = false}) {
    if (hidden) return 'Rp••••••';
    if (amount < 0) {
      return '-${_idrFormat.format(amount.abs())}';
    }
    return _idrFormat.format(amount);
  }

  /// Formats plain number without Rp prefix, e.g. `25.000`.
  static String formatNumber(int amount) => _plainNumber.format(amount);

  /// Compact Indonesian display, e.g. `Rp1,5 jt`, `Rp250 rb`.
  static String formatCompact(int amount, {bool hidden = false}) {
    if (hidden) return 'Rp••••';
    final sign = amount < 0 ? '-' : '';
    final abs = amount.abs();
    if (abs >= 1000000000) {
      final v = (abs / 1000000000).toStringAsFixed(abs % 1000000000 == 0 ? 0 : 1);
      return '${sign}Rp${v.replaceAll('.', ',')} M';
    }
    if (abs >= 1000000) {
      final v = (abs / 1000000).toStringAsFixed(abs % 1000000 == 0 ? 0 : 1);
      return '${sign}Rp${v.replaceAll('.', ',')} jt';
    }
    if (abs >= 10000) {
      final v = (abs / 1000).toStringAsFixed(abs % 1000 == 0 ? 0 : 1);
      return '${sign}Rp${v.replaceAll('.', ',')} rb';
    }
    return format(amount);
  }

  /// Parses Indonesian amount shorthand such as `25000`, `25.000`, `25k`, `25rb`,
  /// `25 ribu`, `1,5 jt`, `1.5 juta` into integer Rupiah. Returns null if invalid.
  static int? parseIndonesianAmount(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    final cleaned = normalized
        .replaceAll('rp', '')
        .replaceAll('idr', '')
        .trim();

    // Check shorthand suffixes: juta/jt, ribu/rb/k, miliar/m
    final regex = RegExp(r'^([0-9.,]+)\s*(miliar|m|juta|jt|ribu|rb|k)?$');
    final match = regex.firstMatch(cleaned);
    if (match != null) {
      final numPart = match.group(1)!;
      final unit = match.group(2);
      if (unit != null) {
        final decimalStr = numPart.replaceAll(',', '.');
        final value = double.tryParse(decimalStr);
        if (value == null) return null;
        final multiplier = switch (unit) {
          'miliar' || 'm' => 1000000000,
          'juta' || 'jt' => 1000000,
          'ribu' || 'rb' || 'k' => 1000,
          _ => 1,
        };
        return (value * multiplier).round();
      }
    }

    // Standard Indonesian integer string with dots as thousand separators
    final digitsOnly = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return null;
    return int.tryParse(digitsOnly);
  }

  /// Deterministically distributes [totalAmount] equally across [count] parts
  /// so that the sum of parts equals [totalAmount] (FR-14).
  static List<int> splitEqually(int totalAmount, int count) {
    if (count <= 0) {
      throw ArgumentError.value(count, 'count', 'Must be positive');
    }
    final base = totalAmount ~/ count;
    final remainder = totalAmount % count;
    return List<int>.generate(
      count,
      (i) => i < remainder ? base + 1 : base,
    );
  }

  /// Deterministically allocates [totalAmount] by integer weights (e.g. percentages
  /// or item subtotals) so the sum always matches [totalAmount].
  static List<int> allocateByWeights(int totalAmount, List<int> weights) {
    if (weights.isEmpty) return const [];
    final totalWeight = weights.fold<int>(0, (sum, w) => sum + w);
    if (totalWeight <= 0) {
      return splitEqually(totalAmount, weights.length);
    }

    final baseAmounts = <int>[];
    final remainders = <({int index, int rem})>[];
    var allocated = 0;

    for (var i = 0; i < weights.length; i++) {
      final numerator = totalAmount * weights[i];
      final floorVal = numerator ~/ totalWeight;
      baseAmounts.add(floorVal);
      allocated += floorVal;
      remainders.add((index: i, rem: numerator % totalWeight));
    }

    // Distribute remaining Rupiah deterministically by largest remainder, then lowest index
    remainders.sort((a, b) {
      final cmp = b.rem.compareTo(a.rem);
      return cmp != 0 ? cmp : a.index.compareTo(b.index);
    });

    var diff = totalAmount - allocated;
    var cursor = 0;
    while (diff > 0) {
      baseAmounts[remainders[cursor].index] += 1;
      diff--;
      cursor = (cursor + 1) % remainders.length;
    }
    return baseAmounts;
  }
}
