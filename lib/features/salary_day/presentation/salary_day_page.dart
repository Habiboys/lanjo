import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../bills/domain/bill_service.dart';
import '../domain/salary_day_service.dart';

/// Salary Day income allocation planner (FR-12).
class SalaryDayPage extends ConsumerStatefulWidget {
  const SalaryDayPage({
    super.key,
    this.initialAmount,
    this.sourceTransactionId,
  });

  final int? initialAmount;
  final String? sourceTransactionId;

  @override
  ConsumerState<SalaryDayPage> createState() => _SalaryDayPageState();
}

class _SalaryDayPageState extends ConsumerState<SalaryDayPage> {
  late final TextEditingController _incomeCtrl;
  final List<({String label, String? categoryId, TextEditingController amountCtrl})>
      _rows = [];
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    final savedSalary = ref.read(appSettingsProvider).valueOrNull?.monthlySalary;
    final initial = widget.initialAmount ?? savedSalary ?? 5000000;
    _incomeCtrl = TextEditingController(text: initial.toString());
    _apply503020(initial);
  }

  void _apply503020(int income) {
    for (final r in _rows) {
      r.amountCtrl.dispose();
    }
    _rows.clear();
    final drafts = ref.read(salaryDayServiceProvider).build503020Template(income);
    for (final d in drafts) {
      _rows.add((
        label: d.label,
        categoryId: d.categoryId,
        amountCtrl: TextEditingController(text: d.amount.toString()),
      ));
    }
  }

  @override
  void dispose() {
    _incomeCtrl.dispose();
    for (final r in _rows) {
      r.amountCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _confirmIncomeReceived(BillOccurrenceView item) async {
    final amtCtrl =
        TextEditingController(text: item.remainingAmount.toString());
    final accepted = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Terima ${item.bill.name}'),
        content: TextField(
          controller: amtCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nominal gaji diterima (Rp)',
            helperText: 'Otomatis menambah saldo dompet & menjadwalkan bulan depan.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final amt = int.tryParse(amtCtrl.text.trim()) ?? 0;
              if (amt > 0) Navigator.pop(ctx, amt);
            },
            child: const Text('Konfirmasi Terima'),
          ),
        ],
      ),
    );
    amtCtrl.dispose();
    if (accepted == null || !mounted) return;

    await ref.read(billServiceProvider).confirmPayment(
          occurrenceId: item.occurrence.id,
          actualAmount: accepted,
          allowNegativeBalance: true,
        );
    ref.invalidate(upcomingIncomeSchedulesProvider);
    ref.invalidate(safeToSpendProvider);
    if (!mounted) return;
    setState(() {
      _incomeCtrl.text = accepted.toString();
      _apply503020(accepted);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Pemasukan ${item.bill.name} (+${MoneyFormatter.format(accepted)}) tercatat ke dompet!',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalIncome = int.tryParse(_incomeCtrl.text.trim()) ?? 0;
    final allocated = _rows.fold<int>(
      0,
      (sum, r) => sum + (int.tryParse(r.amountCtrl.text.trim()) ?? 0),
    );
    final exceeds = allocated > totalIncome;
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final incomeSchedules =
        ref.watch(upcomingIncomeSchedulesProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Salary Day')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          for (final item in incomeSchedules) ...[
            Card(
              color: ArusColors.income.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.banknote,
                          color: ArusColors.income,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.bill.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '+${MoneyFormatter.format(item.remainingAmount)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: ArusColors.income,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Jadwal masuk: ${ArusDateUtils.formatShortDate(item.occurrence.dueDate)} • Dompet: ${item.wallet?.name ?? '-'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _confirmIncomeReceived(item),
                          icon: const Icon(LucideIcons.checkCircle2, size: 17),
                          label: const Text('Catat Gaji Masuk'),
                        ),
                        TextButton(
                          onPressed: () async {
                            await ref
                                .read(billServiceProvider)
                                .skipOccurrence(item.occurrence.id);
                            ref.invalidate(upcomingIncomeSchedulesProvider);
                          },
                          child: const Text('Lewati'),
                        ),
                        IconButton(
                          tooltip: 'Hapus pengingat gaji',
                          icon: const Icon(LucideIcons.trash2, size: 18),
                          onPressed: () async {
                            await ref
                                .read(billServiceProvider)
                                .cancelBill(item.bill.id);
                            ref.invalidate(upcomingIncomeSchedulesProvider);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _incomeCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Nominal Gaji / Pemasukan (Rp)',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('Template 50 / 30 / 20'),
                onPressed: () => setState(() => _apply503020(totalIncome)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _rows.length; i++) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _rows[i].label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _rows[i].amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Alokasi (Rp)',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Card(
            child: ListTile(
              title: const Text('Total Dialokasikan'),
              subtitle: Text(
                exceeds
                    ? 'Melebihi total gaji!'
                    : 'Sisa belum dialokasikan: ${MoneyFormatter.format(totalIncome - allocated)}',
              ),
              trailing: Text(
                MoneyFormatter.format(allocated),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: exceeds ? Colors.red : null,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _applying || exceeds || totalIncome <= 0
                ? null
                : () async {
                    setState(() => _applying = true);
                    try {
                      final items = [
                        for (final r in _rows)
                          SalaryAllocationDraft(
                            label: r.label,
                            categoryId: r.categoryId,
                            amount: int.tryParse(r.amountCtrl.text.trim()) ?? 0,
                          ),
                      ];
                      await ref.read(salaryDayServiceProvider).applySalaryPlan(
                            title: 'Rencana Gaji',
                            totalIncome: totalIncome,
                            templateType: '50_30_20',
                            items: items,
                            sourceTransactionId: widget.sourceTransactionId,
                            paydayDay: settings?.paydayDay,
                          );
                      ref.invalidate(budgetProgressesProvider);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Alokasi Salary Day & anggaran diperbarui!'),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _applying = false);
                    }
                  },
            child: const Text('Terapkan ke Anggaran'),
          ),
        ),
      ),
    );
  }
}
