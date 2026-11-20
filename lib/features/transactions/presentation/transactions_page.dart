import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/lanjo_ui.dart';
import '../../../core/widgets/swipe_action_card.dart';

/// Full Transaction history with search, multi-criteria filter, and CSV export.
class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  final _searchCtrl = TextEditingController();
  String _typeFilter = 'all';
  String? _walletFilter;
  String? _categoryFilter;
  String? _tagFilter;
  DateTimeRange? _dateRange;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hidden = ref.watch(appSettingsProvider).valueOrNull?.privacyMode ?? false;
    final txs = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    final wallets = ref.watch(walletsProvider).valueOrNull ?? const [];
    final walletMap = {for (final w in wallets) w.id: w};
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final catMap = {for (final c in categories) c.id: c};
    final allTags = ref.watch(tagsStreamProvider).valueOrNull ?? const [];
    final txTagsMap =
        ref.watch(transactionTagsMapProvider).valueOrNull ?? const {};

    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = txs.where((tx) {
      if (_typeFilter != 'all' && tx.type != _typeFilter) return false;
      if (_walletFilter != null &&
          tx.primaryWalletId != _walletFilter &&
          tx.destinationWalletId != _walletFilter) {
        return false;
      }
      if (_categoryFilter != null && tx.primaryCategoryId != _categoryFilter) {
        return false;
      }
      if (_tagFilter != null) {
        final tags = txTagsMap[tx.id] ?? const [];
        if (!tags.contains(_tagFilter)) return false;
      }
      if (_dateRange != null) {
        final endInclusive = _dateRange!.end.add(const Duration(days: 1));
        if (tx.occurredAt.isBefore(_dateRange!.start) ||
            !tx.occurredAt.isBefore(endInclusive)) {
          return false;
        }
      }
      if (query.isNotEmpty) {
        final catName = catMap[tx.primaryCategoryId]?.name.toLowerCase() ?? '';
        final walletName = walletMap[tx.primaryWalletId]?.name.toLowerCase() ?? '';
        final tagJoined = (txTagsMap[tx.id] ?? const []).join(' ').toLowerCase();
        final matchDesc = tx.description.toLowerCase().contains(query);
        final matchMerchant = (tx.merchant ?? '').toLowerCase().contains(query);
        final matchAmt = tx.amount.toString().contains(query);
        if (!matchDesc &&
            !matchMerchant &&
            !matchAmt &&
            !catName.contains(query) &&
            !walletName.contains(query) &&
            !tagJoined.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();

    var filteredIncome = 0;
    var filteredExpense = 0;
    final dailyNetExpenseMap = <DateTime, int>{};
    for (final tx in filtered) {
      final dayKey = DateTime(
        tx.occurredAt.year,
        tx.occurredAt.month,
        tx.occurredAt.day,
      );
      if (tx.type == 'income') {
        filteredIncome += tx.amount;
      } else if (tx.type == 'expense') {
        filteredExpense += tx.amount;
        dailyNetExpenseMap[dayKey] =
            (dailyNetExpenseMap[dayKey] ?? 0) + tx.amount;
      } else if (tx.type == 'refund') {
        filteredExpense -= tx.amount;
        dailyNetExpenseMap[dayKey] =
            (dailyNetExpenseMap[dayKey] ?? 0) - tx.amount;
      }
    }
    if (filteredExpense < 0) filteredExpense = 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Transaksi'),
        actions: [
          Tooltip(
            message: _dateRange == null ? 'Filter Tanggal' : 'Hapus Filter Tanggal',
            child: Material(
              color: _dateRange == null
                  ? context.lanjoSurfaceSecondary
                  : theme.colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () async {
                  if (_dateRange != null) {
                    setState(() => _dateRange = null);
                    return;
                  }
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) setState(() => _dateRange = picked);
                },
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    LucideIcons.calendar,
                    size: 18,
                    color: _dateRange == null
                        ? context.lanjoInk
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Export CSV',
            child: Material(
              color: context.lanjoSurfaceSecondary,
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: filtered.isEmpty
                    ? null
                    : () async {
                        final file = await ref
                            .read(importExportServiceProvider)
                            .exportTransactionsCsv(filtered);
                        await Share.shareXFiles([file]);
                      },
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    LucideIcons.download,
                    size: 18,
                    color: filtered.isEmpty
                        ? context.lanjoSubtle
                        : context.lanjoInk,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Cari nominal, deskripsi, merchant, kategori...',
                prefixIcon: Icon(
                  LucideIcons.search,
                  size: 18,
                  color: context.lanjoMuted,
                ),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(LucideIcons.x, size: 17, color: context.lanjoMuted),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final item in const [
                  ('all', 'Semua'),
                  ('expense', 'Pengeluaran'),
                  ('income', 'Pemasukan'),
                  ('transfer', 'Transfer'),
                  ('refund', 'Refund'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterPill(
                      label: item.$2,
                      selected: _typeFilter == item.$1,
                      onTap: () => setState(() => _typeFilter = item.$1),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _PickerPill(
                    icon: LucideIcons.wallet,
                    label: _walletFilter == null
                        ? 'Semua Dompet'
                        : (walletMap[_walletFilter]?.name ?? 'Dompet'),
                    active: _walletFilter != null,
                    onTap: () async {
                      final selected = await showModalBottomSheet<String?>(
                        context: context,
                        isScrollControlled: true,
                        builder: (ctx) => SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const LanjoSheetHeader(title: 'Filter Dompet'),
                                const SizedBox(height: 12),
                                Flexible(
                                  child: ListView(
                                    shrinkWrap: true,
                                    children: [
                                      ListTile(
                                        title: const Text('Semua Dompet'),
                                        onTap: () => Navigator.pop(ctx, ''),
                                      ),
                                      for (final w
                                          in wallets.where((w) => !w.isArchived))
                                        ListTile(
                                          leading: LanjoIconBox(
                                            icon: arusIconFromName(w.icon),
                                            color: Color(w.colorValue),
                                            size: 34,
                                          ),
                                          title: Text(w.name),
                                          onTap: () => Navigator.pop(ctx, w.id),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      if (selected != null) {
                        setState(
                          () => _walletFilter = selected.isEmpty ? null : selected,
                        );
                      }
                    },
                  ),
                ),
                _PickerPill(
                  icon: LucideIcons.shapes,
                  label: _categoryFilter == null
                      ? 'Semua Kategori'
                      : (catMap[_categoryFilter]?.name ?? 'Kategori'),
                  active: _categoryFilter != null,
                  onTap: () async {
                    final selected = await showModalBottomSheet<String?>(
                      context: context,
                      isScrollControlled: true,
                      builder: (ctx) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const LanjoSheetHeader(title: 'Filter Kategori'),
                              const SizedBox(height: 12),
                              Flexible(
                                child: ListView(
                                  shrinkWrap: true,
                                  children: [
                                    ListTile(
                                      title: const Text('Semua Kategori'),
                                      onTap: () => Navigator.pop(ctx, ''),
                                    ),
                                    for (final c
                                        in categories.where((c) => !c.isArchived))
                                      ListTile(
                                        leading: LanjoIconBox(
                                          icon: arusIconFromName(c.icon),
                                          color: Color(c.colorValue),
                                          size: 34,
                                        ),
                                        title: Text(c.name),
                                        onTap: () => Navigator.pop(ctx, c.id),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                    if (selected != null) {
                      setState(
                        () => _categoryFilter = selected.isEmpty ? null : selected,
                      );
                    }
                  },
                ),
                if (allTags.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _PickerPill(
                    icon: LucideIcons.bookmark,
                    label: _tagFilter == null ? 'Semua #Tag' : '#$_tagFilter',
                    active: _tagFilter != null,
                    onTap: () async {
                      final selected = await showModalBottomSheet<String?>(
                        context: context,
                        isScrollControlled: true,
                        builder: (ctx) => SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const LanjoSheetHeader(title: 'Filter #Tag'),
                                const SizedBox(height: 12),
                                Flexible(
                                  child: ListView(
                                    shrinkWrap: true,
                                    children: [
                                      ListTile(
                                        title: const Text('Semua #Tag'),
                                        onTap: () => Navigator.pop(ctx, ''),
                                      ),
                                      for (final t in allTags)
                                        ListTile(
                                          leading: const LanjoIconBox(
                                            icon: LucideIcons.bookmark,
                                            color: ArusColors.primary,
                                            size: 34,
                                          ),
                                          title: Text('#${t.name}'),
                                          onTap: () =>
                                              Navigator.pop(ctx, t.name),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      if (selected != null) {
                        setState(
                          () => _tagFilter = selected.isEmpty ? null : selected,
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (filtered.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: context.lanjoSurfaceSecondary.withValues(alpha: 0.65),
                border: Border.symmetric(
                  horizontal: BorderSide(color: context.lanjoBorder),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '${filtered.length} transaksi',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.lanjoInk,
                    ),
                  ),
                  const Spacer(),
                  if (filteredIncome > 0) ...[
                    Text(
                      '+${MoneyFormatter.formatCompact(filteredIncome, hidden: hidden)}',
                      style: lanjoMoneyStyle(
                        context,
                        fontSize: 12,
                        color: ArusColors.income,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    'Keluar: ${MoneyFormatter.formatCompact(filteredExpense, hidden: hidden)}',
                    style: lanjoMoneyStyle(
                      context,
                      fontSize: 12,
                      color: ArusColors.expense,
                    ),
                  ),
                ],
              ),
            )
          else
            const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: EmptyStateCard(
                        icon: LucideIcons.search,
                        title: 'Tidak ada transaksi',
                        subtitle: txs.isEmpty
                            ? 'Belum ada transaksi. Yuk catat pengeluaran pertama.'
                            : 'Tidak ada transaksi yang cocok dengan filter saat ini.',
                        actionLabel: 'Catat Transaksi',
                        onAction: () =>
                            context.push('/transactions/new?type=expense'),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final tx = filtered[index];
                      final dayKey = DateTime(
                        tx.occurredAt.year,
                        tx.occurredAt.month,
                        tx.occurredAt.day,
                      );
                      final prevDayKey = index > 0
                          ? DateTime(
                              filtered[index - 1].occurredAt.year,
                              filtered[index - 1].occurredAt.month,
                              filtered[index - 1].occurredAt.day,
                            )
                          : null;
                      final showDayHeader =
                          prevDayKey == null || prevDayKey != dayKey;
                      final dayExpense =
                          (dailyNetExpenseMap[dayKey] ?? 0).clamp(0, 1 << 30);

                      final cat = catMap[tx.primaryCategoryId];
                      final srcWallet = walletMap[tx.primaryWalletId];
                      final dstWallet = walletMap[tx.destinationWalletId];

                      final color = switch (tx.type) {
                        'income' || 'refund' => ArusColors.income,
                        'transfer' => ArusColors.transfer,
                        'opening_balance' => ArusColors.primary,
                        'balance_adjustment' => ArusColors.warning,
                        _ => ArusColors.expense,
                      };

                      final txTags = txTagsMap[tx.id] ?? const [];
                      final subtitleParts = <String>[
                        if (srcWallet != null)
                          dstWallet != null
                              ? '${srcWallet.name} → ${dstWallet.name}'
                              : srcWallet.name,
                        if (cat != null) cat.name,
                        if (txTags.isNotEmpty)
                          txTags.map((t) => '#$t').join(' '),
                        ArusDateUtils.formatTime(tx.occurredAt),
                      ];

                      final canEditDirect = tx.type == 'expense' ||
                          tx.type == 'income' ||
                          tx.type == 'transfer';
                      final isDebtTx = tx.type == 'debt_disbursement' ||
                          tx.type == 'debt_repayment' ||
                          tx.source == 'debt';

                      final iconColor =
                          cat != null ? Color(cat.colorValue) : color;
                      final iconData = cat != null
                          ? arusIconFromName(cat.icon)
                          : (tx.type == 'transfer'
                              ? LucideIcons.arrowLeftRight
                              : tx.type == 'income'
                                  ? LucideIcons.arrowDownLeft
                                  : LucideIcons.receiptText);

                      final cardWidget = SwipeActionCard(
                        borderRadius: 18,
                        onEdit: canEditDirect
                            ? () => context.push('/transactions/edit/${tx.id}')
                            : (isDebtTx
                                ? () => context.push('/plans/debts')
                                : null),
                        onDelete: () async {
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
                          if (confirm != true) return;
                          await ref
                              .read(ledgerEngineProvider)
                              .voidTransaction(tx.id);
                          ref.invalidate(safeToSpendProvider);
                        },
                        child: LanjoSurface(
                          onTap: () => context.push('/transactions/${tx.id}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              LanjoIconBox(
                                icon: iconData,
                                color: iconColor,
                                size: 42,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tx.description.isNotEmpty
                                          ? tx.description
                                          : (cat?.name ?? tx.type),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(fontSize: 14.5),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitleParts.join(' • '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${tx.type == 'income' || tx.type == 'refund' ? '+' : (tx.type == 'expense' ? '-' : '')}${MoneyFormatter.format(tx.amount, hidden: hidden)}',
                                style: lanjoMoneyStyle(
                                  context,
                                  fontSize: 13.5,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );

                      if (!showDayHeader) return cardWidget;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              top: index == 0 ? 2 : 10,
                              bottom: 6,
                              left: 4,
                              right: 4,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  ArusDateUtils.formatShortDate(
                                    dayKey,
                                  ).toUpperCase(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    letterSpacing: 0.6,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (dayExpense > 0)
                                  Text(
                                    '-${MoneyFormatter.format(dayExpense, hidden: hidden)}',
                                    style: lanjoMoneyStyle(
                                      context,
                                      fontSize: 11.5,
                                      color: context.lanjoMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          cardWidget,
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onDarkAccent =
        ThemeData.estimateBrightnessForColor(context.lanjoPrimaryLight) ==
                Brightness.light
            ? const Color(0xFF041C14)
            : Colors.white;
    final bg = selected
        ? (context.isDark
            ? context.lanjoPrimaryLight
            : context.lanjoPalette.lightButtonBg)
        : context.lanjoCard;
    final fg = selected
        ? (context.isDark ? onDarkAccent : Colors.white)
        : context.lanjoInk;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? Colors.transparent : context.lanjoBorder,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: ArusColors.fontFamily,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerPill extends StatelessWidget {
  const _PickerPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: active ? primary.withValues(alpha: 0.12) : context.lanjoCard,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? primary.withValues(alpha: 0.4) : context.lanjoBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: active ? primary : context.lanjoMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: ArusColors.fontFamily,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? primary : context.lanjoInk,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                LucideIcons.chevronRight,
                size: 13,
                color: active ? primary : context.lanjoSubtle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
