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
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/swipe_action_card.dart';

/// Wishlist & Purchase Simulator page (FR-15).
/// Shows exact impact of a purchase on Safe-to-Spend without blocking user choice.
class WishlistPage extends ConsumerWidget {
  const WishlistPage({super.key});

  Future<void> _showWishlistFormDialog(
    BuildContext context,
    WidgetRef ref, {
    WishlistRecord? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(
      text: existing != null ? existing.price.toString() : '',
    );
    final coolingCtrl = TextEditingController(
      text: (existing?.coolingOffDays ?? 3).toString(),
    );
    final cats = (ref.read(categoriesProvider).valueOrNull ?? const [])
        .where((c) => !c.isArchived && c.kind == 'expense')
        .toList();
    String? catId = existing != null &&
            cats.any((c) => c.id == existing.categoryId)
        ? existing.categoryId
        : cats.firstOrNull?.id;
    final isEditing = existing != null;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(isEditing ? 'Edit Wishlist' : 'Tambah Wishlist'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama barang (mis. Headphone)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Harga (Rp)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: coolingCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Masa tunggu cooling-off (hari)',
                  ),
                ),
                if (cats.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: catId,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    items: [
                      for (final c in cats)
                        DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(c.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => catId = v),
                  ),
                ],
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
                final price = int.tryParse(priceCtrl.text.trim()) ?? 0;
                final cooling = int.tryParse(coolingCtrl.text.trim()) ?? 3;
                final cleanName = nameCtrl.text.trim();
                if (cleanName.isEmpty || price <= 0) return;
                final db = ref.read(appDatabaseProvider);
                final notifs = ref.read(localNotificationServiceProvider);
                final until = DateTime.now().add(Duration(days: cooling));

                if (isEditing) {
                  await (db.update(db.wishlists)
                        ..where((w) => w.id.equals(existing.id)))
                      .write(
                    WishlistsCompanion(
                      name: Value(cleanName),
                      price: Value(price),
                      categoryId: Value(catId),
                      coolingOffDays: Value(cooling),
                      coolingOffUntil: Value(
                        cooling != existing.coolingOffDays
                            ? until
                            : existing.coolingOffUntil,
                      ),
                    ),
                  );
                } else {
                  final id = const Uuid().v4();
                  await db.into(db.wishlists).insert(
                        WishlistsCompanion.insert(
                          id: id,
                          name: cleanName,
                          price: price,
                          categoryId: Value(catId),
                          coolingOffDays: Value(cooling),
                          coolingOffUntil: Value(until),
                          createdAt: DateTime.now(),
                        ),
                      );
                  if (cooling > 0) {
                    await notifs.scheduleReminder(
                      kind: 'wishlist',
                      title: 'Masa Tunggu Wishlist Selesai',
                      body: 'Apakah kamu masih ingin membeli $cleanName?',
                      scheduledAt: until,
                      deepLink: '/plans/wishlist',
                      referenceId: id,
                    );
                  }
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

  Future<void> _confirmDeleteWishlist(
    BuildContext context,
    WidgetRef ref,
    WishlistRecord item,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Wishlist?'),
        content: Text(
          'Item "${item.name}" akan dihapus dari daftar wishlist dan pengingatnya dibatalkan.',
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
    await ref.read(localNotificationServiceProvider).cancelForReference(item.id);
    final db = ref.read(appDatabaseProvider);
    await (db.delete(db.wishlists)..where((w) => w.id.equals(item.id))).go();
  }

  Future<void> _showSimulatorDialog(
    BuildContext context,
    WidgetRef ref,
    WishlistRecord item,
  ) async {
    final result =
        await ref.read(safeToSpendServiceProvider).simulatePurchase(item.price);
    final wallets = ref.read(activeWalletsProvider);
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Simulasi Beli: ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Harga: ${MoneyFormatter.format(item.price)}'),
            const Divider(),
            Text(
              'Dana bebas saat ini: ${MoneyFormatter.format(result.before.freeFunds)}',
            ),
            Text(
              'Dana bebas setelah beli: ${MoneyFormatter.format(result.freeFundsAfter)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: result.causesShortfall
                    ? ArusColors.expense
                    : ArusColors.income,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Anggaran harian: ${MoneyFormatter.format(result.before.dailySafeSpend)} → ${MoneyFormatter.format(result.dailySafeSpendAfter)} / hari',
            ),
            if (result.before.upcomingBillsCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Catatan: masih ada ${result.before.upcomingBillsCount} tagihan senilai ${MoneyFormatter.format(result.before.unpaidBillsCommitment)} yang harus diprioritaskan.',
                ),
              ),
            if (result.causesShortfall)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '⚠️ Pembelian ini menyebabkan kekurangan dana bebas sebelum gajian berikutnya.',
                  style: TextStyle(color: ArusColors.expense),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
          if (wallets.isNotEmpty)
            FilledButton(
              onPressed: () async {
                final ledger = ref.read(ledgerEngineProvider);
                final db = ref.read(appDatabaseProvider);
                final txId = await ledger.recordExpense(
                  walletId: wallets.first.id,
                  amount: item.price,
                  splits: [
                    CategorySplitInput(
                      categoryId:
                          item.categoryId ?? DefaultCategoryIds.shopping,
                      amount: item.price,
                      description: item.name,
                    ),
                  ],
                  occurredAt: DateTime.now(),
                  description: item.name,
                  source: 'wishlist',
                  allowNegativeBalance: true,
                );
                await (db.update(db.wishlists)
                      ..where((w) => w.id.equals(item.id)))
                    .write(
                  WishlistsCompanion(
                    status: const Value('purchased'),
                    purchasedTxId: Value(txId),
                  ),
                );
                ref.invalidate(safeToSpendProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Konversi ke Pengeluaran'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    final stream = db.select(db.wishlists).watch();

    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist & Simulasi Beli')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showWishlistFormDialog(context, ref),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Tambah Wishlist'),
      ),
      body: StreamBuilder<List<WishlistRecord>>(
        stream: stream,
        builder: (context, snap) {
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyStateCard(
                icon: LucideIcons.shoppingBag,
                title: 'Wishlist masih kosong',
                subtitle: 'Tambahkan barang impianmu dan simulasikan dampaknya ke Safe-to-Spend sebelum membeli.',
                actionLabel: 'Tambah Barang',
                onAction: () => _showWishlistFormDialog(context, ref),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
            itemCount: items.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text(
                  'Geser kartu ke kiri untuk Edit / Hapus wishlist.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                );
              }
              final item = items[index - 1];
              return SwipeActionCard(
                onEdit: () =>
                    _showWishlistFormDialog(context, ref, existing: item),
                onDelete: () => _confirmDeleteWishlist(context, ref, item),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    title: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${MoneyFormatter.format(item.price)} • Status: ${item.status}'
                      '${item.coolingOffUntil != null ? '\nCooling-off s/d ${ArusDateUtils.formatShortDate(item.coolingOffUntil!)}' : ''}',
                    ),
                    trailing: item.status == 'purchased'
                        ? const Chip(label: Text('Terbeli'))
                        : FilledButton.tonal(
                            onPressed: () =>
                                _showSimulatorDialog(context, ref, item),
                            child: const Text('Simulasi'),
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
