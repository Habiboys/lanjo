import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/lanjo_ui.dart';
import '../domain/report_service.dart';

/// Offline-first interactive financial reports with fl_chart, calendar,
/// drill-down, and CSV/PDF export (FR-21).
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  String _rangeKey = 'month';
  DateTimeRange? _customRange;

  ({DateTime start, DateTime end, String label}) _resolveRange(int? paydayDay) {
    final now = DateTime.now();
    if (_rangeKey == 'custom' && _customRange != null) {
      return (
        start: _customRange!.start,
        end: _customRange!.end.add(const Duration(hours: 23, minutes: 59)),
        label: 'Periode Custom',
      );
    }
    if (_rangeKey == 'today') {
      final start = DateTime(now.year, now.month, now.day);
      return (
        start: start,
        end: DateTime(now.year, now.month, now.day, 23, 59, 59),
        label: 'Hari Ini',
      );
    }
    if (_rangeKey == 'week') {
      final start = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      return (start: start, end: now, label: 'Minggu Ini');
    }
    if (_rangeKey == 'year') {
      return (
        start: DateTime(now.year, 1, 1),
        end: now,
        label: 'Tahun ${now.year}',
      );
    }
    final period = ArusDateUtils.currentFinancialPeriod(
      now: now,
      paydayDay: paydayDay,
    );
    return (
      start: period.start,
      end: period.endExclusive.subtract(const Duration(seconds: 1)),
      label: 'Periode Berjalan',
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final range = _resolveRange(settings?.paydayDay);
    final reportFuture = ref
        .watch(reportServiceProvider)
        .generateSummary(start: range.start, end: range.end);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Keuangan'),
        actions: [
          Tooltip(
            message: 'Financial Recap',
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Material(
                color: context.lanjoSurfaceSecondary,
                borderRadius: BorderRadius.circular(11),
                child: InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: () => context.push('/reports/recap'),
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(LucideIcons.sparkles, size: 18),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in const [
                    ('today', 'Hari Ini'),
                    ('week', 'Minggu Ini'),
                    ('month', 'Periode Ini'),
                    ('year', 'Tahun Ini'),
                    ('custom', 'Custom'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(item.$2),
                        showCheckmark: false,
                        selected: _rangeKey == item.$1,
                        onSelected: (_) async {
                          if (item.$1 == 'custom') {
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) {
                              setState(() {
                                _customRange = picked;
                                _rangeKey = 'custom';
                              });
                            }
                          } else {
                            setState(() => _rangeKey = item.$1);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<FinancialSummaryReport>(
              future: reportFuture,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  );
                }
                final r = snap.data!;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
                  children: [
                    // Export Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final file = await ref
                                  .read(importExportServiceProvider)
                                  .exportFinancialReportPdf(
                                    title: range.label,
                                    start: range.start,
                                    end: range.end,
                                    totalIncome: r.totalIncome,
                                    totalExpense: r.totalConsumptionExpense,
                                    categoryRows: [
                                      for (final c in r.expenseByCategory)
                                        (name: c.category.name, amount: c.amount),
                                    ],
                                  );
                              await Share.shareXFiles([file]);
                            },
                            icon: const Icon(LucideIcons.fileDown, size: 17),
                            label: const Text('Export PDF'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => context.push('/reports/recap'),
                            icon: const Icon(LucideIcons.sparkles, size: 17),
                            label: const Text('Buka Recap'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Financial Health Score (0-100) Bento Card
                    _FinancialHealthScoreCard(
                      report: r,
                      sts: ref.watch(safeToSpendProvider).valueOrNull,
                    ),
                    const SizedBox(height: 12),

                    // Summary Card: Consumption vs Cashflow (FR-21)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              range.label,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 160,
                              child: BarChart(
                                BarChartData(
                                  borderData: FlBorderData(show: false),
                                  gridData: const FlGridData(show: false),
                                  titlesData: FlTitlesData(
                                    topTitles: const AxisTitles(),
                                    rightTitles: const AxisTitles(),
                                    leftTitles: const AxisTitles(),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (val, _) {
                                          return Text(
                                            val.toInt() == 0
                                                ? 'Pemasukan'
                                                : 'Pengeluaran',
                                            style: const TextStyle(fontSize: 12),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  barGroups: [
                                    BarChartGroupData(
                                      x: 0,
                                      barRods: [
                                        BarChartRodData(
                                          toY: r.totalIncome.toDouble(),
                                          color: ArusColors.income,
                                          width: 34,
                                          borderRadius:
                                              const BorderRadius.vertical(
                                            top: Radius.circular(10),
                                          ),
                                        ),
                                      ],
                                    ),
                                    BarChartGroupData(
                                      x: 1,
                                      barRods: [
                                        BarChartRodData(
                                          toY: r.totalConsumptionExpense
                                              .toDouble(),
                                          color: ArusColors.expense,
                                          width: 34,
                                          borderRadius:
                                              const BorderRadius.vertical(
                                            top: Radius.circular(10),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 20),
                            _MetricLine(
                              'Pemasukan',
                              MoneyFormatter.format(r.totalIncome),
                              ArusColors.income,
                            ),
                            _MetricLine(
                              'Pengeluaran Konsumsi',
                              MoneyFormatter.format(r.totalConsumptionExpense),
                              ArusColors.expense,
                            ),
                            _MetricLine(
                              'Arus Kas Masuk / Keluar',
                              '${MoneyFormatter.formatCompact(r.cashInflow)} / ${MoneyFormatter.formatCompact(r.cashOutflow)}',
                              null,
                            ),
                            if (r.savingRatePercent != null)
                              _MetricLine(
                                'Saving Rate',
                                '${r.savingRatePercent!.toStringAsFixed(1)}%',
                                ArusColors.primary,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Daily Summary & Average Expense Card
                    _DailySummaryCard(report: r),
                    const SizedBox(height: 12),

                    // Interactive Cashflow Heatmap Calendar
                    _CashflowHeatmapCalendarCard(
                      report: r,
                      dailySafeBenchmark: ref
                              .watch(safeToSpendProvider)
                              .valueOrNull
                              ?.dailySafeSpend ??
                          r.averageDailyExpense,
                    ),
                    const SizedBox(height: 12),

                    // Category Pie Chart
                    if (r.expenseByCategory.isNotEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pengeluaran per Kategori',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 180,
                                child: PieChart(
                                  PieChartData(
                                    centerSpaceRadius: 38,
                                    sectionsSpace: 2,
                                    sections: [
                                      for (final slice in r.expenseByCategory)
                                        PieChartSectionData(
                                          value: slice.amount.toDouble(),
                                          color: Color(slice.category.colorValue),
                                          title:
                                              '${slice.percentage.round()}%',
                                          radius: 48,
                                          titleStyle: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              for (final slice in r.expenseByCategory)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    children: [
                                      LanjoIconBox(
                                        icon: arusIconFromName(
                                          slice.category.icon,
                                        ),
                                        color: Color(slice.category.colorValue),
                                        size: 36,
                                        iconSize: 17,
                                        radius: 11,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              slice.category.name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall,
                                            ),
                                            Text(
                                              '${slice.txCount} transaksi • ${slice.percentage.toStringAsFixed(1)}%',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        MoneyFormatter.format(slice.amount),
                                        style: lanjoMoneyStyle(
                                          context,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Top Merchants
                    if (r.topMerchants.isNotEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Merchant Teratas',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              for (final m in r.topMerchants)
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(m.merchant),
                                  subtitle: Text('${m.visitCount}x transaksi'),
                                  trailing: Text(
                                    MoneyFormatter.format(m.totalAmount),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
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
          const SizedBox(width: 8),
          Text(
            value,
            style: lanjoMoneyStyle(
              context,
              fontSize: 13.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DailySummaryCard extends StatelessWidget {
  const _DailySummaryCard({required this.report});

  final FinancialSummaryReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dailyDesc = report.sortedDailyDescending;
    final chartDays = dailyDesc.take(14).toList().reversed.toList();
    final highest = report.highestExpenseDay;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ringkasan & Rata-Rata Harian',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DailyKpiBox(
                    label: 'Hari Ini',
                    value: MoneyFormatter.formatCompact(report.todayExpense),
                    sub: 'Pengeluaran hari ini',
                    color: ArusColors.expense,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DailyKpiBox(
                    label: 'Rata-rata / Hari',
                    value:
                        MoneyFormatter.formatCompact(report.averageDailyExpense),
                    sub: 'Dari ${report.elapsedDaysInRange} hari periode',
                    color: ArusColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DailyKpiBox(
                    label: 'Rata-rata Hari Aktif',
                    value: MoneyFormatter.formatCompact(
                      report.averageActiveDayExpense,
                    ),
                    sub: '${report.activeExpenseDaysCount} hari ada belanja',
                    color: null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DailyKpiBox(
                    label: 'Hari Tertinggi',
                    value: highest == null
                        ? 'Rp0'
                        : MoneyFormatter.formatCompact(highest.amount),
                    sub: highest == null
                        ? 'Belum ada data'
                        : ArusDateUtils.formatShortDate(highest.day),
                    color: ArusColors.warning,
                  ),
                ),
              ],
            ),
            if (chartDays.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Grafik Pengeluaran Harian',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 150,
                child: BarChart(
                  BarChartData(
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      leftTitles: const AxisTitles(),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= chartDays.length) {
                              return const SizedBox.shrink();
                            }
                            if (chartDays.length > 7 && idx % 2 != 0) {
                              return const SizedBox.shrink();
                            }
                            final d = chartDays[idx].day;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${d.day}/${d.month}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < chartDays.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: chartDays[i].expense.toDouble(),
                              color: ArusColors.expense,
                              width: chartDays.length > 8 ? 11 : 18,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (dailyDesc.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                'Total Per Hari',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              for (final item in dailyDesc.take(31))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          ArusDateUtils.formatShortDate(item.day),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (item.income > 0) ...[
                        Text(
                          '+${MoneyFormatter.formatCompact(item.income)}',
                          style: const TextStyle(
                            color: ArusColors.income,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        item.expense > 0
                            ? '-${MoneyFormatter.format(item.expense)}'
                            : 'Rp0',
                        style: TextStyle(
                          color: item.expense > 0
                              ? ArusColors.expense
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                'Belum ada transaksi di rentang tanggal ini.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DailyKpiBox extends StatelessWidget {
  const _DailyKpiBox({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  final String label;
  final String value;
  final String sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.lanjoSurfaceSecondary.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.lanjoBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: lanjoMoneyStyle(
              context,
              fontSize: 15.5,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: context.lanjoSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

class _CashflowHeatmapCalendarCard extends StatefulWidget {
  const _CashflowHeatmapCalendarCard({
    required this.report,
    required this.dailySafeBenchmark,
  });

  final FinancialSummaryReport report;
  final int dailySafeBenchmark;

  @override
  State<_CashflowHeatmapCalendarCard> createState() =>
      _CashflowHeatmapCalendarCardState();
}

class _CashflowHeatmapCalendarCardState
    extends State<_CashflowHeatmapCalendarCard> {
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anchor = widget.report.end;
    final year = anchor.year;
    final month = anchor.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leadingBlanks = firstDay.weekday - 1; // Mon = 0 .. Sun = 6
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final benchmark = widget.dailySafeBenchmark > 0
        ? widget.dailySafeBenchmark
        : (widget.report.averageDailyExpense > 0
            ? widget.report.averageDailyExpense
            : 100000);

    final selected = _selectedDay ??
        (today.year == year && today.month == month ? today : firstDay);
    final selectedFlow =
        widget.report.dailyCashflow[selected] ?? (income: 0, expense: 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Kalender Heatmap Harian',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  ArusDateUtils.formatMonthYear(firstDay),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Hijau = di bawah batas aman (${MoneyFormatter.formatCompact(benchmark)}/hr) • Merah = melebihi batas.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final wd in const [
                  'Sen',
                  'Sel',
                  'Rab',
                  'Kam',
                  'Jum',
                  'Sab',
                  'Min',
                ])
                  Expanded(
                    child: Center(
                      child: Text(
                        wd,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: context.lanjoSubtle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: leadingBlanks + daysInMonth,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.05,
              ),
              itemBuilder: (context, index) {
                if (index < leadingBlanks) {
                  return const SizedBox.shrink();
                }
                final dayNum = index - leadingBlanks + 1;
                final date = DateTime(year, month, dayNum);
                final isFuture = date.isAfter(today);
                final flow = widget.report.dailyCashflow[date] ??
                    (income: 0, expense: 0);
                final exp = flow.expense;
                final isSelected = selected.year == date.year &&
                    selected.month == date.month &&
                    selected.day == date.day;

                Color bgColor;
                Color textColor = context.lanjoInk;
                if (isFuture) {
                  bgColor = context.lanjoSurfaceSecondary.withValues(alpha: 0.4);
                  textColor = context.lanjoSubtle;
                } else if (exp == 0) {
                  bgColor = ArusColors.income.withValues(
                    alpha: context.isDark ? 0.16 : 0.11,
                  );
                  textColor = ArusColors.income;
                } else if (exp <= benchmark * 0.85) {
                  bgColor = ArusColors.income.withValues(
                    alpha: context.isDark ? 0.28 : 0.20,
                  );
                  textColor = ArusColors.income;
                } else if (exp <= benchmark) {
                  bgColor = ArusColors.warning.withValues(
                    alpha: context.isDark ? 0.25 : 0.18,
                  );
                  textColor = ArusColors.warning;
                } else {
                  bgColor = ArusColors.expense.withValues(
                    alpha: context.isDark ? 0.28 : 0.18,
                  );
                  textColor = ArusColors.expense;
                }

                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _selectedDay = date),
                  child: Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(
                              color: theme.colorScheme.primary,
                              width: 1.8,
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$dayNum',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        if (flow.income > 0)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: BoxDecoration(
                              color: context.lanjoPrimary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.lanjoSurfaceSecondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.calendar,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ArusDateUtils.formatShortDate(selected),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (selectedFlow.income > 0) ...[
                    Text(
                      '+${MoneyFormatter.formatCompact(selectedFlow.income)}',
                      style: lanjoMoneyStyle(
                        context,
                        fontSize: 12.5,
                        color: ArusColors.income,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    selectedFlow.expense > 0
                        ? '-${MoneyFormatter.format(selectedFlow.expense)}'
                        : 'Rp0 (Hemat)',
                    style: lanjoMoneyStyle(
                      context,
                      fontSize: 13,
                      color: selectedFlow.expense > benchmark
                          ? ArusColors.expense
                          : (selectedFlow.expense > 0
                              ? context.lanjoInk
                              : ArusColors.income),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinancialHealthScoreCard extends StatelessWidget {
  const _FinancialHealthScoreCard({
    required this.report,
    required this.sts,
  });

  final FinancialSummaryReport report;
  final dynamic sts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Compute a deterministic 0-100 Financial Health Score across 3 pillars
    final savingRate = report.savingRatePercent ??
        (report.totalConsumptionExpense == 0 ? 50.0 : 0.0);
    final savingScore = (savingRate.clamp(0.0, 40.0) / 40.0 * 40).round();

    final isShortfall = (sts?.isShortfall as bool?) ?? false;
    final runwayScore = isShortfall ? 10 : 35;

    final activeRatio = report.elapsedDaysInRange > 0
        ? (report.activeExpenseDaysCount / report.elapsedDaysInRange)
        : 0.5;
    final disciplineScore = ((1.0 - (activeRatio * 0.4)).clamp(0.4, 1.0) * 25)
        .round();

    final totalScore =
        (savingScore + runwayScore + disciplineScore).clamp(0, 100);

    final (Color badgeColor, String gradeLabel, String tip) = switch (totalScore) {
      >= 80 => (
          ArusColors.income,
          'Sangat Sehat',
          'Arus kas & cadangan likuidmu sangat terjaga. Pertahankan ritme ini!'
        ),
      >= 60 => (
          ArusColors.primary,
          'Stabil & Terkendali',
          'Pengeluaran harianmu masih dalam batas wajar. Sisihkan ekstra ke Target Tabungan.'
        ),
      _ => (
          ArusColors.warning,
          'Perlu Perhatian',
          'Tekan pengeluaran non-prioritas beberapa hari ke depan agar Safe-to-Spend kembali naik.'
        ),
    };

    return LanjoSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeColor.withValues(
                    alpha: context.isDark ? 0.22 : 0.12,
                  ),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: badgeColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  '$totalScore',
                  style: lanjoMoneyStyle(
                    context,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: badgeColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Skor Kesehatan Finansial',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        LanjoPillBadge(label: gradeLabel, color: badgeColor),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tip,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: totalScore / 100.0,
              minHeight: 7,
              backgroundColor: context.lanjoSurfaceSecondary,
              valueColor: AlwaysStoppedAnimation(badgeColor),
            ),
          ),
        ],
      ),
    );
  }
}
