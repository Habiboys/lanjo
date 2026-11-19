import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/lanjo_ui.dart';
import '../domain/safe_to_spend_service.dart';

/// Detailed Safe-to-Spend breakdown and editable reserve/essentials assumptions.
class SafeToSpendSheet extends ConsumerStatefulWidget {
  const SafeToSpendSheet({super.key, required this.breakdown});

  final SafeToSpendBreakdown breakdown;

  @override
  ConsumerState<SafeToSpendSheet> createState() => _SafeToSpendSheetState();
}

class _SafeToSpendSheetState extends ConsumerState<SafeToSpendSheet> {
  late final TextEditingController _reserveCtrl;
  late final TextEditingController _essentialsCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reserveCtrl = TextEditingController(
      text: widget.breakdown.extraReserve.toString(),
    );
    _essentialsCtrl = TextEditingController(
      text: widget.breakdown.estimatedRemainingEssentials.toString(),
    );
  }

  @override
  void dispose() {
    _reserveCtrl.dispose();
    _essentialsCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAssumptions() async {
    setState(() => _saving = true);
    try {
      await ref.read(safeToSpendServiceProvider).updateAssumptions(
            reserve: int.tryParse(_reserveCtrl.text.trim()) ?? 0,
            essentials: int.tryParse(_essentialsCtrl.text.trim()) ?? 0,
          );
      ref.invalidate(safeToSpendProvider);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.breakdown;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LanjoSheetHeader(
                title: 'Rincian Safe-to-Spend',
                subtitle:
                    'Periode ${ArusDateUtils.formatShortDate(b.periodStart)} – ${ArusDateUtils.formatShortDate(b.periodEndExclusive.subtract(const Duration(days: 1)))} (${b.remainingDays} hari tersisa)',
              ),
              const SizedBox(height: 16),
              LanjoSurface(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _BreakdownRow(
                      label: 'Saldo likuid siap belanja',
                      value: MoneyFormatter.format(b.spendableLiquidBalance),
                      positive: true,
                    ),
                    _BreakdownRow(
                      label: 'Tagihan belum dibayar (${b.upcomingBillsCount})',
                      value: '- ${MoneyFormatter.format(b.unpaidBillsCommitment)}',
                    ),
                    _BreakdownRow(
                      label: 'Alokasi tabungan tertunda',
                      value: '- ${MoneyFormatter.format(b.pendingGoalSavings)}',
                    ),
                    _BreakdownRow(
                      label: 'Cadangan dana tambahan',
                      value: '- ${MoneyFormatter.format(b.extraReserve)}',
                    ),
                    _BreakdownRow(
                      label: 'Estimasi kebutuhan pokok tersisa',
                      value:
                          '- ${MoneyFormatter.format(b.estimatedRemainingEssentials)}',
                    ),
                    const Divider(height: 20),
                    _BreakdownRow(
                      label: b.isShortfall ? 'Kekurangan Dana' : 'Dana Bebas Tersedia',
                      value: MoneyFormatter.format(b.freeFunds),
                      bold: true,
                      color: b.isShortfall ? ArusColors.expense : ArusColors.income,
                    ),
                    _BreakdownRow(
                      label: 'Batas Aman Harian (${b.remainingDays} hari)',
                      value: '${MoneyFormatter.format(b.dailySafeSpend)} / hari',
                      bold: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Koreksi Asumsi Perhitungan',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reserveCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cadangan Tambahan',
                        prefixText: 'Rp ',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _essentialsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Kebutuhan Pokok',
                        prefixText: 'Rp ',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        context.push('/plans/wishlist');
                      },
                      icon: const Icon(LucideIcons.calculator, size: 17),
                      label: const Text('Simulasi Beli'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _saveAssumptions,
                      child: const Text('Simpan Asumsi'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    this.positive = false,
    this.bold = false,
    this.color,
  });

  final String label;
  final String value;
  final bool positive;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? (positive ? ArusColors.income : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                color: bold ? context.lanjoInk : context.lanjoMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: lanjoMoneyStyle(
              context,
              fontSize: bold ? 14 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
