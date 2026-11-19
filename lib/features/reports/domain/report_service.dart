import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

class CategorySpendSlice {
  const CategorySpendSlice({
    required this.category,
    required this.amount,
    required this.percentage,
    required this.txCount,
  });

  final CategoryRecord category;
  final int amount;
  final double percentage;
  final int txCount;
}

class MerchantSpendSummary {
  const MerchantSpendSummary({
    required this.merchant,
    required this.totalAmount,
    required this.visitCount,
  });

  final String merchant;
  final int totalAmount;
  final int visitCount;
}

class FinancialSummaryReport {
  const FinancialSummaryReport({
    required this.start,
    required this.end,
    required this.totalIncome,
    required this.totalConsumptionExpense,
    required this.cashInflow,
    required this.cashOutflow,
    required this.netSavings,
    required this.savingRatePercent,
    required this.expenseByCategory,
    required this.topMerchants,
    required this.dailyCashflow,
  });

  final DateTime start;
  final DateTime end;
  final int totalIncome;
  final int totalConsumptionExpense;
  final int cashInflow;
  final int cashOutflow;
  final int netSavings;
  final double? savingRatePercent;
  final List<CategorySpendSlice> expenseByCategory;
  final List<MerchantSpendSummary> topMerchants;
  final Map<DateTime, ({int income, int expense})> dailyCashflow;

  int get elapsedDaysInRange {
    final now = DateTime.now();
    final startDay = DateTime(start.year, start.month, start.day);
    final rawEnd = end.isAfter(now) ? now : end;
    final endDay = DateTime(rawEnd.year, rawEnd.month, rawEnd.day);
    return math.max(1, endDay.difference(startDay).inDays + 1);
  }

  int get activeExpenseDaysCount =>
      dailyCashflow.values.where((d) => d.expense > 0).length;

  int get averageDailyExpense =>
      (totalConsumptionExpense / elapsedDaysInRange).round();

  int get averageActiveDayExpense => activeExpenseDaysCount > 0
      ? (totalConsumptionExpense / activeExpenseDaysCount).round()
      : 0;

  int get todayExpense {
    final now = DateTime.now();
    final key = DateTime(now.year, now.month, now.day);
    return dailyCashflow[key]?.expense ?? 0;
  }

  ({DateTime day, int amount})? get highestExpenseDay {
    DateTime? bestDay;
    var bestAmt = 0;
    for (final e in dailyCashflow.entries) {
      if (e.value.expense > bestAmt) {
        bestAmt = e.value.expense;
        bestDay = e.key;
      }
    }
    return bestDay == null ? null : (day: bestDay, amount: bestAmt);
  }

  ({DateTime day, int amount})? get lowestActiveExpenseDay {
    DateTime? bestDay;
    int? bestAmt;
    for (final e in dailyCashflow.entries) {
      if (e.value.expense <= 0) continue;
      if (bestAmt == null || e.value.expense < bestAmt) {
        bestAmt = e.value.expense;
        bestDay = e.key;
      }
    }
    return bestDay == null || bestAmt == null
        ? null
        : (day: bestDay, amount: bestAmt);
  }

  List<({DateTime day, int income, int expense})> get sortedDailyDescending {
    final list = [
      for (final e in dailyCashflow.entries)
        (day: e.key, income: e.value.income, expense: e.value.expense),
    ];
    list.sort((a, b) => b.day.compareTo(a.day));
    return list;
  }
}

class FinancialRecapData {
  const FinancialRecapData({
    required this.summary,
    required this.previousSummary,
    required this.topCategory,
    required this.biggestExpense,
    required this.highestSpendDay,
    required this.highestSpendDayAmount,
    required this.topFrequentMerchant,
    required this.achievedGoalsCount,
    required this.potentialSavingTip,
  });

  final FinancialSummaryReport summary;
  final FinancialSummaryReport previousSummary;
  final CategorySpendSlice? topCategory;
  final TransactionRecord? biggestExpense;
  final DateTime? highestSpendDay;
  final int highestSpendDayAmount;
  final MerchantSpendSummary? topFrequentMerchant;
  final int achievedGoalsCount;
  final String potentialSavingTip;
}

