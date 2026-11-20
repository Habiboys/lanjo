import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/lanjo_ui.dart';

/// Hub for all planning modules grouped cleanly by financial role.
class PlansHubPage extends ConsumerWidget {
  const PlansHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sts = ref.watch(safeToSpendProvider).valueOrNull;
    final budgets = ref.watch(budgetProgressesProvider).valueOrNull ?? const [];
    final bills = ref.watch(activeBillOccurrencesProvider).valueOrNull ?? const [];
    final incomes =
        ref.watch(upcomingIncomeSchedulesProvider).valueOrNull ?? const [];

    final controlGroup = <_PlanModuleItem>[
      (
        icon: LucideIcons.pieChart,
        color: context.lanjoPrimary,
        title: 'Anggaran (Budget)',
        subtitle: budgets.isEmpty
            ? 'Atur batas pengeluaran per kategori atau periode'
            : '${budgets.length} anggaran aktif dipantau',
        route: '/plans/budgets',
      ),
      (
        icon: LucideIcons.calendarClock,
        color: ArusColors.warning,
        title: 'Tagihan & Subscription',
        subtitle: bills.isEmpty
            ? 'Catat kos, listrik, cicilan, dan langganan rutin'
            : '${bills.length} tagihan menunggu pembayaran',
        route: '/plans/bills',
      ),
      (
        icon: LucideIcons.banknote,
        color: ArusColors.income,
        title: 'Salary Day',
        subtitle: incomes.isEmpty
            ? 'Bagi pemasukan gaji dengan 50/30/20 atau template custom'
            : 'Jadwal ${incomes.first.bill.name} ${ArusDateUtils.formatShortDate(incomes.first.occurrence.dueDate)} • Alokasi 50/30/20',
        route: '/plans/salary-day',
      ),
    ];

    final wealthGroup = <_PlanModuleItem>[
      (
        icon: LucideIcons.piggyBank,
        color: const Color(0xFF059669),
        title: 'Target Tabungan',
        subtitle: 'Dana darurat, gadget, liburan, atau alokasi virtual',
        route: '/plans/goals',
      ),
      (
        icon: LucideIcons.handCoins,
        color: ArusColors.transfer,
        title: 'Utang & Piutang',
        subtitle: 'Pantau pinjaman pribadi, cicilan, dan pelunasan',
        route: '/plans/debts',
      ),
    ];

    final utilityGroup = <_PlanModuleItem>[
      (
        icon: LucideIcons.shoppingBag,
        color: const Color(0xFF7C3AED),
        title: 'Wishlist & Simulasi Pembelian',
        subtitle: 'Cek dampak pembelian terhadap Safe-to-Spend sebelum beli',
        route: '/plans/wishlist',
      ),
      (
        icon: LucideIcons.split,
        color: ArusColors.primaryLight,
        title: 'Split Bill',
        subtitle: 'Bagi tagihan nongkrong & lacak pembayaran teman',
        route: '/plans/split-bill',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Rencana Keuangan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
        children: [
          if (sts != null) ...[
            LanjoFadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [context.lanjoHeroDeep, context.lanjoHeroMid],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        LucideIcons.shieldCheck,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DANA BEBAS SAFE-TO-SPEND',
                            style: TextStyle(
                              fontFamily: ArusColors.fontFamily,
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${MoneyFormatter.format(sts.dailySafeSpend)} / hari',
                            style: const TextStyle(
                              fontFamily: ArusColors.fontFamily,
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            '${sts.remainingDays} hari tersisa di periode ini',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      MoneyFormatter.formatCompact(sts.freeFunds),
                      style: const TextStyle(
                        fontFamily: ArusColors.fontFamily,
                        color: ArusColors.primaryVibrant,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          _ModuleGroupSection(
            label: 'KONTROL KAS HARIAN',
            items: controlGroup,
            theme: theme,
          ),
          const SizedBox(height: 18),
          _ModuleGroupSection(
            label: 'TABUNGAN & KOMITMEN',
            items: wealthGroup,
            theme: theme,
          ),
          const SizedBox(height: 18),
          _ModuleGroupSection(
            label: 'SIMULASI & SOSIAL',
            items: utilityGroup,
            theme: theme,
          ),
        ],
      ),
    );
  }
}

typedef _PlanModuleItem = ({
  IconData icon,
  Color color,
  String title,
  String subtitle,
  String route,
});

class _ModuleGroupSection extends StatelessWidget {
  const _ModuleGroupSection({
    required this.label,
    required this.items,
    required this.theme,
  });

  final String label;
  final List<_PlanModuleItem> items;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.7),
          ),
        ),
        LanjoSurface(
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(indent: 68),
                InkWell(
                  onTap: () => context.push(items[i].route),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        LanjoIconBox(
                          icon: items[i].icon,
                          color: items[i].color,
                          size: 42,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                items[i].title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                items[i].subtitle,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          LucideIcons.chevronRight,
                          size: 16,
                          color: context.lanjoSubtle,
                        ),
                      ],
                    ),
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
