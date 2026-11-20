import 'package:drift/drift.dart' show OrderingTerm;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/app_database.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/file_ops.dart';
import '../domain/import_export_service.dart';

/// CSV/Excel transaction importer with column mapping, validation, duplicate skip,
/// batch rollback, and CSV export (FR-25).
class ImportExportPage extends ConsumerStatefulWidget {
  const ImportExportPage({super.key});

  @override
  ConsumerState<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends ConsumerState<ImportExportPage> {
  String? _fileName;
  List<List<String>> _rawRows = const [];
  List<ImportRowCandidate> _preview = const [];
  String? _walletId;
  int _dateCol = 0;
  int _amountCol = 1;
  int _descCol = 2;
  int? _typeCol;
  bool _skipDuplicates = true;
  bool _busy = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
      withData: true,
    );
    if (result == null) return;
    final picked = result.files.single;
    final bytes =
        picked.bytes ?? await readFileBytesByPathImpl(picked.path);
    if (bytes == null) return;
    final table = ref
        .read(importExportServiceProvider)
        .parseTableBytes(bytes, picked.name);

    final wallets = ref.read(activeWalletsProvider);
    setState(() {
      _fileName = picked.name;
      _rawRows = table;
      _walletId ??= wallets.firstOrNull?.id;
      _preview = const [];
    });
    await _refreshPreview();
  }

  Future<void> _refreshPreview() async {
    if (_rawRows.isEmpty || _walletId == null) return;
    final preview = await ref.read(importExportServiceProvider).previewMappedRows(
          rawRows: _rawRows,
          mapping: ImportColumnMapping(
            dateCol: _dateCol,
            amountCol: _amountCol,
            descriptionCol: _descCol,
            typeCol: _typeCol,
          ),
          walletId: _walletId!,
        );
    if (mounted) setState(() => _preview = preview);
  }

  Future<void> _commit() async {
    if (_fileName == null || _walletId == null || _preview.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(importExportServiceProvider).commitImport(
            fileName: _fileName!,
            walletId: _walletId!,
            rows: _preview,
            skipDuplicates: _skipDuplicates,
          );
      ref.invalidate(safeToSpendProvider);
      if (mounted) {
        setState(() {
          _rawRows = const [];
          _preview = const [];
          _fileName = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import transaksi berhasil!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(activeWalletsProvider);
    final txs = ref.watch(transactionsStreamProvider).valueOrNull ?? const [];
    final db = ref.watch(appDatabaseProvider);
    final batchesStream = (db.select(db.importBatches)
          ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
        .watch();

    final colCount = _rawRows.isNotEmpty ? _rawRows.first.length : 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Import & Export')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(LucideIcons.download, size: 20),
              title: const Text('Export Semua Transaksi (CSV)'),
              subtitle: Text('${txs.length} transaksi tercatat'),
              onTap: txs.isEmpty
                  ? null
                  : () async {
                      final file = await ref
                          .read(importExportServiceProvider)
                          .exportTransactionsCsv(txs);
                      await Share.shareXFiles([file]);
                    },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Import Mutasi (CSV / Excel)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(LucideIcons.folderOpen, size: 17),
                    label: Text(_fileName ?? 'Pilih File CSV / XLSX'),
                  ),
                  if (colCount > 0) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _walletId,
                      decoration: const InputDecoration(labelText: 'Dompet Tujuan'),
                      items: [
                        for (final w in wallets)
                          DropdownMenuItem(
                            value: w.id,
                            child: Text(w.name, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() => _walletId = v);
                        _refreshPreview();
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: _dateCol.clamp(0, colCount - 1),
                            decoration: const InputDecoration(labelText: 'Kolom Tanggal'),
                            items: [
                              for (var i = 0; i < colCount; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(
                                    'Kolom ${i + 1}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _dateCol = v);
                                _refreshPreview();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: _amountCol.clamp(0, colCount - 1),
                            decoration: const InputDecoration(labelText: 'Kolom Nominal'),
                            items: [
                              for (var i = 0; i < colCount; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(
                                    'Kolom ${i + 1}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _amountCol = v);
                                _refreshPreview();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: _descCol.clamp(0, colCount - 1),
                            decoration: const InputDecoration(labelText: 'Kolom Deskripsi'),
                            items: [
                              for (var i = 0; i < colCount; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(
                                    'Kolom ${i + 1}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _descCol = v);
                                _refreshPreview();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int?>(
                            isExpanded: true,
                            value: _typeCol,
                            decoration: const InputDecoration(labelText: 'Kolom Jenis'),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text(
                                  'Otomatis',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              for (var i = 0; i < colCount; i++)
                                DropdownMenuItem<int?>(
                                  value: i,
                                  child: Text(
                                    'Kolom ${i + 1}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              setState(() => _typeCol = v);
                              _refreshPreview();
                            },
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Lewati transaksi duplikat'),
                      value: _skipDuplicates,
                      onChanged: (v) => setState(() => _skipDuplicates = v),
                    ),
                    if (_preview.isNotEmpty) ...[
                      Text(
                        'Preview (${_preview.where((e) => e.isValid).length} valid, '
                        '${_preview.where((e) => e.isDuplicate).length} duplikat, '
                        '${_preview.where((e) => !e.isValid).length} error)',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      for (final row in _preview.take(6))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(row.description),
                          subtitle: Text(
                            row.errorReason ??
                                (row.isDuplicate
                                    ? 'Duplikat terdeteksi'
                                    : '${row.type} • ${row.date?.toIso8601String().substring(0, 10)}'),
                          ),
                          trailing: Text(
                            row.amount == null
                                ? '-'
                                : MoneyFormatter.format(row.amount!),
                          ),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _commit,
                          child: const Text('Konfirmasi Import'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Riwayat Batch Import',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<ImportBatchRecord>>(
            stream: batchesStream,
            builder: (context, snap) {
              final batches = snap.data ?? const [];
              if (batches.isEmpty) {
                return const Text('Belum ada riwayat import.');
              }
              return Column(
                children: [
                  for (final b in batches)
                    Card(
                      child: ListTile(
                        title: Text(b.fileName),
                        subtitle: Text(
                          '${b.importedRows} diimpor • Status: ${b.status}',
                        ),
                        trailing: b.status == 'completed'
                            ? TextButton(
                                onPressed: () async {
                                  await ref
                                      .read(importExportServiceProvider)
                                      .rollbackImportBatch(b.id);
                                  ref.invalidate(safeToSpendProvider);
                                },
                                child: const Text('Batalkan'),
                              )
                            : const Chip(label: Text('Dibatalkan')),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
