import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../money/money_formatter.dart';
import 'lanjo_ui.dart';

/// Hero Rupiah numeric input with live formatted readout, zero-count guard,
/// quick amount pills, and built-in Fintech Smart Calculator (+10% PB1, +11% PPN, 000 key).
class AmountInputField extends StatefulWidget {
  const AmountInputField({
    super.key,
    required this.controller,
    this.label = 'Nominal',
    this.onChanged,
    this.quickAmounts = const [10000, 20000, 50000, 100000],
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<int>? onChanged;
  final List<int> quickAmounts;

  @override
  State<AmountInputField> createState() => _AmountInputFieldState();
}

class _AmountInputFieldState extends State<AmountInputField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant AmountInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _setAmount(int value) {
    final clamped = value.clamp(0, 2000000000);
    widget.controller.text = clamped.toString();
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    widget.onChanged?.call(clamped);
  }

  String _humanReadableScale(int amount) {
    if (amount <= 0) return 'Rp0';
    if (amount >= 1000000000) {
      final v = (amount / 1000000000).toStringAsFixed(2).replaceAll('.', ',');
      return '${MoneyFormatter.format(amount)} • $v Miliar';
    }
    if (amount >= 1000000) {
      final v = (amount / 1000000).toStringAsFixed(2).replaceAll(',00', '').replaceAll('.', ',');
      return '${MoneyFormatter.format(amount)} • $v Juta';
    }
    if (amount >= 1000) {
      final v = (amount / 1000).toStringAsFixed(0);
      return '${MoneyFormatter.format(amount)} • $v Ribu';
    }
    return MoneyFormatter.format(amount);
  }

  Future<void> _openSmartCalculator() async {
    final current = int.tryParse(widget.controller.text.trim()) ?? 0;
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SmartCalculatorSheet(initialAmount: current),
    );
    if (result != null) {
      _setAmount(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentVal = int.tryParse(widget.controller.text.trim()) ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: context.lanjoMuted,
                ),
              ),
            ),
            if (currentVal > 0)
              Text(
                _humanReadableScale(currentVal),
                style: lanjoMoneyStyle(
                  context,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: lanjoMoneyStyle(
            context,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          decoration: InputDecoration(
            prefixText: 'Rp ',
            prefixStyle: lanjoMoneyStyle(
              context,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
            hintText: '0',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (currentVal > 0)
                  IconButton(
                    tooltip: 'Reset nominal',
                    icon: Icon(
                      LucideIcons.x,
                      size: 16,
                      color: context.lanjoSubtle,
                    ),
                    onPressed: () => _setAmount(0),
                  ),
                Tooltip(
                  message: 'Kalkulator Pintar (+Pajak/Diskon)',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _openSmartCalculator,
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.calculator,
                            size: 15,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Hitung',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          onChanged: (val) {
            final parsed = int.tryParse(val) ?? 0;
            widget.onChanged?.call(parsed);
          },
        ),
        if (widget.quickAmounts.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final amt in widget.quickAmounts)
                Material(
                  color: context.lanjoSurfaceSecondary,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      final current = int.tryParse(widget.controller.text) ?? 0;
                      _setAmount(current + amt);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: context.lanjoBorder),
                      ),
                      child: Text(
                        '+${MoneyFormatter.formatCompact(amt)}',
                        style: lanjoMoneyStyle(
                          context,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SmartCalculatorSheet extends StatefulWidget {
  const _SmartCalculatorSheet({required this.initialAmount});

  final int initialAmount;

  @override
  State<_SmartCalculatorSheet> createState() => _SmartCalculatorSheetState();
}

class _SmartCalculatorSheetState extends State<_SmartCalculatorSheet> {
  late String _expr;

  @override
  void initState() {
    super.initState();
    _expr = widget.initialAmount > 0 ? widget.initialAmount.toString() : '';
  }

  int _evaluate(String raw) {
    final cleaned = raw.replaceAll(' ', '');
    if (cleaned.isEmpty) return 0;

    // Simple left-to-right arithmetic tokenizer supporting +, -, *, /
    final tokens = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < cleaned.length; i++) {
      final ch = cleaned[i];
      if ('+-×÷*/'.contains(ch)) {
        if (buf.isNotEmpty) {
          tokens.add(buf.toString());
          buf.clear();
        }
        tokens.add(ch);
      } else if (RegExp(r'[0-9]').hasMatch(ch)) {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) tokens.add(buf.toString());
    if (tokens.isEmpty) return 0;

    double acc = double.tryParse(tokens.first) ?? 0;
    for (var i = 1; i + 1 < tokens.length; i += 2) {
      final op = tokens[i];
      final rhs = double.tryParse(tokens[i + 1]) ?? 0;
      switch (op) {
        case '+':
          acc += rhs;
        case '-':
          acc -= rhs;
        case '×':
        case '*':
          acc *= rhs;
        case '÷':
        case '/':
          if (rhs != 0) acc /= rhs;
      }
    }
    return acc.round().clamp(0, 2000000000);
  }

  void _append(String token) {
    setState(() {
      if ('+-×÷'.contains(token)) {
        if (_expr.isEmpty) return;
        final last = _expr[_expr.length - 1];
        if ('+-×÷'.contains(last)) {
          _expr = _expr.substring(0, _expr.length - 1) + token;
          return;
        }
      }
      _expr += token;
    });
  }

  void _applyMultiplier(double factor) {
    final base = _evaluate(_expr);
    if (base <= 0) return;
    setState(() {
      _expr = (base * factor).round().toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _evaluate(_expr);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LanjoSheetHeader(
              title: 'Kalkulator Transaksi Pintar',
              subtitle: 'Hitung belanjaan, pajak PB1/PPN, atau diskon langsung',
            ),
            const SizedBox(height: 12),
            LanjoSurface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              color: context.lanjoSurfaceSecondary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      _expr.isEmpty ? '0' : _expr,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: context.lanjoMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    MoneyFormatter.format(result),
                    textAlign: TextAlign.right,
                    style: lanjoMoneyStyle(
                      context,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Quick Tax & Discount Presets
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _PresetChip(
                    label: '+10% PB1 Resto',
                    onTap: () => _applyMultiplier(1.10),
                  ),
                  const SizedBox(width: 6),
                  _PresetChip(
                    label: '+11% PPN',
                    onTap: () => _applyMultiplier(1.11),
                  ),
                  const SizedBox(width: 6),
                  _PresetChip(
                    label: '+15% Tax+Service',
                    onTap: () => _applyMultiplier(1.155),
                  ),
                  const SizedBox(width: 6),
                  _PresetChip(
                    label: '-10% Diskon',
                    onTap: () => _applyMultiplier(0.90),
                  ),
                  const SizedBox(width: 6),
                  _PresetChip(
                    label: '÷2 Bagi Dua',
                    onTap: () => _applyMultiplier(0.50),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Tactile Keypad Grid
            for (final row in const [
              ['7', '8', '9', '÷'],
              ['4', '5', '6', '×'],
              ['1', '2', '3', '-'],
              ['0', '000', '⌫', '+'],
            ]) ...[
              Row(
                children: [
                  for (var i = 0; i < row.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _CalcKeyButton(
                        label: row[i],
                        isOperator: '+-×÷'.contains(row[i]),
                        onTap: () {
                          final key = row[i];
                          if (key == '⌫') {
                            if (_expr.isNotEmpty) {
                              setState(() {
                                _expr = _expr.substring(0, _expr.length - 1);
                              });
                            }
                          } else {
                            _append(key);
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _expr = ''),
                  child: const Text('Reset (C)'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, result),
                    icon: const Icon(LucideIcons.check, size: 17),
                    label: Text('Pakai ${MoneyFormatter.formatCompact(result)}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}

class _CalcKeyButton extends StatelessWidget {
  const _CalcKeyButton({
    required this.label,
    required this.isOperator,
    required this.onTap,
  });

  final String label;
  final bool isOperator;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: isOperator
          ? primary.withValues(alpha: context.isDark ? 0.22 : 0.12)
          : context.lanjoSurfaceSecondary,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isOperator
                  ? primary.withValues(alpha: 0.3)
                  : context.lanjoBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: ArusColors.fontFamily,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isOperator ? primary : context.lanjoInk,
            ),
          ),
        ),
      ),
    );
  }
}
