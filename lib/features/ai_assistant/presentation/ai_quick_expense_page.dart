import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/ai_finance_service.dart';

/// AI Quick Expense & Voice Input page (FR-17, FR-19).
/// Never writes directly to SQLite; always previews editable drafts first.
class AiQuickExpensePage extends ConsumerStatefulWidget {
  const AiQuickExpensePage({
    super.key,
    this.startWithVoice = false,
    this.initialText,
  });

  final bool startWithVoice;
  final String? initialText;

  @override
  ConsumerState<AiQuickExpensePage> createState() => _AiQuickExpensePageState();
}

class _AiQuickExpensePageState extends ConsumerState<AiQuickExpensePage> {
  final _inputCtrl = TextEditingController();
  final SpeechToText _stt = SpeechToText();

  bool _listening = false;
  bool _parsing = false;
  bool _saving = false;
  AiQuickExpenseParseResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null && widget.initialText!.trim().isNotEmpty) {
      _inputCtrl.text = widget.initialText!.trim();
    }
    if (widget.startWithVoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toggleVoice());
    }
  }

  @override
  void dispose() {
    _stt.stop();
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Input Suara'),
        content: const Text(
          'Lanjo memprioritaskan pengenalan suara di perangkat. Jika layanan perangkat memerlukan internet, audio hanya diproses untuk transkripsi teks dan tidak disimpan secara default.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mulai Bicara'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final bridge = ref.read(nativeBridgeServiceProvider);
    final micGranted = await bridge.requestPermission('microphone');
    if (!micGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Izin Mikrofon diperlukan untuk input suara.'),
            action: SnackBarAction(
              label: 'Pengaturan',
              onPressed: bridge.openAppSettings,
            ),
          ),
        );
      }
      return;
    }

    try {
      final available = await _stt.initialize();
      if (!available) {
        if (mounted) {
          setState(
            () => _error =
                'Pengenalan suara tidak tersedia di perangkat ini. Silakan ketik manual.',
          );
        }
        return;
      }
      setState(() {
        _listening = true;
        _error = null;
      });
      await _stt.listen(
        listenOptions: SpeechListenOptions(localeId: 'id_ID'),
        onResult: (res) {
          if (!mounted) return;
          setState(() {
            _inputCtrl.text = res.recognizedWords;
            if (res.finalResult) _listening = false;
          });
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _listening = false;
          _error = 'Gagal memulai mikrofon: $e';
        });
      }
    }
  }

  Future<void> _parse() async {
    setState(() {
      _parsing = true;
      _error = null;
      _result = null;
    });
    try {
      final res = await ref
          .read(aiFinanceServiceProvider)
          .parseNaturalInput(_inputCtrl.text);
      if (mounted) setState(() => _result = res);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  Future<void> _confirmSave() async {
    final res = _result;
    if (res == null || _saving) return;
    setState(() => _saving = true);
    try {
      final summary = res.computeSummary();
      final ids = await ref.read(aiFinanceServiceProvider).commitDrafts(
            drafts: res.drafts,
            batchIdempotencyKey: res.idempotencyKey,
            source: widget.startWithVoice ? 'voice' : 'ai',
          );
      await ref.read(budgetServiceProvider).evaluateAlerts();
      if (!mounted) return;

      if (ids.length > 1) {
        final cats = ref.read(categoriesProvider).valueOrNull ?? const [];
        final catMap = {for (final c in cats) c.id: c.name};
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('${ids.length} Transaksi Tersimpan'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Pengeluaran: ${MoneyFormatter.format(summary.totalExpense)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (summary.totalIncome > 0)
                    Text(
                      'Total Pemasukan: ${MoneyFormatter.format(summary.totalIncome)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  if (summary.byDate.isNotEmpty) ...[
                    const Divider(),
                    const Text(
                      'Ringkasan per Tanggal:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    for (final d in summary.byDate)
                      Text(
                        '• ${ArusDateUtils.formatShortDate(d.date)}: ${MoneyFormatter.format(d.total)} (${d.count}x)',
                      ),
                  ],
                  if (summary.byCategory.isNotEmpty) ...[
                    const Divider(),
                    const Text(
                      'Ringkasan per Kategori:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    for (final c in summary.byCategory)
                      Text(
                        '• ${catMap[c.categoryId] ?? c.categoryId}: ${MoneyFormatter.format(c.total)} (${c.count}x)',
                      ),
                  ],
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Selesai'),
              ),
            ],
          ),
        );
      }

      if (!mounted) return;
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ids.length} transaksi berhasil disimpan!')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final wallets = ref.watch(activeWalletsProvider);
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? const [])
        .where((c) => !c.isArchived)
        .toList();

    final aiReady = settings?.aiEnabled == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Catat Cepat dengan AI'),
        actions: [
          IconButton(
            tooltip: 'Pengaturan AI',
            icon: const Icon(LucideIcons.slidersHorizontal, size: 19),
            onPressed: () => context.push('/settings/ai'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          if (!aiReady)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(LucideIcons.info, size: 20),
                title: const Text('AI belum diaktifkan'),
                subtitle: const Text(
                  'Aktifkan Gemini / OpenCode BYOK di Pengaturan, atau lanjutkan catat manual.',
                ),
                trailing: TextButton(
                  onPressed: () => context.push('/settings/ai'),
                  child: const Text('Atur AI'),
                ),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _inputCtrl,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: 'Tulis, tempel daftar transaksi, atau ucapkan',
              hintText:
                  'Contoh: Tadi makan ayam geprek 25 ribu, bensin 20 ribu, atau tempel rincian belanja beberapa tanggal sekaligus.',
              suffixIcon: IconButton(
                tooltip: _listening ? 'Berhenti' : 'Input Suara',
                icon: Icon(
                  _listening ? LucideIcons.micOff : LucideIcons.mic,
                  size: 19,
                  color: _listening ? ArusColors.expense : null,
                ),
                onPressed: _toggleVoice,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _parsing ? null : _parse,
                  icon: _parsing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.sparkles, size: 17),
                  label: Text(_parsing ? 'Menganalisis...' : 'Buat Draft Transaksi'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => context.pushReplacement('/transactions/new'),
                child: const Text('Manual'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_error!),
              ),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            if (_result!.clarificationQuestion != null)
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: ListTile(
                  leading: const Icon(LucideIcons.helpCircle, size: 20),
                  title: const Text('Perlu Klarifikasi'),
                  subtitle: Text(_result!.clarificationQuestion!),
                ),
              ),
            if (_result!.drafts.isNotEmpty) ...[
              Builder(
                builder: (context) {
                  final summary = _result!.computeSummary();
                  final catMap = {for (final c in categories) c.id: c.name};
                  return Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ringkasan Terpilih',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          if (summary.totalExpense > 0)
                            Text(
                              'Total Pengeluaran: ${MoneyFormatter.format(summary.totalExpense)}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          if (summary.totalIncome > 0)
                            Text(
                              'Total Pemasukan: ${MoneyFormatter.format(summary.totalIncome)}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          if (summary.byDate.length > 1) ...[
                            const Divider(height: 16),
                            const Text(
                              'Per Tanggal:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            for (final d in summary.byDate)
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${ArusDateUtils.formatShortDate(d.date)} (${d.count}x)',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    MoneyFormatter.format(d.total),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                          if (summary.byCategory.isNotEmpty) ...[
                            const Divider(height: 16),
                            const Text(
                              'Per Kategori:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            for (final c in summary.byCategory)
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${catMap[c.categoryId] ?? c.categoryId} (${c.count}x)',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    MoneyFormatter.format(c.total),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                          if (summary.pendingCount > 0 ||
                              summary.duplicateCount > 0) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              children: [
                                if (summary.pendingCount > 0)
                                  Chip(
                                    label: Text(
                                      '${summary.pendingCount} Pending',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (summary.duplicateCount > 0)
                                  Chip(
                                    label: Text(
                                      '${summary.duplicateCount} Potensi Duplikat',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Draft Transaksi (${_result!.drafts.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              for (final d in _result!.drafts)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: d.selected,
                              onChanged: (v) =>
                                  setState(() => d.selected = v ?? true),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.description,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${ArusDateUtils.formatShortDate(d.occurredAt)}'
                                    '${d.merchant != null && d.merchant!.isNotEmpty ? ' • ${d.merchant}' : ''}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              MoneyFormatter.format(d.amount),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (d.statusNote == 'pending' ||
                            d.isPotentialDuplicate ||
                            d.walletAssumed)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, bottom: 8),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (d.statusNote == 'pending')
                                  Chip(
                                    label: const Text(
                                      'Pending (Diproses)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: ArusColors.warning,
                                      ),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (d.isPotentialDuplicate)
                                  Chip(
                                    label: const Text(
                                      'Potensi Duplikat',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: ArusColors.expense,
                                      ),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (d.walletAssumed)
                                  Chip(
                                    label: Text(
                                      d.paymentMethodLabel != null &&
                                              d.paymentMethodLabel!.isNotEmpty
                                          ? 'Metode: ${d.paymentMethodLabel} (pakai default)'
                                          : 'Dompet diasumsikan default',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: d.walletId,
                                decoration: const InputDecoration(
                                  labelText: 'Dompet',
                                  isDense: true,
                                ),
                                items: [
                                  for (final w in wallets)
                                    DropdownMenuItem(
                                      value: w.id,
                                      child: Text(
                                        w.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() {
                                      d.walletId = v;
                                      d.walletAssumed = false;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (d.type != 'transfer')
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: d.categoryId,
                                  decoration: const InputDecoration(
                                    labelText: 'Kategori',
                                    isDense: true,
                                  ),
                                  items: [
                                    for (final c in categories.where(
                                      (c) => c.kind == d.type,
                                    ))
                                      DropdownMenuItem(
                                        value: c.id,
                                        child: Text(
                                          c.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) setState(() => d.categoryId = v);
                                  },
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
      bottomNavigationBar: _result != null && _result!.drafts.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _saving ? null : _confirmSave,
                  child: Text(
                    _saving ? 'Menyimpan...' : 'Konfirmasi & Simpan ke Lokal',
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
