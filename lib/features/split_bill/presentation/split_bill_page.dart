import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/swipe_action_card.dart';
import '../domain/split_bill_service.dart';

/// Split Bill creation, deterministic Rupiah rounding, friend repayment tracking,
/// cancellation/deletion, title edit, and WhatsApp/text share (FR-14).
class SplitBillPage extends ConsumerWidget {
  const SplitBillPage({super.key});

  Future<void> _showCreateSplitDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final wallets = ref.read(activeWalletsProvider);
    final cats = (ref.read(categoriesProvider).valueOrNull ?? const [])
        .where((c) => !c.isArchived && c.kind == 'expense')
        .toList();
    if (wallets.isEmpty || cats.isEmpty) return;

    final titleCtrl = TextEditingController();
    final totalCtrl = TextEditingController();
    final friendsCtrl = TextEditingController(text: 'Andi, Budi, Citra');
    var walletId = wallets.first.id;
    var catId = cats.first.id;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Buat Split Bill'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama acara / tagihan',
                    hintText: 'Contoh: Makan malam tim',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: totalCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Total tagihan (Rp)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: friendsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama teman (pisahkan koma)',
                    helperText: 'Bagianmu otomatis ditambahkan sebagai peserta "Saya".',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: walletId,
                  decoration: const InputDecoration(labelText: 'Dompet Pembayar'),
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
                  initialValue: catId,
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
                final total = int.tryParse(totalCtrl.text.trim()) ?? 0;
                final friendNames = friendsCtrl.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                if (titleCtrl.text.trim().isEmpty ||
                    total <= 0 ||
                    friendNames.isEmpty) {
                  return;
                }

                final parts = MoneyFormatter.splitEqually(
                  total,
                  friendNames.length + 1,
                );
                final participants = <SplitParticipantInput>[
                  SplitParticipantInput(
                    name: 'Saya',
                    isSelf: true,
                    shareAmount: parts[0],
                  ),
                  for (var i = 0; i < friendNames.length; i++)
                    SplitParticipantInput(
                      name: friendNames[i],
                      isSelf: false,
                      shareAmount: parts[i + 1],
                    ),
                ];

                await ref.read(splitBillServiceProvider).createSplitBill(
                      title: titleCtrl.text.trim(),
                      totalAmount: total,
                      payerWalletId: walletId,
                      categoryId: catId,
                      splitMode: 'equal',
                      participants: participants,
                      occurredAt: DateTime.now(),
                      allowNegativeBalance: true,
                    );
                ref.invalidate(safeToSpendProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditTitleDialog(
    BuildContext context,
    WidgetRef ref,
    SplitBillRecord bill,
  ) async {
    final titleCtrl = TextEditingController(text: bill.title);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Judul Split Bill'),
        content: TextField(
          controller: titleCtrl,
          decoration: const InputDecoration(labelText: 'Nama acara / tagihan'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty) return;
              await ref.read(splitBillServiceProvider).updateSplitBillTitle(
                    splitBillId: bill.id,
                    title: titleCtrl.text.trim(),
                  );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Simpan Perubahan'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancelSplitBill(
    BuildContext context,
    WidgetRef ref,
    SplitBillRecord bill,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus / Batalkan Split Bill?'),
        content: Text(
          'Split bill "${bill.title}" beserta transaksi bagianmu dan piutang teman akan dibatalkan & saldo dikembalikan.',
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
    await ref.read(splitBillServiceProvider).cancelSplitBill(bill.id);
    ref.invalidate(safeToSpendProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    final svc = ref.read(splitBillServiceProvider);
    final wallets = ref.watch(activeWalletsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Split Bill')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSplitDialog(context, ref),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Buat Split Bill'),
      ),
      body: StreamBuilder<List<SplitBillRecord>>(
        stream: db.select(db.splitBills).watch(),
        builder: (context, snap) {
          final bills = (snap.data ?? const [])
              .where((b) => b.status != 'cancelled')
              .toList();
          if (bills.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyStateCard(
                icon: LucideIcons.split,
                title: 'Belum ada Split Bill',
                subtitle: 'Bagi tagihan bersama teman. Bagian teman tercatat sebagai piutang, bukan pengeluaran pribadimu.',
                actionLabel: 'Buat Split Bill',
                onAction: () => _showCreateSplitDialog(context, ref),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            itemCount: bills.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text(
                  'Geser kartu ke kiri untuk Edit judul / Hapus split bill.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                );
              }
              final bill = bills[index - 1];
              return StreamBuilder<List<SplitBillMemberRecord>>(
                stream: (db.select(db.splitBillMembers)
                      ..where((m) => m.splitBillId.equals(bill.id)))
                    .watch(),
                builder: (context, mSnap) {
                  final members = mSnap.data ?? const [];
                  return SwipeActionCard(
                    onEdit: () => _showEditTitleDialog(context, ref, bill),
                    onDelete: () => _confirmCancelSplitBill(context, ref, bill),
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
                                    bill.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Text(
                                  MoneyFormatter.format(bill.totalAmount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(),
                            for (final m in members)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(m.name),
                                subtitle: Text(
                                  MoneyFormatter.format(m.shareAmount),
                                ),
                                trailing: m.isSelf
                                    ? const Chip(label: Text('Bagianku'))
                                    : (m.isSettled
                                        ? const Chip(label: Text('Lunas'))
                                        : FilledButton.tonal(
                                            onPressed: wallets.isEmpty
                                                ? null
                                                : () async {
                                                    await svc.markMemberPaid(
                                                      memberId: m.id,
                                                      walletId:
                                                          bill.payerWalletId,
                                                    );
                                                    ref.invalidate(
                                                      safeToSpendProvider,
                                                    );
                                                  },
                                            child: const Text('Sudah Bayar'),
                                          )),
                              ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () {
                                  final text = svc.buildShareText(bill, members);
                                  Share.share(text);
                                },
                                icon: const Icon(LucideIcons.share2, size: 16),
                                label: const Text('Bagikan'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
