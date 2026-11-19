import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ai_assistant/domain/ai_finance_service.dart';
import '../../features/backup/domain/backup_service.dart';
import '../../features/bills/domain/bill_service.dart';
import '../../features/budgets/domain/budget_service.dart';
import '../../features/goals/domain/goal_service.dart';
import '../../features/import_export/domain/import_export_service.dart';
import '../../features/reports/domain/report_service.dart';
import '../../features/safe_to_spend/domain/safe_to_spend_service.dart';
import '../../features/salary_day/domain/salary_day_service.dart';
import '../../features/split_bill/domain/split_bill_service.dart';
import 'core_providers.dart';

final safeToSpendServiceProvider = Provider<SafeToSpendService>((ref) {
  return SafeToSpendService(ref.watch(appDatabaseProvider));
});

final safeToSpendProvider = FutureProvider<SafeToSpendBreakdown>((ref) async {
  ref.watch(transactionsStreamProvider);
  ref.watch(walletsProvider);
  ref.watch(appSettingsProvider);
  return ref.watch(safeToSpendServiceProvider).calculate();
});

final budgetServiceProvider = Provider<BudgetService>((ref) {
  return BudgetService(
    ref.watch(appDatabaseProvider),
    ref.watch(localNotificationServiceProvider),
  );
});

final budgetProgressesProvider =
    FutureProvider<List<BudgetProgress>>((ref) async {
  ref.watch(transactionsStreamProvider);
  return ref.watch(budgetServiceProvider).getActiveBudgetProgresses();
});

final billServiceProvider = Provider<BillService>((ref) {
  return BillService(
    ref.watch(appDatabaseProvider),
    ref.watch(ledgerEngineProvider),
    ref.watch(localNotificationServiceProvider),
  );
});

final activeBillOccurrencesProvider =
    FutureProvider<List<BillOccurrenceView>>((ref) async {
  ref.watch(transactionsStreamProvider);
  return ref
      .watch(billServiceProvider)
      .getUpcomingAndActiveOccurrences(kind: 'expense');
});

final upcomingIncomeSchedulesProvider =
    FutureProvider<List<BillOccurrenceView>>((ref) async {
  ref.watch(transactionsStreamProvider);
  return ref
      .watch(billServiceProvider)
      .getUpcomingAndActiveOccurrences(kind: 'income');
});

final goalServiceProvider = Provider<GoalService>((ref) {
  return GoalService(
    ref.watch(appDatabaseProvider),
    ref.watch(ledgerEngineProvider),
  );
});

final salaryDayServiceProvider = Provider<SalaryDayService>((ref) {
  return SalaryDayService(ref.watch(appDatabaseProvider));
});

final splitBillServiceProvider = Provider<SplitBillService>((ref) {
  return SplitBillService(
    ref.watch(appDatabaseProvider),
    ref.watch(ledgerEngineProvider),
  );
});

final reportServiceProvider = Provider<ReportService>((ref) {
  return ReportService(ref.watch(appDatabaseProvider));
});

final importExportServiceProvider = Provider<ImportExportService>((ref) {
  return ImportExportService(
    ref.watch(appDatabaseProvider),
    ref.watch(ledgerEngineProvider),
  );
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    ref.watch(appDatabaseProvider),
    ref.watch(localNotificationServiceProvider),
  );
});

final aiFinanceServiceProvider = Provider<AiFinanceService>((ref) {
  return AiFinanceService(
    ref.watch(appDatabaseProvider),
    ref.watch(ledgerEngineProvider),
    ref.watch(geminiClientProvider),
    ref.watch(secureStorageProvider),
    ref.watch(safeToSpendServiceProvider),
    ref.watch(reportServiceProvider),
    ref.watch(billServiceProvider),
  );
});
