import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/date_utils.dart';

class SafeToSpendBreakdown {
  const SafeToSpendBreakdown({
    required this.spendableLiquidBalance,
    required this.totalLiquidAssets,
    required this.netWorth,
    required this.unpaidBillsCommitment,
    required this.pendingGoalSavings,
    required this.extraReserve,
    required this.estimatedRemainingEssentials,
    required this.freeFunds,
    required this.dailySafeSpend,
    required this.remainingDays,
    required this.periodStart,
    required this.periodEndExclusive,
    required this.upcomingBillsCount,
  });

  final int spendableLiquidBalance;
  final int totalLiquidAssets;
  final int netWorth;
  final int unpaidBillsCommitment;
  final int pendingGoalSavings;
  final int extraReserve;
  final int estimatedRemainingEssentials;
  final int freeFunds;
  final int dailySafeSpend;
  final int remainingDays;
  final DateTime periodStart;
  final DateTime periodEndExclusive;
  final int upcomingBillsCount;

  bool get isShortfall => freeFunds < 0;
  int get shortfallAmount => freeFunds < 0 ? freeFunds.abs() : 0;
}

class PurchaseSimulationResult {
  const PurchaseSimulationResult({
    required this.itemPrice,
    required this.before,
    required this.freeFundsAfter,
    required this.dailySafeSpendAfter,
    required this.causesShortfall,
    required this.impactDaysOfDailyBudget,
  });

  final int itemPrice;
  final SafeToSpendBreakdown before;
  final int freeFundsAfter;
  final int dailySafeSpendAfter;
  final bool causesShortfall;
  final int impactDaysOfDailyBudget;
}

/// Deterministic Safe-to-Spend & Purchase Simulator service (FR-09, FR-15).
class SafeToSpendService {
  SafeToSpendService(this.db);

  final AppDatabase db;

