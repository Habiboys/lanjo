import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/ledger_engine.dart';
import '../../../core/errors/arus_exception.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/file_ops.dart';
import '../../../core/widgets/amount_input_field.dart';
import '../../../core/widgets/lanjo_ui.dart';

/// Fast transaction creation & editing form (FR-03, FR-04, PRD 14.3).
/// Focuses on Nominal, Type, Wallet, and Category; hides extra fields in More Details.
class TransactionFormPage extends ConsumerStatefulWidget {
  const TransactionFormPage({
    super.key,
    this.initialType = 'expense',
    this.editTransactionId,
  });

  final String initialType;
  final String? editTransactionId;

  @override
  ConsumerState<TransactionFormPage> createState() =>
      _TransactionFormPageState();
}

class _TransactionFormPageState extends ConsumerState<TransactionFormPage> {
  final _amountCtrl = TextEditingController();
  final _adminFeeCtrl = TextEditingController(text: '0');
  final _descCtrl = TextEditingController();
  final _merchantCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();

  late String _type;
  String? _walletId;
  String? _destinationWalletId;
  String? _categoryId;
  DateTime _occurredAt = DateTime.now();
  bool _saving = false;
  bool _loadingEdit = false;
  Uint8List? _attachmentBytes;
  String? _attachmentExt;

