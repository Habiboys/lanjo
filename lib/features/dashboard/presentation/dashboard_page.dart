import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/ledger_engine.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/native/native_bridge_service.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/lanjo_ui.dart';
import '../../budgets/domain/budget_service.dart';
import '../../safe_to_spend/domain/safe_to_spend_service.dart';
import '../../safe_to_spend/presentation/safe_to_spend_sheet.dart';

/// Main Dashboard (Beranda) showing balances, Safe-to-Spend, Quick Add,
/// wallets, recent transactions, upcoming bills, and budget progress.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool _quickRecording = false;

  Future<void> _togglePrivacy(bool current) async {
    final db = ref.read(appDatabaseProvider);
    await (db.update(db.appSettings)..where((s) => s.id.equals('default')))
        .write(
      AppSettingsCompanion(
        privacyMode: Value(!current),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _quickUseTemplate(TransactionTemplateRecord tpl) async {
    if (_quickRecording) return;
    setState(() => _quickRecording = true);
    try {
      final ledger = ref.read(ledgerEngineProvider);
      final db = ref.read(appDatabaseProvider);
      late String txId;
      if (tpl.type == 'income') {
        txId = await ledger.recordIncome(
          walletId: tpl.walletId,
          categoryId: tpl.categoryId,
          amount: tpl.amount,
          occurredAt: DateTime.now(),
          description: tpl.description.isEmpty ? tpl.title : tpl.description,
          merchant: tpl.merchant,
          source: 'template',
        );
      } else {
        txId = await ledger.recordExpense(
          walletId: tpl.walletId,
          amount: tpl.amount,
          splits: [
            CategorySplitInput(
              categoryId: tpl.categoryId,
              amount: tpl.amount,
              description: tpl.description.isEmpty ? tpl.title : tpl.description,
            ),
          ],
          occurredAt: DateTime.now(),
          description: tpl.description.isEmpty ? tpl.title : tpl.description,
          merchant: tpl.merchant,
          source: 'template',
          allowNegativeBalance: true,
        );
      }

      await (db.update(db.transactionTemplates)
            ..where((t) => t.id.equals(tpl.id)))
          .write(
        TransactionTemplatesCompanion(useCount: Value(tpl.useCount + 1)),
      );
      await ref.read(budgetServiceProvider).evaluateAlerts();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tercatat: ${tpl.title} (${MoneyFormatter.format(tpl.amount)})',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => ledger.voidTransaction(txId, reason: 'Undo Quick Add'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencatat: $e')),
      );
    } finally {
      if (mounted) setState(() => _quickRecording = false);
    }
  }

  Future<void> _saveSmartInboxItem(
    SmartInboxItem item, {
    required List<AccountRecord> wallets,
    required String? defaultWalletId,
  }) async {
    if (_quickRecording) return;
    if (wallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan dompet terlebih dahulu.')),
      );
      return;
    }
    setState(() => _quickRecording = true);
    try {
      final wallet = wallets
              .where((w) => w.id == defaultWalletId)
              .firstOrNull ??
          wallets.first;
      final ledger = ref.read(ledgerEngineProvider);
      late String txId;
      if (item.type == 'income') {
        txId = await ledger.recordIncome(
          walletId: wallet.id,
          categoryId: DefaultCategoryIds.incomeOther,
          amount: item.amount,
          occurredAt: item.detectedAt,
          description: '${item.sourceApp}: ${item.title}',
          merchant: item.sourceApp,
          source: 'smart_notif',
        );
      } else {
        txId = await ledger.recordExpense(
          walletId: wallet.id,
          amount: item.amount,
          splits: [
            CategorySplitInput(
              categoryId: DefaultCategoryIds.food,
              amount: item.amount,
              description: '${item.sourceApp}: ${item.title}',
            ),
          ],
          occurredAt: item.detectedAt,
          description:
              item.body.isNotEmpty ? item.body : '${item.sourceApp}: ${item.title}',
          merchant: item.sourceApp,
          source: 'smart_notif',
          allowNegativeBalance: true,
        );
      }
      await ref
          .read(nativeBridgeServiceProvider)
          .removeSmartInboxItem(item.id);
      ref.read(smartInboxRevisionProvider.notifier).state++;
      await ref.read(budgetServiceProvider).evaluateAlerts();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tersimpan dari ${item.sourceApp}: ${MoneyFormatter.format(item.amount)}',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () =>
                ledger.voidTransaction(txId, reason: 'Undo Smart Inbox'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan: $e')),
      );
    } finally {
      if (mounted) setState(() => _quickRecording = false);
    }
  }

  ({int streakDays, int todaySpent, String? anomalyText}) _computeSmartInsights(
    List<TransactionRecord> txs,
    Map<String, CategoryRecord> catMap,
    SafeToSpendBreakdown? sts,
    DateTime periodStart,
  ) {
    final now = DateTime.now();
    final todayKey = DateTime(now.year, now.month, now.day);
    final dailySpend = <DateTime, int>{};

    final sevenDaysAgo = todayKey.subtract(const Duration(days: 7));
    final fourteenDaysAgo = todayKey.subtract(const Duration(days: 14));
    final recentCatSpend = <String, int>{};
    final prevCatSpend = <String, int>{};

    for (final tx in txs) {
      final d = DateTime(
        tx.occurredAt.year,
        tx.occurredAt.month,
        tx.occurredAt.day,
      );
      if (tx.type == 'expense') {
        dailySpend[d] = (dailySpend[d] ?? 0) + tx.amount;
        final cid = tx.primaryCategoryId;
        if (cid != null) {
          if (!d.isBefore(sevenDaysAgo)) {
            recentCatSpend[cid] = (recentCatSpend[cid] ?? 0) + tx.amount;
          } else if (!d.isBefore(fourteenDaysAgo) && d.isBefore(sevenDaysAgo)) {
            prevCatSpend[cid] = (prevCatSpend[cid] ?? 0) + tx.amount;
          }
        }
      } else if (tx.type == 'refund') {
        dailySpend[d] = (dailySpend[d] ?? 0) - tx.amount;
      }
    }

    final todaySpent = (dailySpend[todayKey] ?? 0).clamp(0, 1 << 30);
    var streak = 0;
    if (sts != null && sts.dailySafeSpend > 0 && txs.isNotEmpty) {
      final startDay = DateTime(
        periodStart.year,
        periodStart.month,
        periodStart.day,
      );
      var cursor = todayKey;
      while (!cursor.isBefore(startDay) && streak < 60) {
        final spent = (dailySpend[cursor] ?? 0).clamp(0, 1 << 30);
        if (spent <= sts.dailySafeSpend) {
          streak++;
          cursor = cursor.subtract(const Duration(days: 1));
        } else {
          break;
        }
      }
    }

    String? anomaly;
    var biggestSpikeDiff = 0;
    for (final entry in recentCatSpend.entries) {
      final prev = prevCatSpend[entry.key] ?? 0;
      if (prev >= 50000 && entry.value > (prev * 1.5)) {
        final diff = entry.value - prev;
        if (diff > biggestSpikeDiff) {
          biggestSpikeDiff = diff;
          final catName = catMap[entry.key]?.name ?? 'Kategori';
          final pct = (((entry.value - prev) / prev) * 100).round();
          anomaly =
              'Pengeluaran $catName 7 hari terakhir naik +$pct% dibanding minggu lalu.';
        }
      }
    }

    return (
      streakDays: streak,
      todaySpent: todaySpent,
      anomalyText: anomaly,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final hidden = settings?.privacyMode ?? false;
    final hiddenWidgets = (settings?.dashboardHiddenWidgets ?? '')
        .split(',')
        .where((e) => e.isNotEmpty)
        .toSet();

    final wallets = ref.watch(activeWalletsProvider);
    final txs = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final catMap = {for (final c in categories) c.id: c};
    final templates = ref.watch(templatesStreamProvider).valueOrNull ?? const [];
    final stsAsync = ref.watch(safeToSpendProvider);
    final budgetsAsync = ref.watch(budgetProgressesProvider);
    final billsAsync = ref.watch(activeBillOccurrencesProvider);
    final incomeSchedulesAsync = ref.watch(upcomingIncomeSchedulesProvider);
    final smartInboxItems =
        ref.watch(smartInboxProvider).valueOrNull ?? const [];

    final period = ArusDateUtils.currentFinancialPeriod(
      paydayDay: settings?.paydayDay,
    );
    var periodIncome = 0;
    var periodExpense = 0;
    for (final tx in txs) {
      if (tx.occurredAt.isBefore(period.start) ||
          !tx.occurredAt.isBefore(period.endExclusive)) {
        continue;
      }
      if (tx.type == 'income') periodIncome += tx.amount;
      if (tx.type == 'expense') periodExpense += tx.amount;
      if (tx.type == 'refund') periodExpense -= tx.amount;
    }
    if (periodExpense < 0) periodExpense = 0;

    final hasNickname = settings?.nickname?.trim().isNotEmpty == true;
    final greeting = hasNickname ? 'Halo, ${settings!.nickname}' : 'Beranda Lanjo';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/lanjo_icon.png',
                width: 26,
                height: 26,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: hasNickname
                  ? Text(
                      greeting,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : Image.asset(
                      theme.brightness == Brightness.dark
                          ? 'assets/images/lanjo_wordmark_dark.png'
                          : 'assets/images/lanjo_wordmark_light.png',
                      height: 20,
                      fit: BoxFit.contain,
                    ),
            ),
          ],
        ),
        actions: [
          _HeaderIconBtn(
            tooltip: 'Asisten AI',
            icon: LucideIcons.sparkles,
            onPressed: () => context.push('/ai/chat'),
          ),
          const SizedBox(width: 6),
          _HeaderIconBtn(
            tooltip: 'Laporan & Recap',
            icon: LucideIcons.barChart2,
            onPressed: () => context.push('/reports'),
          ),
          const SizedBox(width: 6),
          _HeaderIconBtn(
            tooltip: hidden ? 'Tampilkan nominal' : 'Sembunyikan nominal',
            icon: hidden ? LucideIcons.eyeOff : LucideIcons.eye,
            onPressed: () => _togglePrivacy(hidden),
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(safeToSpendProvider);
          ref.invalidate(budgetProgressesProvider);
          ref.invalidate(activeBillOccurrencesProvider);
          ref.invalidate(upcomingIncomeSchedulesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
          children: [
            // 1. Safe-to-Spend & Net Balance Hero Card
            LanjoFadeSlideIn(
              child: stsAsync.when(
                data: (sts) {
                  final insights = _computeSmartInsights(
                    txs,
                    catMap,
                    sts,
                    period.start,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SafeToSpendHeroCard(
                        sts: sts,
                        hidden: hidden,
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => SafeToSpendSheet(breakdown: sts),
                        ),
                      ),
                      if (insights.streakDays > 0 ||
                          insights.anomalyText != null) ...[
                        const SizedBox(height: 10),
                        _SmartDisciplineBanner(
                          streakDays: insights.streakDays,
                          todaySpent: insights.todaySpent,
                          dailySafeSpend: sts.dailySafeSpend,
                          anomalyText: insights.anomalyText,
                          hidden: hidden,
                          onTapReport: () => context.push('/reports'),
                        ),
                      ],
                    ],
                  );
                },
                loading: () => const LanjoSurface(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
                ),
                error: (e, _) => LanjoSurface(
                  padding: const EdgeInsets.all(16),
                  child: Text('Gagal menghitung Safe-to-Spend: $e'),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 1b. Smart Auto-Detect Notification Inbox (Android Native Bridge)
            if (smartInboxItems.isNotEmpty) ...[
              _SmartInboxSection(
                items: smartInboxItems,
                hidden: hidden,
                onSave: (item) => _saveSmartInboxItem(
                  item,
                  wallets: wallets,
                  defaultWalletId: settings?.defaultWalletId,
                ),
                onReviewAi: (item) async {
                  await ref
                      .read(nativeBridgeServiceProvider)
                      .removeSmartInboxItem(item.id);
                  ref.read(smartInboxRevisionProvider.notifier).state++;
                  if (!context.mounted) return;
                  context.push(
                    Uri(
                      path: '/ai/quick-expense',
                      queryParameters: {
                        'text': '${item.sourceApp}: ${item.title}. ${item.body}',
                      },
                    ).toString(),
                  );
                },
                onDismiss: (item) async {
                  await ref
                      .read(nativeBridgeServiceProvider)
                      .removeSmartInboxItem(item.id);
                  ref.read(smartInboxRevisionProvider.notifier).state++;
                },
                onClearAll: () async {
                  await ref.read(nativeBridgeServiceProvider).clearSmartInbox();
                  ref.read(smartInboxRevisionProvider.notifier).state++;
                },
              ),
              const SizedBox(height: 16),
            ],

            // 2. Period Income vs Expense Pair
            if (!hiddenWidgets.contains('summary'))
              LanjoFadeSlideIn(
                delayMs: 40,
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryMiniCard(
                        label: 'Pemasukan',
                        amount: periodIncome,
                        hidden: hidden,
                        color: ArusColors.income,
                        icon: LucideIcons.arrowDownLeft,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryMiniCard(
                        label: 'Pengeluaran',
                        amount: periodExpense,
                        hidden: hidden,
                        color: ArusColors.expense,
                        icon: LucideIcons.arrowUpRight,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // 3. Quick Add & Templates
            if (!hiddenWidgets.contains('quick_add')) ...[
              LanjoSectionHeader(
                title: 'Catat Cepat',
                actionLabel: 'Template',
                onAction: () => context.push('/transactions/templates'),
              ),
              const SizedBox(height: 10),
              if (templates.isEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _QuickPillButton(
                      icon: LucideIcons.plus,
                      label: 'Pengeluaran',
                      accent: ArusColors.expense,
                      onTap: () => context.push('/transactions/new?type=expense'),
                    ),
                    _QuickPillButton(
                      icon: LucideIcons.sparkles,
                      label: 'Catat via AI',
                      accent: theme.colorScheme.primary,
                      onTap: () => context.push('/ai/quick-expense'),
                    ),
                    _QuickPillButton(
                      icon: LucideIcons.zap,
                      label: 'Buat Template',
                      accent: ArusColors.warning,
                      onTap: () => context.push('/transactions/templates'),
                    ),
                  ],
                )
              else
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: templates.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final tpl = templates[index];
                      return _QuickPillButton(
                        icon: LucideIcons.zap,
                        label:
                            '${tpl.title} • ${MoneyFormatter.formatCompact(tpl.amount, hidden: hidden)}',
                        accent: ArusColors.warning,
                        onTap: () => _quickUseTemplate(tpl),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 22),
            ],

            // 4. Wallets Section
            if (!hiddenWidgets.contains('wallets')) ...[
              LanjoSectionHeader(
                title: 'Dompet & Rekening',
                actionLabel: 'Kelola',
                onAction: () => context.push('/settings/wallets'),
              ),
              const SizedBox(height: 10),
              if (wallets.isEmpty)
                EmptyStateCard(
                  icon: LucideIcons.wallet,
                  title: 'Belum ada wallet',
                  subtitle: 'Tambahkan rekening bank, e-wallet, atau uang tunai.',
                  actionLabel: 'Tambah Dompet',
                  onAction: () => context.push('/settings/wallets'),
                )
              else ...[
                if (wallets.where((w) => w.cachedBalance > 0).length > 1) ...[
                  _WalletAllocationBar(wallets: wallets),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  height: 112,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: wallets.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final w = wallets[index];
                      final color = Color(w.colorValue);
                      return SizedBox(
                        width: 180,
                        child: LanjoSurface(
                          onTap: () => context.push('/settings/wallets'),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  LanjoIconBox(
                                    icon: arusIconFromName(w.icon),
                                    color: color,
                                    size: 32,
                                    iconSize: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      w.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    MoneyFormatter.format(
                                      w.cachedBalance,
                                      hidden: hidden,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: lanjoMoneyStyle(
                                      context,
                                      fontSize: 15.5,
                                    ),
                                  ),
                                  if (!w.includeInSpendable) ...[
                                    const SizedBox(height: 1),
                                    Text(
                                      w.accountClass == 'liability'
                                          ? 'Kewajiban'
                                          : 'Dana Terpisah',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        fontSize: 10.5,
                                        color: context.lanjoSubtle,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 22),
            ],

            // 5. Scheduled Income (Gajian) & Upcoming Bills
            if (!hiddenWidgets.contains('bills')) ...[
              incomeSchedulesAsync.when(
                data: (incomes) {
                  if (incomes.isEmpty) return const SizedBox.shrink();
                  final slice = incomes.take(2).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LanjoSectionHeader(
                        title: 'Jadwal Pemasukan (Gajian)',
                        actionLabel: 'Salary Day',
                        onAction: () => context.push('/plans/salary-day'),
                      ),
                      const SizedBox(height: 10),
                      LanjoSurface(
                        child: Column(
                          children: [
                            for (var i = 0; i < slice.length; i++) ...[
                              if (i > 0) const Divider(indent: 66),
                              InkWell(
                                onTap: () => context.push('/plans/salary-day'),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      const LanjoIconBox(
                                        icon: LucideIcons.banknote,
                                        color: ArusColors.income,
                                        size: 40,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              slice[i].bill.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(fontSize: 14),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Perkiraan masuk ${ArusDateUtils.formatShortDate(slice[i].occurrence.dueDate)}',
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '+${MoneyFormatter.format(slice[i].remainingAmount, hidden: hidden)}',
                                        style: lanjoMoneyStyle(
                                          context,
                                          fontSize: 13.5,
                                          color: ArusColors.income,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              billsAsync.when(
                data: (bills) {
                  if (bills.isEmpty) return const SizedBox.shrink();
                  final slice = bills.take(3).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LanjoSectionHeader(
                        title: 'Tagihan Mendatang',
                        actionLabel: 'Semua',
                        onAction: () => context.push('/plans/bills'),
                      ),
                      const SizedBox(height: 10),
                      LanjoSurface(
                        child: Column(
                          children: [
                            for (var i = 0; i < slice.length; i++) ...[
                              if (i > 0) const Divider(indent: 66),
                              InkWell(
                                onTap: () => context.push('/plans/bills'),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      const LanjoIconBox(
                                        icon: LucideIcons.calendarClock,
                                        color: ArusColors.warning,
                                        size: 40,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              slice[i].bill.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(fontSize: 14),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Jatuh tempo ${ArusDateUtils.formatShortDate(slice[i].occurrence.dueDate)}',
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        MoneyFormatter.format(
                                          slice[i].remainingAmount,
                                          hidden: hidden,
                                        ),
                                        style: lanjoMoneyStyle(
                                          context,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
            ],

            // 6. Active Budgets Preview
            if (!hiddenWidgets.contains('budgets'))
              budgetsAsync.when(
                data: (budgets) {
                  if (budgets.isEmpty) return const SizedBox.shrink();
                  final slice = budgets.take(3).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LanjoSectionHeader(
                        title: 'Anggaran Periode Ini',
                        actionLabel: 'Semua',
                        onAction: () => context.push('/plans/budgets'),
                      ),
                      const SizedBox(height: 10),
                      LanjoSurface(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            for (var i = 0; i < slice.length; i++) ...[
                              if (i > 0) const SizedBox(height: 14),
                              _BudgetMiniRow(
                                progress: slice[i],
                                hidden: hidden,
                                onTap: () => context.push('/plans/budgets'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),

            // 7. Recent Transactions
            LanjoSectionHeader(
              title: 'Transaksi Terbaru',
              actionLabel: 'Semua',
              onAction: () => context.go('/transactions'),
            ),
            const SizedBox(height: 10),
            if (txs.isEmpty)
              EmptyStateCard(
                icon: LucideIcons.receiptText,
                title: 'Belum ada transaksi',
                subtitle: 'Tekan tombol + di bawah untuk mencatat transaksi pertama.',
                actionLabel: 'Catat Sekarang',
                onAction: () => context.push('/transactions/new?type=expense'),
              )
            else
              LanjoSurface(
                child: Column(
                  children: [
                    for (var i = 0; i < txs.take(5).length; i++) ...[
                      if (i > 0) const Divider(indent: 66),
                      _RecentTxRow(
                        tx: txs[i],
                        category: catMap[txs[i].primaryCategoryId],
                        hidden: hidden,
                        onTap: () => context.push('/transactions/${txs[i].id}'),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  const _HeaderIconBtn({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: context.lanjoSurfaceSecondary,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(11),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              icon,
              size: 18,
              color: context.lanjoInk,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickPillButton extends StatelessWidget {
  const _QuickPillButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.lanjoCard,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: context.lanjoBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14.5, color: accent),
              const SizedBox(width: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: context.lanjoInk,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetMiniRow extends StatelessWidget {
  const _BudgetMiniRow({
    required this.progress,
    required this.hidden,
    required this.onTap,
  });

  final BudgetProgress progress;
  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = progress.isExceeded
        ? ArusColors.expense
        : progress.isWarning80
            ? ArusColors.warning
            : context.lanjoPrimaryLight;
    final pct = (progress.ratio * 100).clamp(0, 999).round();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.budget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${MoneyFormatter.formatCompact(progress.spentAmount, hidden: hidden)} / ${MoneyFormatter.formatCompact(progress.effectiveLimit, hidden: hidden)}',
                style: lanjoMoneyStyle(
                  context,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.lanjoMuted,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$pct%',
                style: lanjoMoneyStyle(
                  context,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.ratio.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: context.lanjoSurfaceSecondary,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTxRow extends StatelessWidget {
  const _RecentTxRow({
    required this.tx,
    required this.category,
    required this.hidden,
    required this.onTap,
  });

  final TransactionRecord tx;
  final CategoryRecord? category;
  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isIncome = tx.type == 'income' || tx.type == 'refund';
    final isExpense = tx.type == 'expense';
    final isTransfer = tx.type == 'transfer';
    final color = isTransfer
        ? ArusColors.transfer
        : isIncome
            ? ArusColors.income
            : isExpense
                ? ArusColors.expense
                : tx.type == 'opening_balance'
                    ? ArusColors.primary
                    : ArusColors.warning;
    final prefix = isIncome ? '+' : (isExpense ? '-' : '');

    final catColor =
        category != null ? Color(category!.colorValue) : color;
    final iconData = category != null
        ? arusIconFromName(category!.icon)
        : (isTransfer
            ? LucideIcons.arrowLeftRight
            : isIncome
                ? LucideIcons.arrowDownLeft
                : LucideIcons.receiptText);

    final titleText = tx.description.trim().isNotEmpty
        ? tx.description
        : (category?.name ?? 'Transaksi');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            LanjoIconBox(
              icon: iconData,
              color: catColor,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${category?.name ?? tx.type} • ${ArusDateUtils.formatRelativeDay(tx.occurredAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$prefix${MoneyFormatter.format(tx.amount, hidden: hidden)}',
              style: lanjoMoneyStyle(
                context,
                fontSize: 13.5,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafeToSpendHeroCard extends StatelessWidget {
  const _SafeToSpendHeroCard({
    required this.sts,
    required this.hidden,
    required this.onTap,
  });

  final SafeToSpendBreakdown sts;
  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gradientColors = sts.isShortfall
        ? const [Color(0xFF4C0519), Color(0xFF881337), Color(0xFF9F1239)]
        : [context.lanjoHeroDeep, context.lanjoHeroMid, context.lanjoHeroEnd];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: (sts.isShortfall ? const Color(0xFF881337) : context.lanjoHeroDeep)
                .withValues(alpha: context.isDark ? 0.35 : 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              // Subtle ambient highlight orb
              Positioned(
                top: -42,
                right: -28,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.14),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sts.isShortfall
                                ? 'KOMITMEN MELEBIHI KAS'
                                : 'AMAN DIBELANJAKAN / HARI',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: ArusColors.fontFamily,
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                LucideIcons.calendarClock,
                                size: 12,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${sts.remainingDays} hari lagi',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(
                                LucideIcons.chevronRight,
                                size: 12,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        MoneyFormatter.format(sts.dailySafeSpend, hidden: hidden),
                        style: const TextStyle(
                          fontFamily: ArusColors.fontFamily,
                          color: Colors.white,
                          fontSize: 31,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.9,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _HeroMetric(
                            label: 'Kas Likuid',
                            value: MoneyFormatter.formatCompact(
                              sts.spendableLiquidBalance,
                              hidden: hidden,
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 26,
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: _HeroMetric(
                              label: 'Kekayaan',
                              value: MoneyFormatter.formatCompact(
                                sts.netWorth,
                                hidden: hidden,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 26,
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: _HeroMetric(
                              label: 'Dana Bebas',
                              value: MoneyFormatter.formatCompact(
                                sts.freeFunds,
                                hidden: hidden,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: ArusColors.fontFamily,
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: ArusColors.fontFamily,
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _SummaryMiniCard extends StatelessWidget {
  const _SummaryMiniCard({
    required this.label,
    required this.amount,
    required this.hidden,
    required this.color,
    required this.icon,
  });

  final String label;
  final int amount;
  final bool hidden;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return LanjoSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          LanjoIconBox(
            icon: icon,
            color: color,
            size: 36,
            iconSize: 17,
            radius: 11,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  MoneyFormatter.formatCompact(amount, hidden: hidden),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: lanjoMoneyStyle(
                    context,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartDisciplineBanner extends StatelessWidget {
  const _SmartDisciplineBanner({
    required this.streakDays,
    required this.todaySpent,
    required this.dailySafeSpend,
    required this.anomalyText,
    required this.hidden,
    required this.onTapReport,
  });

  final int streakDays;
  final int todaySpent;
  final int dailySafeSpend;
  final String? anomalyText;
  final bool hidden;
  final VoidCallback onTapReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remainingToday = (dailySafeSpend - todaySpent).clamp(0, 1 << 30);
    return LanjoSurface(
      onTap: onTapReport,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (streakDays > 0)
            Row(
              children: [
                const LanjoIconBox(
                  icon: LucideIcons.sparkles,
                  color: ArusColors.income,
                  size: 32,
                  iconSize: 15,
                  radius: 10,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Streak Hemat $streakDays Hari Berturut-turut',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Sisa kuota aman hari ini: ${MoneyFormatter.formatCompact(remainingToday, hidden: hidden)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const LanjoPillBadge(
                  label: 'Disiplin',
                  color: ArusColors.income,
                ),
              ],
            ),
          if (streakDays > 0 && anomalyText != null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(),
            ),
          if (anomalyText != null)
            Row(
              children: [
                const LanjoIconBox(
                  icon: LucideIcons.trendingUp,
                  color: ArusColors.warning,
                  size: 32,
                  iconSize: 15,
                  radius: 10,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    anomalyText!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.lanjoInk,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 15,
                  color: context.lanjoSubtle,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SmartInboxSection extends StatelessWidget {
  const _SmartInboxSection({
    required this.items,
    required this.hidden,
    required this.onSave,
    required this.onReviewAi,
    required this.onDismiss,
    required this.onClearAll,
  });

  final List<SmartInboxItem> items;
  final bool hidden;
  final ValueChanged<SmartInboxItem> onSave;
  final ValueChanged<SmartInboxItem> onReviewAi;
  final ValueChanged<SmartInboxItem> onDismiss;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LanjoSectionHeader(
          title: 'Deteksi Otomatis Notifikasi (${items.length})',
          actionLabel: 'Bersihkan',
          onAction: onClearAll,
        ),
        const SizedBox(height: 8),
        LanjoSurface(
          child: Column(
            children: [
              for (var i = 0; i < items.take(4).length; i++) ...[
                if (i > 0) const Divider(indent: 14, endIndent: 14),
                Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          LanjoPillBadge(
                            label: items[i].sourceApp,
                            color: items[i].type == 'income'
                                ? ArusColors.income
                                : ArusColors.primary,
                            icon: LucideIcons.smartphone,
                          ),
                          const Spacer(),
                          Text(
                            '${items[i].type == 'income' ? '+' : '-'}${MoneyFormatter.format(items[i].amount, hidden: hidden)}',
                            style: lanjoMoneyStyle(
                              context,
                              fontSize: 14,
                              color: items[i].type == 'income'
                                  ? ArusColors.income
                                  : ArusColors.expense,
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => onDismiss(items[i]),
                            borderRadius: BorderRadius.circular(999),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                LucideIcons.x,
                                size: 15,
                                color: context.lanjoSubtle,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        items[i].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (items[i].body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          items[i].body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => onSave(items[i]),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 36),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              icon: const Icon(LucideIcons.check, size: 15),
                              label: const Text(
                                'Simpan 1-Ketuk',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => onReviewAi(items[i]),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            icon: const Icon(LucideIcons.sparkles, size: 15),
                            label: const Text(
                              'Tinjau AI',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WalletAllocationBar extends StatelessWidget {
  const _WalletAllocationBar({required this.wallets});

  final List<AccountRecord> wallets;

  @override
  Widget build(BuildContext context) {
    final positive = wallets.where((w) => w.cachedBalance > 0).toList();
    final total = positive.fold<int>(0, (sum, w) => sum + w.cachedBalance);
    if (total <= 0) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 7,
        child: Row(
          children: [
            for (var i = 0; i < positive.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: ((positive[i].cachedBalance / total) * 1000)
                    .round()
                    .clamp(25, 1000),
                child: Container(
                  color: Color(positive[i].colorValue),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
