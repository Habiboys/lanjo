import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/ledger_engine.dart';
import '../../../core/errors/arus_exception.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/utils/date_utils.dart';

class BillOccurrenceView {
  const BillOccurrenceView({
    required this.bill,
    required this.occurrence,
    required this.category,
    required this.wallet,
  });

  final BillRecord bill;
  final BillOccurrenceRecord occurrence;
  final CategoryRecord? category;
  final AccountRecord? wallet;

  int get remainingAmount =>
      (occurrence.expectedAmount - occurrence.paidAmount).clamp(0, 1 << 60);
}

/// Recurring bill, salary, and subscription manager (FR-10, BR-08).
class BillService {
  BillService(this.db, this._ledger, this._notifications, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final AppDatabase db;
  final LedgerEngine _ledger;
  final LocalNotificationService _notifications;
  final Uuid _uuid;

  Future<String> createBill({
    required String name,
    required String kind, // 'expense' or 'income'
    required int estimatedAmount,
    required String categoryId,
    required String walletId,
    required String frequency, // daily, weekly, monthly, yearly
    required DateTime firstDueDate,
    DateTime? endDate,
    bool isSubscription = false,
    String reminderOffsets = '7,3,1',
  }) async {
    if (name.trim().isEmpty) {
      throw const ValidationException('Nama tagihan tidak boleh kosong.');
    }
    if (estimatedAmount <= 0) {
      throw const ValidationException('Nominal estimasi harus > 0.');
    }

    final billId = _uuid.v4();
    final occId = _uuid.v4();
    final now = DateTime.now();

    await db.transaction(() async {
      await db.into(db.bills).insert(
            BillsCompanion.insert(
              id: billId,
              name: name.trim(),
              kind: Value(kind),
              estimatedAmount: estimatedAmount,
              categoryId: categoryId,
              walletId: walletId,
              frequency: frequency,
              dueDayOfMonth: Value(firstDueDate.day),
              startDate: firstDueDate,
              endDate: Value(endDate),
              isSubscription: Value(isSubscription),
              reminderOffsets: Value(reminderOffsets),
              createdAt: now,
            ),
          );

      await db.into(db.billOccurrences).insert(
            BillOccurrencesCompanion.insert(
              id: occId,
              billId: billId,
              dueDate: firstDueDate,
              expectedAmount: estimatedAmount,
              status: Value(
                firstDueDate.isBefore(DateTime(now.year, now.month, now.day))
                    ? 'overdue'
                    : 'upcoming',
              ),
              updatedAt: now,
            ),
          );
    });

    await _scheduleBillReminders(
      occurrenceId: occId,
      billName: name.trim(),
      kind: kind,
      dueDate: firstDueDate,
      offsetsCsv: reminderOffsets,
    );
    return billId;
  }

  Future<void> updateBill({
    required String billId,
    required String name,
    required int estimatedAmount,
    required String categoryId,
    required String walletId,
    required String frequency,
    required DateTime dueDate,
    required bool isSubscription,
  }) async {
    if (name.trim().isEmpty) {
      throw const ValidationException('Nama tagihan tidak boleh kosong.');
    }
    if (estimatedAmount <= 0) {
      throw const ValidationException('Nominal estimasi harus > 0.');
    }

    late String billKind;
    late String offsetsCsv;
    String? activeOccId;

    await db.transaction(() async {
      final bill = await (db.select(db.bills)..where((b) => b.id.equals(billId)))
          .getSingleOrNull();
      if (bill == null) {
        throw const ValidationException('Tagihan tidak ditemukan.');
      }
      billKind = bill.kind;
      offsetsCsv = bill.reminderOffsets;

      await (db.update(db.bills)..where((b) => b.id.equals(billId))).write(
        BillsCompanion(
          name: Value(name.trim()),
          estimatedAmount: Value(estimatedAmount),
          categoryId: Value(categoryId),
          walletId: Value(walletId),
          frequency: Value(frequency),
          dueDayOfMonth: Value(dueDate.day),
          isSubscription: Value(isSubscription),
        ),
      );

      final occs = await (db.select(db.billOccurrences)
            ..where((o) =>
                o.billId.equals(billId) &
                o.status.isIn(['upcoming', 'unpaid', 'overdue']))
            ..orderBy([(o) => OrderingTerm.asc(o.dueDate)]))
          .get();
      if (occs.isNotEmpty) {
        final occ = occs.first;
        activeOccId = occ.id;
        await (db.update(db.billOccurrences)
              ..where((o) => o.id.equals(occ.id)))
            .write(
          BillOccurrencesCompanion(
            dueDate: Value(dueDate),
            expectedAmount: Value(estimatedAmount),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });

    if (activeOccId != null) {
      await _notifications.cancelForReference(activeOccId!);
      await _scheduleBillReminders(
        occurrenceId: activeOccId!,
        billName: name.trim(),
        kind: billKind,
        dueDate: dueDate,
        offsetsCsv: offsetsCsv,
      );
    }
  }

  /// Confirms payment (full or partial, with optional adjusted actual amount),
  /// posts the actual transaction, and schedules the next unique occurrence (FR-10).
  Future<String> confirmPayment({
    required String occurrenceId,
    required int actualAmount,
    String? walletIdOverride,
    DateTime? paidAt,
    bool allowNegativeBalance = false,
  }) async {
    if (actualAmount <= 0) {
      throw const ValidationException('Nominal pembayaran harus > 0.');
    }

    late String txId;
    late String billId;
    DateTime? nextDue;
    late String billName;
    late String billKind;
    late String offsetsCsv;
    late int estimatedAmount;
    String? nextOccId;

    await db.transaction(() async {
      final occ = await (db.select(db.billOccurrences)
            ..where((o) => o.id.equals(occurrenceId)))
          .getSingleOrNull();
      if (occ == null) {
        throw const ValidationException('Jadwal tagihan tidak ditemukan.');
      }
      if (occ.status == 'paid' || occ.status == 'cancelled') {
        throw const ValidationException('Tagihan ini sudah lunas atau dibatalkan.');
      }

      final bill = await (db.select(db.bills)
            ..where((b) => b.id.equals(occ.billId)))
          .getSingle();
      billId = bill.id;
      billName = bill.name;
      billKind = bill.kind;
      offsetsCsv = bill.reminderOffsets;
      estimatedAmount = bill.estimatedAmount;

      final targetWalletId = walletIdOverride ?? bill.walletId;
      final paymentTime = paidAt ?? DateTime.now();

      if (bill.kind == 'income') {
        txId = await _ledger.recordIncome(
          walletId: targetWalletId,
          categoryId: bill.categoryId,
          amount: actualAmount,
          occurredAt: paymentTime,
          description: bill.name,
          source: 'bill',
        );
      } else {
        txId = await _ledger.recordExpense(
          walletId: targetWalletId,
          amount: actualAmount,
          splits: [
            CategorySplitInput(
              categoryId: bill.categoryId,
              amount: actualAmount,
              description: bill.name,
            ),
          ],
          occurredAt: paymentTime,
          description: bill.name,
          source: 'bill',
          allowNegativeBalance: allowNegativeBalance,
        );
      }

      await db.into(db.billPayments).insert(
            BillPaymentsCompanion.insert(
              id: _uuid.v4(),
              occurrenceId: occurrenceId,
              transactionId: txId,
              amount: actualAmount,
              paidAt: paymentTime,
            ),
          );

      final newPaid = occ.paidAmount + actualAmount;
      final isFullyPaid = newPaid >= occ.expectedAmount;
      final newStatus = isFullyPaid ? 'paid' : 'unpaid';

      await (db.update(db.billOccurrences)
            ..where((o) => o.id.equals(occurrenceId)))
          .write(
        BillOccurrencesCompanion(
          paidAmount: Value(newPaid),
          status: Value(newStatus),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (isFullyPaid && bill.isActive) {
        final candidateNext = ArusDateUtils.nextDueDate(
          occ.dueDate,
          bill.frequency,
          preferredDayOfMonth: bill.dueDayOfMonth,
        );
        if (bill.endDate == null || !candidateNext.isAfter(bill.endDate!)) {
          // Ensure no duplicate occurrence exists for the same bill & due date (BR-08)
          final dup = await (db.select(db.billOccurrences)
                ..where((o) =>
                    o.billId.equals(billId) &
                    o.dueDate.equals(candidateNext)))
              .getSingleOrNull();
          if (dup == null) {
            nextOccId = _uuid.v4();
            nextDue = candidateNext;
            await db.into(db.billOccurrences).insert(
                  BillOccurrencesCompanion.insert(
                    id: nextOccId!,
                    billId: billId,
                    dueDate: candidateNext,
                    expectedAmount: estimatedAmount,
                    status: const Value('upcoming'),
                    updatedAt: DateTime.now(),
                  ),
                );
          }
        }
      }
    });

    await _notifications.cancelForReference(occurrenceId);
    if (nextOccId != null && nextDue != null) {
      await _scheduleBillReminders(
        occurrenceId: nextOccId!,
        billName: billName,
        kind: billKind,
        dueDate: nextDue!,
        offsetsCsv: offsetsCsv,
      );
    }
    return txId;
  }

  Future<void> skipOccurrence(String occurrenceId) async {
    final occ = await (db.select(db.billOccurrences)
          ..where((o) => o.id.equals(occurrenceId)))
        .getSingleOrNull();
    if (occ == null) return;
    final bill = await (db.select(db.bills)
          ..where((b) => b.id.equals(occ.billId)))
        .getSingle();

    await db.transaction(() async {
      await (db.update(db.billOccurrences)
            ..where((o) => o.id.equals(occurrenceId)))
          .write(
        BillOccurrencesCompanion(
          status: const Value('skipped'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (bill.isActive) {
        final next = ArusDateUtils.nextDueDate(
          occ.dueDate,
          bill.frequency,
          preferredDayOfMonth: bill.dueDayOfMonth,
        );
        final dup = await (db.select(db.billOccurrences)
              ..where((o) => o.billId.equals(bill.id) & o.dueDate.equals(next)))
            .getSingleOrNull();
        if (dup == null) {
          await db.into(db.billOccurrences).insert(
                BillOccurrencesCompanion.insert(
                  id: _uuid.v4(),
                  billId: bill.id,
                  dueDate: next,
                  expectedAmount: bill.estimatedAmount,
                  status: const Value('upcoming'),
                  updatedAt: DateTime.now(),
                ),
              );
        }
      }
    });
    await _notifications.cancelForReference(occurrenceId);
  }

  Future<void> cancelBill(String billId) async {
    final occs = await (db.select(db.billOccurrences)
          ..where((o) =>
              o.billId.equals(billId) &
              o.status.isIn(['upcoming', 'unpaid', 'overdue'])))
        .get();
    await db.transaction(() async {
      await (db.update(db.bills)..where((b) => b.id.equals(billId)))
          .write(const BillsCompanion(isActive: Value(false)));
      await (db.update(db.billOccurrences)
            ..where((o) =>
                o.billId.equals(billId) &
                o.status.isIn(['upcoming', 'unpaid', 'overdue'])))
          .write(
        BillOccurrencesCompanion(
          status: const Value('cancelled'),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
    for (final o in occs) {
      await _notifications.cancelForReference(o.id);
    }
  }

  Future<List<BillOccurrenceView>> getUpcomingAndActiveOccurrences({
    String? kind,
  }) async {
    final billsQuery = db.select(db.bills)
      ..where((b) {
        final active = b.isActive.equals(true);
        return kind == null ? active : active & b.kind.equals(kind);
      });
    final bills = await billsQuery.get();
    if (bills.isEmpty) return const [];
    final billMap = {for (final b in bills) b.id: b};

    final occs = await (db.select(db.billOccurrences)
          ..where((o) =>
              o.billId.isIn(billMap.keys.toList()) &
              o.status.isIn(['upcoming', 'unpaid', 'overdue']))
          ..orderBy([(o) => OrderingTerm.asc(o.dueDate)]))
        .get();

    final cats = await db.select(db.categories).get();
    final catMap = {for (final c in cats) c.id: c};
    final wallets = await db.select(db.accounts).get();
    final walletMap = {for (final w in wallets) w.id: w};

    return occs
        .map(
          (o) => BillOccurrenceView(
            bill: billMap[o.billId]!,
            occurrence: o,
            category: catMap[billMap[o.billId]!.categoryId],
            wallet: walletMap[billMap[o.billId]!.walletId],
          ),
        )
        .toList();
  }

  Future<({int monthlyTotal, int yearlyTotal, List<BillRecord> subscriptions})>
      getSubscriptionSummary() async {
    final subs = await (db.select(db.bills)
          ..where((b) =>
              b.isActive.equals(true) & b.isSubscription.equals(true)))
        .get();

    var monthly = 0;
    for (final s in subs) {
      monthly += switch (s.frequency) {
        'daily' => s.estimatedAmount * 30,
        'weekly' => s.estimatedAmount * 4,
        'yearly' => (s.estimatedAmount / 12).round(),
        _ => s.estimatedAmount,
      };
    }
    return (
      monthlyTotal: monthly,
      yearlyTotal: monthly * 12,
      subscriptions: subs,
    );
  }

  Future<void> _scheduleBillReminders({
    required String occurrenceId,
    required String billName,
    required String kind,
    required DateTime dueDate,
    required String offsetsCsv,
  }) async {
    final isIncome = kind == 'income';
    final offsets = offsetsCsv
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>();
    for (final daysBefore in offsets) {
      final remindAt = DateTime(
        dueDate.year,
        dueDate.month,
        dueDate.day,
        9,
        0,
      ).subtract(Duration(days: daysBefore));
      if (remindAt.isAfter(DateTime.now())) {
        await _notifications.scheduleReminder(
          kind: isIncome ? 'income_schedule' : 'bill',
          title: isIncome
              ? 'Pengingat Gajian: $billName'
              : 'Pengingat Tagihan: $billName',
          body: daysBefore == 0
              ? (isIncome
                  ? 'Perkiraan gaji masuk hari ini.'
                  : 'Jatuh tempo hari ini.')
              : (isIncome
                  ? 'Perkiraan gaji masuk $daysBefore hari lagi.'
                  : 'Jatuh tempo $daysBefore hari lagi.'),
          scheduledAt: remindAt,
          deepLink: isIncome ? '/plans/salary-day' : '/plans/bills',
          referenceId: occurrenceId,
        );
      }
    }
  }
}
