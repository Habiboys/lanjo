import 'package:drift/drift.dart';

import 'db_connection.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// System account IDs used by the internal double-entry ledger (PRD 13.3).
abstract final class SystemAccountIds {
  static const String incomeDefault = 'sys_inc_default';
  static const String expenseDefault = 'sys_exp_default';
  static const String equityOpening = 'sys_eq_opening';
  static const String equityAdjustment = 'sys_eq_adjustment';
  static const String receivable = 'sys_asset_receivable';
  static const String debt = 'sys_liability_debt';
}

/// Default category IDs seeded on first launch (FR-05).
abstract final class DefaultCategoryIds {
  static const String food = 'cat_exp_food';
  static const String transport = 'cat_exp_transport';
  static const String housing = 'cat_exp_housing';
  static const String shopping = 'cat_exp_shopping';
  static const String health = 'cat_exp_health';
  static const String education = 'cat_exp_education';
  static const String entertainment = 'cat_exp_entertainment';
  static const String telecom = 'cat_exp_telecom';
  static const String bills = 'cat_exp_bills';
  static const String family = 'cat_exp_family';
  static const String adminFee = 'cat_exp_admin';
  static const String expenseOther = 'cat_exp_other';

  static const String salary = 'cat_inc_salary';
  static const String freelance = 'cat_inc_freelance';
  static const String bonus = 'cat_inc_bonus';
  static const String business = 'cat_inc_business';
  static const String gift = 'cat_inc_gift';
  static const String incomeOther = 'cat_inc_other';
}