/// Deterministic reporting & Financial Recap engine (FR-21, FR-22).
/// Separates cashflow (including debt disbursements/repayments) from personal
/// consumption expenses and income.
class ReportService {
  ReportService(this.db);

  final AppDatabase db;

  Future<FinancialSummaryReport> generateSummary({
    required DateTime start,
    required DateTime end,
  }) async {
    final txs = await (db.select(db.transactions)
          ..where((t) =>
              t.status.equals('posted') &
              t.occurredAt.isBiggerOrEqualValue(start) &
              t.occurredAt.isSmallerOrEqualValue(end)))
        .get();

    final cats = await db.select(db.categories).get();
    final catMap = {for (final c in cats) c.id: c};

    var totalIncome = 0;
    var totalExpense = 0;
    var cashIn = 0;
    var cashOut = 0;

    final txById = <String, TransactionRecord>{};
    final merchantAgg = <String, ({int total, int count})>{};
    final daily = <DateTime, ({int income, int expense})>{};

    for (final tx in txs) {
      txById[tx.id] = tx;
      final dayKey = DateTime(
        tx.occurredAt.year,
        tx.occurredAt.month,
        tx.occurredAt.day,
      );
      final dayPrev = daily[dayKey] ?? (income: 0, expense: 0);

      switch (tx.type) {
        case 'income':
          totalIncome += tx.amount;
          cashIn += tx.amount;
          daily[dayKey] = (
            income: dayPrev.income + tx.amount,
            expense: dayPrev.expense,
          );
        case 'expense':
          totalExpense += tx.amount;
          cashOut += tx.amount;
          daily[dayKey] = (
            income: dayPrev.income,
            expense: dayPrev.expense + tx.amount,
          );
          final mName = (tx.merchant?.trim().isNotEmpty == true)
              ? tx.merchant!.trim()
              : (tx.description.trim().isNotEmpty ? tx.description.trim() : null);
          if (mName != null) {
            final prevM = merchantAgg[mName] ?? (total: 0, count: 0);
            merchantAgg[mName] = (
              total: prevM.total + tx.amount,
              count: prevM.count + 1,
            );
          }
        case 'refund':
          totalExpense -= tx.amount;
          cashIn += tx.amount;
          daily[dayKey] = (
            income: dayPrev.income,
            expense: math.max(0, dayPrev.expense - tx.amount),
          );
        case 'debt_disbursement':
        case 'debt_repayment':
          // Debt principal alters cashflow, not personal consumption/income (FR-13, FR-21)
          if (tx.description.toLowerCase().contains('utang dari') ||
              tx.description.toLowerCase().contains('pelunasan piutang')) {
            cashIn += tx.amount;
          } else {
            cashOut += tx.amount;
          }
        default:
          break;
      }
    }

    totalExpense = math.max(0, totalExpense);
    final splits = txById.isEmpty
        ? <TransactionSplitRecord>[]
        : await (db.select(db.transactionSplits)
              ..where((s) => s.transactionId.isIn(txById.keys.toList())))
            .get();

    final catAgg = <String, ({int amount, Set<String> txIds})>{};
    for (final s in splits) {
      final parentTx = txById[s.transactionId];
      if (parentTx == null) continue;
      if (parentTx.type != 'expense' &&
          parentTx.type != 'refund' &&
          parentTx.type != 'transfer') {
        continue;
      }
      // Note: transfer admin fee split uses DefaultCategoryIds.adminFee
      final sign = parentTx.type == 'refund' ? -1 : 1;
      final prev = catAgg[s.categoryId] ?? (amount: 0, txIds: <String>{});
      catAgg[s.categoryId] = (
        amount: prev.amount + (s.amount * sign),
        txIds: {...prev.txIds, s.transactionId},
      );
      if (parentTx.type == 'transfer') {
        totalExpense += s.amount;
      }
    }

    final slices = <CategorySpendSlice>[];
    for (final entry in catAgg.entries) {
      if (entry.value.amount <= 0) continue;
      final cat = catMap[entry.key];
      if (cat == null) continue;
      slices.add(
        CategorySpendSlice(
          category: cat,
          amount: entry.value.amount,
          percentage:
              totalExpense > 0 ? (entry.value.amount / totalExpense) * 100 : 0,
          txCount: entry.value.txIds.length,
        ),
      );
    }
    slices.sort((a, b) => b.amount.compareTo(a.amount));

    final merchants = merchantAgg.entries
        .map(
          (e) => MerchantSpendSummary(
            merchant: e.key,
            totalAmount: e.value.total,
            visitCount: e.value.count,
          ),
        )
        .toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    final netSavings = totalIncome - totalExpense;
    final savingRate =
        totalIncome > 0 ? (netSavings / totalIncome) * 100 : null;

    return FinancialSummaryReport(
      start: start,
      end: end,
      totalIncome: totalIncome,
      totalConsumptionExpense: totalExpense,
      cashInflow: cashIn,
      cashOutflow: cashOut,
      netSavings: netSavings,
      savingRatePercent: savingRate,
      expenseByCategory: slices,
      topMerchants: merchants.take(10).toList(),
      dailyCashflow: daily,
    );
  }

