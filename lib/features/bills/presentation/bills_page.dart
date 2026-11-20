import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/swipe_action_card.dart';
import '../../bills/domain/bill_service.dart';

/// Recurring bills & active subscriptions page (FR-10).
class BillsPage extends ConsumerWidget {
  const BillsPage({super.key});

  Future<void> _showBillFormDialog(
    BuildContext context,
    WidgetRef ref, {
    BillOccurrenceView? existing,
  }) async {
    final wallets = ref.read(activeWalletsProvider);
    final cats = (ref.read(categoriesProvider).valueOrNull ?? const [])
        .where((c) => !c.isArchived && c.kind == 'expense')
        .toList();
    if (wallets.isEmpty || cats.isEmpty) return;

    final b = existing?.bill;
    final nameCtrl = TextEditingController(text: b?.name ?? '');
    final amtCtrl = TextEditingController(
      text: b != null ? b.estimatedAmount.toString() : '',
    );
    var walletId = b != null && wallets.any((w) => w.id == b.walletId)
        ? b.walletId
        : wallets.first.id;
    var catId = b != null && cats.any((c) => c.id == b.categoryId)
        ? b.categoryId
        : cats.first.id;
    var freq = b?.frequency ?? 'monthly';
    var isSub = b?.isSubscription ?? false;
    var dueDate =
        existing?.occurrence.dueDate ?? DateTime.now().add(const Duration(days: 3));
    final isEditing = existing != null;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            isEditing ? 'Edit Tagihan / Langganan' : 'Tambah Tagihan / Langganan',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama (mis. Kos / Internet / Netflix)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amtCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: freq,
                  decoration: const InputDecoration(labelText: 'Frekuensi'),
                  items: const [
                    DropdownMenuItem(value: 'weekly', child: Text('Mingguan')),
                    DropdownMenuItem(value: 'monthly', child: Text('Bulanan')),
                    DropdownMenuItem(value: 'yearly', child: Text('Tahunan')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => freq = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: walletId,
                  decoration: const InputDecoration(labelText: 'Dompet'),
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
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: catId,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: [
                    for (final c in cats)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => catId = v);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(isEditing ? 'Jatuh tempo berikutnya' : 'Jatuh tempo pertama'),
                  subtitle: Text(ArusDateUtils.formatShortDate(dueDate)),
                  trailing: const Icon(LucideIcons.calendar, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: dueDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) setState(() => dueDate = picked);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Termasuk Subscription'),
                  value: isSub,
                  onChanged: (v) => setState(() => isSub = v),
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
                if (nameCtrl.text.trim().isEmpty || amt <= 0) return;
                final svc = ref.read(billServiceProvider);
                if (isEditing) {
                  await svc.updateBill(
                    billId: b!.id,
                    name: nameCtrl.text.trim(),
                    estimatedAmount: amt,
                    categoryId: catId,
                    walletId: walletId,
                    frequency: freq,
                    dueDate: dueDate,
                    isSubscription: isSub,
                  );
                } else {
                  await svc.createBill(
                    name: nameCtrl.text.trim(),
                    kind: 'expense',
                    estimatedAmount: amt,
                    categoryId: catId,
                    walletId: walletId,
                    frequency: freq,
                    firstDueDate: dueDate,
                    isSubscription: isSub,
                  );
                }
                ref.invalidate(activeBillOccurrencesProvider);
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

  Future<void> _showConfirmPaymentDialog(
    BuildContext context,
    WidgetRef ref,
    BillOccurrenceView view,
  ) async {
    final amtCtrl =
        TextEditingController(text: view.remainingAmount.toString());
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bayar ${view.bill.name}'),
        content: TextField(
          controller: amtCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nominal aktual dibayar (Rp)',
            helperText: 'Bisa bayar sebagian atau ubah nominal jika berbeda.',
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
              await ref.read(billServiceProvider).confirmPayment(
                    occurrenceId: view.occurrence.id,
                    actualAmount: amt,
                    allowNegativeBalance: true,
                  );
              ref.invalidate(activeBillOccurrencesProvider);
              ref.invalidate(safeToSpendProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Konfirmasi Bayar'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteBill(
    BuildContext context,
    WidgetRef ref,
    BillOccurrenceView item,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus / Hentikan Tagihan?'),
        content: Text(
          'Tagihan "${item.bill.name}" akan dihentikan dan pengingat jadwalnya dibatalkan. Riwayat pembayaran sebelumnya tetap tersimpan.',
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
    await ref.read(billServiceProvider).cancelBill(item.bill.id);
    ref.invalidate(activeBillOccurrencesProvider);
    ref.invalidate(safeToSpendProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billsAsync = ref.watch(activeBillOccurrencesProvider);
    final subSummaryFuture = ref.watch(billServiceProvider).getSubscriptionSummary();

    return Scaffold(
      appBar: AppBar(title: const Text('Tagihan & Subscription')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBillFormDialog(context, ref),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Tambah Tagihan'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          FutureBuilder(
            future: subSummaryFuture,
            builder: (context, snap) {
              if (!snap.hasData || snap.data!.subscriptions.isEmpty) {
                return const SizedBox.shrink();
              }
              final sub = snap.data!;
              return Card(
                child: ListTile(
                  leading: const Icon(LucideIcons.repeat, size: 20, color: ArusColors.warning),
                  title: Text(
                    'Subscription Aktif (${sub.subscriptions.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Estimasi: ${MoneyFormatter.format(sub.monthlyTotal)}/bln • ${MoneyFormatter.format(sub.yearlyTotal)}/thn',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          billsAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return EmptyStateCard(
                  icon: LucideIcons.calendarClock,
                  title: 'Belum ada tagihan terjadwal',
                  subtitle: 'Tagihan mendatang tidak memotong saldo sampai kamu mengonfirmasi pembayaran.',
                  actionLabel: 'Tambah Tagihan',
                  onAction: () => _showBillFormDialog(context, ref),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Geser kartu ke kiri untuk Edit / Hapus tagihan.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  for (final item in items) ...[
                    SwipeActionCard(
                      onEdit: () =>
                          _showBillFormDialog(context, ref, existing: item),
                      onDelete: () => _confirmDeleteBill(context, ref, item),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.bill.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    MoneyFormatter.format(item.remainingAmount),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: ArusColors.expense,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Jatuh tempo: ${ArusDateUtils.formatShortDate(item.occurrence.dueDate)} • Status: ${item.occurrence.status}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  FilledButton.tonal(
                                    onPressed: () => _showConfirmPaymentDialog(
                                      context,
                                      ref,
                                      item,
                                    ),
                                    child: const Text('Bayar'),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () async {
                                      await ref
                                          .read(billServiceProvider)
                                          .skipOccurrence(item.occurrence.id);
                                      ref.invalidate(
                                        activeBillOccurrencesProvider,
                                      );
                                      ref.invalidate(safeToSpendProvider);
                                    },
                                    child: const Text('Lewati'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}
