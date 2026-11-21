import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanjo/core/database/app_database.dart';
import 'package:lanjo/core/database/ledger_engine.dart';
import 'package:lanjo/core/notifications/local_notification_service.dart';
import 'package:lanjo/features/bills/domain/bill_service.dart';
import 'package:lanjo/features/budgets/domain/budget_service.dart';
import 'package:lanjo/features/goals/domain/goal_service.dart';
import 'package:lanjo/features/reports/domain/report_service.dart';
import 'package:lanjo/features/safe_to_spend/domain/safe_to_spend_service.dart';
import 'package:lanjo/features/split_bill/domain/split_bill_service.dart';

void main() {
  late AppDatabase db;
  late LedgerEngine ledger;
  late LocalNotificationService notif;
  late SafeToSpendService safeToSpend;
  late BillService bills;
  late GoalService goals;
  late SplitBillService splitBills;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    ledger = LedgerEngine(db);
    notif = LocalNotificationService(db);
    safeToSpend = SafeToSpendService(db);
    bills = BillService(db, ledger, notif);
    goals = GoalService(db, ledger);
    splitBills = SplitBillService(db, ledger);
    await db.select(db.categories).get();
  });

  tearDown(() async {
    await db.close();
  });

  test('Safe-to-Spend matches PRD FR-09 example calculation', () async {
    // Payday = 1st of Dec, now = Nov 16 -> 15 remaining days
    await (db.update(db.appSettings)..where((s) => s.id.equals('default')))
        .write(
      AppSettingsCompanion(
        paydayDay: const Value(1),
        safeToSpendEssentials: const Value(750000),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final wallet = await ledger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 3000000,
    );

    // Upcoming bill 1.000.000 due Nov 20
    await bills.createBill(
      name: 'Kos',
      kind: 'expense',
      estimatedAmount: 1000000,
      categoryId: DefaultCategoryIds.housing,
      walletId: wallet,
      frequency: 'monthly',
      firstDueDate: DateTime(2026, 11, 20),
    );

    // Goal needing 500.000 within 1 month
    final goalId = await goals.createGoal(
      name: 'Dana Darurat',
      targetAmount: 500000,
      targetDate: DateTime(2026, 11, 30),
      sourceWalletId: wallet,
    );
    expect(goalId, isNotEmpty);

    final result = await safeToSpend.calculate(now: DateTime(2026, 11, 16));
    expect(result.spendableLiquidBalance, 3000000);
    expect(result.unpaidBillsCommitment, 1000000);
    expect(result.pendingGoalSavings, 500000);
    expect(result.estimatedRemainingEssentials, 750000);
    expect(result.freeFunds, 750000);
    expect(result.remainingDays, 15);
    expect(result.dailySafeSpend, 50000);
  });

  test('Savings wallet excluded from spendable is not double counted in Safe-to-Spend', () async {
    final mainWallet = await ledger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 2000000,
    );
    final savingsWallet = await ledger.createWallet(
      name: 'Tabungan',
      accountType: 'savings',
      icon: 'savings',
      colorValue: 0xFF16A34A,
      openingBalance: 0,
      includeInSpendable: false,
    );

    await goals.createGoal(
      name: 'Laptop',
      targetAmount: 5000000,
      targetDate: DateTime(2027, 1, 1),
      sourceWalletId: savingsWallet,
    );

    await ledger.recordTransfer(
      sourceWalletId: mainWallet,
      destinationWalletId: savingsWallet,
      amount: 500000,
      occurredAt: DateTime(2026, 11, 16),
    );

    final sts = await safeToSpend.calculate(now: DateTime(2026, 11, 16));
    expect(sts.spendableLiquidBalance, 1500000);
    expect(sts.totalLiquidAssets, 2000000);
    expect(sts.pendingGoalSavings, 0);
    expect(sts.freeFunds, 1500000);
  });

  test('Split Bill records personal share as expense, friends as receivables, and cancels cleanly', () async {
    final bca = await ledger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 500000,
    );

    final splitId = await splitBills.createSplitBill(
      title: 'Makan Berempat',
      totalAmount: 240000,
      payerWalletId: bca,
      categoryId: DefaultCategoryIds.food,
      splitMode: 'equal',
      occurredAt: DateTime(2026, 11, 16),
      participants: const [
        SplitParticipantInput(name: 'Saya', isSelf: true, shareAmount: 60000),
        SplitParticipantInput(name: 'Andi', isSelf: false, shareAmount: 60000),
        SplitParticipantInput(name: 'Budi', isSelf: false, shareAmount: 60000),
        SplitParticipantInput(name: 'Citra', isSelf: false, shareAmount: 60000),
      ],
    );

    // Total outflow from BCA = 60.000 (self) + 180.000 (3 receivables) = 240.000
    expect(await ledger.computeAccountBalance(bca), 260000);

    // Cancel split bill restores full 500.000 balance cleanly
    await splitBills.cancelSplitBill(splitId);
    expect(await ledger.computeAccountBalance(bca), 500000);
    expect((await ledger.verifyLedgerIntegrity()).isBalanced, isTrue);
  });

  test('Income salary schedule stays separated from expense bills and credits wallet when received', () async {
    final bank = await ledger.createWallet(
      name: 'Mandiri',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 1000000,
    );

    await bills.createBill(
      name: 'Gaji Bulanan',
      kind: 'income',
      estimatedAmount: 5000000,
      categoryId: DefaultCategoryIds.salary,
      walletId: bank,
      frequency: 'monthly',
      firstDueDate: DateTime(2026, 11, 25),
    );
    await bills.createBill(
      name: 'Internet',
      kind: 'expense',
      estimatedAmount: 300000,
      categoryId: DefaultCategoryIds.telecom,
      walletId: bank,
      frequency: 'monthly',
      firstDueDate: DateTime(2026, 11, 20),
    );

    final expenseBills = await bills.getUpcomingAndActiveOccurrences(kind: 'expense');
    final incomeSchedules = await bills.getUpcomingAndActiveOccurrences(kind: 'income');

    expect(expenseBills.map((e) => e.bill.name).toList(), ['Internet']);
    expect(incomeSchedules.map((e) => e.bill.name).toList(), ['Gaji Bulanan']);

    await bills.confirmPayment(
      occurrenceId: incomeSchedules.first.occurrence.id,
      actualAmount: 5000000,
    );
    expect(await ledger.computeAccountBalance(bank), 6000000);
  });

  test('Budgets, Goals, and unused Wallets support edit and delete cleanly', () async {
    final budgets = BudgetService(db, notif);
    final budgetId = await budgets.createBudget(
      name: 'Jajan',
      categoryId: DefaultCategoryIds.food,
      limitAmount: 500000,
      periodType: 'monthly',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 30),
    );
    await budgets.updateBudget(
      budgetId: budgetId,
      name: 'Makan & Minum',
      categoryId: DefaultCategoryIds.food,
      limitAmount: 900000,
      periodType: 'monthly',
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 30),
      rolloverEnabled: true,
    );
    var activeBudgets = await budgets.getActiveBudgetProgresses(
      now: DateTime(2026, 11, 17),
    );
    expect(activeBudgets.single.budget.name, 'Makan & Minum');
    expect(activeBudgets.single.effectiveLimit, 900000);

    await budgets.deleteBudget(budgetId);
    activeBudgets = await budgets.getActiveBudgetProgresses(
      now: DateTime(2026, 11, 17),
    );
    expect(activeBudgets, isEmpty);

    // Goal edit + delete releases virtual allocation cleanly
    final bank = await ledger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 1000000,
    );
    final goalId = await goals.createGoal(
      name: 'Laptop',
      targetAmount: 3000000,
    );
    await goals.contribute(
      goalId: goalId,
      amount: 400000,
      fromWalletId: bank,
      isVirtual: true,
    );
    expect((await safeToSpend.calculate()).pendingGoalSavings, 400000);
    await goals.updateGoal(
      goalId: goalId,
      name: 'Laptop Kerja',
      targetAmount: 4000000,
    );
    await goals.deleteGoal(goalId);
    expect((await safeToSpend.calculate()).pendingGoalSavings, 0);

    // Unused wallet deletes cleanly while keeping ledger balanced
    expect(await ledger.deleteWalletIfUnused(bank), isTrue);
    expect((await ledger.verifyLedgerIntegrity()).isBalanced, isTrue);
  });

  test('Scheduled bill payment via BillService is excluded from discretionary heatmap spend while preserved in totals', () async {
    final bank = await ledger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 5000000,
    );

    final day1 = DateTime(2026, 11, 10, 10);
    final day2 = DateTime(2026, 11, 11, 10);

    await bills.createBill(
      name: 'Listrik & Air',
      kind: 'expense',
      estimatedAmount: 800000,
      categoryId: DefaultCategoryIds.bills,
      walletId: bank,
      frequency: 'monthly',
      firstDueDate: day1,
    );
    await bills.createBill(
      name: 'Sewa Kost',
      kind: 'expense',
      estimatedAmount: 1200000,
      categoryId: DefaultCategoryIds.bills,
      walletId: bank,
      frequency: 'monthly',
      firstDueDate: day2,
    );

    final occs = await bills.getUpcomingAndActiveOccurrences(kind: 'expense');
    final billOcc1 = occs.firstWhere((e) => e.bill.name == 'Listrik & Air');
    final billOcc2 = occs.firstWhere((e) => e.bill.name == 'Sewa Kost');

    await bills.confirmPayment(
      occurrenceId: billOcc1.occurrence.id,
      actualAmount: 800000,
      paidAt: day1,
    );
    await bills.confirmPayment(
      occurrenceId: billOcc2.occurrence.id,
      actualAmount: 1200000,
      paidAt: day2,
    );

    await ledger.recordExpense(
      walletId: bank,
      amount: 45000,
      splits: const [
        CategorySplitInput(
          categoryId: DefaultCategoryIds.food,
          amount: 45000,
        ),
      ],
      occurredAt: day2,
      description: 'Makan Siang',
    );

    final report = await ReportService(db).generateSummary(
      start: DateTime(2026, 11, 1),
      end: DateTime(2026, 11, 30, 23, 59),
    );

    expect(report.totalConsumptionExpense, 2045000);
    expect(report.totalBillExpense, 2000000);
    expect(report.totalDiscretionaryExpense, 45000);
    expect(report.billExpenseOn(day1), 800000);
    expect(report.discretionaryExpenseOn(day1), 0);
    expect(report.billExpenseOn(day2), 1200000);
    expect(report.discretionaryExpenseOn(day2), 45000);

    final allTxs = await db.select(db.transactions).get();
    expect(ReportService.discretionaryExpenseForDay(allTxs, day1), 0);
    expect(ReportService.discretionaryExpenseForDay(allTxs, day2), 45000);
  });
}
