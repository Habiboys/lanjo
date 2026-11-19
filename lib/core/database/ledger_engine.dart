import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../errors/arus_exception.dart';
import 'app_database.dart';

class CategorySplitInput {
  const CategorySplitInput({
    required this.categoryId,
    required this.amount,
    this.description = '',
  });

  final String categoryId;
  final int amount;
  final String description;
}

class LedgerPosting {
  const LedgerPosting({
    required this.accountId,
    required this.side,
    required this.amount,
  });

  final String accountId;
  final String side; // 'debit' or 'credit'
  final int amount;
}

/// Deterministic double-entry ledger & transaction engine (BR-01..BR-08).
class LedgerEngine {
  LedgerEngine(this.db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase db;
  final Uuid _uuid;

  /// Computes live balance of an account directly from [LedgerEntries] (BR-02).
  Future<int> computeAccountBalance(String accountId) async {
    final account = await (db.select(db.accounts)
          ..where((a) => a.id.equals(accountId)))
        .getSingle();

    final entries = await (db.select(db.ledgerEntries)
          ..where((e) => e.accountId.equals(accountId)))
        .get();

    var debits = 0;
    var credits = 0;
    for (final e in entries) {
      if (e.side == 'debit') {
        debits += e.amount;
      } else {
        credits += e.amount;
      }
    }

    // Asset & Expense accounts increase on debit; Liability, Income, Equity increase on credit.
    if (account.accountClass == 'asset' || account.accountClass == 'expense') {
      return debits - credits;
    }
    return credits - debits;
  }

  /// Recomputes and syncs [Accounts.cachedBalance] for the given account IDs.
  Future<void> _syncCachedBalances(Iterable<String> accountIds) async {
    final uniqueIds = accountIds.toSet();
    final now = DateTime.now();
    for (final id in uniqueIds) {
      final balance = await computeAccountBalance(id);
      await (db.update(db.accounts)..where((a) => a.id.equals(id))).write(
        AccountsCompanion(
          cachedBalance: Value(balance),
          updatedAt: Value(now),
        ),
      );
    }
  }

  /// Validates and inserts balanced [LedgerPosting] rows, then updates affected cached balances.
  Future<void> _postBalancedEntries({
    required String transactionId,
    required List<LedgerPosting> postings,
    required DateTime timestamp,
  }) async {
    if (postings.isEmpty) {
      throw const LedgerImbalanceException('Transaksi tidak memiliki entri ledger.');
    }

    var totalDebit = 0;
    var totalCredit = 0;
    for (final p in postings) {
      if (p.amount <= 0) {
        throw const ValidationException('Nominal entri ledger harus lebih besar dari nol.');
      }
      if (p.side == 'debit') {
        totalDebit += p.amount;
      } else if (p.side == 'credit') {
        totalCredit += p.amount;
      } else {
        throw ValidationException('Sisi ledger tidak valid: ${p.side}');
      }
    }

    if (totalDebit != totalCredit) {
      throw LedgerImbalanceException(
        'Ledger tidak seimbang: debit=$totalDebit, credit=$totalCredit',
      );
    }

    await db.batch((b) {
      for (final p in postings) {
        b.insert(
          db.ledgerEntries,
          LedgerEntriesCompanion.insert(
            id: _uuid.v4(),
            transactionId: transactionId,
            accountId: p.accountId,
            side: p.side,
            amount: p.amount,
            createdAt: timestamp,
          ),
        );
      }
    });

    await _syncCachedBalances(postings.map((e) => e.accountId));
  }

  Future<void> _writeAudit({
    required String entityType,
    required String entityId,
    required String action,
    required String summary,
    Map<String, dynamic>? payload,
  }) async {
    await db.into(db.auditLogs).insert(
          AuditLogsCompanion.insert(
            id: _uuid.v4(),
            entityType: entityType,
            entityId: entityId,
            action: action,
            summary: summary,
            payloadJson: Value(payload == null ? null : jsonEncode(payload)),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<String> _resolveCategoryLedgerAccount(String categoryId) async {
    final cat = await (db.select(db.categories)
          ..where((c) => c.id.equals(categoryId)))
        .getSingleOrNull();
    if (cat == null) {
      throw ValidationException('Kategori tidak ditemukan: $categoryId');
    }
    if (cat.ledgerAccountId != null) {
      return cat.ledgerAccountId!;
    }
    if (cat.parentId != null) {
      final parent = await (db.select(db.categories)
            ..where((c) => c.id.equals(cat.parentId!)))
          .getSingleOrNull();
      if (parent?.ledgerAccountId != null) return parent!.ledgerAccountId!;
    }
    return cat.kind == 'income'
        ? SystemAccountIds.incomeDefault
        : SystemAccountIds.expenseDefault;
  }

  Future<void> _checkNegativeAssetBalance({
    required AccountRecord wallet,
    required int outflowAmount,
    required bool allowNegativeBalance,
  }) async {
    if (wallet.accountClass != 'asset' || allowNegativeBalance) return;
    final current = await computeAccountBalance(wallet.id);
    final projected = current - outflowAmount;
    if (projected < 0) {
      throw NegativeAssetBalanceException(
        walletName: wallet.name,
        currentBalance: current,
        projectedBalance: projected,
      );
    }
  }

  Future<bool> _hasIdempotencyDuplicate(String? key) async {
    if (key == null || key.isEmpty) return false;
    final existing = await (db.select(db.transactions)
          ..where((t) => t.idempotencyKey.equals(key) & t.status.equals('posted')))
        .getSingleOrNull();
    return existing != null;
  }

  /// Creates a new user wallet and posts its opening balance via equity (not income).
  Future<String> createWallet({
    required String name,
    required String accountType,
    required String icon,
    required int colorValue,
    int openingBalance = 0,
    bool includeInTotal = true,
    bool includeInSpendable = true,
    bool setAsDefault = false,
  }) async {
    if (name.trim().isEmpty) {
      throw const ValidationException('Nama dompet tidak boleh kosong.');
    }
    final isLiability = accountType == 'credit_card' || accountType == 'paylater';
    final accountClass = isLiability ? 'liability' : 'asset';
    final walletId = _uuid.v4();
    final now = DateTime.now();

    await db.transaction(() async {
      final existingCount = await (db.select(db.accounts)
            ..where((a) => a.isSystem.equals(false)))
          .get()
          .then((rows) => rows.length);

      await db.into(db.accounts).insert(
            AccountsCompanion.insert(
              id: walletId,
              name: name.trim(),
              accountType: accountType,
              accountClass: accountClass,
              icon: Value(icon),
              colorValue: Value(colorValue),
              openingBalance: Value(openingBalance),
              cachedBalance: const Value(0),
              includeInTotal: Value(includeInTotal),
              includeInSpendable: Value(isLiability ? false : includeInSpendable),
              sortOrder: Value(existingCount),
              createdAt: now,
              updatedAt: now,
            ),
          );

      if (openingBalance > 0) {
        final txId = _uuid.v4();
        await db.into(db.transactions).insert(
              TransactionsCompanion.insert(
                id: txId,
                type: 'opening_balance',
                amount: openingBalance,
                description: Value('Saldo awal ${name.trim()}'),
                occurredAt: now,
                source: const Value('manual'),
                primaryWalletId: Value(walletId),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _postBalancedEntries(
          transactionId: txId,
          timestamp: now,
          postings: isLiability
              ? [
                  LedgerPosting(
                    accountId: SystemAccountIds.equityOpening,
                    side: 'debit',
                    amount: openingBalance,
                  ),
                  LedgerPosting(
                    accountId: walletId,
                    side: 'credit',
                    amount: openingBalance,
                  ),
                ]
              : [
                  LedgerPosting(
                    accountId: walletId,
                    side: 'debit',
                    amount: openingBalance,
                  ),
                  LedgerPosting(
                    accountId: SystemAccountIds.equityOpening,
                    side: 'credit',
                    amount: openingBalance,
                  ),
                ],
        );
      }

      if (setAsDefault || existingCount == 0) {
        await (db.update(db.appSettings)..where((s) => s.id.equals('default')))
            .write(
          AppSettingsCompanion(
            defaultWalletId: Value(walletId),
            updatedAt: Value(now),
          ),
        );
      }

      await _writeAudit(
        entityType: 'account',
        entityId: walletId,
        action: 'create',
        summary: 'Buat dompet ${name.trim()} (saldo awal $openingBalance)',
      );
    });

    return walletId;
  }

  /// Updates wallet name, classification, icon, and inclusion flags cleanly.
  Future<void> updateWallet({
    required String walletId,
    required String name,
    required String accountType,
    required String icon,
    required bool includeInTotal,
    required bool includeInSpendable,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw const ValidationException('Nama dompet tidak boleh kosong.');
    }
    final isLiability = accountType == 'credit_card' || accountType == 'paylater';
    final accountClass = isLiability ? 'liability' : 'asset';

    await (db.update(db.accounts)..where((a) => a.id.equals(walletId))).write(
      AccountsCompanion(
        name: Value(clean),
        accountType: Value(accountType),
        accountClass: Value(accountClass),
        icon: Value(icon),
        includeInTotal: Value(includeInTotal),
        includeInSpendable: Value(isLiability ? false : includeInSpendable),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _writeAudit(
      entityType: 'account',
      entityId: walletId,
      action: 'update',
      summary: 'Edit dompet $clean ($accountType)',
    );
  }

  /// Deletes a wallet if it has no activity beyond its opening balance;
  /// otherwise returns false so the caller can safely archive it instead.
  Future<bool> deleteWalletIfUnused(String walletId) async {
    return db.transaction(() async {
      final nonOpeningTxs = await (db.select(db.transactions)
            ..where((t) =>
                t.type.isNotIn(['opening_balance']) &
                (t.primaryWalletId.equals(walletId) |
                    t.destinationWalletId.equals(walletId))))
          .get();
      if (nonOpeningTxs.isNotEmpty) {
        return false;
      }

      final activeBills = await (db.select(db.bills)
            ..where((b) => b.walletId.equals(walletId) & b.isActive.equals(true)))
          .get();
      if (activeBills.isNotEmpty) {
        return false;
      }

      final openingTxs = await (db.select(db.transactions)
            ..where((t) =>
                t.type.equals('opening_balance') &
                t.primaryWalletId.equals(walletId)))
          .get();
      for (final tx in openingTxs) {
        await _voidTransactionInTx(
          tx.id,
          reason: 'Hapus dompet belum terpakai',
          skipDebtSync: true,
        );
        await (db.delete(db.ledgerEntries)
              ..where((e) => e.transactionId.equals(tx.id)))
            .go();
        await (db.delete(db.transactions)..where((t) => t.id.equals(tx.id))).go();
      }
      await _syncCachedBalances({walletId, SystemAccountIds.equityOpening});

      final remainingEntries = await (db.select(db.ledgerEntries)
            ..where((e) => e.accountId.equals(walletId)))
          .get();
      if (remainingEntries.isNotEmpty) {
        return false;
      }

      final settings = await (db.select(db.appSettings)
            ..where((s) => s.id.equals('default')))
          .getSingleOrNull();
      if (settings?.defaultWalletId == walletId) {
        final other = await (db.select(db.accounts)
              ..where((a) =>
                  a.isSystem.equals(false) &
                  a.isArchived.equals(false) &
                  a.id.isNotIn([walletId]))
              ..limit(1))
            .getSingleOrNull();
        await (db.update(db.appSettings)..where((s) => s.id.equals('default')))
            .write(
          AppSettingsCompanion(
            defaultWalletId: Value(other?.id),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      await (db.delete(db.accounts)..where((a) => a.id.equals(walletId))).go();
      await _writeAudit(
        entityType: 'account',
        entityId: walletId,
        action: 'delete',
        summary: 'Hapus dompet belum terpakai $walletId',
      );
      return true;
    });
  }

  /// Records an income transaction (FR-03).
  Future<String> recordIncome({
    required String walletId,
    required String categoryId,
    required int amount,
    required DateTime occurredAt,
    String description = '',
    String? merchant,
    String source = 'manual',
    String? idempotencyKey,
    String? importBatchId,
    List<String> tagNames = const [],
  }) async {
    if (amount <= 0) {
      throw const ValidationException('Nominal pemasukan harus lebih besar dari nol.');
    }

    return db.transaction(() async {
      if (await _hasIdempotencyDuplicate(idempotencyKey)) {
        final existing = await (db.select(db.transactions)
              ..where((t) => t.idempotencyKey.equals(idempotencyKey!)))
            .getSingle();
        return existing.id;
      }

      final wallet = await (db.select(db.accounts)
            ..where((a) => a.id.equals(walletId) & a.isSystem.equals(false)))
          .getSingleOrNull();
      if (wallet == null) {
        throw const ValidationException('Dompet tidak ditemukan.');
      }

      final incomeLedgerId = await _resolveCategoryLedgerAccount(categoryId);
      final txId = _uuid.v4();
      final now = DateTime.now();

      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: txId,
              type: 'income',
              amount: amount,
              description: Value(description.trim()),
              merchant: Value(merchant?.trim()),
              occurredAt: occurredAt,
              source: Value(source),
              primaryWalletId: Value(walletId),
              primaryCategoryId: Value(categoryId),
              idempotencyKey: Value(idempotencyKey),
              importBatchId: Value(importBatchId),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await db.into(db.transactionSplits).insert(
            TransactionSplitsCompanion.insert(
              id: _uuid.v4(),
              transactionId: txId,
              categoryId: categoryId,
              amount: amount,
              description: Value(description.trim()),
            ),
          );

      await _postBalancedEntries(
        transactionId: txId,
        timestamp: now,
        postings: [
          LedgerPosting(accountId: walletId, side: 'debit', amount: amount),
          LedgerPosting(
            accountId: incomeLedgerId,
            side: 'credit',
            amount: amount,
          ),
        ],
      );

      await _attachTags(txId, tagNames);
      await _writeAudit(
        entityType: 'transaction',
        entityId: txId,
        action: 'create',
        summary: 'Pemasukan $amount ke ${wallet.name}',
      );
      return txId;
    });
  }

  /// Records an expense transaction with single or multiple category splits (FR-03).
  Future<String> recordExpense({
    required String walletId,
    required int amount,
    required List<CategorySplitInput> splits,
    required DateTime occurredAt,
    String description = '',
    String? merchant,
    String source = 'manual',
    String? idempotencyKey,
    String? importBatchId,
    List<String> tagNames = const [],
    bool allowNegativeBalance = false,
  }) async {
    if (amount <= 0) {
      throw const ValidationException('Nominal pengeluaran harus lebih besar dari nol.');
    }
    if (splits.isEmpty) {
      throw const ValidationException('Minimal satu kategori harus dipilih.');
    }
    final splitSum = splits.fold<int>(0, (s, e) => s + e.amount);
    if (splitSum != amount) {
      throw ValidationException(
        'Total alokasi kategori ($splitSum) harus sama dengan nominal transaksi ($amount).',
      );
    }

    return db.transaction(() async {
      if (await _hasIdempotencyDuplicate(idempotencyKey)) {
        final existing = await (db.select(db.transactions)
              ..where((t) => t.idempotencyKey.equals(idempotencyKey!)))
            .getSingle();
        return existing.id;
      }

      final wallet = await (db.select(db.accounts)
            ..where((a) => a.id.equals(walletId) & a.isSystem.equals(false)))
          .getSingleOrNull();
      if (wallet == null) {
        throw const ValidationException('Dompet tidak ditemukan.');
      }

      await _checkNegativeAssetBalance(
        wallet: wallet,
        outflowAmount: amount,
        allowNegativeBalance: allowNegativeBalance,
      );

      final txId = _uuid.v4();
      final now = DateTime.now();

      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: txId,
              type: 'expense',
              amount: amount,
              description: Value(description.trim()),
              merchant: Value(merchant?.trim()),
              occurredAt: occurredAt,
              source: Value(source),
              primaryWalletId: Value(walletId),
              primaryCategoryId: Value(splits.first.categoryId),
              idempotencyKey: Value(idempotencyKey),
              importBatchId: Value(importBatchId),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final postings = <LedgerPosting>[];
      for (final split in splits) {
        if (split.amount <= 0) {
          throw const ValidationException('Nominal split kategori harus > 0.');
        }
        await db.into(db.transactionSplits).insert(
              TransactionSplitsCompanion.insert(
                id: _uuid.v4(),
                transactionId: txId,
                categoryId: split.categoryId,
                amount: split.amount,
                description: Value(split.description.trim()),
              ),
            );
        final ledgerAccId = await _resolveCategoryLedgerAccount(split.categoryId);
        postings.add(
          LedgerPosting(
            accountId: ledgerAccId,
            side: 'debit',
            amount: split.amount,
          ),
        );
      }

      postings.add(
        LedgerPosting(accountId: walletId, side: 'credit', amount: amount),
      );

      await _postBalancedEntries(
        transactionId: txId,
        timestamp: now,
        postings: postings,
      );

      await _attachTags(txId, tagNames);
      await _writeAudit(
        entityType: 'transaction',
        entityId: txId,
        action: 'create',
        summary: 'Pengeluaran $amount dari ${wallet.name}',
      );
      return txId;
    });
  }

  /// Records a wallet-to-wallet transfer (including e-wallet top-up or credit card payment)
  /// with optional [adminFee] treated as an expense (FR-04).
  Future<String> recordTransfer({
    required String sourceWalletId,
    required String destinationWalletId,
    required int amount,
    required DateTime occurredAt,
    int adminFee = 0,
    String description = '',
    String source = 'manual',
    String? idempotencyKey,
    bool allowNegativeBalance = false,
  }) async {
    if (sourceWalletId == destinationWalletId) {
      throw const ValidationException('Dompet asal dan tujuan tidak boleh sama.');
    }
    if (amount <= 0) {
      throw const ValidationException('Nominal transfer harus lebih besar dari nol.');
    }
    if (adminFee < 0) {
      throw const ValidationException('Biaya admin tidak boleh negatif.');
    }

    return db.transaction(() async {
      if (await _hasIdempotencyDuplicate(idempotencyKey)) {
        final existing = await (db.select(db.transactions)
              ..where((t) => t.idempotencyKey.equals(idempotencyKey!)))
            .getSingle();
        return existing.id;
      }

      final srcWallet = await (db.select(db.accounts)
            ..where((a) => a.id.equals(sourceWalletId) & a.isSystem.equals(false)))
          .getSingleOrNull();
      final dstWallet = await (db.select(db.accounts)
            ..where((a) =>
                a.id.equals(destinationWalletId) & a.isSystem.equals(false)))
          .getSingleOrNull();
      if (srcWallet == null || dstWallet == null) {
        throw const ValidationException('Dompet asal atau tujuan tidak ditemukan.');
      }

      final totalOutflow = amount + adminFee;
      await _checkNegativeAssetBalance(
        wallet: srcWallet,
        outflowAmount: totalOutflow,
        allowNegativeBalance: allowNegativeBalance,
      );

      final txId = _uuid.v4();
      final now = DateTime.now();

      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: txId,
              type: 'transfer',
              amount: amount,
              description: Value(
                description.trim().isEmpty
                    ? 'Transfer ${srcWallet.name} ke ${dstWallet.name}'
                    : description.trim(),
              ),
              occurredAt: occurredAt,
              source: Value(source),
              primaryWalletId: Value(sourceWalletId),
              destinationWalletId: Value(destinationWalletId),
              idempotencyKey: Value(idempotencyKey),
              createdAt: now,
              updatedAt: now,
            ),
          );

      // Debit destination wallet (for asset increases asset; for liability decreases liability!)
      final postings = <LedgerPosting>[
        LedgerPosting(
          accountId: destinationWalletId,
          side: 'debit',
          amount: amount,
        ),
        LedgerPosting(
          accountId: sourceWalletId,
          side: 'credit',
          amount: totalOutflow,
        ),
      ];

      if (adminFee > 0) {
        final feeLedger =
            await _resolveCategoryLedgerAccount(DefaultCategoryIds.adminFee);
        postings.add(
          LedgerPosting(
            accountId: feeLedger,
            side: 'debit',
            amount: adminFee,
          ),
        );
        await db.into(db.transactionSplits).insert(
              TransactionSplitsCompanion.insert(
                id: _uuid.v4(),
                transactionId: txId,
                categoryId: DefaultCategoryIds.adminFee,
                amount: adminFee,
                description: const Value('Biaya admin transfer'),
              ),
            );
      }

      await _postBalancedEntries(
        transactionId: txId,
        timestamp: now,
        postings: postings,
      );

      await _writeAudit(
        entityType: 'transaction',
        entityId: txId,
        action: 'create',
        summary:
            'Transfer $amount dari ${srcWallet.name} ke ${dstWallet.name} (admin $adminFee)',
      );
      return txId;
    });
  }

  /// Records a refund reducing spending in [categoryId] (FR-03).
  Future<String> recordRefund({
    required String walletId,
    required String categoryId,
    required int amount,
    required DateTime occurredAt,
    String description = 'Refund',
    String? relatedTransactionId,
  }) async {
    if (amount <= 0) {
      throw const ValidationException('Nominal refund harus lebih besar dari nol.');
    }

    return db.transaction(() async {
      final wallet = await (db.select(db.accounts)
            ..where((a) => a.id.equals(walletId) & a.isSystem.equals(false)))
          .getSingleOrNull();
      if (wallet == null) {
        throw const ValidationException('Dompet tidak ditemukan.');
      }

      final expenseLedger = await _resolveCategoryLedgerAccount(categoryId);
      final txId = _uuid.v4();
      final now = DateTime.now();

      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: txId,
              type: 'refund',
              amount: amount,
              description: Value(description.trim()),
              occurredAt: occurredAt,
              source: const Value('manual'),
              primaryWalletId: Value(walletId),
              primaryCategoryId: Value(categoryId),
              relatedTransactionId: Value(relatedTransactionId),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await db.into(db.transactionSplits).insert(
            TransactionSplitsCompanion.insert(
              id: _uuid.v4(),
              transactionId: txId,
              categoryId: categoryId,
              amount: amount,
              description: Value(description.trim()),
            ),
          );

      await _postBalancedEntries(
        transactionId: txId,
        timestamp: now,
        postings: [
          LedgerPosting(accountId: walletId, side: 'debit', amount: amount),
          LedgerPosting(
            accountId: expenseLedger,
            side: 'credit',
            amount: amount,
          ),
        ],
      );

      await _writeAudit(
        entityType: 'transaction',
        entityId: txId,
        action: 'create',
        summary: 'Refund $amount ke ${wallet.name}',
      );
      return txId;
    });
  }

  /// Reconciles a wallet balance to [actualBalance] using a balance_adjustment entry (FR-26).
  Future<String?> reconcileWalletBalance({
    required String walletId,
    required int actualBalance,
    String reason = 'Penyesuaian saldo aktual',
  }) async {
    return db.transaction(() async {
      final wallet = await (db.select(db.accounts)
            ..where((a) => a.id.equals(walletId) & a.isSystem.equals(false)))
          .getSingleOrNull();
      if (wallet == null) {
        throw const ValidationException('Dompet tidak ditemukan.');
      }

      final current = await computeAccountBalance(walletId);
      final delta = actualBalance - current;
      if (delta == 0) return null;

      final absDelta = delta.abs();
      final txId = _uuid.v4();
      final now = DateTime.now();

      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: txId,
              type: 'balance_adjustment',
              amount: absDelta,
              description: Value(reason.trim()),
              occurredAt: now,
              source: const Value('manual'),
              primaryWalletId: Value(walletId),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final isAsset = wallet.accountClass == 'asset';
      final increaseWalletDebit =
          (isAsset && delta > 0) || (!isAsset && delta < 0);

      await _postBalancedEntries(
        transactionId: txId,
        timestamp: now,
        postings: increaseWalletDebit
            ? [
                LedgerPosting(
                  accountId: walletId,
                  side: 'debit',
                  amount: absDelta,
                ),
                LedgerPosting(
                  accountId: SystemAccountIds.equityAdjustment,
                  side: 'credit',
                  amount: absDelta,
                ),
              ]
            : [
                LedgerPosting(
                  accountId: SystemAccountIds.equityAdjustment,
                  side: 'debit',
                  amount: absDelta,
                ),
                LedgerPosting(
                  accountId: walletId,
                  side: 'credit',
                  amount: absDelta,
                ),
              ],
      );

      await _writeAudit(
        entityType: 'transaction',
        entityId: txId,
        action: 'reconcile',
        summary: 'Rekonsiliasi ${wallet.name}: $current -> $actualBalance ($reason)',
      );
      return txId;
    });
  }

  /// Records a personal debt (utang) or receivable (piutang) disbursement (FR-13).
  /// Set [affectsWallet] to false when recording an existing/old debt or receivable
  /// so current wallet balances are NOT modified (balanced via opening equity).
  Future<String> recordDebt({
    required String counterparty,
    required String kind, // 'debt' or 'receivable'
    required int principalAmount,
    String? walletId,
    required DateTime occurredAt,
    DateTime? dueDate,
    String note = '',
    bool affectsWallet = true,
    bool allowNegativeBalance = false,
  }) async {
    final cleanParty = counterparty.trim();
    if (cleanParty.isEmpty) {
      throw const ValidationException('Nama pihak harus diisi.');
    }
    if (principalAmount <= 0) {
      throw const ValidationException('Nominal pokok harus > 0.');
    }
    if (affectsWallet && (walletId == null || walletId.trim().isEmpty)) {
      throw const ValidationException('Pilih dompet terkait.');
    }

    return db.transaction(() async {
      final effectiveWalletId = affectsWallet ? walletId!.trim() : null;
      if (effectiveWalletId != null) {
        final wallet = await (db.select(db.accounts)
              ..where((a) =>
                  a.id.equals(effectiveWalletId) & a.isSystem.equals(false)))
            .getSingleOrNull();
        if (wallet == null) {
          throw const ValidationException('Dompet tidak ditemukan.');
        }

        if (kind == 'receivable') {
          await _checkNegativeAssetBalance(
            wallet: wallet,
            outflowAmount: principalAmount,
            allowNegativeBalance: allowNegativeBalance,
          );
        }
      }

      final txId = _uuid.v4();
      final debtId = _uuid.v4();
      final now = DateTime.now();

      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: txId,
              type: affectsWallet ? 'debt_disbursement' : 'opening_balance',
              amount: principalAmount,
              description: Value(
                kind == 'receivable'
                    ? (affectsWallet
                        ? 'Piutang ke $cleanParty'
                        : 'Piutang lama dari $cleanParty')
                    : (affectsWallet
                        ? 'Utang dari $cleanParty'
                        : 'Utang lama ke $cleanParty'),
              ),
              merchant: Value(cleanParty),
              occurredAt: occurredAt,
              source: const Value('debt'),
              primaryWalletId: Value(effectiveWalletId),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final contraAccountId =
          effectiveWalletId ?? SystemAccountIds.equityOpening;
      await _postBalancedEntries(
        transactionId: txId,
        timestamp: now,
        postings: kind == 'receivable'
            ? [
                LedgerPosting(
                  accountId: SystemAccountIds.receivable,
                  side: 'debit',
                  amount: principalAmount,
                ),
                LedgerPosting(
                  accountId: contraAccountId,
                  side: 'credit',
                  amount: principalAmount,
                ),
              ]
            : [
                LedgerPosting(
                  accountId: contraAccountId,
                  side: 'debit',
                  amount: principalAmount,
                ),
                LedgerPosting(
                  accountId: SystemAccountIds.debt,
                  side: 'credit',
                  amount: principalAmount,
                ),
              ],
      );

      await db.into(db.debts).insert(
            DebtsCompanion.insert(
              id: debtId,
              counterparty: cleanParty,
              kind: kind,
              principalAmount: principalAmount,
              remainingAmount: principalAmount,
              walletId: Value(effectiveWalletId),
              disbursementTxId: Value(txId),
              occurredAt: occurredAt,
              dueDate: Value(dueDate),
              note: Value(note.trim()),
              createdAt: now,
            ),
          );

      await _writeAudit(
        entityType: 'debt',
        entityId: debtId,
        action: 'create',
        summary:
            '$kind $principalAmount ($cleanParty, affectsWallet=$affectsWallet)',
      );
      return debtId;
    });
  }

  /// Updates an existing debt or receivable record and synchronizes ledger postings atomically.
  Future<void> updateDebt({
    required String debtId,
    required String counterparty,
    required int principalAmount,
    bool? affectsWallet,
    String? walletId,
    DateTime? occurredAt,
    DateTime? dueDate,
    bool clearDueDate = false,
    String note = '',
    bool allowNegativeBalance = false,
  }) async {
    final cleanParty = counterparty.trim();
    if (cleanParty.isEmpty) {
      throw const ValidationException('Nama pihak harus diisi.');
    }
    if (principalAmount <= 0) {
      throw const ValidationException('Nominal pokok harus > 0.');
    }

    await db.transaction(() async {
      final debt = await (db.select(db.debts)
            ..where((d) => d.id.equals(debtId)))
          .getSingleOrNull();
      if (debt == null || debt.status == 'cancelled') {
        throw const ValidationException('Data utang/piutang tidak ditemukan.');
      }

      final paidSoFar = debt.principalAmount - debt.remainingAmount;
      if (principalAmount < paidSoFar) {
        throw ValidationException(
          'Nominal pokok ($principalAmount) tidak boleh lebih kecil dari total yang sudah dibayar ($paidSoFar).',
        );
      }

      final useWallet = affectsWallet ?? (debt.walletId != null);
      final targetWalletId =
          useWallet ? (walletId?.trim() ?? debt.walletId) : null;
      if (useWallet && (targetWalletId == null || targetWalletId.isEmpty)) {
        throw const ValidationException('Pilih dompet terkait.');
      }

      if (targetWalletId != null) {
        final wallet = await (db.select(db.accounts)
              ..where((a) =>
                  a.id.equals(targetWalletId) & a.isSystem.equals(false)))
            .getSingleOrNull();
        if (wallet == null) {
          throw const ValidationException('Dompet tidak ditemukan.');
        }
      }

      final now = DateTime.now();
      final txId = debt.disbursementTxId;
      if (txId != null) {
        final oldEntries = await (db.select(db.ledgerEntries)
              ..where((e) => e.transactionId.equals(txId)))
            .get();
        final affectedIds = <String>{
          for (final e in oldEntries) e.accountId,
          if (targetWalletId != null) targetWalletId,
          SystemAccountIds.equityOpening,
          SystemAccountIds.debt,
          SystemAccountIds.receivable,
        };
        await (db.delete(db.ledgerEntries)
              ..where((e) => e.transactionId.equals(txId)))
            .go();
        await _syncCachedBalances(affectedIds);

        if (targetWalletId != null && debt.kind == 'receivable') {
          final freshWallet = await (db.select(db.accounts)
                ..where((a) => a.id.equals(targetWalletId)))
              .getSingle();
          await _checkNegativeAssetBalance(
            wallet: freshWallet,
            outflowAmount: principalAmount,
            allowNegativeBalance: allowNegativeBalance,
          );
        }

        final contraAccountId =
            targetWalletId ?? SystemAccountIds.equityOpening;
        final newPostings = debt.kind == 'receivable'
            ? [
                LedgerPosting(
                  accountId: SystemAccountIds.receivable,
                  side: 'debit',
                  amount: principalAmount,
                ),
                LedgerPosting(
                  accountId: contraAccountId,
                  side: 'credit',
                  amount: principalAmount,
                ),
              ]
            : [
                LedgerPosting(
                  accountId: contraAccountId,
                  side: 'debit',
                  amount: principalAmount,
                ),
                LedgerPosting(
                  accountId: SystemAccountIds.debt,
                  side: 'credit',
                  amount: principalAmount,
                ),
              ];

        await _postBalancedEntries(
          transactionId: txId,
          timestamp: now,
          postings: newPostings,
        );

        await (db.update(db.transactions)..where((t) => t.id.equals(txId)))
            .write(
          TransactionsCompanion(
            type: Value(useWallet ? 'debt_disbursement' : 'opening_balance'),
            amount: Value(principalAmount),
            description: Value(
              debt.kind == 'receivable'
                  ? (useWallet
                      ? 'Piutang ke $cleanParty'
                      : 'Piutang lama dari $cleanParty')
                  : (useWallet
                      ? 'Utang dari $cleanParty'
                      : 'Utang lama ke $cleanParty'),
            ),
            merchant: Value(cleanParty),
            occurredAt: Value(occurredAt ?? debt.occurredAt),
            primaryWalletId: Value(targetWalletId),
            updatedAt: Value(now),
          ),
        );
      }

      final newRemaining = principalAmount - paidSoFar;
      final newStatus = newRemaining == 0
          ? 'settled'
          : (paidSoFar > 0 ? 'partial' : 'open');

      await (db.update(db.debts)..where((d) => d.id.equals(debtId))).write(
        DebtsCompanion(
          counterparty: Value(cleanParty),
          principalAmount: Value(principalAmount),
          remainingAmount: Value(newRemaining),
          walletId: Value(targetWalletId),
          occurredAt: Value(occurredAt ?? debt.occurredAt),
          dueDate: clearDueDate
              ? const Value(null)
              : Value(dueDate ?? debt.dueDate),
          note: Value(note.trim()),
          status: Value(newStatus),
        ),
      );

      await _writeAudit(
        entityType: 'debt',
        entityId: debtId,
        action: 'update',
        summary: 'Edit $debtId -> $cleanParty $principalAmount',
      );
    });
  }

  /// Deletes/cancels a debt or receivable and voids its disbursement + all repayments atomically.
  Future<void> deleteDebt(String debtId) async {
    await db.transaction(() async {
      final debt = await (db.select(db.debts)
            ..where((d) => d.id.equals(debtId)))
          .getSingleOrNull();
      if (debt == null || debt.status == 'cancelled') return;

      final payments = await (db.select(db.debtPayments)
            ..where((p) => p.debtId.equals(debtId)))
          .get();
      for (final p in payments) {
        await _voidTransactionInTx(
          p.transactionId,
          reason: 'Hapus utang/piutang',
          skipDebtSync: true,
        );
      }
      await (db.delete(db.debtPayments)..where((p) => p.debtId.equals(debtId)))
          .go();

      if (debt.disbursementTxId != null) {
        await _voidTransactionInTx(
          debt.disbursementTxId!,
          reason: 'Hapus utang/piutang',
          skipDebtSync: true,
        );
      }

      await (db.update(db.debts)..where((d) => d.id.equals(debtId))).write(
        const DebtsCompanion(
          status: Value('cancelled'),
        ),
      );

      await _writeAudit(
        entityType: 'debt',
        entityId: debtId,
        action: 'delete',
        summary: 'Hapus ${debt.kind} (${debt.counterparty})',
      );
    });
  }

  /// Records partial or full repayment for a debt or receivable (FR-13).
  Future<String> recordDebtRepayment({
    required String debtId,
    required String walletId,
    required int principalPaid,
    int interestOrFeePaid = 0,
    DateTime? paidAt,
    bool allowNegativeBalance = false,
  }) async {
    if (principalPaid <= 0) {
      throw const ValidationException('Nominal pokok pelunasan harus > 0.');
    }
    if (interestOrFeePaid < 0) {
      throw const ValidationException('Bunga/denda tidak boleh negatif.');
    }

    return db.transaction(() async {
      final debt = await (db.select(db.debts)
            ..where((d) => d.id.equals(debtId)))
          .getSingleOrNull();
      if (debt == null) {
        throw const ValidationException('Data utang/piutang tidak ditemukan.');
      }
      if (principalPaid > debt.remainingAmount) {
        throw ValidationException(
          'Nominal pokok ($principalPaid) melebihi sisa (${debt.remainingAmount}).',
        );
      }

      final wallet = await (db.select(db.accounts)
            ..where((a) => a.id.equals(walletId) & a.isSystem.equals(false)))
          .getSingleOrNull();
      if (wallet == null) {
        throw const ValidationException('Dompet tidak ditemukan.');
      }

      final totalCashFlow = principalPaid + interestOrFeePaid;
      if (debt.kind == 'debt') {
        await _checkNegativeAssetBalance(
          wallet: wallet,
          outflowAmount: totalCashFlow,
          allowNegativeBalance: allowNegativeBalance,
        );
      }

      final txTime = paidAt ?? DateTime.now();
      final now = DateTime.now();
      final txId = _uuid.v4();

      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: txId,
              type: 'debt_repayment',
              amount: totalCashFlow,
              description: Value(
                debt.kind == 'receivable'
                    ? 'Pelunasan piutang dari ${debt.counterparty}'
                    : 'Bayar utang ke ${debt.counterparty}',
              ),
              merchant: Value(debt.counterparty),
              occurredAt: txTime,
              source: const Value('debt'),
              primaryWalletId: Value(walletId),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final postings = <LedgerPosting>[];
      if (debt.kind == 'receivable') {
        postings.add(
          LedgerPosting(
            accountId: walletId,
            side: 'debit',
            amount: totalCashFlow,
          ),
        );
        postings.add(
          LedgerPosting(
            accountId: SystemAccountIds.receivable,
            side: 'credit',
            amount: principalPaid,
          ),
        );
        if (interestOrFeePaid > 0) {
          postings.add(
            LedgerPosting(
              accountId: SystemAccountIds.incomeDefault,
              side: 'credit',
              amount: interestOrFeePaid,
            ),
          );
        }
      } else {
        postings.add(
          LedgerPosting(
            accountId: SystemAccountIds.debt,
            side: 'debit',
            amount: principalPaid,
          ),
        );
        if (interestOrFeePaid > 0) {
          postings.add(
            LedgerPosting(
              accountId: SystemAccountIds.expenseDefault,
              side: 'debit',
              amount: interestOrFeePaid,
            ),
          );
        }
        postings.add(
          LedgerPosting(
            accountId: walletId,
            side: 'credit',
            amount: totalCashFlow,
          ),
        );
      }

      await _postBalancedEntries(
        transactionId: txId,
        timestamp: now,
        postings: postings,
      );

      await db.into(db.debtPayments).insert(
            DebtPaymentsCompanion.insert(
              id: _uuid.v4(),
              debtId: debtId,
              transactionId: txId,
              principalPaid: principalPaid,
              interestOrFeePaid: Value(interestOrFeePaid),
              paidAt: txTime,
            ),
          );

      final newRemaining = debt.remainingAmount - principalPaid;
      final newStatus = newRemaining == 0 ? 'settled' : 'partial';
      await (db.update(db.debts)..where((d) => d.id.equals(debtId))).write(
        DebtsCompanion(
          remainingAmount: Value(newRemaining),
          status: Value(newStatus),
        ),
      );

      await _writeAudit(
        entityType: 'debt',
        entityId: debtId,
        action: 'update',
        summary: 'Pembayaran $principalPaid (bunga/biaya $interestOrFeePaid)',
      );
      return txId;
    });
  }

  /// Voids a posted transaction by reversing its ledger entries atomically (BR-06).
  Future<void> voidTransaction(
    String transactionId, {
    String reason = 'Dihapus pengguna',
  }) async {
    await db.transaction(() async {
      await _voidTransactionInTx(transactionId, reason: reason);
    });
  }

  Future<void> _voidTransactionInTx(
    String transactionId, {
    required String reason,
    bool skipDebtSync = false,
  }) async {
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(transactionId)))
        .getSingleOrNull();
    if (tx == null || tx.status == 'voided') return;

    final entries = await (db.select(db.ledgerEntries)
          ..where((e) => e.transactionId.equals(transactionId)))
        .get();

    final now = DateTime.now();
    if (entries.isNotEmpty) {
      final reversals = entries
          .map(
            (e) => LedgerPosting(
              accountId: e.accountId,
              side: e.side == 'debit' ? 'credit' : 'debit',
              amount: e.amount,
            ),
          )
          .toList();
      await _postBalancedEntries(
        transactionId: transactionId,
        timestamp: now,
        postings: reversals,
      );
    }

    await (db.update(db.transactions)..where((t) => t.id.equals(transactionId)))
        .write(
      TransactionsCompanion(
        status: const Value('voided'),
        updatedAt: Value(now),
      ),
    );

    if (!skipDebtSync) {
      if (tx.type == 'debt_repayment') {
        final payments = await (db.select(db.debtPayments)
              ..where((p) => p.transactionId.equals(transactionId)))
            .get();
        for (final p in payments) {
          final debt = await (db.select(db.debts)
                ..where((d) => d.id.equals(p.debtId)))
              .getSingleOrNull();
          if (debt != null && debt.status != 'cancelled') {
            final restored =
                (debt.remainingAmount + p.principalPaid).clamp(0, debt.principalAmount);
            final restoredStatus =
                restored >= debt.principalAmount ? 'open' : 'partial';
            await (db.update(db.debts)..where((d) => d.id.equals(debt.id))).write(
              DebtsCompanion(
                remainingAmount: Value(restored),
                status: Value(restoredStatus),
              ),
            );
          }
        }
        await (db.delete(db.debtPayments)
              ..where((p) => p.transactionId.equals(transactionId)))
            .go();
      } else if (tx.type == 'debt_disbursement' ||
          (tx.source == 'debt' && tx.type == 'opening_balance')) {
        final linkedDebts = await (db.select(db.debts)
              ..where((d) => d.disbursementTxId.equals(transactionId)))
            .get();
        for (final debt in linkedDebts) {
          final payments = await (db.select(db.debtPayments)
                ..where((p) => p.debtId.equals(debt.id)))
              .get();
          for (final p in payments) {
            await _voidTransactionInTx(
              p.transactionId,
              reason: reason,
              skipDebtSync: true,
            );
          }
          await (db.delete(db.debtPayments)..where((p) => p.debtId.equals(debt.id)))
              .go();
          await (db.update(db.debts)..where((d) => d.id.equals(debt.id))).write(
            const DebtsCompanion(status: Value('cancelled')),
          );
        }
      }
    }

    await _writeAudit(
      entityType: 'transaction',
      entityId: transactionId,
      action: 'void',
      summary: 'Void transaksi ${tx.type} ${tx.amount}: $reason',
    );
  }

  /// Edits an existing simple income/expense/transfer transaction atomically,
  /// updating its ledger entries and affected wallet balances (FR-03).
  Future<void> updateSimpleTransaction({
    required String transactionId,
    required int amount,
    required String walletId,
    String? destinationWalletId,
    String? categoryId,
    required DateTime occurredAt,
    String description = '',
    String? merchant,
    bool allowNegativeBalance = false,
  }) async {
    if (amount <= 0) {
      throw const ValidationException('Nominal harus lebih besar dari nol.');
    }

    await db.transaction(() async {
      final existing = await (db.select(db.transactions)
            ..where((t) => t.id.equals(transactionId)))
          .getSingleOrNull();
      if (existing == null || existing.status == 'voided') {
        throw const ValidationException('Transaksi tidak ditemukan atau sudah dihapus.');
      }

      // 1. Reverse existing ledger entries
      final oldEntries = await (db.select(db.ledgerEntries)
            ..where((e) => e.transactionId.equals(transactionId)))
          .get();
      final affectedIds = <String>{
        for (final e in oldEntries) e.accountId,
        walletId,
        if (destinationWalletId != null) destinationWalletId,
      };
      await (db.delete(db.ledgerEntries)
            ..where((e) => e.transactionId.equals(transactionId)))
          .go();
      await _syncCachedBalances(affectedIds);

      final now = DateTime.now();
      final newPostings = <LedgerPosting>[];

      if (existing.type == 'expense') {
        final catId = categoryId ?? existing.primaryCategoryId;
        if (catId == null) {
          throw const ValidationException('Kategori wajib diisi.');
        }
        final wallet = await (db.select(db.accounts)
              ..where((a) => a.id.equals(walletId)))
            .getSingle();
        await _checkNegativeAssetBalance(
          wallet: wallet,
          outflowAmount: amount,
          allowNegativeBalance: allowNegativeBalance,
        );
        final expLedger = await _resolveCategoryLedgerAccount(catId);
        newPostings.addAll([
          LedgerPosting(accountId: expLedger, side: 'debit', amount: amount),
          LedgerPosting(accountId: walletId, side: 'credit', amount: amount),
        ]);
        await (db.delete(db.transactionSplits)
              ..where((s) => s.transactionId.equals(transactionId)))
            .go();
        await db.into(db.transactionSplits).insert(
              TransactionSplitsCompanion.insert(
                id: _uuid.v4(),
                transactionId: transactionId,
                categoryId: catId,
                amount: amount,
                description: Value(description.trim()),
              ),
            );
      } else if (existing.type == 'income') {
        final catId = categoryId ?? existing.primaryCategoryId;
        if (catId == null) {
          throw const ValidationException('Kategori wajib diisi.');
        }
        final incLedger = await _resolveCategoryLedgerAccount(catId);
        newPostings.addAll([
          LedgerPosting(accountId: walletId, side: 'debit', amount: amount),
          LedgerPosting(accountId: incLedger, side: 'credit', amount: amount),
        ]);
        await (db.delete(db.transactionSplits)
              ..where((s) => s.transactionId.equals(transactionId)))
            .go();
        await db.into(db.transactionSplits).insert(
              TransactionSplitsCompanion.insert(
                id: _uuid.v4(),
                transactionId: transactionId,
                categoryId: catId,
                amount: amount,
                description: Value(description.trim()),
              ),
            );
      } else if (existing.type == 'transfer') {
        final dstId = destinationWalletId ?? existing.destinationWalletId;
        if (dstId == null || dstId == walletId) {
          throw const ValidationException('Dompet tujuan transfer tidak valid.');
        }
        final srcWallet = await (db.select(db.accounts)
              ..where((a) => a.id.equals(walletId)))
            .getSingle();
        await _checkNegativeAssetBalance(
          wallet: srcWallet,
          outflowAmount: amount,
          allowNegativeBalance: allowNegativeBalance,
        );
        newPostings.addAll([
          LedgerPosting(accountId: dstId, side: 'debit', amount: amount),
          LedgerPosting(accountId: walletId, side: 'credit', amount: amount),
        ]);
      } else {
        throw ValidationException(
          'Jenis transaksi ${existing.type} tidak mendukung edit langsung.',
        );
      }

      await (db.update(db.transactions)
            ..where((t) => t.id.equals(transactionId)))
          .write(
        TransactionsCompanion(
          amount: Value(amount),
          primaryWalletId: Value(walletId),
          destinationWalletId: Value(destinationWalletId ?? existing.destinationWalletId),
          primaryCategoryId: Value(categoryId ?? existing.primaryCategoryId),
          occurredAt: Value(occurredAt),
          description: Value(description.trim()),
          merchant: Value(merchant?.trim()),
          updatedAt: Value(now),
        ),
      );

      await _postBalancedEntries(
        transactionId: transactionId,
        timestamp: now,
        postings: newPostings,
      );

      await _writeAudit(
        entityType: 'transaction',
        entityId: transactionId,
        action: 'update',
        summary: 'Edit transaksi ${existing.amount} -> $amount',
      );
    });
  }

  Future<void> _attachTags(String txId, List<String> tagNames) async {
    for (final raw in tagNames) {
      final clean = raw.trim().toLowerCase();
      if (clean.isEmpty) continue;
      var tag = await (db.select(db.tags)..where((t) => t.name.equals(clean)))
          .getSingleOrNull();
      if (tag == null) {
        final tagId = _uuid.v4();
        await db.into(db.tags).insert(
              TagsCompanion.insert(id: tagId, name: clean),
            );
        tag = await (db.select(db.tags)..where((t) => t.id.equals(tagId)))
            .getSingle();
      }
      await db.into(db.transactionTags).insertOnConflictUpdate(
            TransactionTagsCompanion.insert(
              transactionId: txId,
              tagId: tag.id,
            ),
          );
    }
  }

  /// Diagnostics: verifies every transaction's debits == credits AND cachedBalance == ledger sum (NFR-07).
  Future<({bool isBalanced, int checkedTransactions, int checkedAccounts})>
      verifyLedgerIntegrity() async {
    final allEntries = await db.select(db.ledgerEntries).get();
    final byTx = <String, ({int debit, int credit})>{};
    for (final e in allEntries) {
      final prev = byTx[e.transactionId] ?? (debit: 0, credit: 0);
      if (e.side == 'debit') {
        byTx[e.transactionId] = (debit: prev.debit + e.amount, credit: prev.credit);
      } else {
        byTx[e.transactionId] = (debit: prev.debit, credit: prev.credit + e.amount);
      }
    }

    for (final entry in byTx.entries) {
      if (entry.value.debit != entry.value.credit) {
        return (
          isBalanced: false,
          checkedTransactions: byTx.length,
          checkedAccounts: 0,
        );
      }
    }

    final allAccounts = await db.select(db.accounts).get();
    for (final acc in allAccounts) {
      final computed = await computeAccountBalance(acc.id);
      if (computed != acc.cachedBalance) {
        return (
          isBalanced: false,
          checkedTransactions: byTx.length,
          checkedAccounts: allAccounts.length,
        );
      }
    }

    return (
      isBalanced: true,
      checkedTransactions: byTx.length,
      checkedAccounts: allAccounts.length,
    );
  }
}
