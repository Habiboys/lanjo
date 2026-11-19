import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/ledger_engine.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/file_ops.dart';
import '../../../core/widgets/lanjo_ui.dart';

/// Receipt-style Transaction detail page supporting Edit, Duplicate, Save as Template, and Void/Delete.
class TransactionDetailPage extends ConsumerWidget {
  const TransactionDetailPage({super.key, required this.transactionId});

  final String transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final txs = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    final tx = txs.where((t) => t.id == transactionId).firstOrNull;
    final wallets = ref.watch(walletsProvider).valueOrNull ?? const [];
    final walletMap = {for (final w in wallets) w.id: w};
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final catMap = {for (final c in categories) c.id: c};
    final txTagsMap =
        ref.watch(transactionTagsMapProvider).valueOrNull ?? const {};
    final txTags = txTagsMap[transactionId] ?? const [];

    if (tx == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detail Transaksi')),
        body: const Center(
          child: Text('Transaksi tidak ditemukan atau sudah dihapus.'),
        ),
      );
    }

    final cat = catMap[tx.primaryCategoryId];
    final src = walletMap[tx.primaryWalletId];
    final dst = walletMap[tx.destinationWalletId];
    final canEdit =
        tx.type == 'expense' || tx.type == 'income' || tx.type == 'transfer';
    final isDebtTx = tx.type == 'debt_disbursement' ||
        tx.type == 'debt_repayment' ||
        tx.source == 'debt';

    final amountColor = tx.type == 'income' || tx.type == 'refund'
        ? ArusColors.income
        : (tx.type == 'transfer' ? ArusColors.transfer : ArusColors.expense);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Transaksi'),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(LucideIcons.pencil, size: 19),
              onPressed: () => context.push('/transactions/edit/${tx.id}'),
            ),
          if (isDebtTx)
            IconButton(
              tooltip: 'Edit / Kelola di Utang & Piutang',
              icon: const Icon(LucideIcons.handCoins, size: 19),
              onPressed: () => context.push('/plans/debts'),
            ),
          IconButton(
            tooltip: 'Hapus',
            icon: const Icon(LucideIcons.trash2, size: 19),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Hapus Transaksi?'),
                  content: const Text(
                    'Pengaruh transaksi terhadap saldo dompet dan anggaran akan dikembalikan.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Batal'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: ArusColors.expense,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Hapus'),
                    ),
                  ],
                ),
              );
              if (confirm != true || !context.mounted) return;
              await ref.read(ledgerEngineProvider).voidTransaction(tx.id);
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          LanjoSurface(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              children: [
                LanjoIconBox(
                  icon: cat != null
                      ? arusIconFromName(cat.icon)
                      : (tx.type == 'transfer'
                          ? LucideIcons.arrowLeftRight
                          : LucideIcons.receiptText),
                  color: cat != null ? Color(cat.colorValue) : amountColor,
                  size: 52,
                  iconSize: 24,
                  radius: 16,
                ),
                const SizedBox(height: 14),
                LanjoPillBadge(
                  label: tx.type.toUpperCase(),
                  color: amountColor,
                ),
                const SizedBox(height: 12),
                Text(
                  MoneyFormatter.format(tx.amount),
                  style: lanjoMoneyStyle(
                    context,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: amountColor,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tx.description.isEmpty ? (cat?.name ?? '-') : tx.description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LanjoSurface(
            child: Column(
              children: [
                _DetailMetaRow(
                  label: 'Tanggal & Waktu',
                  value: ArusDateUtils.formatDateTime(tx.occurredAt),
                ),
                if (src != null) ...[
                  const Divider(indent: 16, endIndent: 16),
                  _DetailMetaRow(
                    label: tx.type == 'transfer' ? 'Dompet Asal' : 'Dompet',
                    value: src.name,
                  ),
                ],
                if (dst != null) ...[
                  const Divider(indent: 16, endIndent: 16),
                  _DetailMetaRow(label: 'Dompet Tujuan', value: dst.name),
                ],
                if (cat != null) ...[
                  const Divider(indent: 16, endIndent: 16),
                  _DetailMetaRow(label: 'Kategori', value: cat.name),
                ],
                if (tx.merchant != null && tx.merchant!.isNotEmpty) ...[
                  const Divider(indent: 16, endIndent: 16),
                  _DetailMetaRow(label: 'Merchant', value: tx.merchant!),
                ],
                if (txTags.isNotEmpty) ...[
                  const Divider(indent: 16, endIndent: 16),
                  _DetailMetaRow(
                    label: 'Tag',
                    value: txTags.map((t) => '#$t').join('  '),
                  ),
                ],
                const Divider(indent: 16, endIndent: 16),
                _DetailMetaRow(label: 'Sumber Input', value: tx.source),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ReceiptAttachmentSection(transactionId: tx.id),
          const SizedBox(height: 18),
          if (tx.type == 'expense' || tx.type == 'income') ...[
            OutlinedButton.icon(
              onPressed: () async {
                final ledger = ref.read(ledgerEngineProvider);
                if (tx.type == 'income' &&
                    tx.primaryWalletId != null &&
                    tx.primaryCategoryId != null) {
                  await ledger.recordIncome(
                    walletId: tx.primaryWalletId!,
                    categoryId: tx.primaryCategoryId!,
                    amount: tx.amount,
                    occurredAt: DateTime.now(),
                    description: tx.description,
                    merchant: tx.merchant,
                  );
                } else if (tx.type == 'expense' &&
                    tx.primaryWalletId != null &&
                    tx.primaryCategoryId != null) {
                  await ledger.recordExpense(
                    walletId: tx.primaryWalletId!,
                    amount: tx.amount,
                    splits: [
                      CategorySplitInput(
                        categoryId: tx.primaryCategoryId!,
                        amount: tx.amount,
                        description: tx.description,
                      ),
                    ],
                    occurredAt: DateTime.now(),
                    description: tx.description,
                    merchant: tx.merchant,
                    allowNegativeBalance: true,
                  );
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Transaksi diduplikasi ke hari ini'),
                    ),
                  );
                }
              },
              icon: const Icon(LucideIcons.copy, size: 17),
              label: const Text('Duplikasi ke Hari Ini'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () async {
                if (tx.primaryWalletId == null || tx.primaryCategoryId == null) {
                  return;
                }
                final db = ref.read(appDatabaseProvider);
                await db.into(db.transactionTemplates).insert(
                      TransactionTemplatesCompanion.insert(
                        id: const Uuid().v4(),
                        title: tx.description.isNotEmpty
                            ? tx.description
                            : (cat?.name ?? 'Template'),
                        type: tx.type,
                        amount: tx.amount,
                        walletId: tx.primaryWalletId!,
                        categoryId: tx.primaryCategoryId!,
                        description: tx.description.isNotEmpty
                            ? Value(tx.description)
                            : const Value(''),
                        merchant: Value(tx.merchant),
                        createdAt: DateTime.now(),
                      ),
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Disimpan sebagai Template Quick Add'),
                    ),
                  );
                }
              },
              icon: const Icon(LucideIcons.zap, size: 17),
              label: const Text('Jadikan Template Favorit'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailMetaRow extends StatelessWidget {
  const _DetailMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.lanjoMuted,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptAttachmentSection extends ConsumerWidget {
  const _ReceiptAttachmentSection({required this.transactionId});

  final String transactionId;

  Future<Uint8List?> _loadAttachmentBytes(AppDatabase db) async {
    final rows = await (db.select(db.attachments)
          ..where((a) => a.transactionId.equals(transactionId)))
        .get();
    if (rows.isEmpty) return null;
    final att = rows.first;
    final baseDir = await AppDatabase.getAttachmentsDirectoryPath();
    final fullPath = p.join(baseDir, att.relativePath);
    return readFileBytesByPathImpl(fullPath);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return FutureBuilder<Uint8List?>(
      future: _loadAttachmentBytes(db),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LanjoSectionHeader(
              title: 'Lampiran Foto Struk',
              subtitle: 'Ketuk gambar untuk memperbesar (Pinch-to-Zoom)',
            ),
            const SizedBox(height: 8),
            LanjoSurface(
              onTap: () {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => Dialog.fullscreen(
                    backgroundColor: Colors.black,
                    child: Stack(
                      children: [
                        Center(
                          child: InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 4.5,
                            child: Image.memory(bytes, fit: BoxFit.contain),
                          ),
                        ),
                        Positioned(
                          top: 24,
                          right: 16,
                          child: IconButton.filled(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(LucideIcons.x),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.memory(
                  bytes,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
