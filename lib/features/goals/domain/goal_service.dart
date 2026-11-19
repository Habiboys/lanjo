import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/ledger_engine.dart';
import '../../../core/errors/arus_exception.dart';

/// Saving Goals & virtual/real fund allocation manager (FR-11).
class GoalService {
  GoalService(this.db, this._ledger, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase db;
  final LedgerEngine _ledger;
  final Uuid _uuid;

  Future<String> createGoal({
    required String name,
    required int targetAmount,
    DateTime? targetDate,
    String? sourceWalletId,
    String icon = 'savings',
    int priority = 1,
  }) async {
    if (name.trim().isEmpty) {
      throw const ValidationException('Nama target tabungan wajib diisi.');
    }
    if (targetAmount <= 0) {
      throw const ValidationException('Nominal target harus > 0.');
    }
    final id = _uuid.v4();
    await db.into(db.goals).insert(
          GoalsCompanion.insert(
            id: id,
            name: name.trim(),
            targetAmount: targetAmount,
            targetDate: Value(targetDate),
            sourceWalletId: Value(sourceWalletId),
            icon: Value(icon),
            priority: Value(priority),
            createdAt: DateTime.now(),
          ),
        );
    return id;
  }

  Future<void> updateGoal({
    required String goalId,
    required String name,
    required int targetAmount,
    DateTime? targetDate,
    bool clearTargetDate = false,
  }) async {
    if (name.trim().isEmpty) {
      throw const ValidationException('Nama target tabungan wajib diisi.');
    }
    if (targetAmount <= 0) {
      throw const ValidationException('Nominal target harus > 0.');
    }
    final existing = await (db.select(db.goals)
          ..where((g) => g.id.equals(goalId)))
        .getSingleOrNull();
    if (existing == null) return;

    await (db.update(db.goals)..where((g) => g.id.equals(goalId))).write(
      GoalsCompanion(
        name: Value(name.trim()),
        targetAmount: Value(targetAmount),
        targetDate: clearTargetDate ? const Value(null) : Value(targetDate),
        status: Value(
          existing.currentAmount >= targetAmount ? 'completed' : 'active',
        ),
      ),
    );
  }

  Future<void> deleteGoal(String goalId) async {
    await db.transaction(() async {
      await (db.delete(db.fundAllocations)
            ..where(
                (a) => a.targetType.equals('goal') & a.targetId.equals(goalId)))
          .go();
      await (db.delete(db.goalContributions)
            ..where((c) => c.goalId.equals(goalId)))
          .go();
      await (db.delete(db.goals)..where((g) => g.id.equals(goalId))).go();
    });
  }

  /// Contributes to a saving goal either via virtual allocation (keeps wallet balance
  /// untouched while locking funds in [FundAllocations]) OR via real wallet transfer.
  Future<void> contribute({
    required String goalId,
    required int amount,
    required String fromWalletId,
    String? savingsWalletId,
    bool isVirtual = true,
    String note = '',
  }) async {
    if (amount <= 0) {
      throw const ValidationException('Nominal kontribusi harus > 0.');
    }

    await db.transaction(() async {
      final goal = await (db.select(db.goals)..where((g) => g.id.equals(goalId)))
          .getSingleOrNull();
      if (goal == null) {
        throw const ValidationException('Target tabungan tidak ditemukan.');
      }

      if (isVirtual) {
        // Ensure virtual allocations in fromWalletId don't exceed wallet balance (FR-11)
        final walletBalance = await _ledger.computeAccountBalance(fromWalletId);
        final existingAllocs = await (db.select(db.fundAllocations)
              ..where((a) => a.walletId.equals(fromWalletId)))
            .get();
        final alreadyAllocated =
            existingAllocs.fold<int>(0, (s, e) => s + e.amount);
        if (alreadyAllocated + amount > walletBalance) {
          throw ValidationException(
            'Dana bebas dompet tidak mencukupi untuk alokasi virtual ini '
            '(tersisa ${walletBalance - alreadyAllocated}).',
          );
        }

        final existingForGoal = existingAllocs
            .where((a) => a.targetType == 'goal' && a.targetId == goalId)
            .firstOrNull;
        if (existingForGoal == null) {
          await db.into(db.fundAllocations).insert(
                FundAllocationsCompanion.insert(
                  id: _uuid.v4(),
                  walletId: fromWalletId,
                  targetType: 'goal',
                  targetId: goalId,
                  amount: amount,
                  updatedAt: DateTime.now(),
                ),
              );
        } else {
          await (db.update(db.fundAllocations)
                ..where((a) => a.id.equals(existingForGoal.id)))
              .write(
            FundAllocationsCompanion(
              amount: Value(existingForGoal.amount + amount),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }

        await db.into(db.goalContributions).insert(
              GoalContributionsCompanion.insert(
                id: _uuid.v4(),
                goalId: goalId,
                amount: amount,
                isVirtual: const Value(true),
                note: Value(note.trim()),
                createdAt: DateTime.now(),
              ),
            );
      } else {
        final dstWallet = savingsWalletId ?? goal.sourceWalletId;
        if (dstWallet == null || dstWallet == fromWalletId) {
          throw const ValidationException(
            'Pilih dompet tabungan tujuan yang berbeda dari dompet sumber.',
          );
        }
        final txId = await _ledger.recordTransfer(
          sourceWalletId: fromWalletId,
          destinationWalletId: dstWallet,
          amount: amount,
          occurredAt: DateTime.now(),
          description: 'Tabungan: ${goal.name}',
          source: 'goal',
        );
        await db.into(db.goalContributions).insert(
              GoalContributionsCompanion.insert(
                id: _uuid.v4(),
                goalId: goalId,
                transactionId: Value(txId),
                amount: amount,
                isVirtual: const Value(false),
                note: Value(note.trim()),
                createdAt: DateTime.now(),
              ),
            );
      }

      final newAmount = goal.currentAmount + amount;
      await (db.update(db.goals)..where((g) => g.id.equals(goalId))).write(
        GoalsCompanion(
          currentAmount: Value(newAmount),
          status: Value(
            newAmount >= goal.targetAmount ? 'completed' : 'active',
          ),
        ),
      );
    });
  }

  /// Withdraws allocated funds from a goal back to available spending funds.
  Future<void> withdraw({
    required String goalId,
    required int amount,
    String note = 'Penarikan dana target',
  }) async {
    if (amount <= 0) {
      throw const ValidationException('Nominal penarikan harus > 0.');
    }
    await db.transaction(() async {
      final goal = await (db.select(db.goals)..where((g) => g.id.equals(goalId)))
          .getSingleOrNull();
      if (goal == null) {
        throw const ValidationException('Target tabungan tidak ditemukan.');
      }
      if (amount > goal.currentAmount) {
        throw const ValidationException('Nominal penarikan melebihi dana terkumpul.');
      }

      // Reduce virtual allocations proportionally/sequentially
      var remainingToRelease = amount;
      final allocs = await (db.select(db.fundAllocations)
            ..where(
                (a) => a.targetType.equals('goal') & a.targetId.equals(goalId)))
          .get();
      for (final alloc in allocs) {
        if (remainingToRelease <= 0) break;
        final cut = math.min(alloc.amount, remainingToRelease);
        final left = alloc.amount - cut;
        if (left == 0) {
          await (db.delete(db.fundAllocations)
                ..where((a) => a.id.equals(alloc.id)))
              .go();
        } else {
          await (db.update(db.fundAllocations)
                ..where((a) => a.id.equals(alloc.id)))
              .write(
            FundAllocationsCompanion(
              amount: Value(left),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
        remainingToRelease -= cut;
      }

      await db.into(db.goalContributions).insert(
            GoalContributionsCompanion.insert(
              id: _uuid.v4(),
              goalId: goalId,
              amount: -amount,
              isVirtual: const Value(true),
              note: Value(note.trim()),
              createdAt: DateTime.now(),
            ),
          );

      final newAmount = goal.currentAmount - amount;
      await (db.update(db.goals)..where((g) => g.id.equals(goalId))).write(
        GoalsCompanion(
          currentAmount: Value(newAmount),
          status: Value(newAmount >= goal.targetAmount ? 'completed' : 'active'),
        ),
      );
    });
  }

  /// Calculates required monthly saving to reach [goal] on time.
  static int monthlyNeeded(GoalRecord goal, {DateTime? now}) {
    final remaining = math.max(0, goal.targetAmount - goal.currentAmount);
    if (remaining == 0 || goal.targetDate == null) return 0;
    final ref = now ?? DateTime.now();
    final months = math.max(1, (goal.targetDate!.difference(ref).inDays / 30).ceil());
    return (remaining / months).ceil();
  }
}
