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
import '../domain/goal_service.dart';

/// Saving Goals page with virtual allocation, savings wallet transfers,
/// and swipe-to-edit/delete (FR-11).
class GoalsPage extends ConsumerWidget {
  const GoalsPage({super.key});

  Future<void> _showGoalFormDialog(
    BuildContext context,
    WidgetRef ref, {
    GoalRecord? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final targetCtrl = TextEditingController(
      text: existing != null ? existing.targetAmount.toString() : '',
    );
    DateTime? targetDate = existing?.targetDate;
    final isEditing = existing != null;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(isEditing ? 'Edit Target Tabungan' : 'Target Tabungan Baru'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama target (mis. Dana Darurat)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: targetCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nominal Target (Rp)'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tanggal Target (opsional)'),
                  subtitle: Text(
                    targetDate == null
                        ? 'Belum ditentukan'
                        : ArusDateUtils.formatShortDate(targetDate!),
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if (targetDate != null)
                        IconButton(
                          tooltip: 'Hapus tanggal target',
                          icon: const Icon(LucideIcons.x, size: 17),
                          onPressed: () => setState(() => targetDate = null),
                        ),
                      const Icon(LucideIcons.calendar, size: 18),
                    ],
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: targetDate ??
                          DateTime.now().add(const Duration(days: 180)),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2040),
                    );
                    if (picked != null) setState(() => targetDate = picked);
                  },
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
                final target = int.tryParse(targetCtrl.text.trim()) ?? 0;
                if (nameCtrl.text.trim().isEmpty || target <= 0) return;
                final svc = ref.read(goalServiceProvider);
                if (isEditing) {
                  await svc.updateGoal(
                    goalId: existing.id,
                    name: nameCtrl.text.trim(),
                    targetAmount: target,
                    targetDate: targetDate,
                    clearTargetDate: targetDate == null,
                  );
                } else {
                  await svc.createGoal(
                    name: nameCtrl.text.trim(),
                    targetAmount: target,
                    targetDate: targetDate,
                  );
                }
                ref.invalidate(safeToSpendProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(isEditing ? 'Simpan Perubahan' : 'Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showContributeDialog(
    BuildContext context,
    WidgetRef ref,
    GoalRecord goal,
  ) async {
    final wallets = ref.read(activeWalletsProvider);
    if (wallets.isEmpty) return;

    final amtCtrl = TextEditingController();
    var walletId = wallets.first.id;
    String? savingsWalletId;
    var isVirtual = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Tabung ke ${goal.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amtCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: walletId,
                  decoration: const InputDecoration(labelText: 'Dari Dompet'),
                  items: [
                    for (final w in wallets)
                      DropdownMenuItem(
                        value: w.id,
                        child: Text(w.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => walletId = v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Alokasi virtual'),
                  subtitle: const Text('Tandai dana tanpa transfer antarwallet'),
                  value: isVirtual,
                  onChanged: (v) => setState(() => isVirtual = v),
                ),
                if (!isVirtual)
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: savingsWalletId,
                    decoration: const InputDecoration(
                      labelText: 'Ke Dompet Tabungan',
                    ),
                    items: [
                      for (final w in wallets)
                        if (w.id != walletId)
                          DropdownMenuItem<String?>(
                            value: w.id,
                            child: Text(w.name, overflow: TextOverflow.ellipsis),
                          ),
                    ],
                    onChanged: (v) => setState(() => savingsWalletId = v),
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
                final amt = int.tryParse(amtCtrl.text.trim()) ?? 0;
                if (amt <= 0) return;
                try {
                  await ref.read(goalServiceProvider).contribute(
                        goalId: goal.id,
                        amount: amt,
                        fromWalletId: walletId,
                        savingsWalletId: savingsWalletId,
                        isVirtual: isVirtual,
                      );
                  ref.invalidate(safeToSpendProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('$e')),
                    );
                  }
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteGoal(
    BuildContext context,
    WidgetRef ref,
    GoalRecord goal,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Target Tabungan?'),
        content: Text(
          'Target "${goal.name}" akan dihapus dan alokasi dana virtual yang terkunci akan dikembalikan ke dana bebas Anda.',
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
    await ref.read(goalServiceProvider).deleteGoal(goal.id);
    ref.invalidate(safeToSpendProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    final goalsStream = db.select(db.goals).watch();

    return Scaffold(
      appBar: AppBar(title: const Text('Target Tabungan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGoalFormDialog(context, ref),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Target Baru'),
      ),
      body: StreamBuilder<List<GoalRecord>>(
        stream: goalsStream,
        builder: (context, snap) {
          final goals = snap.data ?? const [];
          if (goals.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyStateCard(
                icon: LucideIcons.piggyBank,
                title: 'Belum ada target tabungan',
                subtitle: 'Buat target tabungan dan pantau progresnya setiap bulan.',
                actionLabel: 'Buat Target',
                onAction: () => _showGoalFormDialog(context, ref),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            itemCount: goals.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text(
                  'Geser kartu ke kiri untuk Edit / Hapus target tabungan.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                );
              }
              final g = goals[index - 1];
              final ratio = g.targetAmount > 0
                  ? (g.currentAmount / g.targetAmount).clamp(0.0, 1.0)
                  : 0.0;
              final monthly = GoalService.monthlyNeeded(g);
              return SwipeActionCard(
                onEdit: () => _showGoalFormDialog(context, ref, existing: g),
                onDelete: () => _confirmDeleteGoal(context, ref, g),
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
                                g.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Text(
                              '${(ratio * 100).round()}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: ArusColors.income,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: ratio,
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(5),
                          color: ArusColors.income,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${MoneyFormatter.format(g.currentAmount)} / ${MoneyFormatter.format(g.targetAmount)}',
                        ),
                        if (monthly > 0)
                          Text(
                            'Kebutuhan menabung: ${MoneyFormatter.format(monthly)} / bulan',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            FilledButton.tonal(
                              onPressed: () =>
                                  _showContributeDialog(context, ref, g),
                              child: const Text('Tambah Dana'),
                            ),
                            const SizedBox(width: 8),
                            if (g.currentAmount > 0)
                              TextButton(
                                onPressed: () async {
                                  await ref.read(goalServiceProvider).withdraw(
                                        goalId: g.id,
                                        amount: g.currentAmount,
                                      );
                                  ref.invalidate(safeToSpendProvider);
                                },
                                child: const Text('Tarik Dana'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
