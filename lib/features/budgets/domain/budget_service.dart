import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/utils/date_utils.dart';

class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.category,
    required this.spentAmount,
    required this.effectiveLimit,
    required this.projectedEndSpend,
  });

  final BudgetRecord budget;
  final CategoryRecord? category;
  final int spentAmount;
  final int effectiveLimit;
  final int projectedEndSpend;

  int get remaining => effectiveLimit - spentAmount;
  double get ratio => effectiveLimit <= 0 ? 0 : spentAmount / effectiveLimit;
  bool get isWarning80 => ratio >= 0.8 && ratio < 1.0;
  bool get isExceeded => ratio >= 1.0;
}

/// Deterministic budget tracking, forecasting, and 80%/100% warnings (FR-08).
class BudgetService {
  BudgetService(this.db, this._notifications, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final AppDatabase db;
  final LocalNotificationService _notifications;
  final Uuid _uuid;

  Future<String> createBudget({
    required String name,
    String? categoryId,
    required int limitAmount,
    required String periodType,
    required DateTime startDate,
    required DateTime endDate,
    bool rolloverEnabled = false,
  }) async {
    final id = _uuid.v4();
    await db.into(db.budgets).insert(
          BudgetsCompanion.insert(
            id: id,
            name: name.trim(),
            categoryId: Value(categoryId),
            limitAmount: limitAmount,
            periodType: periodType,
            startDate: startDate,
            endDate: endDate,
            rolloverEnabled: Value(rolloverEnabled),
            createdAt: DateTime.now(),
          ),
        );
    return id;
  }

  Future<void> updateBudget({
    required String budgetId,
    required String name,
    String? categoryId,
    required int limitAmount,
    required String periodType,
    required DateTime startDate,
    required DateTime endDate,
    required bool rolloverEnabled,
  }) async {
    await (db.update(db.budgets)..where((b) => b.id.equals(budgetId))).write(
      BudgetsCompanion(
        name: Value(name.trim()),
        categoryId: Value(categoryId),
        limitAmount: Value(limitAmount),
        periodType: Value(periodType),
        startDate: Value(startDate),
        endDate: Value(endDate),
        rolloverEnabled: Value(rolloverEnabled),
        alert80Sent: const Value(false),
        alert100Sent: const Value(false),
      ),
    );
  }

  Future<void> deleteBudget(String budgetId) async {
    await (db.delete(db.budgets)..where((b) => b.id.equals(budgetId))).go();
  }

  Future<List<BudgetProgress>> getActiveBudgetProgresses({DateTime? now}) async {
    final ref = now ?? DateTime.now();
    final activeBudgets = await (db.select(db.budgets)
          ..where((b) => b.isActive.equals(true)))
        .get();
    final categories = await db.select(db.categories).get();
    final catMap = {for (final c in categories) c.id: c};

    final result = <BudgetProgress>[];
    for (final b in activeBudgets) {
      final spent = await computeSpentForPeriod(
        categoryId: b.categoryId,
        start: b.startDate,
        end: b.endDate,
        allCategories: categories,
      );
      final effectiveLimit =
          b.limitAmount + (b.rolloverEnabled ? b.rolloverAmount : 0);

      final totalDays = math.max(1, b.endDate.difference(b.startDate).inDays + 1);
      final elapsedDays = ref.isBefore(b.startDate)
          ? 1
          : math.min(totalDays, ref.difference(b.startDate).inDays + 1);
      final projected = ((spent / elapsedDays) * totalDays).round();

      result.add(
        BudgetProgress(
          budget: b,
          category: b.categoryId == null ? null : catMap[b.categoryId],
          spentAmount: spent,
          effectiveLimit: effectiveLimit,
          projectedEndSpend: projected,
        ),
      );
    }
    return result;
  }

  /// Sums posted expenses minus refunds for [categoryId] (including subcategories)
  /// within `[start, end]`. Transfers and debt principal are naturally excluded.
  Future<int> computeSpentForPeriod({
    String? categoryId,
    required DateTime start,
    required DateTime end,
    List<CategoryRecord>? allCategories,
  }) async {
    final cats = allCategories ?? await db.select(db.categories).get();
    Set<String>? targetCategoryIds;
    if (categoryId != null) {
      targetCategoryIds = {
        categoryId,
        ...cats.where((c) => c.parentId == categoryId).map((c) => c.id),
      };
    }

    final txs = await (db.select(db.transactions)
          ..where((t) =>
              t.status.equals('posted') &
              t.type.isIn(['expense', 'refund']) &
              t.occurredAt.isBiggerOrEqualValue(start) &
              t.occurredAt.isSmallerOrEqualValue(end)))
        .get();
    if (txs.isEmpty) return 0;

    final txTypeMap = {for (final t in txs) t.id: t.type};
    final splits = await (db.select(db.transactionSplits)
          ..where((s) => s.transactionId.isIn(txTypeMap.keys.toList())))
        .get();

    var netSpent = 0;
    for (final split in splits) {
      if (targetCategoryIds != null &&
          !targetCategoryIds.contains(split.categoryId)) {
        continue;
      }
      final txType = txTypeMap[split.transactionId];
      if (txType == 'expense') {
        netSpent += split.amount;
      } else if (txType == 'refund') {
        netSpent -= split.amount;
      }
    }
    return math.max(0, netSpent);
  }

  /// Checks all active budgets after a transaction and triggers 80%/100% alerts once.
  Future<void> evaluateAlerts() async {
    final progresses = await getActiveBudgetProgresses();
    for (final p in progresses) {
      if (p.isExceeded && !p.budget.alert100Sent) {
        await (db.update(db.budgets)..where((b) => b.id.equals(p.budget.id)))
            .write(const BudgetsCompanion(alert100Sent: Value(true)));
        await _notifications.showImmediateAlert(
          kind: 'budget',
          title: 'Anggaran ${p.budget.name} terlampaui',
          body: 'Pengeluaran telah mencapai 100% dari batas anggaran.',
          deepLink: '/plans/budgets',
        );
      } else if (p.isWarning80 && !p.budget.alert80Sent) {
        await (db.update(db.budgets)..where((b) => b.id.equals(p.budget.id)))
            .write(const BudgetsCompanion(alert80Sent: Value(true)));
        await _notifications.showImmediateAlert(
          kind: 'budget',
          title: 'Anggaran ${p.budget.name} hampir habis',
          body: 'Pengeluaran sudah mencapai 80% batas anggaran periode ini.',
          deepLink: '/plans/budgets',
        );
      }
    }
  }

  /// Duplicates last month's budgets into the current period without creating duplicates.
  Future<int> duplicatePreviousMonthBudgets({int? paydayDay}) async {
    final period = ArusDateUtils.currentFinancialPeriod(paydayDay: paydayDay);
    final existing = await (db.select(db.budgets)
          ..where((b) => b.isActive.equals(true)))
        .get();
    final existingKeys = existing
        .where((b) => !b.startDate.isBefore(period.start))
        .map((b) => '${b.categoryId ?? 'all'}_${b.name}')
        .toSet();

    final source = existing
        .where((b) => b.startDate.isBefore(period.start))
        .toList();
    var created = 0;
    for (final b in source) {
      final key = '${b.categoryId ?? 'all'}_${b.name}';
      if (existingKeys.contains(key)) continue;
      var rollover = 0;
      if (b.rolloverEnabled) {
        final prevSpent = await computeSpentForPeriod(
          categoryId: b.categoryId,
          start: b.startDate,
          end: b.endDate,
        );
        rollover = math.max(0, b.limitAmount + b.rolloverAmount - prevSpent);
      }
      await db.into(db.budgets).insert(
            BudgetsCompanion.insert(
              id: _uuid.v4(),
              name: b.name,
              categoryId: Value(b.categoryId),
              limitAmount: b.limitAmount,
              periodType: b.periodType,
              startDate: period.start,
              endDate: period.endExclusive.subtract(const Duration(seconds: 1)),
              rolloverEnabled: Value(b.rolloverEnabled),
              rolloverAmount: Value(rollover),
              createdAt: DateTime.now(),
            ),
          );
      created++;
    }
    return created;
  }

  /// Recommends a monthly budget based on average spending over the last 3 months.
  Future<int> recommendMonthlyBudget(String categoryId) async {
    final now = DateTime.now();
    final threeMonthsAgo = DateTime(now.year, now.month - 3, now.day);
    final total = await computeSpentForPeriod(
      categoryId: categoryId,
      start: threeMonthsAgo,
      end: now,
    );
    if (total == 0) return 0;
    return (total / 3).round();
  }
}
