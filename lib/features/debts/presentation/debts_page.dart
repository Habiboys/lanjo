import 'dart:math' as math;

import 'package:drift/drift.dart' show OrderingTerm;
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
import '../../../core/widgets/lanjo_ui.dart';
import '../../../core/widgets/swipe_action_card.dart';

/// Personal Debt (Utang) & Receivable (Piutang) tracker (FR-13).
class DebtsPage extends ConsumerWidget {
  const DebtsPage({super.key});

  Future<void> _showDebtFormDialog(
    BuildContext context, {
    DebtRecord? existing,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _DebtFormDialog(existing: existing),
    );
  }

  Future<void> _showRepayAndSimulateSheet(
    BuildContext context,
    DebtRecord debt,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RepayAndSimulateSheet(initialDebt: debt),
    );
  }

  Future<void> _confirmDeleteDebt(
    BuildContext context,
    WidgetRef ref,
    DebtRecord debt,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Utang / Piutang?'),
        content: Text(
          'Data ${debt.kind == 'receivable' ? 'piutang' : 'utang'} dengan ${debt.counterparty} beserta seluruh riwayat pencatatan/angsurannya akan dihapus dan saldo dompet terkait akan dikembalikan.',
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
    await ref.read(ledgerEngineProvider).deleteDebt(debt.id);
    ref.invalidate(safeToSpendProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    final debtsStream = (db.select(db.debts)
          ..orderBy([(d) => OrderingTerm.desc(d.occurredAt)]))
        .watch();

    return Scaffold(
      appBar: AppBar(title: const Text('Utang & Piutang')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showDebtFormDialog(context),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Tambah'),
      ),
      body: StreamBuilder<List<DebtRecord>>(
        stream: debtsStream,
        builder: (context, snap) {
          final items = (snap.data ?? const [])
              .where((d) => d.status != 'cancelled')
              .toList();
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyStateCard(
                icon: LucideIcons.handCoins,
                title: 'Belum ada utang atau piutang',
                subtitle:
                    'Bisa catat utang/piutang baru maupun utang lama tanpa mengubah saldo dompet saat ini.',
                actionLabel: 'Catat Utang / Piutang',
                onAction: () => _showDebtFormDialog(context),
              ),
            );
          }

          var totalDebtRemaining = 0;
          var totalReceivableRemaining = 0;
          for (final item in items) {
            if (item.status == 'settled') continue;
            if (item.kind == 'debt') {
              totalDebtRemaining += item.remainingAmount;
            } else {
              totalReceivableRemaining += item.remainingAmount;
            }
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: items.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                final activePayables = items
                    .where((d) => d.kind != 'receivable' && d.remainingAmount > 0)
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Card(
                            color: ArusColors.expense.withValues(alpha: 0.08),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Sisa Utang Kita',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    MoneyFormatter.format(totalDebtRemaining),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: ArusColors.expense,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Card(
                            color: ArusColors.income.withValues(alpha: 0.08),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Sisa Piutang Orang',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    MoneyFormatter.format(
                                      totalReceivableRemaining,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: ArusColors.income,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (activePayables.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _DebtPayoffStrategyCard(
                        payables: activePayables,
                        totalRemaining: totalDebtRemaining,
                      ),
                    ],
                  ],
                );
              }

              final d = items[index - 1];
              final isReceivable = d.kind == 'receivable';
              final color = isReceivable ? ArusColors.income : ArusColors.expense;
              final paid =
                  (d.principalAmount - d.remainingAmount).clamp(0, d.principalAmount);
              final progress = d.principalAmount > 0
                  ? (paid / d.principalAmount).clamp(0.0, 1.0)
                  : 0.0;
              final isOldRecord = d.walletId == null;
              final pacingText = _buildTempoPacingText(d);

              return SwipeActionCard(
                onEdit: () => _showDebtFormDialog(context, existing: d),
                onDelete: () => _confirmDeleteDebt(context, ref, d),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showRepayAndSimulateSheet(context, d),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LanjoIconBox(
                              icon: isReceivable
                                  ? LucideIcons.arrowDownLeft
                                  : LucideIcons.arrowUpRight,
                              color: color,
                              size: 42,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${isReceivable ? 'Piutang' : 'Utang'} • ${d.counterparty}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Sisa: ${MoneyFormatter.format(d.remainingAmount)} dari ${MoneyFormatter.format(d.principalAmount)}',
                                    style: lanjoMoneyStyle(
                                      context,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: d.status == 'settled'
                                          ? ArusColors.income
                                          : color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(LucideIcons.pencil, size: 18),
                              onPressed: () => _showDebtFormDialog(
                                context,
                                existing: d,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Hapus',
                              icon: const Icon(LucideIcons.trash2, size: 18),
                              onPressed: () =>
                                  _confirmDeleteDebt(context, ref, d),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 7,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'Terbayar: ${MoneyFormatter.formatCompact(paid)} (${(progress * 100).round()}%)',
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isOldRecord)
                              Text(
                                'Saldo lama (non-dompet)',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                              ),
                          ],
                        ),
                        if (pacingText != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            pacingText,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: pacingText.startsWith('Melewati')
                                      ? ArusColors.expense
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                ),
                          ),
                        ],
                        if (d.note.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Catatan: ${d.note}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (d.status != 'settled')
                              FilledButton.icon(
                                onPressed: () =>
                                    _showRepayAndSimulateSheet(context, d),
                                icon: const Icon(LucideIcons.banknote, size: 17),
                                label: Text(
                                  isReceivable
                                      ? 'Terima Cicilan'
                                      : 'Bayar / Angsur',
                                ),
                              )
                            else
                              const LanjoPillBadge(
                                label: 'Lunas',
                                icon: LucideIcons.checkCircle2,
                                color: ArusColors.income,
                              ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _showRepayAndSimulateSheet(context, d),
                              icon: const Icon(LucideIcons.calculator, size: 17),
                              label: const Text('Simulasi & Riwayat'),
                            ),
                          ],
                        ),
                      ],
                    ),
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

  static String? _buildTempoPacingText(DebtRecord d) {
    if (d.dueDate == null) return null;
    if (d.status == 'settled' || d.remainingAmount <= 0) {
      return 'Jatuh tempo: ${ArusDateUtils.formatShortDate(d.dueDate!)} (Lunas)';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(d.dueDate!.year, d.dueDate!.month, d.dueDate!.day);
    final daysLeft = dueDay.difference(today).inDays;

    if (daysLeft < 0) {
      return 'Melewati jatuh tempo ${ArusDateUtils.formatShortDate(d.dueDate!)} (${daysLeft.abs()} hari lalu)';
    }
    if (daysLeft == 0) {
      return 'Jatuh tempo hari ini (${ArusDateUtils.formatShortDate(d.dueDate!)})';
    }
    final monthsLeft = math.max(1, (daysLeft / 30).ceil());
    final weeksLeft = math.max(1, (daysLeft / 7).ceil());
    final perMonth = (d.remainingAmount / monthsLeft).ceil();
    final perWeek = (d.remainingAmount / weeksLeft).ceil();
    return 'Tempo: ${ArusDateUtils.formatShortDate(d.dueDate!)} ($daysLeft hari lagi) • Estimasi ~${MoneyFormatter.formatCompact(perMonth)}/bln atau ~${MoneyFormatter.formatCompact(perWeek)}/mg';
  }
}

