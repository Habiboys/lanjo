import 'package:drift/drift.dart';

/// 1. app_settings: Local user profile & app preferences (FR-01, FR-16, FR-23, FR-24).
@DataClassName('AppSettingRecord')
class AppSettings extends Table {
  TextColumn get id => text()();
  TextColumn get nickname => text().nullable()();
  TextColumn get baseCurrency => text().withDefault(const Constant('IDR'))();
  IntColumn get paydayDay => integer().nullable()();
  IntColumn get monthlySalary => integer().nullable()();
  TextColumn get defaultWalletId => text().nullable()();
  BoolColumn get onboardingCompleted =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get privacyMode => boolean().withDefault(const Constant(false))();
  TextColumn get themeMode =>
      text().withDefault(const Constant('system'))(); // system, light, dark
  BoolColumn get aiEnabled => boolean().withDefault(const Constant(false))();
  TextColumn get aiModel => text().nullable()();
  BoolColumn get aiSaveHistory =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get aiIncludeContext =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get aiAllowImages =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get fcmEnabled => boolean().withDefault(const Constant(false))();
  BoolColumn get localNotificationsEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get hideAmountInNotifications =>
      boolean().withDefault(const Constant(true))();
  IntColumn get quietHoursStartMinute => integer().nullable()();
  IntColumn get quietHoursEndMinute => integer().nullable()();
  IntColumn get dailyReminderHour => integer().withDefault(const Constant(20))();
  IntColumn get dailyReminderMinute =>
      integer().withDefault(const Constant(0))();
  BoolColumn get appLockEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get biometricEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get autoLockTimeoutSeconds =>
      integer().withDefault(const Constant(60))();
  IntColumn get safeToSpendReserve =>
      integer().withDefault(const Constant(0))();
  IntColumn get safeToSpendEssentials =>
      integer().withDefault(const Constant(0))();
  TextColumn get dashboardHiddenWidgets =>
      text().withDefault(const Constant(''))(); // comma separated keys
  DateTimeColumn get lastBackupAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 2. accounts: User wallets (asset/liability) AND internal ledger system accounts
/// (income, expense, equity). Only accounts with isSystem == false are shown as wallets.
@DataClassName('AccountRecord')
@TableIndex(name: 'idx_accounts_class', columns: {#accountClass, #isArchived})
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get accountType =>
      text()(); // cash, bank, ewallet, savings, credit_card, paylater, other, system_income, system_expense, system_equity, system_receivable, system_debt
  TextColumn get accountClass =>
      text()(); // asset, liability, income, expense, equity
  TextColumn get currency => text().withDefault(const Constant('IDR'))();
  TextColumn get icon => text().withDefault(const Constant('wallet'))();
  IntColumn get colorValue => integer().withDefault(const Constant(0xFF0F766E))();
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();
  IntColumn get cachedBalance => integer().withDefault(const Constant(0))();
  BoolColumn get isVisible => boolean().withDefault(const Constant(true))();
  BoolColumn get includeInTotal => boolean().withDefault(const Constant(true))();
  BoolColumn get includeInSpendable =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 3. categories: Expense and income categories + subcategories (FR-05).
@DataClassName('CategoryRecord')
@TableIndex(name: 'idx_categories_type', columns: {#kind, #isArchived})
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => text()(); // expense, income
  TextColumn get parentId =>
      text().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  TextColumn get ledgerAccountId =>
      text().nullable().references(Accounts, #id, onDelete: KeyAction.setNull)();
  TextColumn get icon => text().withDefault(const Constant('category'))();
  IntColumn get colorValue => integer().withDefault(const Constant(0xFF64748B))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 4. transactions: Transaction header (FR-03, FR-04, BR-03, BR-06).
@DataClassName('TransactionRecord')
@TableIndex(name: 'idx_tx_occurred', columns: {#occurredAt, #status})
@TableIndex(name: 'idx_tx_type', columns: {#type, #status})
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type =>
      text()(); // income, expense, transfer, balance_adjustment, debt_disbursement, debt_repayment, refund, opening_balance
  IntColumn get amount => integer()(); // Always positive integer Rupiah
  TextColumn get currency => text().withDefault(const Constant('IDR'))();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get merchant => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get source =>
      text().withDefault(const Constant('manual'))(); // manual, ai, scan, voice, import, template, bill, split_bill, debt, goal, wishlist
  TextColumn get status =>
      text().withDefault(const Constant('posted'))(); // posted, voided
  TextColumn get primaryWalletId =>
      text().nullable().references(Accounts, #id, onDelete: KeyAction.setNull)();
  TextColumn get destinationWalletId =>
      text().nullable().references(Accounts, #id, onDelete: KeyAction.setNull)();
  TextColumn get primaryCategoryId =>
      text().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  TextColumn get relatedTransactionId => text().nullable()();
  TextColumn get importBatchId => text().nullable()();
  TextColumn get idempotencyKey => text().nullable()();
  TextColumn get location => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 5. ledger_entries: Balanced double-entry postings per transaction (BR-02, BR-03).
@DataClassName('LedgerEntryRecord')
@TableIndex(name: 'idx_ledger_tx', columns: {#transactionId})
@TableIndex(name: 'idx_ledger_account', columns: {#accountId})
class LedgerEntries extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId =>
      text().references(Transactions, #id, onDelete: KeyAction.cascade)();
  TextColumn get accountId =>
      text().references(Accounts, #id, onDelete: KeyAction.restrict)();
  TextColumn get side => text()(); // debit, credit
  IntColumn get amount => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 6. transaction_splits: Category allocation lines for each transaction (FR-03).
@DataClassName('TransactionSplitRecord')
@TableIndex(name: 'idx_splits_tx', columns: {#transactionId})
@TableIndex(name: 'idx_splits_cat', columns: {#categoryId})
class TransactionSplits extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId =>
      text().references(Transactions, #id, onDelete: KeyAction.cascade)();
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.restrict)();
  IntColumn get amount => integer()();
  TextColumn get description => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 7. tags: Master tag list.
@DataClassName('TagRecord')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  IntColumn get colorValue => integer().withDefault(const Constant(0xFF0284C7))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 8. transaction_tags: Many-to-many join between transactions and tags.
@DataClassName('TransactionTagRecord')
class TransactionTags extends Table {
  TextColumn get transactionId =>
      text().references(Transactions, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {transactionId, tagId};
}

/// 9. attachments: Local relative file references (images/receipts).
@DataClassName('AttachmentRecord')
class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId =>
      text().nullable().references(Transactions, #id, onDelete: KeyAction.cascade)();
  TextColumn get relativePath => text()();
  TextColumn get mimeType => text().withDefault(const Constant('image/jpeg'))();
  TextColumn get contentHash => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 10. transaction_templates: Quick Add & favorite templates (FR-06).
@DataClassName('TransactionTemplateRecord')
class TransactionTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get type => text()(); // expense, income
  IntColumn get amount => integer()();
  TextColumn get walletId =>
      text().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.cascade)();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get merchant => text().nullable()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(true))();
  IntColumn get useCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 11. budgets: Category/period spending limits (FR-08).
@DataClassName('BudgetRecord')
@TableIndex(name: 'idx_budgets_period', columns: {#periodType, #startDate})
class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id, onDelete: KeyAction.cascade)();
  IntColumn get limitAmount => integer()();
  TextColumn get periodType =>
      text()(); // daily, weekly, monthly, custom
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  BoolColumn get rolloverEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get rolloverAmount => integer().withDefault(const Constant(0))();
  BoolColumn get alert80Sent => boolean().withDefault(const Constant(false))();
  BoolColumn get alert100Sent => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 12. bills: Recurring bills, salaries, and subscriptions (FR-10).
@DataClassName('BillRecord')
class Bills extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => text().withDefault(const Constant('expense'))(); // expense, income
  IntColumn get estimatedAmount => integer()();
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.restrict)();
  TextColumn get walletId =>
      text().references(Accounts, #id, onDelete: KeyAction.restrict)();
  TextColumn get frequency =>
      text()(); // daily, weekly, monthly, yearly
  IntColumn get dueDayOfMonth => integer().nullable()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get isSubscription =>
      boolean().withDefault(const Constant(false))();
  TextColumn get reminderOffsets =>
      text().withDefault(const Constant('7,3,1'))(); // days before due
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 13. bill_occurrences: Unique scheduled occurrences per period (BR-08).
@DataClassName('BillOccurrenceRecord')
@TableIndex(name: 'idx_bill_occ_due', columns: {#dueDate, #status})
class BillOccurrences extends Table {
  TextColumn get id => text()();
  TextColumn get billId =>
      text().references(Bills, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get dueDate => dateTime()();
  IntColumn get expectedAmount => integer()();
  IntColumn get paidAmount => integer().withDefault(const Constant(0))();
  TextColumn get status =>
      text().withDefault(const Constant('upcoming'))(); // upcoming, unpaid, paid, overdue, skipped, cancelled
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 14. bill_payments: Payment links between bill occurrences and posted transactions.
@DataClassName('BillPaymentRecord')
class BillPayments extends Table {
  TextColumn get id => text()();
  TextColumn get occurrenceId =>
      text().references(BillOccurrences, #id, onDelete: KeyAction.cascade)();
  TextColumn get transactionId =>
      text().references(Transactions, #id, onDelete: KeyAction.cascade)();
  IntColumn get amount => integer()();
  DateTimeColumn get paidAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 15. goals: Saving goals (FR-11).
@DataClassName('GoalRecord')
class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get targetAmount => integer()();
  IntColumn get currentAmount => integer().withDefault(const Constant(0))();
  DateTimeColumn get targetDate => dateTime().nullable()();
  TextColumn get sourceWalletId =>
      text().nullable().references(Accounts, #id, onDelete: KeyAction.setNull)();
  TextColumn get icon => text().withDefault(const Constant('savings'))();
  IntColumn get priority => integer().withDefault(const Constant(1))();
  TextColumn get status =>
      text().withDefault(const Constant('active'))(); // active, completed, paused
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 16. fund_allocations: Virtual envelopes preventing double allocation across goals/plans.
@DataClassName('FundAllocationRecord')
class FundAllocations extends Table {
  TextColumn get id => text()();
  TextColumn get walletId =>
      text().references(Accounts, #id, onDelete: KeyAction.cascade)();
  TextColumn get targetType => text()(); // goal, salary_envelope, reserve
  TextColumn get targetId => text()();
  IntColumn get amount => integer()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 17. goal_contributions: Contribution & withdrawal history for goals.
@DataClassName('GoalContributionRecord')
class GoalContributions extends Table {
  TextColumn get id => text()();
  TextColumn get goalId =>
      text().references(Goals, #id, onDelete: KeyAction.cascade)();
  TextColumn get transactionId =>
      text().nullable().references(Transactions, #id, onDelete: KeyAction.setNull)();
  IntColumn get amount => integer()(); // positive = contribution, negative = withdrawal
  BoolColumn get isVirtual => boolean().withDefault(const Constant(true))();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 18. debts: Personal debts (utang) and receivables (piutang) (FR-13).
@DataClassName('DebtRecord')
@TableIndex(name: 'idx_debts_status', columns: {#kind, #status})
class Debts extends Table {
  TextColumn get id => text()();
  TextColumn get counterparty => text()();
  TextColumn get kind => text()(); // debt (utang), receivable (piutang)
  IntColumn get principalAmount => integer()();
  IntColumn get remainingAmount => integer()();
  TextColumn get walletId =>
      text().nullable().references(Accounts, #id, onDelete: KeyAction.setNull)();
  TextColumn get disbursementTxId =>
      text().nullable().references(Transactions, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get status =>
      text().withDefault(const Constant('open'))(); // open, partial, settled, cancelled
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 19. debt_payments: Principal + interest/fee repayments (FR-13).
@DataClassName('DebtPaymentRecord')
class DebtPayments extends Table {
  TextColumn get id => text()();
  TextColumn get debtId =>
      text().references(Debts, #id, onDelete: KeyAction.cascade)();
  TextColumn get transactionId =>
      text().references(Transactions, #id, onDelete: KeyAction.cascade)();
  IntColumn get principalPaid => integer()();
  IntColumn get interestOrFeePaid => integer().withDefault(const Constant(0))();
  DateTimeColumn get paidAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 20. split_bills: Shared bill header (FR-14).
@DataClassName('SplitBillRecord')
class SplitBills extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get totalAmount => integer()();
  IntColumn get taxAmount => integer().withDefault(const Constant(0))();
  IntColumn get serviceAmount => integer().withDefault(const Constant(0))();
  TextColumn get payerWalletId =>
      text().references(Accounts, #id, onDelete: KeyAction.restrict)();
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.restrict)();
  TextColumn get transactionId =>
      text().nullable().references(Transactions, #id, onDelete: KeyAction.setNull)();
  TextColumn get splitMode =>
      text().withDefault(const Constant('equal'))(); // equal, item, exact, percentage
  TextColumn get status =>
      text().withDefault(const Constant('active'))(); // active, settled, cancelled
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 21. split_bill_members: Participant shares & linked receivable (FR-14).
@DataClassName('SplitBillMemberRecord')
class SplitBillMembers extends Table {
  TextColumn get id => text()();
  TextColumn get splitBillId =>
      text().references(SplitBills, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  BoolColumn get isSelf => boolean().withDefault(const Constant(false))();
  IntColumn get shareAmount => integer()();
  IntColumn get paidAmount => integer().withDefault(const Constant(0))();
  TextColumn get debtId =>
      text().nullable().references(Debts, #id, onDelete: KeyAction.setNull)();
  BoolColumn get isSettled => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 22. wishlists: Purchase planning & cooling-off period (FR-15).
@DataClassName('WishlistRecord')
class Wishlists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get price => integer()();
  IntColumn get priority => integer().withDefault(const Constant(2))(); // 1=High, 2=Med, 3=Low
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get targetDate => dateTime().nullable()();
  IntColumn get coolingOffDays => integer().withDefault(const Constant(3))();
  DateTimeColumn get coolingOffUntil => dateTime().nullable()();
  TextColumn get productUrl => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending, purchased, cancelled
  TextColumn get purchasedTxId =>
      text().nullable().references(Transactions, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 23. salary_plans: Income allocation plan (FR-12).
@DataClassName('SalaryPlanRecord')
class SalaryPlans extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  IntColumn get totalIncome => integer()();
  TextColumn get templateType =>
      text().withDefault(const Constant('50_30_20'))(); // 50_30_20, custom, historical
  TextColumn get sourceTransactionId =>
      text().nullable().references(Transactions, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get appliedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 24. salary_plan_items: Individual allocation lines in a salary plan.
@DataClassName('SalaryPlanItemRecord')
class SalaryPlanItems extends Table {
  TextColumn get id => text()();
  TextColumn get salaryPlanId =>
      text().references(SalaryPlans, #id, onDelete: KeyAction.cascade)();
  TextColumn get label => text()();
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id, onDelete: KeyAction.setNull)();
  TextColumn get goalId =>
      text().nullable().references(Goals, #id, onDelete: KeyAction.setNull)();
  IntColumn get percentage => integer().withDefault(const Constant(0))();
  IntColumn get allocatedAmount => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 25. notifications: Scheduled local notification ledger (FR-23).
@DataClassName('NotificationRecord')
@TableIndex(name: 'idx_notif_sched', columns: {#scheduledAt, #status})
class Notifications extends Table {
  TextColumn get id => text()();
  IntColumn get platformId => integer()();
  TextColumn get kind =>
      text()(); // daily, bill, budget, salary, saving, debt, weekly_recap, monthly_recap, wishlist
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get deepLink => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  DateTimeColumn get scheduledAt => dateTime()();
  TextColumn get status =>
      text().withDefault(const Constant('scheduled'))(); // scheduled, fired, cancelled

  @override
  Set<Column> get primaryKey => {id};
}

/// 26. ai_conversations: Local AI chat threads (FR-20).
@DataClassName('AiConversationRecord')
class AiConversations extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 27. ai_messages: Local AI chat messages (FR-20).
@DataClassName('AiMessageRecord')
class AiMessages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId =>
      text().references(AiConversations, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()(); // user, assistant, tool
  TextColumn get content => text()();
  TextColumn get metadataJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 28. import_batches: CSV/Excel import batch metadata for audit & rollback (FR-25).
@DataClassName('ImportBatchRecord')
class ImportBatches extends Table {
  TextColumn get id => text()();
  TextColumn get fileName => text()();
  TextColumn get walletId =>
      text().references(Accounts, #id, onDelete: KeyAction.cascade)();
  IntColumn get totalRows => integer()();
  IntColumn get importedRows => integer()();
  IntColumn get skippedDuplicates => integer().withDefault(const Constant(0))();
  TextColumn get status =>
      text().withDefault(const Constant('completed'))(); // completed, reverted
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 29. audit_logs: Immutable audit trail for financial edits/voids/reconciliations (BR-06).
@DataClassName('AuditLogRecord')
@TableIndex(name: 'idx_audit_entity', columns: {#entityType, #entityId})
class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()(); // create, update, void, reconcile, import, restore
  TextColumn get summary => text()();
  TextColumn get payloadJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
