import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/lanjo_ui.dart';
import '../domain/report_service.dart';

/// Editorial Financial Recap computed deterministically offline.
class FinancialRecapPage extends ConsumerStatefulWidget {
  const FinancialRecapPage({super.key});

  @override
  ConsumerState<FinancialRecapPage> createState() => _FinancialRecapPageState();
}

class _FinancialRecapPageState extends ConsumerState<FinancialRecapPage> {
  int _storyIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final period = ArusDateUtils.currentFinancialPeriod(
      paydayDay: settings?.paydayDay,
    );
    final future = ref.watch(reportServiceProvider).generateRecap(
          start: period.start,
          end: DateTime.now(),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Financial Recap')),
      body: FutureBuilder<FinancialRecapData>(
        future: future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2.2),
            );
          }
          final recap = snap.data!;
          final s = recap.summary;
          final prev = recap.previousSummary;
          final expDiff =
              s.totalConsumptionExpense - prev.totalConsumptionExpense;

          final cards = <({
            List<Color> gradient,
            String kicker,
            String hero,
            String sub,
          })>[
            (
              gradient: const [ArusColors.heroDeep, ArusColors.heroEnd],
              kicker: 'Ringkasan Lanjo Periode Ini',
              hero: MoneyFormatter.format(s.totalConsumptionExpense),
              sub: 'Total pemasukan ${MoneyFormatter.format(s.totalIncome)}'
                  '${s.savingRatePercent != null ? ' • Saving rate ${s.savingRatePercent!.toStringAsFixed(1)}%' : ''}',
            ),
            (
              gradient: const [Color(0xFF312E81), Color(0xFF4F46E5)],
              kicker: 'Kategori Terbesar',
              hero: recap.topCategory?.category.name ?? 'Belum ada data',
              sub: recap.topCategory == null
                  ? 'Catat transaksi untuk melihat kategori dominan.'
                  : '${MoneyFormatter.format(recap.topCategory!.amount)} (${recap.topCategory!.percentage.round()}% dari total pengeluaran)',
            ),
            (
              gradient: const [Color(0xFF78350F), Color(0xFFD97706)],
              kicker: 'Kebiasaan & Merchant Favorit',
              hero: recap.topFrequentMerchant?.merchant ?? '-',
              sub: recap.topFrequentMerchant == null
                  ? 'Belum ada pola merchant berulang.'
                  : 'Dikunjungi ${recap.topFrequentMerchant!.visitCount} kali • Total ${MoneyFormatter.format(recap.topFrequentMerchant!.totalAmount)}',
            ),
            (
              gradient: const [Color(0xFF064E3B), Color(0xFF059669)],
              kicker: 'Peluang Penghematan',
              hero: recap.biggestExpense != null
                  ? MoneyFormatter.format(recap.biggestExpense!.amount)
                  : 'Rp0',
              sub: recap.potentialSavingTip,
            ),
          ];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
            children: [
              SizedBox(
                height: 268,
                child: PageView.builder(
                  itemCount: cards.length,
                  onPageChanged: (idx) => setState(() => _storyIndex = idx),
                  itemBuilder: (context, i) {
                    final c = cards[i];
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: c.gradient,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${i + 1}/${cards.length} • ${c.kicker}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            c.hero,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 26,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            c.sub,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < cards.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _storyIndex ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _storyIndex
                            ? theme.colorScheme.primary
                            : context.lanjoBorder,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              LanjoSurface(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Perbandingan Periode Sebelumnya',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            expDiff == 0
                                ? 'Pengeluaran sama persis dengan periode sebelumnya.'
                                : expDiff > 0
                                    ? 'Naik ${MoneyFormatter.format(expDiff)} dibanding periode sebelumnya.'
                                    : 'Turun ${MoneyFormatter.format(expDiff.abs())} dibanding periode sebelumnya.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    _RecapRow(
                      label: 'Rata-rata Pengeluaran / Hari',
                      value: MoneyFormatter.format(s.averageDailyExpense),
                    ),
                    if (recap.highestSpendDay != null) ...[
                      const Divider(indent: 16, endIndent: 16),
                      _RecapRow(
                        label: 'Hari Pengeluaran Tertinggi',
                        value:
                            '${ArusDateUtils.formatShortDate(recap.highestSpendDay!)} (${MoneyFormatter.formatCompact(recap.highestSpendDayAmount)})',
                      ),
                    ],
                    const Divider(indent: 16, endIndent: 16),
                    _RecapRow(
                      label: 'Target Tabungan Tercapai',
                      value: '${recap.achievedGoalsCount} target',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () {
                  final text = StringBuffer()
                    ..writeln('📊 *Lanjo Financial Recap*')
                    ..writeln(
                      'Pengeluaran: ${MoneyFormatter.format(s.totalConsumptionExpense)}',
                    )
                    ..writeln(
                      'Kategori terbesar: ${recap.topCategory?.category.name ?? '-'}',
                    );
                  if (s.savingRatePercent != null) {
                    text.writeln(
                      'Saving rate: ${s.savingRatePercent!.toStringAsFixed(1)}%',
                    );
                  }
                  text.writeln('\n${recap.potentialSavingTip}');
                  Share.share(text.toString());
                },
                icon: const Icon(LucideIcons.share2, size: 17),
                label: const Text('Bagikan Recap (Tanpa Saldo Sensitif)'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecapRow extends StatelessWidget {
  const _RecapRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.lanjoMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: lanjoMoneyStyle(context, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}