  // Optional category splitting for expense
  bool _splitMode = false;
  final List<({String categoryId, TextEditingController amountCtrl})> _splits =
      [];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    if (widget.editTransactionId != null) {
      _loadExisting(widget.editTransactionId!);
    }
  }

  Future<void> _loadExisting(String txId) async {
    setState(() => _loadingEdit = true);
    final db = ref.read(appDatabaseProvider);
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingleOrNull();
    if (tx != null && mounted) {
      setState(() {
        _type = tx.type;
        _amountCtrl.text = tx.amount.toString();
        _walletId = tx.primaryWalletId;
        _destinationWalletId = tx.destinationWalletId;
        _categoryId = tx.primaryCategoryId;
        _occurredAt = tx.occurredAt;
        _descCtrl.text = tx.description;
        _merchantCtrl.text = tx.merchant ?? '';
      });
    }
    if (mounted) setState(() => _loadingEdit = false);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _adminFeeCtrl.dispose();
    _descCtrl.dispose();
    _merchantCtrl.dispose();
    _tagsCtrl.dispose();
    for (final s in _splits) {
      s.amountCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _attachmentBytes = bytes;
      _attachmentExt = p.extension(picked.name).isEmpty
          ? '.jpg'
          : p.extension(picked.name);
    });
  }

  Future<void> _save({bool allowNegativeBalance = false}) async {
    if (_saving) return;
    final amount = int.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nominal lebih dari Rp0.')),
      );
      return;
    }

    final wallets = ref.read(activeWalletsProvider);
    final settings = ref.read(appSettingsProvider).valueOrNull;
    final selectedWalletId =
        _walletId ?? settings?.defaultWalletId ?? wallets.firstOrNull?.id;
    if (selectedWalletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Buat dompet terlebih dahulu.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final ledger = ref.read(ledgerEngineProvider);
      final db = ref.read(appDatabaseProvider);
      final tags = _tagsCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      late String txId;
      if (widget.editTransactionId != null) {
        txId = widget.editTransactionId!;
        await ledger.updateSimpleTransaction(
          transactionId: txId,
          amount: amount,
          walletId: selectedWalletId,
          destinationWalletId: _destinationWalletId,
          categoryId: _categoryId,
          occurredAt: _occurredAt,
          description: _descCtrl.text,
          merchant: _merchantCtrl.text.isEmpty ? null : _merchantCtrl.text,
          allowNegativeBalance: allowNegativeBalance,
        );
      } else if (_type == 'transfer') {
        if (_destinationWalletId == null ||
            _destinationWalletId == selectedWalletId) {
          throw const ValidationException('Pilih dompet tujuan yang berbeda.');
        }
        final adminFee = int.tryParse(_adminFeeCtrl.text.trim()) ?? 0;
        txId = await ledger.recordTransfer(
          sourceWalletId: selectedWalletId,
          destinationWalletId: _destinationWalletId!,
          amount: amount,
          adminFee: adminFee,
          occurredAt: _occurredAt,
          description: _descCtrl.text,
          allowNegativeBalance: allowNegativeBalance,
        );
      } else if (_type == 'income') {
        final catId = _categoryId ?? DefaultCategoryIds.salary;
        txId = await ledger.recordIncome(
          walletId: selectedWalletId,
          categoryId: catId,
          amount: amount,
          occurredAt: _occurredAt,
          description: _descCtrl.text,
          merchant: _merchantCtrl.text.isEmpty ? null : _merchantCtrl.text,
          tagNames: tags,
        );
      } else if (_type == 'refund') {
        final catId = _categoryId ?? DefaultCategoryIds.expenseOther;
        txId = await ledger.recordRefund(
          walletId: selectedWalletId,
          categoryId: catId,
          amount: amount,
          occurredAt: _occurredAt,
          description:
              _descCtrl.text.isEmpty ? 'Refund' : _descCtrl.text,
        );
      } else {
        final splitList = _splitMode && _splits.isNotEmpty
            ? [
                for (final s in _splits)
                  CategorySplitInput(
                    categoryId: s.categoryId,
                    amount: int.tryParse(s.amountCtrl.text.trim()) ?? 0,
                    description: _descCtrl.text,
                  ),
              ]
            : [
                CategorySplitInput(
                  categoryId: _categoryId ?? DefaultCategoryIds.food,
                  amount: amount,
                  description: _descCtrl.text,
                ),
              ];

        txId = await ledger.recordExpense(
          walletId: selectedWalletId,
          amount: amount,
          splits: splitList,
          occurredAt: _occurredAt,
          description: _descCtrl.text,
          merchant: _merchantCtrl.text.isEmpty ? null : _merchantCtrl.text,
          tagNames: tags,
          allowNegativeBalance: allowNegativeBalance,
        );
      }

      if (_attachmentBytes != null) {
        final attDirPath = await AppDatabase.getAttachmentsDirectoryPath();
        final fileName = '${const Uuid().v4()}${_attachmentExt ?? '.jpg'}';
        final rel = await saveAttachmentBytesImpl(
          attDirPath,
          fileName,
          _attachmentBytes!,
        );
        await db.into(db.attachments).insert(
              AttachmentsCompanion.insert(
                id: const Uuid().v4(),
                transactionId: Value(txId),
                relativePath: rel,
                createdAt: DateTime.now(),
              ),
            );
      }

      await ref.read(budgetServiceProvider).evaluateAlerts();

      if (!mounted) return;
      // FR-12: Offer Salary Day flow when recording Salary income!
      if (widget.editTransactionId == null &&
          _type == 'income' &&
          (_categoryId == DefaultCategoryIds.salary)) {
        final goSalaryDay = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Gaji Masuk Tercatat!'),
            content: Text(
              'Pemasukan gaji ${MoneyFormatter.format(amount)} berhasil disimpan. Ingin langsung membagi alokasi gaji (Salary Day)?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Nanti Saja'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Atur Salary Day'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (goSalaryDay == true) {
          context.pop();
          context.push('/plans/salary-day?amount=$amount&txId=$txId');
          return;
        }
      }

      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Transaksi disimpan'),
          action: widget.editTransactionId != null
              ? null
              : SnackBarAction(
                  label: 'Undo',
                  onPressed: () => ledger.voidTransaction(txId, reason: 'Undo'),
                ),
        ),
      );
    } on NegativeAssetBalanceException catch (e) {
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Peringatan Saldo Negatif'),
          content: Text(
            '${e.message}\nSaldo saat ini: ${MoneyFormatter.format(e.currentBalance)}. '
            'Apakah transaksi ini memang mencerminkan kondisi aktual?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tetap Catat'),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) {
        setState(() => _saving = false);
        await _save(allowNegativeBalance: true);
        return;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(activeWalletsProvider);
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final allCats = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final allTxs =
        ref.watch(transactionsStreamProvider).valueOrNull ?? const [];

    final effectiveWalletId =
        _walletId ?? settings?.defaultWalletId ?? wallets.firstOrNull?.id;

    final catKind = _type == 'income' ? 'income' : 'expense';
    final filteredCats = allCats
        .where((c) => !c.isArchived && c.kind == catKind)
        .toList();
    final effectiveCatId = _categoryId ??
        filteredCats.where((c) => c.isFavorite).firstOrNull?.id ??
        filteredCats.firstOrNull?.id;

    // Smart suggestions from recent descriptions in this category
    final recentSuggestions = <String>{};
    for (final tx in allTxs) {
      if (tx.primaryCategoryId == effectiveCatId &&
          tx.description.trim().isNotEmpty &&
          tx.description.trim().length <= 28) {
        recentSuggestions.add(tx.description.trim());
        if (recentSuggestions.length >= 5) break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.editTransactionId == null
              ? 'Catat Transaksi'
              : 'Edit Transaksi',
        ),
      ),
      body: _loadingEdit
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                if (widget.editTransactionId == null) ...[
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'expense', label: Text('Keluar')),
                      ButtonSegment(value: 'income', label: Text('Masuk')),
                      ButtonSegment(value: 'transfer', label: Text('Transfer')),
                      ButtonSegment(value: 'refund', label: Text('Refund')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) {
                      setState(() {
                        _type = s.first;
                        _categoryId = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                AmountInputField(
                  controller: _amountCtrl,
                  label: 'Nominal',
                ),
                const SizedBox(height: 18),
                Text(
                  _type == 'transfer' ? 'Dompet Asal' : 'Pilih Dompet / Rekening',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.lanjoMuted,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 66,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: wallets.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final w = wallets[idx];
                      final isSelected = w.id == effectiveWalletId;
                      final wColor = Color(w.colorValue);
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setState(() => _walletId = w.id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? wColor.withValues(
                                    alpha: context.isDark ? 0.22 : 0.10,
                                  )
                                : context.lanjoCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? wColor : context.lanjoBorder,
                              width: isSelected ? 1.6 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LanjoIconBox(
                                icon: arusIconFromName(w.icon),
                                color: wColor,
                                size: 34,
                                iconSize: 16,
                                radius: 10,
                              ),
                              const SizedBox(width: 9),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    w.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        ),
                                  ),
                                  Text(
                                    MoneyFormatter.formatCompact(
                                      w.cachedBalance,
                                    ),
                                    style: lanjoMoneyStyle(
                                      context,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: context.lanjoMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_type == 'transfer') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    value: _destinationWalletId,
                    decoration: const InputDecoration(
                      labelText: 'Dompet Tujuan',
                    ),
                    items: [
                      for (final w in wallets)
                        if (w.id != effectiveWalletId)
                          DropdownMenuItem<String?>(
                            value: w.id,
                            child: Text(
                              '${w.name} (${MoneyFormatter.formatCompact(w.cachedBalance)})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                    onChanged: (v) => setState(() => _destinationWalletId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _adminFeeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Biaya Admin Transfer (opsional)',
                      prefixText: 'Rp ',
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Pilih Kategori',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: context.lanjoMuted),
                        ),
                      ),
                      if (_type == 'expense' && widget.editTransactionId == null)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _splitMode = !_splitMode;
                              if (_splitMode && _splits.isEmpty && filteredCats.length >= 2) {
                                _splits.add((
                                  categoryId: effectiveCatId ?? filteredCats.first.id,
                                  amountCtrl: TextEditingController(),
                                ));
                                _splits.add((
                                  categoryId: filteredCats[1].id,
                                  amountCtrl: TextEditingController(),
                                ));
                              }
                            });
                          },
                          child: Text(
                            _splitMode ? 'Satu Kategori' : 'Split Kategori',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (!_splitMode)
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredCats.length,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 105,
                        mainAxisExtent: 76,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemBuilder: (context, idx) {
                        final cat = filteredCats[idx];
                        final isSelected = effectiveCatId == cat.id;
                        final catColor = Color(cat.colorValue);
                        return InkWell(
                          borderRadius: BorderRadius.circular(15),
                          onTap: () => setState(() => _categoryId = cat.id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? catColor.withValues(
                                      alpha: context.isDark ? 0.24 : 0.11,
                                    )
                                  : context.lanjoCard,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: isSelected
                                    ? catColor
                                    : context.lanjoBorder,
                                width: isSelected ? 1.6 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  arusIconFromName(cat.icon),
                                  size: 20,
                                  color: catColor,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  cat.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? context.lanjoInk
                                        : context.lanjoMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            for (var i = 0; i < _splits.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: DropdownButtonFormField<String>(
                                        isExpanded: true,
                                        value: _splits[i].categoryId,
                                        decoration: const InputDecoration(
                                          labelText: 'Kategori',
                                        ),
                                        items: [
                                          for (final c in filteredCats)
                                            DropdownMenuItem(
                                              value: c.id,
                                              child: Text(
                                                c.name,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                        onChanged: (v) {
                                          if (v == null) return;
                                          setState(() {
                                            final ctrl = _splits[i].amountCtrl;
                                            _splits[i] = (
                                              categoryId: v,
                                              amountCtrl: ctrl,
                                            );
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: _splits[i].amountCtrl,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Nominal',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _splits.add((
                                    categoryId: filteredCats.first.id,
                                    amountCtrl: TextEditingController(),
                                  ));
                                });
                              },
                              icon: const Icon(LucideIcons.plus, size: 17),
                              label: const Text('Tambah Baris Split'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Catatan / Deskripsi (opsional)',
                    hintText: 'Contoh: Makan siang nasi padang',
                  ),
                ),
                if (recentSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in recentSuggestions)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(s, style: const TextStyle(fontSize: 11.5)),
                          onPressed: () => setState(() => _descCtrl.text = s),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                ExpansionTile(
                  title: const Text('Detail Tambahan'),
                  subtitle: Text(
                    'Tanggal: ${ArusDateUtils.formatDateTime(_occurredAt)}',
                  ),
                  childrenPadding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    ListTile(
                      leading: const Icon(LucideIcons.calendar, size: 19),
                      title: const Text('Tanggal & Waktu'),
                      subtitle: Text(ArusDateUtils.formatDateTime(_occurredAt)),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _occurredAt,
                          firstDate: DateTime(2015),
                          lastDate: DateTime(2035),
                        );
                        if (date == null || !context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(_occurredAt),
                        );
                        if (!mounted) return;
                        setState(() {
                          _occurredAt = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time?.hour ?? _occurredAt.hour,
                            time?.minute ?? _occurredAt.minute,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _merchantCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Merchant / Toko (opsional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tagsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tag (pisahkan dengan koma)',
                        hintText: 'Contoh: kantor, liburan',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickAttachment,
                      icon: const Icon(LucideIcons.paperclip, size: 17),
                      label: Text(
                        _attachmentBytes == null
                            ? 'Lampirkan Foto Struk'
                            : 'Foto Struk Terlampir',
                      ),
                    ),
                  ],
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _saving ? null : () => _save(),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Simpan Transaksi'),
          ),
        ),
      ),
    );
  }
}
