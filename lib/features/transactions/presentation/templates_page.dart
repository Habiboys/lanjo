import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/ledger_engine.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/lanjo_ui.dart';
import '../../../core/widgets/swipe_action_card.dart';

/// Quick Add & Transaction Templates manager with swipe-to-edit/delete (FR-06).
class TemplatesPage extends ConsumerWidget {
  const TemplatesPage({super.key});

  Future<void> _showTemplateDialog(
    BuildContext context,
    WidgetRef ref, {
    TransactionTemplateRecord? existing,
  }) async {
    final wallets = ref.read(activeWalletsProvider);
    final cats = (ref.read(categoriesProvider).valueOrNull ?? const [])
        .where((c) => !c.isArchived && c.kind == 'expense')
        .toList();
    if (wallets.isEmpty || cats.isEmpty) return;

    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final amtCtrl = TextEditingController(
      text: existing != null ? existing.amount.toString() : '',
    );
    var walletId = existing != null &&
            wallets.any((w) => w.id == existing.walletId)
        ? existing.walletId
        : wallets.first.id;
    var catId = existing != null && cats.any((c) => c.id == existing.categoryId)
        ? existing.categoryId
        : cats.first.id;
    final isEditing = existing != null;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            isEditing ? 'Edit Template Cepat' : 'Buat Template Cepat',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama template (mis. Kopi / Parkir)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amtCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nominal (Rp)',
                  ),
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
                final title = titleCtrl.text.trim();
                final amt = int.tryParse(amtCtrl.text.trim()) ?? 0;
                if (title.isEmpty || amt <= 0) return;
                final db = ref.read(appDatabaseProvider);
                if (isEditing) {
                  await (db.update(db.transactionTemplates)
                        ..where((t) => t.id.equals(existing.id)))
                      .write(
                    TransactionTemplatesCompanion(
                      title: Value(title),
                      amount: Value(amt),
                      walletId: Value(walletId),
                      categoryId: Value(catId),
                      description: Value(title),
                    ),
                  );
                } else {
                  await db.into(db.transactionTemplates).insert(
                        TransactionTemplatesCompanion.insert(
                          id: const Uuid().v4(),
                          title: title,
                          type: 'expense',
                          amount: amt,
                          walletId: walletId,
                          categoryId: catId,
                          description: Value(title),
                          createdAt: DateTime.now(),
                        ),
                      );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(isEditing ? 'Simpan Perubahan' : 'Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTemplate(
    BuildContext context,
    WidgetRef ref,
    TransactionTemplateRecord tpl,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Template?'),
        content: Text('Template "${tpl.title}" akan dihapus.'),
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
    final db = ref.read(appDatabaseProvider);
    await (db.delete(db.transactionTemplates)..where((t) => t.id.equals(tpl.id)))
        .go();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesStreamProvider).valueOrNull ?? const [];
    final ledger = ref.read(ledgerEngineProvider);
    final db = ref.read(appDatabaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Template Quick Add')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTemplateDialog(context, ref),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Tambah Template'),
      ),
      body: templates.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyStateCard(
                icon: LucideIcons.zap,
                title: 'Belum ada template',
                subtitle: 'Simpan pengeluaran rutin seperti kopi, bensin, atau parkir agar bisa dicatat dalam 1 ketukan.',
                actionLabel: 'Buat Template',
                onAction: () => _showTemplateDialog(context, ref),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              itemCount: templates.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Text(
                    'Geser kartu ke kiri untuk Edit / Hapus template.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  );
                }
                final tpl = templates[index - 1];
                return SwipeActionCard(
                  onEdit: () =>
                      _showTemplateDialog(context, ref, existing: tpl),
                  onDelete: () => _confirmDeleteTemplate(context, ref, tpl),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const LanjoIconBox(
                        icon: LucideIcons.zap,
                        color: ArusColors.warning,
                        size: 40,
                      ),
                      title: Text(tpl.title),
                      subtitle: Text(
                        '${MoneyFormatter.format(tpl.amount)} • Dipakai ${tpl.useCount}x',
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () async {
                          final txId = await ledger.recordExpense(
                            walletId: tpl.walletId,
                            amount: tpl.amount,
                            splits: [
                              CategorySplitInput(
                                categoryId: tpl.categoryId,
                                amount: tpl.amount,
                                description: tpl.title,
                              ),
                            ],
                            occurredAt: DateTime.now(),
                            description: tpl.title,
                            source: 'template',
                            allowNegativeBalance: true,
                          );
                          await (db.update(db.transactionTemplates)
                                ..where((t) => t.id.equals(tpl.id)))
                              .write(
                            TransactionTemplatesCompanion(
                              useCount: Value(tpl.useCount + 1),
                            ),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Tercatat: ${tpl.title}'),
                                action: SnackBarAction(
                                  label: 'Undo',
                                  onPressed: () => ledger.voidTransaction(txId),
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text('Catat'),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