@DriftDatabase(
  tables: [
    AppSettings,
    Accounts,
    Categories,
    Transactions,
    LedgerEntries,
    TransactionSplits,
    Tags,
    TransactionTags,
    Attachments,
    TransactionTemplates,
    Budgets,
    Bills,
    BillOccurrences,
    BillPayments,
    Goals,
    FundAllocations,
    GoalContributions,
    Debts,
    DebtPayments,
    SplitBills,
    SplitBillMembers,
    Wishlists,
    SalaryPlans,
    SalaryPlanItems,
    Notifications,
    AiConversations,
    AiMessages,
    ImportBatches,
    AuditLogs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  static Future<dynamic> getDatabaseFile() => getDatabaseFileImpl();

  static Future<String> getAttachmentsDirectoryPath() =>
      getAttachmentsDirectoryPathImpl();

  static QueryExecutor _openConnection() => openDefaultConnectionImpl();

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await seedDefaults();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.addColumn(appSettings, appSettings.monthlySalary);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
        },
      );

  /// Seeds default local settings, internal ledger system accounts, and
  /// Indonesian default categories idempotently.
  Future<void> seedDefaults() async {
    final now = DateTime.now();

    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        id: 'default',
        updatedAt: now,
      ),
    );

    final systemAccounts = <AccountsCompanion>[
      AccountsCompanion.insert(
        id: SystemAccountIds.incomeDefault,
        name: 'Sistem Pemasukan',
        accountType: 'system_income',
        accountClass: 'income',
        isVisible: const Value(false),
        includeInTotal: const Value(false),
        includeInSpendable: const Value(false),
        isSystem: const Value(true),
        createdAt: now,
        updatedAt: now,
      ),
      AccountsCompanion.insert(
        id: SystemAccountIds.expenseDefault,
        name: 'Sistem Pengeluaran',
        accountType: 'system_expense',
        accountClass: 'expense',
        isVisible: const Value(false),
        includeInTotal: const Value(false),
        includeInSpendable: const Value(false),
        isSystem: const Value(true),
        createdAt: now,
        updatedAt: now,
      ),
      AccountsCompanion.insert(
        id: SystemAccountIds.equityOpening,
        name: 'Ekuitas Saldo Awal',
        accountType: 'system_equity',
        accountClass: 'equity',
        isVisible: const Value(false),
        includeInTotal: const Value(false),
        includeInSpendable: const Value(false),
        isSystem: const Value(true),
        createdAt: now,
        updatedAt: now,
      ),
      AccountsCompanion.insert(
        id: SystemAccountIds.equityAdjustment,
        name: 'Ekuitas Penyesuaian Saldo',
        accountType: 'system_equity',
        accountClass: 'equity',
        isVisible: const Value(false),
        includeInTotal: const Value(false),
        includeInSpendable: const Value(false),
        isSystem: const Value(true),
        createdAt: now,
        updatedAt: now,
      ),
      AccountsCompanion.insert(
        id: SystemAccountIds.receivable,
        name: 'Aset Piutang',
        accountType: 'system_receivable',
        accountClass: 'asset',
        isVisible: const Value(false),
        includeInTotal: const Value(false),
        includeInSpendable: const Value(false),
        isSystem: const Value(true),
        createdAt: now,
        updatedAt: now,
      ),
      AccountsCompanion.insert(
        id: SystemAccountIds.debt,
        name: 'Kewajiban Utang',
        accountType: 'system_debt',
        accountClass: 'liability',
        isVisible: const Value(false),
        includeInTotal: const Value(false),
        includeInSpendable: const Value(false),
        isSystem: const Value(true),
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final expenseSpecs = <({
      String id,
      String name,
      String icon,
      int color,
      bool fav,
    })>[
      (
        id: DefaultCategoryIds.food,
        name: 'Makanan & Minuman',
        icon: 'restaurant',
        color: 0xFFEA580C,
        fav: true,
      ),
      (
        id: DefaultCategoryIds.transport,
        name: 'Transportasi',
        icon: 'directions_car',
        color: 0xFF0284C7,
        fav: true,
      ),
      (
        id: DefaultCategoryIds.housing,
        name: 'Tempat Tinggal',
        icon: 'home',
        color: 0xFF7C3AED,
        fav: false,
      ),
      (
        id: DefaultCategoryIds.shopping,
        name: 'Belanja',
        icon: 'shopping_bag',
        color: 0xFFDB2777,
        fav: true,
      ),
      (
        id: DefaultCategoryIds.health,
        name: 'Kesehatan',
        icon: 'medical_services',
        color: 0xFFDC2626,
        fav: false,
      ),
      (
        id: DefaultCategoryIds.education,
        name: 'Pendidikan',
        icon: 'school',
        color: 0xFF2563EB,
        fav: false,
      ),
      (
        id: DefaultCategoryIds.entertainment,
        name: 'Hiburan',
        icon: 'movie',
        color: 0xFF9333EA,
        fav: true,
      ),
      (
        id: DefaultCategoryIds.telecom,
        name: 'Internet & Komunikasi',
        icon: 'wifi',
        color: 0xFF0891B2,
        fav: false,
      ),
      (
        id: DefaultCategoryIds.bills,
        name: 'Tagihan',
        icon: 'receipt_long',
        color: 0xFFD97706,
        fav: true,
      ),
      (
        id: DefaultCategoryIds.family,
        name: 'Keluarga',
        icon: 'family_restroom',
        color: 0xFFE11D48,
        fav: false,
      ),
      (
        id: DefaultCategoryIds.adminFee,
        name: 'Biaya Administrasi',
        icon: 'account_balance',
        color: 0xFF475569,
        fav: false,
      ),
      (
        id: DefaultCategoryIds.expenseOther,
        name: 'Lainnya',
        icon: 'more_horiz',
        color: 0xFF64748B,
        fav: false,
      ),
    ];

    final incomeSpecs = <({
      String id,
      String name,
      String icon,
      int color,
      bool fav,
    })>[
      (
        id: DefaultCategoryIds.salary,
        name: 'Gaji',
        icon: 'payments',
        color: 0xFF059669,
        fav: true,
      ),
      (
        id: DefaultCategoryIds.freelance,
        name: 'Freelance',
        icon: 'laptop_mac',
        color: 0xFF0D9488,
        fav: true,
      ),
      (
        id: DefaultCategoryIds.bonus,
        name: 'Bonus',
        icon: 'card_giftcard',
        color: 0xFF16A34A,
        fav: false,
      ),
      (
        id: DefaultCategoryIds.business,
        name: 'Usaha',
        icon: 'storefront',
        color: 0xFF15803D,
        fav: false,
      ),
      (
        id: DefaultCategoryIds.gift,
        name: 'Hadiah',
        icon: 'redeem',
        color: 0xFF65A30D,
        fav: false,
      ),
      (
        id: DefaultCategoryIds.incomeOther,
        name: 'Lainnya',
        icon: 'more_horiz',
        color: 0xFF4D7C0F,
        fav: false,
      ),
    ];

    await batch((b) {
      for (final acc in systemAccounts) {
        b.insert(accounts, acc, mode: InsertMode.insertOrIgnore);
      }

      for (var i = 0; i < expenseSpecs.length; i++) {
        final spec = expenseSpecs[i];
        final ledgerAccId = 'sys_ledger_${spec.id}';
        b.insert(
          accounts,
          AccountsCompanion.insert(
            id: ledgerAccId,
            name: 'Beban ${spec.name}',
            accountType: 'system_expense',
            accountClass: 'expense',
            isVisible: const Value(false),
            includeInTotal: const Value(false),
            includeInSpendable: const Value(false),
            isSystem: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
        b.insert(
          categories,
          CategoriesCompanion.insert(
            id: spec.id,
            name: spec.name,
            kind: 'expense',
            ledgerAccountId: Value(ledgerAccId),
            icon: Value(spec.icon),
            colorValue: Value(spec.color),
            isFavorite: Value(spec.fav),
            isSystem: const Value(true),
            sortOrder: Value(i),
            createdAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }

      for (var i = 0; i < incomeSpecs.length; i++) {
        final spec = incomeSpecs[i];
        final ledgerAccId = 'sys_ledger_${spec.id}';
        b.insert(
          accounts,
          AccountsCompanion.insert(
            id: ledgerAccId,
            name: 'Pendapatan ${spec.name}',
            accountType: 'system_income',
            accountClass: 'income',
            isVisible: const Value(false),
            includeInTotal: const Value(false),
            includeInSpendable: const Value(false),
            isSystem: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
        b.insert(
          categories,
          CategoriesCompanion.insert(
            id: spec.id,
            name: spec.name,
            kind: 'income',
            ledgerAccountId: Value(ledgerAccId),
            icon: Value(spec.icon),
            colorValue: Value(spec.color),
            isFavorite: Value(spec.fav),
            isSystem: const Value(true),
            sortOrder: Value(i),
            createdAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }
}
