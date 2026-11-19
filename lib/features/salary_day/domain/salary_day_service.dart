import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/arus_exception.dart';
import '../../../core/utils/date_utils.dart';

class SalaryAllocationDraft {
  const SalaryAllocationDraft({
    required this.label,
    required this.amount,
    this.percentage = 0,
    this.categoryId,
    this.goalId,
  });

  final String label;
  final int amount;
  final int percentage;
  final String? categoryId;
  final String? goalId;
}

/// Salary Day allocation planner (FR-12).
/// Creates virtual envelopes & budgets without executing fake transfers.
class SalaryDayService {
  SalaryDayService(this.db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase db;
  final Uuid _uuid;

  List<SalaryAllocationDraft> build503020Template(int totalIncome) {
    final needs = (totalIncome * 0.50).round();
    final wants = (totalIncome * 0.30).round();
    final savings = totalIncome - needs - wants;
    return [
      SalaryAllocationDraft(
        label: 'Kebutuhan Pokok (Makan & Kos)',
        amount: needs,
        percentage: 50,
        categoryId: DefaultCategoryIds.food,
      ),
      SalaryAllocationDraft(
        label: 'Keinginan & Hiburan',
        amount: wants,
        percentage: 30,
        categoryId: DefaultCategoryIds.entertainment,
      ),
      SalaryAllocationDraft(
        label: 'Tabungan & Cadangan',
        amount: savings,
        percentage: 20,
      ),
    ];
  }

  Future<String> applySalaryPlan({
    required String title,
    required int totalIncome,
    required String templateType,
    required List<SalaryAllocationDraft> items,
    String? sourceTransactionId,
    bool createBudgets = true,
    int? paydayDay,
  }) async {
    if (totalIncome <= 0) {
      throw const ValidationException('Total pemasukan harus > 0.');
    }
    final allocatedSum = items.fold<int>(0, (sum, i) => sum + i.amount);
    if (allocatedSum > totalIncome) {
      throw ValidationException(
        'Total alokasi ($allocatedSum) tidak boleh melebihi dana gaji ($totalIncome).',
      );
    }

    final planId = _uuid.v4();
    final now = DateTime.now();
    final period = ArusDateUtils.currentFinancialPeriod(
      now: now,
      paydayDay: paydayDay,
    );

    await db.transaction(() async {
      await db.into(db.salaryPlans).insert(
            SalaryPlansCompanion.insert(
              id: planId,
              title: title.trim(),
              totalIncome: totalIncome,
              templateType: Value(templateType),
              sourceTransactionId: Value(sourceTransactionId),
              appliedAt: now,
            ),
          );

      for (final item in items) {
        if (item.amount <= 0) continue;
        await db.into(db.salaryPlanItems).insert(
              SalaryPlanItemsCompanion.insert(
                id: _uuid.v4(),
                salaryPlanId: planId,
                label: item.label.trim(),
                categoryId: Value(item.categoryId),
                goalId: Value(item.goalId),
                percentage: Value(item.percentage),
                allocatedAmount: item.amount,
              ),
            );

        if (createBudgets && item.categoryId != null) {
          await db.into(db.budgets).insert(
                BudgetsCompanion.insert(
                  id: _uuid.v4(),
                  name: item.label.trim(),
                  categoryId: Value(item.categoryId),
                  limitAmount: item.amount,
                  periodType: 'monthly',
                  startDate: period.start,
                  endDate: period.endExclusive.subtract(
                    const Duration(seconds: 1),
                  ),
                  createdAt: now,
                ),
              );
        }
      }
    });

    return planId;
  }
}
