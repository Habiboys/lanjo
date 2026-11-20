import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/widgets/lanjo_ui.dart';
import '../../../core/widgets/swipe_action_card.dart';

/// Category management: add, edit, favorite, archive, or delete custom categories (FR-05).
class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  Future<void> _showCategoryFormDialog(
    BuildContext context,
    WidgetRef ref, {
    CategoryRecord? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    var kind = existing?.kind ?? 'expense';
    String? parentId = existing?.parentId;
    final allCats = ref.read(categoriesProvider).valueOrNull ?? const [];
    final isEditing = existing != null;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(isEditing ? 'Edit Kategori' : 'Tambah Kategori'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: 'expense',
                    label: Text(
                      'Pengeluaran',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: 'income',
                    label: Text(
                      'Pemasukan',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: isEditing
                    ? null
                    : (s) => setState(() {
                          kind = s.first;
                          parentId = null;
                        }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama kategori'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                value: allCats.any(
                  (c) =>
                      c.id == parentId &&
                      c.kind == kind &&
                      c.parentId == null &&
                      c.id != existing?.id,
                )
                    ? parentId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Kategori induk (opsional / subkategori)',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Kategori Utama'),
                  ),
                  for (final c in allCats.where(
                    (c) =>
                        c.kind == kind &&
                        c.parentId == null &&
                        !c.isArchived &&
                        c.id != existing?.id,
                  ))
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => parentId = v),
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
                final cleanName = nameCtrl.text.trim();
                if (cleanName.isEmpty) return;
                final db = ref.read(appDatabaseProvider);
                if (isEditing) {
                  await (db.update(db.categories)
                        ..where((row) => row.id.equals(existing.id)))
                      .write(
                    CategoriesCompanion(
                      name: Value(cleanName),
                      parentId: Value(parentId),
                    ),
                  );
                } else {
                  final ledgerId = kind == 'income'
                      ? SystemAccountIds.incomeDefault
                      : SystemAccountIds.expenseDefault;
                  await db.into(db.categories).insert(
                        CategoriesCompanion.insert(
                          id: const Uuid().v4(),
                          name: cleanName,
                          kind: kind,
                          parentId: Value(parentId),
                          ledgerAccountId: Value(ledgerId),
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

  Future<void> _confirmDeleteOrArchiveCategory(
    BuildContext context,
    WidgetRef ref,
    CategoryRecord c,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus / Arsipkan Kategori?'),
        content: Text(
          c.isSystem
              ? 'Kategori bawaan "${c.name}" akan diarsipkan (bisa diaktifkan lagi kapan saja).'
              : 'Kategori "${c.name}" akan dihapus jika belum dipakai transaksi, atau diarsipkan bila sudah memiliki histori transaksi.',
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

    final db = ref.read(appDatabaseProvider);
    var canHardDelete = !c.isSystem;
    if (canHardDelete) {
      final usedSplits = await (db.select(db.transactionSplits)
            ..where((s) => s.categoryId.equals(c.id))
            ..limit(1))
          .get();
      final usedBills = await (db.select(db.bills)
            ..where((b) => b.categoryId.equals(c.id))
            ..limit(1))
          .get();
      final usedTxs = await (db.select(db.transactions)
            ..where((t) => t.primaryCategoryId.equals(c.id))
            ..limit(1))
          .get();
      if (usedSplits.isNotEmpty || usedBills.isNotEmpty || usedTxs.isNotEmpty) {
        canHardDelete = false;
      }
    }

    if (canHardDelete) {
      await (db.delete(db.categories)..where((row) => row.id.equals(c.id))).go();
    } else {
      await (db.update(db.categories)..where((row) => row.id.equals(c.id)))
          .write(const CategoriesCompanion(isArchived: Value(true)));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Kategori "${c.name}" diarsipkan agar transaksi lama tetap aman.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final db = ref.watch(appDatabaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Kategori')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCategoryFormDialog(context, ref),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Tambah Kategori'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        itemCount: cats.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Text(
              'Geser kartu ke kiri untuk Edit / Hapus kategori.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            );
          }
          final c = cats[index - 1];
          return SwipeActionCard(
            onEdit: () => _showCategoryFormDialog(context, ref, existing: c),
            onDelete: () => _confirmDeleteOrArchiveCategory(context, ref, c),
            child: Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: LanjoIconBox(
                  icon: arusIconFromName(c.icon),
                  color: Color(c.colorValue),
                  size: 40,
                ),
                title: Text(
                  c.name,
                  style: TextStyle(
                    decoration: c.isArchived ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text(
                  '${c.kind == 'income' ? 'Pemasukan' : 'Pengeluaran'}${c.isArchived ? ' • Diarsipkan' : ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        LucideIcons.star,
                        size: 18,
                        color: c.isFavorite ? ArusColors.warning : context.lanjoSubtle,
                      ),
                      onPressed: () async {
                        await (db.update(db.categories)
                              ..where((row) => row.id.equals(c.id)))
                            .write(
                          CategoriesCompanion(isFavorite: Value(!c.isFavorite)),
                        );
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        c.isArchived
                            ? LucideIcons.archiveRestore
                            : LucideIcons.archive,
                        size: 18,
                      ),
                      onPressed: () async {
                        await (db.update(db.categories)
                              ..where((row) => row.id.equals(c.id)))
                            .write(
                          CategoriesCompanion(isArchived: Value(!c.isArchived)),
                        );
                      },
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
