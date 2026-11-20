import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/swipe_action_card.dart';

/// Budget management page with progress bars, forecast, recommendations,
/// rollover, previous-month duplication, and swipe-to-edit/delete (FR-08).
class BudgetsPage extends ConsumerWidget {
  const BudgetsPage({super.key});

  Future<void> _showBudgetFormDialog(
    BuildContext context,
    WidgetRef ref, {
    BudgetRecord? existing,
  }) async {
    final cats = (ref.read(categoriesProvider).valueOrNull ?? const [])
        .where((c) => !c.isArchived && c.kind == 'expense')
        .toList();
    if (cats.isEmpty) return;

    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final limitCtrl = TextEditingController(
      text: existing != null ? existing.limitAmount.toString() : '',
    );
    String? categoryId = existing != null
        ? (existing.categoryId != null && cats.any((c) => c.id == existing.categoryId)
            ? existing.categoryId
            : null)
        : cats.first.id;
    String periodType = existing?.periodType ?? 'monthly';
    bool rollover = existing?.rolloverEnabled ?? false;
    int? recommended;
    final isEditing = existing != null;

    Future<void> loadRec(String? catId, void Function(void Function()) setState) async {
      if (catId == null) return;
      final rec = await ref.read(budgetServiceProvider).recommendMonthlyBudget(catId);
      setState(() => recommended = rec > 0 ? rec : null);
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(isEditing ? 'Edit Anggaran' : 'Buat Anggaran'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  value: categoryId,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Semua Kategori'),
                    ),
                    for (final c in cats)
                      DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      categoryId = v;
                      if (nameCtrl.text.isEmpty && v != null) {
                        nameCtrl.text = cats.firstWhere((c) => c.id == v).name;
                      }
                    });
                    loadRec(v, setState);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama anggaran',
                    hintText: 'Contoh: Makanan Bulanan',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: limitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Batas anggaran (Rp)',
                    helperText: recommended != null
                        ? 'Saran historis: ${MoneyFormatter.format(recommended!)}'
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: periodType,
                  decoration: const InputDecoration(labelText: 'Periode'),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Harian')),
                    DropdownMenuItem(value: 'weekly', child: Text('Mingguan')),
                    DropdownMenuItem(value: 'monthly', child: Text('Bulanan')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => periodType = v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktifkan rollover sisa anggaran'),
                  value: rollover,
                  onChanged: (v) => setState(() => rollover = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final limit = int.tryParse(limitCtrl.text.trim()) ?? 0;
                if (limit <= 0) return;
                final now = DateTime.now();
                final settings = ref.read(appSettingsProvider).valueOrNull;
                late DateTime start;
                late DateTime end;
                if (isEditing && existing.periodType == periodType) {
                  start = existing.startDate;
                  end = existing.endDate;
                } else if (periodType == 'daily') {
                  start = DateTime(now.year, now.month, now.day);
                  end = start.add(const Duration(days: 1)).subtract(
                        const Duration(seconds: 1),
                      );
                } else if (periodType == 'weekly') {
                  start = DateTime(now.year, now.month, now.day)
                      .subtract(Duration(days: now.weekday - 1));
                  end = start.add(const Duration(days: 7)).subtract(
                        const Duration(seconds: 1),
                      );
                } else {
                  final p = ArusDateUtils.currentFinancialPeriod(
                    now: now,
                    paydayDay: settings?.paydayDay,
                  );
                  start = p.start;
                  end = p.endExclusive.subtract(const Duration(seconds: 1));
                }

                final name = nameCtrl.text.trim().isNotEmpty
                    ? nameCtrl.text.trim()
                    : (categoryId == null
                        ? 'Anggaran Umum'
                        : cats.firstWhere((c) => c.id == categoryId).name);

                final svc = ref.read(budgetServiceProvider);
                if (isEditing) {
                  await svc.updateBudget(
                    budgetId: existing.id,
                    name: name,
                    categoryId: categoryId,
                    limitAmount: limit,
                    periodType: periodType,
                    startDate: start,
                    endDate: end,
                    rolloverEnabled: rollover,
                  );
                } else {
                  await svc.createBudget(
                    name: name,
                    categoryId: categoryId,
                    limitAmount: limit,
                    periodType: periodType,
                    startDate: start,
                    endDate: end,
                    rolloverEnabled: rollover,
                  );
                }
                ref.invalidate(budgetProgressesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(isEditing ? 'Simpan Perubahan' : 'Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteBudget(
    BuildContext context,
    WidgetRef ref,
    BudgetRecord budget,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Anggaran?'),
        content: Text(
          'Anggaran "${budget.name}" akan dihapus. Transaksi pengeluaran yang sudah tercatat tidak ikut terhapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ArusColors.expense),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(budgetServiceProvider).deleteBudget(budget.id);
    ref.invalidate(budgetProgressesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetsAsync = ref.watch(budgetProgressesProvider);
    final settings = ref.watch(appSettingsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anggaran'),
        actions: [
          IconButton(
            tooltip: 'Duplikasi bulan lalu',
            icon: const Icon(LucideIcons.copy, size: 19),
            onPressed: () async {
              final count = await ref
                  .read(budgetServiceProvider)
                  .duplicatePreviousMonthBudgets(paydayDay: settings?.paydayDay);
              ref.invalidate(budgetProgressesProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      count > 0
                          ? '$count anggaran berhasil diduplikasi.'
                          : 'Tidak ada anggaran baru untuk diduplikasi.',
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBudgetFormDialog(context, ref),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Buat Anggaran'),
      ),
      body: budgetsAsync.when(
        data: (list) {
          if (list.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyStateCard(
                icon: LucideIcons.pieChart,
                title: 'Belum ada anggaran',
                subtitle: 'Buat batas pengeluaran agar pengeluaranmu lebih terkontrol.',
                actionLabel: 'Buat Anggaran',
                onAction: () => _showBudgetFormDialog(context, ref),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            itemCount: list.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text(
                  'Geser kartu ke kiri untuk Edit / Hapus anggaran.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                );
              }
              final p = list[index - 1];
              final statusColor = p.isExceeded
                  ? ArusColors.expense
                  : (p.isWarning80 ? ArusColors.warning : ArusColors.income);
              return SwipeActionCard(
                onEdit: () =>
                    _showBudgetFormDialog(context, ref, existing: p.budget),
                onDelete: () =>
                    _confirmDeleteBudget(context, ref, p.budget),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                p.budget.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Chip(
                              label: Text(
                                p.isExceeded
                                    ? 'Melebihi'
                                    : (p.isWarning80 ? 'Hampir Habis' : 'Aman'),
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: p.ratio.clamp(0.0, 1.0),
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(5),
                          color: statusColor,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Terpakai: ${MoneyFormatter.format(p.spentAmount)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Batas: ${MoneyFormatter.format(p.effectiveLimit)}',
                                textAlign: TextAlign.end,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sisa: ${MoneyFormatter.format(p.remaining)} • Prediksi akhir: ${MoneyFormatter.format(p.projectedEndSpend)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
