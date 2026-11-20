import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/ledger_engine.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/file_ops.dart';
import '../../ai_assistant/domain/ai_finance_service.dart';

/// AI Receipt Scanner with preview, explicit upload consent, item split support,
/// duplicate warning, and optional local retention (FR-18).
class ReceiptScannerPage extends ConsumerStatefulWidget {
  const ReceiptScannerPage({super.key, this.initialImagePath});

  final String? initialImagePath;

  @override
  ConsumerState<ReceiptScannerPage> createState() => _ReceiptScannerPageState();
}

class _ReceiptScannerPageState extends ConsumerState<ReceiptScannerPage> {
  Uint8List? _imageBytes;
  bool _scanning = false;
  bool _saving = false;
  bool _keepImageLocally = false;
  ReceiptScanResult? _scanResult;
  String? _selectedWalletId;
  String? _selectedCatId;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null &&
        widget.initialImagePath!.trim().isNotEmpty) {
      _loadSharedImage(widget.initialImagePath!.trim());
    }
  }

  Future<void> _loadSharedImage(String path) async {
    final bytes = await readFileBytesByPathImpl(path);
    if (!mounted || bytes == null) return;
    setState(() {
      _imageBytes = bytes;
      _scanResult = null;
      _error = null;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 78,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _scanResult = null;
      _error = null;
    });
  }

  Future<void> _scanWithConsent() async {
    final bytes = _imageBytes;
    if (bytes == null) return;

    final consent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kirim Foto Struk ke AI?'),
        content: const Text(
          'Foto struk akan dikirim ke penyedia AI aktif (Gemini / OpenCode) menggunakan API Key milikmu untuk membaca merchant, tanggal, dan daftar item. Pastikan informasi sensitif yang tidak perlu tidak terlihat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Setuju & Scan'),
          ),
        ],
      ),
    );
    if (consent != true || !mounted) return;

    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(aiFinanceServiceProvider)
          .scanReceiptImage(imageBytes: bytes);
      if (!mounted) return;
      setState(() {
        _scanResult = res;
        _selectedWalletId = res.suggestedWalletId;
        _selectedCatId = res.suggestedCategoryId;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _saveReceipt() async {
    final res = _scanResult;
    if (res == null || _saving) return;
    final walletId = _selectedWalletId ?? res.suggestedWalletId;
    final catId = _selectedCatId ?? res.suggestedCategoryId;

    setState(() => _saving = true);
    try {
      final ledger = ref.read(ledgerEngineProvider);
      final db = ref.read(appDatabaseProvider);
      final txId = await ledger.recordExpense(
        walletId: walletId,
        amount: res.totalAmount,
        splits: [
          CategorySplitInput(
            categoryId: catId,
            amount: res.totalAmount,
            description: res.merchant,
          ),
        ],
        occurredAt: res.date,
        description: 'Struk ${res.merchant}',
        merchant: res.merchant,
        source: 'scan',
        allowNegativeBalance: true,
      );

      if (_keepImageLocally && _imageBytes != null) {
        final attDirPath = await AppDatabase.getAttachmentsDirectoryPath();
        final fileName = '${const Uuid().v4()}.jpg';
        final rel = await saveAttachmentBytesImpl(
          attDirPath,
          fileName,
          _imageBytes!,
        );
        await db.into(db.attachments).insert(
              AttachmentsCompanion.insert(
                id: const Uuid().v4(),
                transactionId: Value(txId),
                relativePath: rel,
                contentHash: Value(res.imageHash),
                createdAt: DateTime.now(),
              ),
            );
      }

      await ref.read(budgetServiceProvider).evaluateAlerts();
      if (!mounted) return;
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaksi dari struk disimpan!')),
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
    final wallets = ref.watch(activeWalletsProvider);
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? const [])
        .where((c) => !c.isArchived && c.kind == 'expense')
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Struk AI')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(LucideIcons.camera, size: 17),
                  label: const Text('Kamera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(LucideIcons.image, size: 17),
                  label: const Text('Galeri'),
                ),
              ),
            ],
          ),
          if (_imageBytes != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                _imageBytes!,
                height: 220,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _scanning ? null : _scanWithConsent,
              icon: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.scanLine, size: 17),
              label: Text(_scanning ? 'Membaca Struk...' : 'Ekstrak Struk dengan AI'),
            ),
          ],
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
          if (_scanResult != null) ...[
            const SizedBox(height: 16),
            if (_scanResult!.isDuplicateSuspected)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: const ListTile(
                  leading: Icon(LucideIcons.alertTriangle, size: 20),
                  title: Text('Peringatan Struk Duplikat'),
                  subtitle: Text(
                    'Struk atau nominal di tanggal ini sudah pernah tercatat sebelumnya.',
                  ),
                ),
              ),
            if (_scanResult!.reconciliationWarning != null)
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_scanResult!.reconciliationWarning!),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _scanResult!.merchant,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      'Total: ${MoneyFormatter.format(_scanResult!.totalAmount)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _selectedWalletId,
                      decoration: const InputDecoration(labelText: 'Dompet'),
                      items: [
                        for (final w in wallets)
                          DropdownMenuItem(
                            value: w.id,
                            child: Text(w.name, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _selectedWalletId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _selectedCatId,
                      decoration: const InputDecoration(labelText: 'Kategori'),
                      items: [
                        for (final c in categories)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _selectedCatId = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Simpan foto struk di perangkat'),
                      value: _keepImageLocally,
                      onChanged: (v) => setState(() => _keepImageLocally = v),
                    ),
                    if (_scanResult!.items.isNotEmpty) ...[
                      const Divider(),
                      const Text(
                        'Daftar Item:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      for (final it in _scanResult!.items)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(it.name)),
                            Text(MoneyFormatter.format(it.price)),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: _scanResult != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _saving ? null : _saveReceipt,
                  child: const Text('Konfirmasi & Simpan Transaksi'),
                ),
              ),
            )
          : null,
    );
  }
}