  Future<SafeToSpendBreakdown> calculate({DateTime? now}) async {
    final ref = now ?? DateTime.now();
    final settings = await (db.select(db.appSettings)
          ..where((s) => s.id.equals('default')))
        .getSingleOrNull();

    final period = ArusDateUtils.currentFinancialPeriod(
      now: ref,
      paydayDay: settings?.paydayDay,
    );

    final accounts = await (db.select(db.accounts)
          ..where((a) => a.isSystem.equals(false)))
        .get();

    var spendableLiquidBalance = 0;
    var totalLiquidAssets = 0;
    var totalAssetsForNetWorth = 0;
    var totalLiabilitiesForNetWorth = 0;

    for (final acc in accounts) {
      if (acc.accountClass == 'asset') {
        // Archived non-zero wallets still count toward net worth (FR-02).
        if (acc.includeInTotal || (acc.isArchived && acc.cachedBalance != 0)) {
          totalAssetsForNetWorth += acc.cachedBalance;
        }
        if (!acc.isArchived && acc.includeInTotal) {
          totalLiquidAssets += acc.cachedBalance;
        }
        if (!acc.isArchived && acc.includeInSpendable) {
          spendableLiquidBalance += acc.cachedBalance;
        }
      } else if (acc.accountClass == 'liability') {
        if (acc.includeInTotal || (acc.isArchived && acc.cachedBalance != 0)) {
          totalLiabilitiesForNetWorth += acc.cachedBalance;
        }
      }
    }

    // Include open receivables & debts in net worth (FR-21).
    final openDebts = await (db.select(db.debts)
          ..where((d) => d.status.isIn(['open', 'partial'])))
        .get();
    for (final d in openDebts) {
      if (d.kind == 'receivable') {
        totalAssetsForNetWorth += d.remainingAmount;
      } else {
        totalLiabilitiesForNetWorth += d.remainingAmount;
      }
    }

    final netWorth = totalAssetsForNetWorth - totalLiabilitiesForNetWorth;

    // Unpaid expense bills due before next income/period end.
    final occurrences = await (db.select(db.billOccurrences)
          ..where((o) =>
              o.status.isIn(['upcoming', 'unpaid', 'overdue']) &
              o.dueDate.isSmallerThanValue(period.endExclusive)))
        .get();

    final bills = await (db.select(db.bills)
          ..where((b) => b.isActive.equals(true) & b.kind.equals('expense')))
        .get();
    final activeExpenseBillIds = bills.map((b) => b.id).toSet();

    var unpaidBillsCommitment = 0;
    var upcomingBillsCount = 0;
    for (final occ in occurrences) {
      if (!activeExpenseBillIds.contains(occ.billId)) continue;
      final remaining = math.max(0, occ.expectedAmount - occ.paidAmount);
      if (remaining > 0) {
        unpaidBillsCommitment += remaining;
        upcomingBillsCount++;
      }
    }

    // Virtual fund allocations already locked in spendable wallets + active goal monthly targets
    final activeGoals = await (db.select(db.goals)
          ..where((g) => g.status.equals('active')))
        .get();
    final spendableWalletIds = accounts
        .where((a) => !a.isArchived && a.includeInSpendable)
        .map((a) => a.id)
        .toSet();

    final allocations = await db.select(db.fundAllocations).get();
    final virtualAllocatedInSpendable = allocations
        .where((a) => spendableWalletIds.contains(a.walletId))
        .fold<int>(0, (sum, a) => sum + a.amount);

    // For goals linked to a dedicated savings wallet (not spendable), do not double-subtract!
    var pendingGoalMonthly = 0;
    for (final goal in activeGoals) {
      final isDedicatedSavings = goal.sourceWalletId != null &&
          !spendableWalletIds.contains(goal.sourceWalletId);
      if (isDedicatedSavings) continue;

      final remainingGoal = math.max(0, goal.targetAmount - goal.currentAmount);
      if (remainingGoal == 0) continue;
      if (goal.targetDate != null) {
        final monthsLeft = math.max(
          1,
          ((goal.targetDate!.difference(ref).inDays) / 30).ceil(),
        );
        pendingGoalMonthly += (remainingGoal / monthsLeft).ceil();
      }
    }

    final pendingGoalSavings =
        math.max(virtualAllocatedInSpendable, pendingGoalMonthly);

    final extraReserve = settings?.safeToSpendReserve ?? 0;
    final estimatedEssentials = settings?.safeToSpendEssentials ?? 0;

    final freeFunds = spendableLiquidBalance -
        unpaidBillsCommitment -
        pendingGoalSavings -
        extraReserve -
        estimatedEssentials;

    final dailySafeSpend =
        freeFunds > 0 ? freeFunds ~/ period.remainingDays : 0;

    return SafeToSpendBreakdown(
      spendableLiquidBalance: spendableLiquidBalance,
      totalLiquidAssets: totalLiquidAssets,
      netWorth: netWorth,
      unpaidBillsCommitment: unpaidBillsCommitment,
      pendingGoalSavings: pendingGoalSavings,
      extraReserve: extraReserve,
      estimatedRemainingEssentials: estimatedEssentials,
      freeFunds: freeFunds,
      dailySafeSpend: dailySafeSpend,
      remainingDays: period.remainingDays,
      periodStart: period.start,
      periodEndExclusive: period.endExclusive,
      upcomingBillsCount: upcomingBillsCount,
    );
  }

  Future<PurchaseSimulationResult> simulatePurchase(int price) async {
    final before = await calculate();
    final freeAfter = before.freeFunds - price;
    final dailyAfter = freeAfter > 0 ? freeAfter ~/ before.remainingDays : 0;
    final impactDays = before.dailySafeSpend > 0
        ? (price / before.dailySafeSpend).ceil()
        : 0;
    return PurchaseSimulationResult(
      itemPrice: price,
      before: before,
      freeFundsAfter: freeAfter,
      dailySafeSpendAfter: dailyAfter,
      causesShortfall: freeAfter < 0,
      impactDaysOfDailyBudget: impactDays,
    );
  }

  Future<void> updateAssumptions({
    required int reserve,
    required int essentials,
  }) async {
    await (db.update(db.appSettings)..where((s) => s.id.equals('default')))
        .write(
      AppSettingsCompanion(
        safeToSpendReserve: Value(math.max(0, reserve)),
        safeToSpendEssentials: Value(math.max(0, essentials)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
