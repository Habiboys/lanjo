import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/ledger_engine.dart';
import '../../../core/errors/arus_exception.dart';
import '../../../core/money/money_formatter.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/file_ops.dart';

class ImportRowCandidate {
  const ImportRowCandidate({
    required this.rowNumber,
    required this.date,
    required this.type,
    required this.amount,
    required this.description,
    required this.categoryId,
    this.isDuplicate = false,
    this.errorReason,
  });

  final int rowNumber;
  final DateTime? date;
  final String type; // income or expense
  final int? amount;
  final String description;
  final String categoryId;
  final bool isDuplicate;
  final String? errorReason;

  bool get isValid => errorReason == null && date != null && (amount ?? 0) > 0;
}

class ImportColumnMapping {
  const ImportColumnMapping({
    required this.dateCol,
    required this.amountCol,
    required this.descriptionCol,
    this.typeCol,
  });

  final int dateCol;
  final int amountCol;
  final int descriptionCol;
  final int? typeCol;
}

/// CSV/PDF report exporter (FR-21) & CSV/Excel batch importer with rollback (FR-25).
class ImportExportService {
  ImportExportService(this.db, this._ledger, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final AppDatabase db;
  final LedgerEngine _ledger;
  final Uuid _uuid;

  Future<XFile> exportTransactionsCsv(
    List<TransactionRecord> txs, {
    String fileName = 'arus_transaksi.csv',
  }) async {
    final cats = await db.select(db.categories).get();
    final catMap = {for (final c in cats) c.id: c.name};
    final wallets = await db.select(db.accounts).get();
    final walletMap = {for (final w in wallets) w.id: w.name};

    final rows = <List<dynamic>>[
      ['Tanggal', 'Jenis', 'Nominal', 'Dompet', 'Kategori', 'Merchant', 'Deskripsi'],
      for (final tx in txs)
        [
          tx.occurredAt.toIso8601String(),
          tx.type,
          tx.amount,
          walletMap[tx.primaryWalletId] ?? '-',
          catMap[tx.primaryCategoryId] ?? '-',
          tx.merchant ?? '',
          tx.description,
        ],
    ];

    final csvString = const ListToCsvConverter().convert(rows);
    return writeTempXFileImpl(
      Uint8List.fromList(utf8.encode(csvString)),
      fileName,
      mimeType: 'text/csv',
    );
  }

  Future<XFile> exportFinancialReportPdf({
    required String title,
    required DateTime start,
    required DateTime end,
    required int totalIncome,
    required int totalExpense,
    required List<({String name, int amount})> categoryRows,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'Laporan Keuangan Lanjo',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(
            '$title (${ArusDateUtils.formatShortDate(start)} - ${ArusDateUtils.formatShortDate(end)})',
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Pemasukan: ${MoneyFormatter.format(totalIncome)}'),
              pw.Text('Total Pengeluaran: ${MoneyFormatter.format(totalExpense)}'),
              pw.Text(
                'Selisih: ${MoneyFormatter.format(totalIncome - totalExpense)}',
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Rincian Pengeluaran per Kategori',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['Kategori', 'Nominal'],
            data: [
              for (final row in categoryRows)
                [row.name, MoneyFormatter.format(row.amount)],
            ],
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    return writeTempXFileImpl(
      bytes,
      'arus_laporan.pdf',
      mimeType: 'application/pdf',
    );
  }

  /// Parses raw CSV or Excel bytes into a 2D table of strings for preview & mapping.
  List<List<String>> parseTableBytes(Uint8List bytes, String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    if (ext == '.xlsx' || ext == '.xls') {
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) return const [];
      final firstSheet = excel.tables.values.first;
      return firstSheet.rows
          .map((row) => row.map((cell) => cell?.value?.toString() ?? '').toList())
          .where((row) => row.any((c) => c.trim().isNotEmpty))
          .toList();
    }

    final text = String.fromCharCodes(bytes);
    final rows = const CsvToListConverter(eol: '\n').convert(text);
    return rows
        .map((r) => r.map((c) => c.toString()).toList())
        .where((r) => r.any((c) => c.trim().isNotEmpty))
        .toList();
  }

  Future<List<ImportRowCandidate>> previewMappedRows({
    required List<List<String>> rawRows,
    required ImportColumnMapping mapping,
    required String walletId,
    bool skipHeader = true,
  }) async {
    final existingTxs = await (db.select(db.transactions)
          ..where((t) =>
              t.primaryWalletId.equals(walletId) & t.status.equals('posted')))
        .get();

    final dupSignatures = existingTxs
        .map((t) =>
            '${t.occurredAt.year}-${t.occurredAt.month}-${t.occurredAt.day}_${t.amount}_${t.description.toLowerCase()}')
        .toSet();

    final startIndex = skipHeader ? 1 : 0;
    final candidates = <ImportRowCandidate>[];

    for (var i = startIndex; i < rawRows.length; i++) {
      final row = rawRows[i];
      String cell(int? idx) =>
          (idx != null && idx >= 0 && idx < row.length) ? row[idx].trim() : '';

      final rawDate = cell(mapping.dateCol);
      final rawAmount = cell(mapping.amountCol);
      final desc = cell(mapping.descriptionCol);
      final rawType = cell(mapping.typeCol).toLowerCase();

      final parsedDate = _parseFlexibleDate(rawDate);
      final parsedAmount = _parseRawSignedAmount(rawAmount);
      String? error;
      if (parsedDate == null) {
        error = 'Format tanggal tidak dikenali ($rawDate)';
      } else if (parsedAmount == null || parsedAmount == 0) {
        error = 'Nominal tidak valid ($rawAmount)';
      }

      var txType = 'expense';
      if (rawType.contains('masuk') ||
          rawType.contains('income') ||
          rawType.contains('credit') ||
          rawType.contains('cr')) {
        txType = 'income';
      } else if (parsedAmount != null && parsedAmount > 0 && rawAmount.startsWith('+')) {
        txType = 'income';
      }

      final absAmount = parsedAmount?.abs();
      var isDup = false;
      if (parsedDate != null && absAmount != null) {
        final sig =
            '${parsedDate.year}-${parsedDate.month}-${parsedDate.day}_${absAmount}_${desc.toLowerCase()}';
        isDup = dupSignatures.contains(sig);
      }

      candidates.add(
        ImportRowCandidate(
          rowNumber: i + 1,
          date: parsedDate,
          type: txType,
          amount: absAmount,
          description: desc.isEmpty ? 'Transaksi Impor' : desc,
          categoryId: txType == 'income'
              ? DefaultCategoryIds.incomeOther
              : DefaultCategoryIds.expenseOther,
          isDuplicate: isDup,
          errorReason: error,
        ),
      );
    }
    return candidates;
  }

  Future<String> commitImport({
    required String fileName,
    required String walletId,
    required List<ImportRowCandidate> rows,
    bool skipDuplicates = true,
  }) async {
    final validRows = rows
        .where((r) => r.isValid && (!skipDuplicates || !r.isDuplicate))
        .toList();
    if (validRows.isEmpty) {
      throw const ValidationException('Tidak ada baris valid untuk diimpor.');
    }

    final batchId = _uuid.v4();
    final skippedDup = rows.where((r) => r.isValid && r.isDuplicate).length;

    await db.transaction(() async {
      await db.into(db.importBatches).insert(
            ImportBatchesCompanion.insert(
              id: batchId,
              fileName: fileName,
              walletId: walletId,
              totalRows: rows.length,
              importedRows: validRows.length,
              skippedDuplicates: Value(skipDuplicates ? skippedDup : 0),
              createdAt: DateTime.now(),
            ),
          );

      for (final row in validRows) {
        if (row.type == 'income') {
          await _ledger.recordIncome(
            walletId: walletId,
            categoryId: row.categoryId,
            amount: row.amount!,
            occurredAt: row.date!,
            description: row.description,
            source: 'import',
            importBatchId: batchId,
          );
        } else {
          await _ledger.recordExpense(
            walletId: walletId,
            amount: row.amount!,
            splits: [
              CategorySplitInput(
                categoryId: row.categoryId,
                amount: row.amount!,
                description: row.description,
              ),
            ],
            occurredAt: row.date!,
            description: row.description,
            source: 'import',
            importBatchId: batchId,
            allowNegativeBalance: true,
          );
        }
      }
    });

    return batchId;
  }

  Future<void> rollbackImportBatch(String batchId) async {
    await db.transaction(() async {
      final txs = await (db.select(db.transactions)
            ..where((t) =>
                t.importBatchId.equals(batchId) & t.status.equals('posted')))
          .get();
      for (final tx in txs) {
        await _ledger.voidTransaction(
          tx.id,
          reason: 'Rollback import batch $batchId',
        );
      }
      await (db.update(db.importBatches)..where((b) => b.id.equals(batchId)))
          .write(const ImportBatchesCompanion(status: Value('reverted')));
    });
  }

  DateTime? _parseFlexibleDate(String raw) {
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;
    final slash = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$').firstMatch(raw);
    if (slash != null) {
      final d = int.parse(slash.group(1)!);
      final m = int.parse(slash.group(2)!);
      var y = int.parse(slash.group(3)!);
      if (y < 100) y += 2000;
      if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return DateTime(y, m, d, 12, 0);
      }
    }
    return null;
  }

  int? _parseRawSignedAmount(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final isNeg = trimmed.startsWith('-');
    final parsed = MoneyFormatter.parseIndonesianAmount(trimmed);
    if (parsed == null) return null;
    return isNeg ? -parsed : parsed;
  }
}