  /// Generates Spotify-Wrapped style Financial Recap comparing an equal-day window (FR-22).
  Future<FinancialRecapData> generateRecap({
    required DateTime start,
    required DateTime end,
  }) async {
    final summary = await generateSummary(start: start, end: end);
    final spanDays = math.max(1, end.difference(start).inDays + 1);
    final prevEnd = start.subtract(const Duration(seconds: 1));
    final prevStart = start.subtract(Duration(days: spanDays));
    final previousSummary =
        await generateSummary(start: prevStart, end: prevEnd);

    final expenses = await (db.select(db.transactions)
          ..where((t) =>
              t.status.equals('posted') &
              t.type.equals('expense') &
              t.occurredAt.isBiggerOrEqualValue(start) &
              t.occurredAt.isSmallerOrEqualValue(end))
          ..orderBy([(t) => OrderingTerm.desc(t.amount)]))
        .get();

    final biggestExpense = expenses.isEmpty ? null : expenses.first;

    DateTime? highestDay;
    var highestDayAmt = 0;
    for (final e in summary.dailyCashflow.entries) {
      if (e.value.expense > highestDayAmt) {
        highestDayAmt = e.value.expense;
        highestDay = e.key;
      }
    }

    final frequentMerchants = [...summary.topMerchants]
      ..sort((a, b) => b.visitCount.compareTo(a.visitCount));
    final topFreq = frequentMerchants.isEmpty ? null : frequentMerchants.first;

    final completedGoals = await (db.select(db.goals)
          ..where((g) => g.status.equals('completed')))
        .get();

    String tip;
    if (topFreq != null && topFreq.visitCount >= 4) {
      final avgPerVisit = (topFreq.totalAmount / topFreq.visitCount).round();
      final potential = avgPerVisit * math.max<int>(1, topFreq.visitCount ~/ 4);
      tip =
          'Kamu bertransaksi di "${topFreq.merchant}" sebanyak ${topFreq.visitCount} kali '
          'total Rp${_fmt(topFreq.totalAmount)}. Mengurangi 25% frekuensi berpotensi '
          'menghemat sekitar Rp${_fmt(potential)}.';
    } else if (summary.expenseByCategory.isNotEmpty) {
      final top = summary.expenseByCategory.first;
      tip =
          'Kategori terbesar adalah ${top.category.name} (${top.percentage.toStringAsFixed(0)}%). '
          'Menetapkan anggaran mingguan dapat membantu menekan pengeluaran impulsif.';
    } else {
      tip = 'Catat transaksi secara rutin untuk mendapatkan insight penghematan.';
    }

    return FinancialRecapData(
      summary: summary,
      previousSummary: previousSummary,
      topCategory: summary.expenseByCategory.isEmpty
          ? null
          : summary.expenseByCategory.first,
      biggestExpense: biggestExpense,
      highestSpendDay: highestDay,
      highestSpendDayAmount: highestDayAmt,
      topFrequentMerchant: topFreq,
      achievedGoalsCount: completedGoals.length,
      potentialSavingTip: tip,
    );
  }

  static String _fmt(int n) {
    final s = n.toString();
    return s.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
  }
}
