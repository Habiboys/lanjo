import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/lanjo_ui.dart';
import '../../../core/widgets/swipe_action_card.dart';

/// Wallet management + Edit/Delete/Archive + Balance Reconciliation (FR-02, FR-26).
class WalletsPage extends ConsumerWidget {
  const WalletsPage({super.key});

  static String _iconForType(String type) => switch (type) {
        'cash' => 'wallet',
        'ewallet' => 'ewallet',
        'savings' => 'savings',
        'credit_card' => 'credit_card',
        'paylater' => 'paylater',
        _ => 'bank',
      };

  Future<void> _showWalletFormDialog(
    BuildContext context,
    WidgetRef ref, {
    AccountRecord? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final balCtrl = TextEditingController(
      text: existing != null ? existing.openingBalance.toString() : '0',
    );
    var type = existing?.accountType ?? 'bank';
    var includeInSpendable = existing?.includeInSpendable ?? true;
    var includeInTotal = existing?.includeInTotal ?? true;
    final isEditing = existing != null;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(isEditing ? 'Edit Dompet' : 'Tambah Dompet'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama dompet (mis. BCA / GoPay)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Jenis'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Tunai (Cash)')),
                    DropdownMenuItem(value: 'bank', child: Text('Rekening Bank')),
                    DropdownMenuItem(value: 'ewallet', child: Text('E-Wallet')),
                    DropdownMenuItem(value: 'savings', child: Text('Tabungan')),
                    DropdownMenuItem(
                      value: 'credit_card',
                      child: Text('Kartu Kredit'),
                    ),
                    DropdownMenuItem(value: 'paylater', child: Text('PayLater')),
                    DropdownMenuItem(value: 'other', child: Text('Lainnya')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        type = v;
                        if (v == 'credit_card' || v == 'paylater') {
                          includeInSpendable = false;
                        } else if (!isEditing) {
                          includeInSpendable = v != 'savings';
                        }
                      });
                    }
                  },
                ),
                if (!isEditing) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: balCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Saldo awal (Rp)',
                      helperText: 'Tidak dihitung sebagai pemasukan',
                    ),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Masuk total kekayaan'),
                  value: includeInTotal,
                  onChanged: (v) => setState(() => includeInTotal = v),
                ),
                if (type != 'credit_card' && type != 'paylater')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tersedia untuk belanja'),
                    value: includeInSpendable,
                    onChanged: (v) => setState(() => includeInSpendable = v),
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
                if (nameCtrl.text.trim().isEmpty) return;
                final ledger = ref.read(ledgerEngineProvider);
                final icon = _iconForType(type);
                if (isEditing) {
                  await ledger.updateWallet(
                    walletId: existing.id,
                    name: nameCtrl.text.trim(),
                    accountType: type,
                    icon: icon,
                    includeInTotal: includeInTotal,
                    includeInSpendable: includeInSpendable,
                  );
                } else {
                  final bal = int.tryParse(balCtrl.text.trim()) ?? 0;
                  await ledger.createWallet(
                    name: nameCtrl.text.trim(),
                    accountType: type,
                    icon: icon,
                    colorValue: ArusColors.primary.toARGB32(),
                    openingBalance: bal,
                    includeInTotal: includeInTotal,
                    includeInSpendable: includeInSpendable,
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

  Future<void> _showReconcileDialog(
    BuildContext context,
    WidgetRef ref,
    AccountRecord wallet,
  ) async {
    final actualCtrl =
        TextEditingController(text: wallet.cachedBalance.toString());
    final reasonCtrl = TextEditingController(text: 'Penyesuaian saldo aktual');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rekonsiliasi: ${wallet.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo di Lanjo: ${MoneyFormatter.format(wallet.cachedBalance)}'),
            const SizedBox(height: 12),
            TextField(
              controller: actualCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Saldo aktual di bank/dompet (Rp)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Alasan penyesuaian'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              final actual = int.tryParse(actualCtrl.text.trim());
              if (actual == null) return;
              await ref.read(ledgerEngineProvider).reconcileWalletBalance(
                    walletId: wallet.id,
                    actualBalance: actual,
                    reason: reasonCtrl.text.trim().isEmpty
                        ? 'Penyesuaian saldo aktual'
                        : reasonCtrl.text.trim(),
                  );
              ref.invalidate(safeToSpendProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Sesuaikan Saldo'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteOrArchiveWallet(
    BuildContext context,
    WidgetRef ref,
    AccountRecord wallet,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus / Arsipkan Dompet?'),
        content: Text(
          'Dompet "${wallet.name}" akan dihapus permanen bila belum memiliki transaksi. Jika sudah pernah dipakai transaksi, dompet akan diarsipkan agar riwayat akuntansi tetap seimbang.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ArusColors.expense),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final deleted =
        await ref.read(ledgerEngineProvider).deleteWalletIfUnused(wallet.id);
    if (!deleted) {
      final db = ref.read(appDatabaseProvider);
      await (db.update(db.accounts)..where((a) => a.id.equals(wallet.id))).write(
        AccountsCompanion(
          isArchived: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Dompet "${wallet.name}" memiliki histori transaksi sehingga diarsipkan.',
            ),
          ),
        );
      }
    }
    ref.invalidate(safeToSpendProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletsProvider).valueOrNull ?? const [];
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final db = ref.watch(appDatabaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dompet & Rekening')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showWalletFormDialog(context, ref),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Tambah Dompet'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        itemCount: wallets.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Text(
              'Geser kartu ke kiri untuk Edit / Hapus dompet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            );
          }
          final w = wallets[index - 1];
          final isDefault = settings?.defaultWalletId == w.id;
          return SwipeActionCard(
            onEdit: () => _showWalletFormDialog(context, ref, existing: w),
            onDelete: () => _confirmDeleteOrArchiveWallet(context, ref, w),
            child: Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: LanjoIconBox(
                  icon: arusIconFromName(w.icon),
                  color: Color(w.colorValue),
                  size: 40,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        w.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration:
                              w.isArchived ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (isDefault)
                      const Chip(
                        label: Text('Default'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                subtitle: Text(
                  '${MoneyFormatter.format(w.cachedBalance)} • ${w.accountType}'
                  '${w.isArchived ? ' (Diarsipkan)' : ''}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'reconcile') {
                      await _showReconcileDialog(context, ref, w);
                    } else if (action == 'default') {
                      await (db.update(db.appSettings)
                            ..where((s) => s.id.equals('default')))
                          .write(
                        AppSettingsCompanion(
                          defaultWalletId: Value(w.id),
                          updatedAt: Value(DateTime.now()),
                        ),
                      );
                    } else if (action == 'archive') {
                      await (db.update(db.accounts)
                            ..where((a) => a.id.equals(w.id)))
                          .write(
                        AccountsCompanion(
                          isArchived: Value(!w.isArchived),
                          updatedAt: Value(DateTime.now()),
                        ),
                      );
                      ref.invalidate(safeToSpendProvider);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'reconcile',
                      child: Text('Rekonsiliasi Saldo'),
                    ),
                    if (!w.isArchived && !isDefault)
                      const PopupMenuItem(
                        value: 'default',
                        child: Text('Jadikan Default'),
                      ),
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(
                        w.isArchived ? 'Aktifkan Kembali' : 'Arsipkan Dompet',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
