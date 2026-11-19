import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanjo/core/database/app_database.dart';
import 'package:lanjo/core/database/ledger_engine.dart';
import 'package:lanjo/core/errors/arus_exception.dart';
import 'package:lanjo/features/reports/domain/report_service.dart';

void main() {
  late AppDatabase db;
  late LedgerEngine ledger;
  late ReportService reports;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    ledger = LedgerEngine(db);
    reports = ReportService(db);
    // Ensure database & seedDefaults run
    await db.select(db.categories).get();
  });

  tearDown(() async {
    await db.close();
  });

  test('opening balance is not counted as income and ledger stays balanced', () async {
    final bcaId = await ledger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 1000000,
    );

    expect(await ledger.computeAccountBalance(bcaId), 1000000);

    final summary = await reports.generateSummary(
      start: DateTime(2020),
      end: DateTime(2030),
    );
    expect(summary.totalIncome, 0);
    expect(summary.totalConsumptionExpense, 0);

    final check = await ledger.verifyLedgerIntegrity();
    expect(check.isBalanced, isTrue);
  });

  test('income, expense, edit, refund, and void preserve exact wallet balance', () async {
    final walletId = await ledger.createWallet(
      name: 'Tunai',
      accountType: 'cash',
      icon: 'wallet',
      colorValue: 0xFF0F766E,
      openingBalance: 0,
    );

    await ledger.recordIncome(
      walletId: walletId,
      categoryId: DefaultCategoryIds.salary,
      amount: 5000000,
      occurredAt: DateTime(2026, 11, 1),
      description: 'Gaji',
    );
    expect(await ledger.computeAccountBalance(walletId), 5000000);

    final expId = await ledger.recordExpense(
      walletId: walletId,
      amount: 25000,
      splits: const [
        CategorySplitInput(
          categoryId: DefaultCategoryIds.food,
          amount: 25000,
        ),
      ],
      occurredAt: DateTime(2026, 11, 2),
      description: 'Ayam geprek',
    );
    expect(await ledger.computeAccountBalance(walletId), 4975000);

    // Edit 25.000 -> 30.000 produces 5.000 difference (FR-03)
    await ledger.updateSimpleTransaction(
      transactionId: expId,
      amount: 30000,
      walletId: walletId,
      categoryId: DefaultCategoryIds.food,
      occurredAt: DateTime(2026, 11, 2),
      description: 'Ayam geprek + es teh',
    );
    expect(await ledger.computeAccountBalance(walletId), 4970000);

    // Refund reduces spending & restores wallet balance
    await ledger.recordRefund(
      walletId: walletId,
      categoryId: DefaultCategoryIds.food,
      amount: 10000,
      occurredAt: DateTime(2026, 11, 3),
    );
    expect(await ledger.computeAccountBalance(walletId), 4980000);

    // Voiding original expense restores the 30.000
    await ledger.voidTransaction(expId);
    expect(await ledger.computeAccountBalance(walletId), 5010000);

    final check = await ledger.verifyLedgerIntegrity();
    expect(check.isBalanced, isTrue);
  });

  test('transfer with admin fee updates both wallets and only fee counts as expense (FR-04)', () async {
    final bca = await ledger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 500000,
    );
    final gopay = await ledger.createWallet(
      name: 'GoPay',
      accountType: 'ewallet',
      icon: 'ewallet',
      colorValue: 0xFF0284C7,
      openingBalance: 0,
    );

    await ledger.recordTransfer(
      sourceWalletId: bca,
      destinationWalletId: gopay,
      amount: 100000,
      adminFee: 1000,
      occurredAt: DateTime(2026, 11, 5),
    );

    expect(await ledger.computeAccountBalance(bca), 399000);
    expect(await ledger.computeAccountBalance(gopay), 100000);

    final summary = await reports.generateSummary(
      start: DateTime(2026, 11, 1),
      end: DateTime(2026, 11, 30),
    );
    expect(summary.totalConsumptionExpense, 1000);
    expect((await ledger.verifyLedgerIntegrity()).isBalanced, isTrue);
  });

  test('credit card payment reduces liability without double counting expense', () async {
    final bca = await ledger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 2000000,
    );
    final cc = await ledger.createWallet(
      name: 'Kartu Kredit',
      accountType: 'credit_card',
      icon: 'credit_card',
      colorValue: 0xFFDC2626,
      openingBalance: 500000,
    );

    await ledger.recordTransfer(
      sourceWalletId: bca,
      destinationWalletId: cc,
      amount: 500000,
      occurredAt: DateTime(2026, 11, 10),
    );

    expect(await ledger.computeAccountBalance(bca), 1500000);
    expect(await ledger.computeAccountBalance(cc), 0);

    final summary = await reports.generateSummary(
      start: DateTime(2026, 11, 1),
      end: DateTime(2026, 11, 30),
    );
    expect(summary.totalConsumptionExpense, 0);
  });

  test('negative asset balance throws warning unless confirmed', () async {
    final cash = await ledger.createWallet(
      name: 'Dompet',
      accountType: 'cash',
      icon: 'wallet',
      colorValue: 0xFF0F766E,
      openingBalance: 10000,
    );

    expect(
      () => ledger.recordExpense(
        walletId: cash,
        amount: 25000,
        splits: const [
          CategorySplitInput(categoryId: DefaultCategoryIds.food, amount: 25000),
        ],
        occurredAt: DateTime.now(),
      ),
      throwsA(isA<NegativeAssetBalanceException>()),
    );

    await ledger.recordExpense(
      walletId: cash,
      amount: 25000,
      splits: const [
        CategorySplitInput(categoryId: DefaultCategoryIds.food, amount: 25000),
      ],
      occurredAt: DateTime.now(),
      allowNegativeBalance: true,
    );
    expect(await ledger.computeAccountBalance(cash), -15000);
  });

  test('receivable and debt principal never inflate consumption or income (FR-13)', () async {
    final bca = await ledger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 1000000,
    );

    final receivableId = await ledger.recordDebt(
      counterparty: 'Andi',
      kind: 'receivable',
      principalAmount: 200000,
      walletId: bca,
      occurredAt: DateTime(2026, 11, 5),
    );
    expect(await ledger.computeAccountBalance(bca), 800000);

    await ledger.recordDebtRepayment(
      debtId: receivableId,
      walletId: bca,
      principalPaid: 200000,
      paidAt: DateTime(2026, 11, 6),
    );
    expect(await ledger.computeAccountBalance(bca), 1000000);

    final summary = await reports.generateSummary(
      start: DateTime(2026, 11, 1),
      end: DateTime(2026, 11, 30),
    );
    expect(summary.totalConsumptionExpense, 0);
    expect(summary.totalIncome, 0);
    expect((await ledger.verifyLedgerIntegrity()).isBalanced, isTrue);
  });

  test('old debt skips current wallet balance, supports installment repayment, edit, void repayment, and delete cleanly', () async {
    final bank = await ledger.createWallet(
      name: 'BRI',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 2000000,
    );

    // 1. Old debt (affectsWallet: false) must NOT add cash to wallet!
    final oldDebtId = await ledger.recordDebt(
      counterparty: 'Toko Motor',
      kind: 'debt',
      principalAmount: 1200000,
      affectsWallet: false,
      occurredAt: DateTime(2026, 10, 1),
      dueDate: DateTime(2027, 2, 1),
      note: 'Cicilan lama sebelum pakai Lanjo',
    );
    expect(await ledger.computeAccountBalance(bank), 2000000);
    expect((await ledger.verifyLedgerIntegrity()).isBalanced, isTrue);

    // 2. Partial installment payment reduces wallet & remainingAmount
    final payTxId = await ledger.recordDebtRepayment(
      debtId: oldDebtId,
      walletId: bank,
      principalPaid: 400000,
      paidAt: DateTime(2026, 11, 17),
    );
    expect(await ledger.computeAccountBalance(bank), 1600000);
    var debtRow = await (db.select(db.debts)..where((d) => d.id.equals(oldDebtId)))
        .getSingle();
    expect(debtRow.remainingAmount, 800000);
    expect(debtRow.status, 'partial');

    // 3. Edit debt principal higher preserves paid installment & updates remaining
    await ledger.updateDebt(
      debtId: oldDebtId,
      counterparty: 'Dealer Motor',
      principalAmount: 1500000,
      affectsWallet: false,
      note: 'Penyesuaian total pokok',
    );
    debtRow = await (db.select(db.debts)..where((d) => d.id.equals(oldDebtId)))
        .getSingle();
    expect(debtRow.counterparty, 'Dealer Motor');
    expect(debtRow.remainingAmount, 1100000);
    expect(await ledger.computeAccountBalance(bank), 1600000);
    expect((await ledger.verifyLedgerIntegrity()).isBalanced, isTrue);

    // 4. Voiding installment restores wallet balance and debt remaining
    await ledger.voidTransaction(payTxId, reason: 'Salah input cicilan');
    expect(await ledger.computeAccountBalance(bank), 2000000);
    debtRow = await (db.select(db.debts)..where((d) => d.id.equals(oldDebtId)))
        .getSingle();
    expect(debtRow.remainingAmount, 1500000);
    expect(debtRow.status, 'open');

    // 5. Deleting debt reverses everything cleanly
    await ledger.recordDebtRepayment(
      debtId: oldDebtId,
      walletId: bank,
      principalPaid: 300000,
    );
    expect(await ledger.computeAccountBalance(bank), 1700000);
    await ledger.deleteDebt(oldDebtId);
    expect(await ledger.computeAccountBalance(bank), 2000000);
    debtRow = await (db.select(db.debts)..where((d) => d.id.equals(oldDebtId)))
        .getSingle();
    expect(debtRow.status, 'cancelled');
    expect((await ledger.verifyLedgerIntegrity()).isBalanced, isTrue);
  });

  test('ReportService computes daily totals, active day average, and range daily average', () async {
    final wallet = await ledger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 1000000,
    );

    await ledger.recordExpense(
      walletId: wallet,
      amount: 100000,
      splits: const [
        CategorySplitInput(categoryId: DefaultCategoryIds.food, amount: 100000),
      ],
      occurredAt: DateTime(2026, 11, 13, 12),
    );
    await ledger.recordExpense(
      walletId: wallet,
      amount: 50000,
      splits: const [
        CategorySplitInput(categoryId: DefaultCategoryIds.food, amount: 50000),
      ],
      occurredAt: DateTime(2026, 11, 15, 12),
    );

    final report = await reports.generateSummary(
      start: DateTime(2026, 11, 13),
      end: DateTime(2026, 11, 15, 23, 59),
    );
    expect(report.totalConsumptionExpense, 150000);
    expect(report.activeExpenseDaysCount, 2);
    expect(report.averageActiveDayExpense, 75000);
    expect(report.elapsedDaysInRange, 3);
    expect(report.averageDailyExpense, 50000);
    expect(report.highestExpenseDay?.amount, 100000);
    expect(report.sortedDailyDescending.first.expense, 50000);
  });
}