class _DebtFormDialog extends ConsumerStatefulWidget {
  const _DebtFormDialog({this.existing});

  final DebtRecord? existing;

  @override
  ConsumerState<_DebtFormDialog> createState() => _DebtFormDialogState();
}

class _DebtFormDialogState extends ConsumerState<_DebtFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amtCtrl;
  late final TextEditingController _noteCtrl;
  late String _kind;
  late bool _isOldRecord;
  String? _walletId;
  DateTime? _dueDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    final wallets = ref.read(activeWalletsProvider);
    _nameCtrl = TextEditingController(text: d?.counterparty ?? '');
    _amtCtrl = TextEditingController(
      text: d != null ? d.principalAmount.toString() : '',
    );
    _noteCtrl = TextEditingController(text: d?.note ?? '');
    _kind = d?.kind ?? 'debt';
    _isOldRecord = d != null ? (d.walletId == null) : false;
    _walletId = d?.walletId ?? (wallets.isNotEmpty ? wallets.first.id : null);
    _dueDate = d?.dueDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(activeWalletsProvider);
    final isEditing = widget.existing != null;
    final principalPreview = int.tryParse(_amtCtrl.text.trim()) ?? 0;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Utang / Piutang' : 'Catat Utang / Piutang'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: 'debt',
                    label: Text(
                      'Utang Saya',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: 'receivable',
                    label: Text(
                      'Piutang',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: isEditing
                    ? null
                    : (s) => setState(() => _kind = s.first),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nama pihak / pemberi pinjaman',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amtCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Total pokok (Rp)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Utang / piutang lama (non-dompet)'),
              subtitle: Text(
                _isOldRecord
                    ? 'Saldo dompet saat ini TIDAK diubah; hanya mencatat sisa tagihan.'
                    : 'Nominal pokok menambah/mengurangi saldo dompet saat ini.',
              ),
              value: _isOldRecord,
              onChanged: (v) => setState(() => _isOldRecord = v),
            ),
            if (!_isOldRecord && wallets.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: wallets.any((w) => w.id == _walletId)
                    ? _walletId
                    : wallets.first.id,
                decoration: InputDecoration(
                  labelText: _kind == 'receivable'
                      ? 'Uang keluar dari dompet'
                      : 'Dana masuk ke dompet',
                ),
                items: [
                  for (final w in wallets)
                    DropdownMenuItem(
                      value: w.id,
                      child: Text(w.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _walletId = v);
                },
              ),
            ],
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Jatuh tempo (opsional)'),
              subtitle: Text(
                _dueDate == null
                    ? 'Tidak ditentukan'
                    : ArusDateUtils.formatShortDate(_dueDate!),
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  if (_dueDate != null)
                    IconButton(
                      tooltip: 'Hapus jatuh tempo',
                      icon: const Icon(LucideIcons.x, size: 17),
                      onPressed: () => setState(() => _dueDate = null),
                    ),
                  const Icon(LucideIcons.calendar, size: 18),
                ],
              ),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate:
                      _dueDate ?? DateTime.now().add(const Duration(days: 30)),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2040),
                );
                if (picked != null) setState(() => _dueDate = picked);
              },
            ),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
            ),
            if (principalPreview > 0) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Simulasi Cepat Cicilan:',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '3x: ${MoneyFormatter.formatCompact((principalPreview / 3).ceil())}/bln • 6x: ${MoneyFormatter.formatCompact((principalPreview / 6).ceil())}/bln • 12x: ${MoneyFormatter.formatCompact((principalPreview / 12).ceil())}/bln',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_dueDate != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _tempoEstimateLine(principalPreview, _dueDate!),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  final amt = int.tryParse(_amtCtrl.text.trim()) ?? 0;
                  if (_nameCtrl.text.trim().isEmpty || amt <= 0) return;
                  if (!_isOldRecord && wallets.isEmpty) return;

                  setState(() => _saving = true);
                  try {
                    final ledger = ref.read(ledgerEngineProvider);
                    final targetWalletId = !_isOldRecord
                        ? (_walletId ?? wallets.first.id)
                        : null;
                    if (isEditing) {
                      await ledger.updateDebt(
                        debtId: widget.existing!.id,
                        counterparty: _nameCtrl.text.trim(),
                        principalAmount: amt,
                        affectsWallet: !_isOldRecord,
                        walletId: targetWalletId,
                        dueDate: _dueDate,
                        clearDueDate: _dueDate == null,
                        note: _noteCtrl.text.trim(),
                        allowNegativeBalance: true,
                      );
                    } else {
                      await ledger.recordDebt(
                        counterparty: _nameCtrl.text.trim(),
                        kind: _kind,
                        principalAmount: amt,
                        walletId: targetWalletId,
                        affectsWallet: !_isOldRecord,
                        occurredAt: DateTime.now(),
                        dueDate: _dueDate,
                        note: _noteCtrl.text.trim(),
                        allowNegativeBalance: true,
                      );
                    }
                    ref.invalidate(safeToSpendProvider);
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: Text(isEditing ? 'Simpan Perubahan' : 'Simpan'),
        ),
      ],
    );
  }

  static String _tempoEstimateLine(int total, DateTime due) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(due.year, due.month, due.day);
    final days = math.max(1, dueDay.difference(today).inDays);
    final months = math.max(1, (days / 30).ceil());
    final perMonth = (total / months).ceil();
    return 'Sesuai tempo ($days hari / $months bln): ~${MoneyFormatter.format(perMonth)}/bln';
  }
}

