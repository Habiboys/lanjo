import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/core_providers.dart';
import '../../features/ai_assistant/presentation/ai_chat_page.dart';
import '../../features/ai_assistant/presentation/ai_quick_expense_page.dart';
import '../../features/backup/presentation/backup_page.dart';
import '../../features/bills/presentation/bills_page.dart';
import '../../features/budgets/presentation/budgets_page.dart';
import '../../features/categories/presentation/categories_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/debts/presentation/debts_page.dart';
import '../../features/goals/presentation/goals_page.dart';
import '../../features/import_export/presentation/import_export_page.dart';
import '../../features/onboarding/presentation/onboarding_page.dart';
import '../../features/plans/presentation/plans_hub_page.dart';
import '../../features/receipt_scanner/presentation/receipt_scanner_page.dart';
import '../../features/reports/presentation/financial_recap_page.dart';
import '../../features/reports/presentation/reports_page.dart';
import '../../features/salary_day/presentation/salary_day_page.dart';
import '../../features/settings/presentation/ai_settings_page.dart';
import '../../features/settings/presentation/android_native_settings_page.dart';
import '../../features/settings/presentation/notification_settings_page.dart';
import '../../features/settings/presentation/security_settings_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/split_bill/presentation/split_bill_page.dart';
import '../../features/transactions/presentation/templates_page.dart';
import '../../features/transactions/presentation/transaction_detail_page.dart';
import '../../features/transactions/presentation/transaction_form_page.dart';
import '../../features/transactions/presentation/transactions_page.dart';
import '../../features/wallets/presentation/wallets_page.dart';
import '../../features/wishlist/presentation/wishlist_page.dart';
import '../shell/main_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

class _RouterRefreshNotifier extends ChangeNotifier {
  void trigger() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.onDispose(refreshNotifier.dispose);

  bool? lastOnboarding;
  ref.listen(appSettingsProvider, (_, next) {
    final nextVal = next.valueOrNull?.onboardingCompleted;
    if (nextVal != lastOnboarding) {
      lastOnboarding = nextVal;
      refreshNotifier.trigger();
    }
  });

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final onboardingDone =
          ref.read(appSettingsProvider).valueOrNull?.onboardingCompleted;
      if (onboardingDone == null) return null;
      final onOnboarding = state.matchedLocation == '/onboarding';
      if (!onboardingDone && !onOnboarding) return '/onboarding';
      if (onboardingDone && onOnboarding) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const DashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/transactions',
                builder: (context, state) => const TransactionsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/plans',
                builder: (context, state) => const PlansHubPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/transactions/new',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => TransactionFormPage(
          initialType: state.uri.queryParameters['type'] ?? 'expense',
        ),
      ),
      GoRoute(
        path: '/transactions/edit/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => TransactionFormPage(
          editTransactionId: state.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: '/transactions/templates',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const TemplatesPage(),
      ),
      GoRoute(
        path: '/transactions/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => TransactionDetailPage(
          transactionId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/plans/budgets',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const BudgetsPage(),
      ),
      GoRoute(
        path: '/plans/bills',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const BillsPage(),
      ),
      GoRoute(
        path: '/plans/goals',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const GoalsPage(),
      ),
      GoRoute(
        path: '/plans/debts',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DebtsPage(),
      ),
      GoRoute(
        path: '/plans/split-bill',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SplitBillPage(),
      ),
      GoRoute(
        path: '/plans/wishlist',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const WishlistPage(),
      ),
      GoRoute(
        path: '/plans/salary-day',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => SalaryDayPage(
          initialAmount: int.tryParse(state.uri.queryParameters['amount'] ?? ''),
          sourceTransactionId: state.uri.queryParameters['txId'],
        ),
      ),
      GoRoute(
        path: '/reports',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ReportsPage(),
      ),
      GoRoute(
        path: '/reports/recap',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const FinancialRecapPage(),
      ),
      GoRoute(
        path: '/ai/quick-expense',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => AiQuickExpensePage(
          startWithVoice: state.uri.queryParameters['voice'] == '1',
          initialText: state.uri.queryParameters['text'],
        ),
      ),
      GoRoute(
        path: '/ai/receipt-scanner',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ReceiptScannerPage(
          initialImagePath: state.uri.queryParameters['path'],
        ),
      ),
      GoRoute(
        path: '/ai/chat',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AiChatPage(),
      ),
      GoRoute(
        path: '/settings/android-native',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AndroidNativeSettingsPage(),
      ),
      GoRoute(
        path: '/settings/wallets',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const WalletsPage(),
      ),
      GoRoute(
        path: '/settings/categories',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CategoriesPage(),
      ),
      GoRoute(
        path: '/settings/ai',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AiSettingsPage(),
      ),
      GoRoute(
        path: '/settings/notifications',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NotificationSettingsPage(),
      ),
      GoRoute(
        path: '/settings/security',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SecuritySettingsPage(),
      ),
      GoRoute(
        path: '/settings/import-export',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ImportExportPage(),
      ),
      GoRoute(
        path: '/settings/backup',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const BackupPage(),
      ),
    ],
  );
});
