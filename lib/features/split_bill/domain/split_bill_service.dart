import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/ledger_engine.dart';
import '../../../core/errors/arus_exception.dart';
import '../../../core/money/money_formatter.dart';

class SplitParticipantInput {
  const SplitParticipantInput({
    required this.name,
    required this.isSelf,
    required this.shareAmount,
  });

  final String name;
  final bool isSelf;
  final int shareAmount;
}

/// Split Bill engine (FR-14):
/// - Records payer's own portion as Expense
/// - Records friends' portions as Receivables (not personal consumption!)
/// - Ensures sum of shares == totalAmount deterministically
/// - Cancellation voids all linked records consistently.
class SplitBillService {
  SplitBillService(this.db, this._ledger, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final AppDatabase db;
  final LedgerEngine _ledger;
  final Uuid _uuid;

  Future<String> createSplitBill({
    required String title,
    required int totalAmount,
    int taxAmount = 0,
    int serviceAmount = 0,
    required String payerWalletId,
    required String categoryId,
    required String splitMode, // equal, item, exact, percentage
    required List<SplitParticipantInput> participants,
    required DateTime occurredAt,
    bool allowNegativeBalance = false,
  }) async {
    if (title.trim().isEmpty) {
      throw const ValidationException('Judul split bill wajib diisi.');
    }
    if (totalAmount <= 0) {
      throw const ValidationException('Total tagihan harus > 0.');
    }
    if (participants.isEmpty) {
      throw const ValidationException('Minimal satu peserta harus ada.');
    }

    final sumShares = participants.fold<int>(0, (s, p) => s + p.shareAmount);
    if (sumShares != totalAmount) {
      throw ValidationException(
        'Jumlah bagian peserta ($sumShares) harus sama dengan total tagihan ($totalAmount).',
      );
    }

    final splitBillId = _uuid.v4();
    final now = DateTime.now();

    await db.transaction(() async {
      final selfPart = participants.where((p) => p.isSelf).fold<int>(
            0,
            (s, p) => s + p.shareAmount,
          );
      String? selfExpenseTxId;
      if (selfPart > 0) {
        selfExpenseTxId = await _ledger.recordExpense(
          walletId: payerWalletId,
          amount: selfPart,
          splits: [
            CategorySplitInput(
              categoryId: categoryId,
              amount: selfPart,
              description: 'Split bill: ${title.trim()}',
            ),
          ],
          occurredAt: occurredAt,
          description: 'Split bill: ${title.trim()}',
          source: 'split_bill',
          allowNegativeBalance: allowNegativeBalance,
        );
      }

      await db.into(db.splitBills).insert(
            SplitBillsCompanion.insert(
              id: splitBillId,
              title: title.trim(),
              totalAmount: totalAmount,
              taxAmount: Value(taxAmount),
              serviceAmount: Value(serviceAmount),
              payerWalletId: payerWalletId,
              categoryId: categoryId,
              transactionId: Value(selfExpenseTxId),
              splitMode: Value(splitMode),
              occurredAt: occurredAt,
              createdAt: now,
            ),
          );

      for (final p in participants) {
        String? debtId;
        if (!p.isSelf && p.shareAmount > 0) {
          debtId = await _ledger.recordDebt(
            counterparty: p.name.trim(),
            kind: 'receivable',
            principalAmount: p.shareAmount,
            walletId: payerWalletId,
            occurredAt: occurredAt,
            note: 'Split bill: ${title.trim()}',
            allowNegativeBalance: allowNegativeBalance,
          );
        }
        await db.into(db.splitBillMembers).insert(
              SplitBillMembersCompanion.insert(
                id: _uuid.v4(),
                splitBillId: splitBillId,
                name: p.name.trim(),
                isSelf: Value(p.isSelf),
                shareAmount: p.shareAmount,
                paidAmount: Value(p.isSelf ? p.shareAmount : 0),
                debtId: Value(debtId),
                isSettled: Value(p.isSelf),
              ),
            );
      }
    });

    return splitBillId;
  }

  Future<void> markMemberPaid({
    required String memberId,
    required String walletId,
    int? amountOverride,
  }) async {
    await db.transaction(() async {
      final member = await (db.select(db.splitBillMembers)
            ..where((m) => m.id.equals(memberId)))
          .getSingleOrNull();
      if (member == null || member.isSelf || member.isSettled) return;

      final remaining = member.shareAmount - member.paidAmount;
      final payAmt = amountOverride ?? remaining;
      if (payAmt <= 0 || payAmt > remaining) {
        throw const ValidationException('Nominal pembayaran peserta tidak valid.');
      }

      if (member.debtId != null) {
        await _ledger.recordDebtRepayment(
          debtId: member.debtId!,
          walletId: walletId,
          principalPaid: payAmt,
        );
      }

      final newPaid = member.paidAmount + payAmt;
      await (db.update(db.splitBillMembers)
            ..where((m) => m.id.equals(memberId)))
          .write(
        SplitBillMembersCompanion(
          paidAmount: Value(newPaid),
          isSettled: Value(newPaid >= member.shareAmount),
        ),
      );

      final siblings = await (db.select(db.splitBillMembers)
            ..where((m) => m.splitBillId.equals(member.splitBillId)))
          .get();
      if (siblings.every((s) => s.isSettled)) {
        await (db.update(db.splitBills)
              ..where((b) => b.id.equals(member.splitBillId)))
            .write(const SplitBillsCompanion(status: Value('settled')));
      }
    });
  }

  /// Cancels a Split Bill and voids all related transactions & receivables atomically (FR-14).
  Future<void> cancelSplitBill(String splitBillId) async {
    await db.transaction(() async {
      final bill = await (db.select(db.splitBills)
            ..where((b) => b.id.equals(splitBillId)))
          .getSingleOrNull();
      if (bill == null || bill.status == 'cancelled') return;

      if (bill.transactionId != null) {
        await _ledger.voidTransaction(
          bill.transactionId!,
          reason: 'Pembatalan split bill ${bill.title}',
        );
      }

      final members = await (db.select(db.splitBillMembers)
            ..where((m) => m.splitBillId.equals(splitBillId)))
          .get();
      for (final m in members) {
        if (m.debtId != null) {
          final debt = await (db.select(db.debts)
                ..where((d) => d.id.equals(m.debtId!)))
              .getSingleOrNull();
          if (debt != null) {
            if (debt.disbursementTxId != null) {
              await _ledger.voidTransaction(
                debt.disbursementTxId!,
                reason: 'Pembatalan split bill ${bill.title}',
              );
            }
            final payments = await (db.select(db.debtPayments)
                  ..where((p) => p.debtId.equals(debt.id)))
                .get();
            for (final p in payments) {
              await _ledger.voidTransaction(
                p.transactionId,
                reason: 'Pembatalan split bill ${bill.title}',
              );
            }
            await (db.update(db.debts)..where((d) => d.id.equals(debt.id)))
                .write(const DebtsCompanion(status: Value('cancelled')));
          }
        }
      }

      await (db.update(db.splitBills)..where((b) => b.id.equals(splitBillId)))
          .write(const SplitBillsCompanion(status: Value('cancelled')));
    });
  }

  Future<void> updateSplitBillTitle({
    required String splitBillId,
    required String title,
  }) async {
    final clean = title.trim();
    if (clean.isEmpty) {
      throw const ValidationException('Judul split bill wajib diisi.');
    }
    await db.transaction(() async {
      final bill = await (db.select(db.splitBills)
            ..where((b) => b.id.equals(splitBillId)))
          .getSingleOrNull();
      if (bill == null) return;

      await (db.update(db.splitBills)..where((b) => b.id.equals(splitBillId)))
          .write(SplitBillsCompanion(title: Value(clean)));

      if (bill.transactionId != null) {
        await (db.update(db.transactions)
              ..where((t) => t.id.equals(bill.transactionId!)))
            .write(
          TransactionsCompanion(
            description: Value('Split bill: $clean'),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });
  }

  String buildShareText(SplitBillRecord bill, List<SplitBillMemberRecord> members) {
    final buf = StringBuffer()
      ..writeln('*Split Bill: ${bill.title}*')
      ..writeln('Total: ${MoneyFormatter.format(bill.totalAmount)}')
      ..writeln('');
    for (final m in members) {
      final status = m.isSelf
          ? '(Saya)'
          : (m.isSettled ? '✅ Lunas' : '⏳ Belum lunas');
      buf.writeln('• ${m.name}: ${MoneyFormatter.format(m.shareAmount)} $status');
    }
    buf.writeln('\nDicatat via Lanjo');
    return buf.toString();
  }
}