class _RepayAndSimulateSheet extends ConsumerStatefulWidget {
  const _RepayAndSimulateSheet({
    required this.initialDebt,
  });

  final DebtRecord initialDebt;

  @override
  ConsumerState<_RepayAndSimulateSheet> createState() =>
      _RepayAndSimulateSheetState();
}

class _RepayAndSimulateSheetState
    extends ConsumerState<_RepayAndSimulateSheet> {
  late final TextEditingController _principalCtrl;
  late final TextEditingController _interestCtrl;
  late final TextEditingController _tenorCtrl;
  late final TextEditingController _affordableCtrl;
  String? _walletId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final wallets = ref.read(activeWalletsProvider);
    final d = widget.initialDebt;
    final defaultTenor = _suggestTenorFromDueDate(d.dueDate);
    final suggestedPerInstallment = d.remainingAmount > 0
        ? (d.remainingAmount / defaultTenor).ceil()
        : 0;

    _tenorCtrl = TextEditingController(text: defaultTenor.toString());
    _affordableCtrl =
        TextEditingController(text: suggestedPerInstallment.toString());
    _principalCtrl = TextEditingController(text: d.remainingAmount.toString());
    _interestCtrl = TextEditingController(text: '0');
    _walletId = d.walletId ?? (wallets.isNotEmpty ? wallets.first.id : null);
  }

  static int _suggestTenorFromDueDate(DateTime? dueDate) {
    if (dueDate == null) return 3;
    final now = DateTime.now();
    final days = dueDate.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days <= 0) return 1;
    return math.max(1, (days / 30).ceil());
  }

  @override
  void dispose() {
    _principalCtrl.dispose();
    _interestCtrl.dispose();
    _tenorCtrl.dispose();
    _affordableCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    final wallets = ref.watch(activeWalletsProvider);
    final sts = ref.watch(safeToSpendProvider).valueOrNull;

    final debtStream = (db.select(db.debts)
          ..where((row) => row.id.equals(widget.initialDebt.id)))
        .watchSingleOrNull();
    final paymentsStream = (db.select(db.debtPayments)
          ..where((p) => p.debtId.equals(widget.initialDebt.id))
          ..orderBy([(p) => OrderingTerm.desc(p.paidAt)]))
        .watch();

    return StreamBuilder<DebtRecord?>(
      stream: debtStream,
      initialData: widget.initialDebt,
      builder: (context, debtSnap) {
        final debt = debtSnap.data ?? widget.initialDebt;
        final isReceivable = debt.kind == 'receivable';
        final color = isReceivable ? ArusColors.income : ArusColors.expense;
        final paid = (debt.principalAmount - debt.remainingAmount)
            .clamp(0, debt.principalAmount);

        final tenor = math.max(1, int.tryParse(_tenorCtrl.text.trim()) ?? 1);
        final simulatedPerInstallment = debt.remainingAmount > 0
            ? (debt.remainingAmount / tenor).ceil()
            : 0;
        final affordable = int.tryParse(_affordableCtrl.text.trim()) ?? 0;
        final neededInstallments =
            (affordable > 0 && debt.remainingAmount > 0)
                ? (debt.remainingAmount / affordable).ceil()
                : 0;

        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  '${isReceivable ? 'Piutang' : 'Utang'} • ${debt.counterparty}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 10),
                Card(
                  color: color.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sisa Saat Ini'),
                            Text(
                              MoneyFormatter.format(debt.remainingAmount),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: debt.remainingAmount == 0
                                    ? ArusColors.income
                                    : color,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Total Pokok: ${MoneyFormatter.format(debt.principalAmount)} • Terbayar: ${MoneyFormatter.format(paid)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (debt.dueDate != null)
                          Text(
                            'Jatuh tempo: ${ArusDateUtils.formatShortDate(debt.dueDate!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
                if (debt.remainingAmount > 0) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Simulasi Rencana Angsuran',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final t in [1, 2, 3, 6, 12])
                                ChoiceChip(
                                  label: Text(t == 1 ? 'Lunas (1x)' : '${t}x'),
                                  selected: tenor == t,
                                  onSelected: (_) {
                                    setState(() {
                                      _tenorCtrl.text = t.toString();
                                      final val =
                                          (debt.remainingAmount / t).ceil();
                                      _affordableCtrl.text = val.toString();
                                    });
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _tenorCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Tenor / jumlah kali',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Cicilan / angsuran',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      MoneyFormatter.format(
                                        simulatedPerInstallment,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _affordableCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Atau kemampuan ansur per kali (Rp)',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          if (neededInstallments > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Dengan ${MoneyFormatter.format(affordable)}/kali, perlu $neededInstallments kali angsuran untuk lunas.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          if (!isReceivable && sts != null && simulatedPerInstallment > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                simulatedPerInstallment <= sts.freeFunds
                                    ? 'Dana bebas periode ini (${MoneyFormatter.format(sts.freeFunds)}) mencukupi untuk 1x angsuran.'
                                    : 'Perlu atur bertahap: dana bebas periode ini (${MoneyFormatter.format(sts.freeFunds)}) di bawah 1x angsuran.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: simulatedPerInstallment <= sts.freeFunds
                                          ? ArusColors.income
                                          : ArusColors.warning,
                                    ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _principalCtrl.text =
                                      simulatedPerInstallment.toString();
                                });
                              },
                              icon: const Icon(LucideIcons.arrowDown, size: 16),
                              label: Text(
                                'Pakai nominal simulasi (${MoneyFormatter.formatCompact(simulatedPerInstallment)})',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isReceivable
                                ? 'Catat Penerimaan Cicilan / Pelunasan'
                                : 'Bayar / Angsur Sekarang',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ActionChip(
                                label: Text(
                                  '1x Simulasi (${MoneyFormatter.formatCompact(simulatedPerInstallment)})',
                                ),
                                onPressed: () => setState(
                                  () => _principalCtrl.text =
                                      simulatedPerInstallment.toString(),
                                ),
                              ),
                              ActionChip(
                                label: const Text('50%'),
                                onPressed: () => setState(
                                  () => _principalCtrl.text =
                                      ((debt.remainingAmount / 2).ceil())
                                          .toString(),
                                ),
                              ),
                              ActionChip(
                                label: const Text('Lunas'),
                                onPressed: () => setState(
                                  () => _principalCtrl.text =
                                      debt.remainingAmount.toString(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _principalCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Nominal pokok dibayar/diterima (Rp)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _interestCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Bunga / biaya admin (Rp)',
                            ),
                          ),
                          if (wallets.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              value:
                                  wallets.any((w) => w.id == _walletId)
                                      ? _walletId
                                      : wallets.first.id,
                              decoration: InputDecoration(
                                labelText: isReceivable
                                    ? 'Masuk ke dompet'
                                    : 'Bayar dari dompet',
                              ),
                              items: [
                                for (final w in wallets)
                                  DropdownMenuItem(
                                    value: w.id,
                                    child: Text(
                                      '${w.name} (${MoneyFormatter.formatCompact(w.cachedBalance)})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _walletId = v);
                              },
                            ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _submitting || wallets.isEmpty
                                  ? null
                                  : () async {
                                      final principal =
                                          int.tryParse(_principalCtrl.text.trim()) ??
                                              0;
                                      final interest =
                                          int.tryParse(_interestCtrl.text.trim()) ??
                                              0;
                                      if (principal <= 0) return;

                                      setState(() => _submitting = true);
                                      try {
                                        await ref
                                            .read(ledgerEngineProvider)
                                            .recordDebtRepayment(
                                              debtId: debt.id,
                                              walletId:
                                                  _walletId ?? wallets.first.id,
                                              principalPaid: principal,
                                              interestOrFeePaid: interest,
                                              allowNegativeBalance: true,
                                            );
                                        ref.invalidate(safeToSpendProvider);
                                        if (!context.mounted) return;
                                        final leftAfter =
                                            debt.remainingAmount - principal;
                                        if (leftAfter > 0) {
                                          _principalCtrl.text =
                                              leftAfter.toString();
                                        }
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              leftAfter <= 0
                                                  ? '${debt.counterparty} resmi LUNAS!'
                                                  : 'Angsuran ${MoneyFormatter.format(principal)} tercatat. Sisa: ${MoneyFormatter.format(leftAfter)}',
                                            ),
                                          ),
                                        );
                                        if (leftAfter <= 0 && context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(content: Text('$e')),
                                          );
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => _submitting = false);
                                        }
                                      }
                                    },
                              icon: const Icon(LucideIcons.checkCircle2, size: 17),
                              label: Text(
                                _submitting
                                    ? 'Menyimpan...'
                                    : (isReceivable
                                        ? 'Konfirmasi Terima Cicilan'
                                        : 'Konfirmasi Bayar / Angsur'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  'Riwayat Angsuran / Pembayaran',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 6),
                StreamBuilder<List<DebtPaymentRecord>>(
                  stream: paymentsStream,
                  builder: (context, pSnap) {
                    final pays = pSnap.data ?? const [];
                    if (pays.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Belum ada riwayat angsuran.'),
                      );
                    }
                    return Column(
                      children: [
                        for (final p in pays)
                          Card(
                            child: ListTile(
                              title: Text(
                                MoneyFormatter.format(p.principalPaid),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${ArusDateUtils.formatDateTime(p.paidAt)}'
                                '${p.interestOrFeePaid > 0 ? ' • Bunga/Biaya: ${MoneyFormatter.format(p.interestOrFeePaid)}' : ''}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Hapus angsuran ini',
                                icon: const Icon(LucideIcons.trash2, size: 18),
                                onPressed: () async {
                                  await ref
                                      .read(ledgerEngineProvider)
                                      .voidTransaction(
                                        p.transactionId,
                                        reason: 'Hapus angsuran utang/piutang',
                                      );
                                  ref.invalidate(safeToSpendProvider);
                                },
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DebtPayoffStrategyCard extends StatefulWidget {
  const _DebtPayoffStrategyCard({
    required this.payables,
    required this.totalRemaining,
  });

  final List<DebtRecord> payables;
  final int totalRemaining;

  @override
  State<_DebtPayoffStrategyCard> createState() =>
      _DebtPayoffStrategyCardState();
}

class _DebtPayoffStrategyCardState extends State<_DebtPayoffStrategyCard> {
  String _strategy = 'snowball'; // 'snowball' | 'avalanche'
  int _monthlyBudget = 1000000;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = [...widget.payables];
    if (_strategy == 'snowball') {
      // Smallest remaining balance first for rapid psychological wins
      ordered.sort((a, b) => a.remainingAmount.compareTo(b.remainingAmount));
    } else {
      // Earliest due date / largest remaining principal first
      ordered.sort((a, b) {
        if (a.dueDate != null && b.dueDate != null) {
          final cmp = a.dueDate!.compareTo(b.dueDate!);
          if (cmp != 0) return cmp;
        } else if (a.dueDate != null) {
          return -1;
        } else if (b.dueDate != null) {
          return 1;
        }
        return b.remainingAmount.compareTo(a.remainingAmount);
      });
    }

    final estMonths = _monthlyBudget > 0
        ? math.max(1, (widget.totalRemaining / _monthlyBudget).ceil())
        : 1;
    final debtFreeDate = DateTime(
      DateTime.now().year,
      DateTime.now().month + estMonths,
      DateTime.now().day,
    );

    return LanjoSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LanjoIconBox(
                icon: LucideIcons.trendingUp,
                color: ArusColors.primary,
                size: 34,
                iconSize: 16,
                radius: 10,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Strategi Pelunasan Cepat',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Estimasi bebas utang: $estMonths bln (${ArusDateUtils.formatMonthYear(debtFreeDate)})',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('Snowball (Kecil Dulu)'),
                  selected: _strategy == 'snowball',
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _strategy = 'snowball'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Avalanche (Prioritas)'),
                  selected: _strategy == 'avalanche',
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _strategy = 'avalanche'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  'Alokasi/bln: ',
                  style: theme.textTheme.labelSmall,
                ),
                for (final amt in const [500000, 1000000, 2000000, 5000000])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: Text(MoneyFormatter.formatCompact(amt)),
                      selected: _monthlyBudget == amt,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _monthlyBudget = amt),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _strategy == 'snowball'
                ? 'Fokus lunasi utang dengan sisa terkecil lebih dulu agar jumlah tagihan cepat berkurang:'
                : 'Fokus lunasi utang dengan tenggat terdekat & beban terbesar lebih dulu:',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < ordered.take(3).length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  LanjoPillBadge(
                    label: '#${i + 1}',
                    color: i == 0 ? ArusColors.primary : context.lanjoMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ordered[i].counterparty,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    MoneyFormatter.format(ordered[i].remainingAmount),
                    style: lanjoMoneyStyle(
                      context,
                      fontSize: 12.5,
                      color: i == 0 ? ArusColors.primary : context.lanjoMuted,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
