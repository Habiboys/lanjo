import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanjo/core/database/app_database.dart';
import 'package:lanjo/core/database/ledger_engine.dart';
import 'package:lanjo/features/import_export/domain/import_export_service.dart';

void main() {
  late AppDatabase db;
  late LedgerEngine ledger;
  late ImportExportService importExport;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    ledger = LedgerEngine(db);
    importExport = ImportExportService(db, ledger);
    await db.select(db.categories).get();
  });

  tearDown(() async {
    await db.close();
  });

  test('CSV import detects duplicates, imports valid rows, and rolls back cleanly', () async {
    final walletId = await ledger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 1000000,
    );

    final rawRows = [
      ['Tanggal', 'Nominal', 'Keterangan', 'Jenis'],
      ['2026-11-10', '50000', 'Makan siang', 'expense'],
      ['2026-11-11', '250000', 'Bonus proyek', 'income'],
      ['tanggal_salah', '10000', 'Baris error', 'expense'],
    ];

    final preview = await importExport.previewMappedRows(
      rawRows: rawRows,
      mapping: const ImportColumnMapping(
        dateCol: 0,
        amountCol: 1,
        descriptionCol: 2,
        typeCol: 3,
      ),
      walletId: walletId,
    );

    expect(preview.length, 3);
    expect(preview[0].isValid, isTrue);
    expect(preview[1].isValid, isTrue);
    expect(preview[2].isValid, isFalse);

    final batchId = await importExport.commitImport(
      fileName: 'mutasi.csv',
      walletId: walletId,
      rows: preview,
    );

    // 1.000.000 - 50.000 + 250.000 = 1.200.000
    expect(await ledger.computeAccountBalance(walletId), 1200000);

    // Second preview marks first two rows as duplicates
    final preview2 = await importExport.previewMappedRows(
      rawRows: rawRows,
      mapping: const ImportColumnMapping(
        dateCol: 0,
        amountCol: 1,
        descriptionCol: 2,
        typeCol: 3,
      ),
      walletId: walletId,
    );
    expect(preview2[0].isDuplicate, isTrue);
    expect(preview2[1].isDuplicate, isTrue);

    // Rollback batch restores 1.000.000 balance
    await importExport.rollbackImportBatch(batchId);
    expect(await ledger.computeAccountBalance(walletId), 1000000);
    expect((await ledger.verifyLedgerIntegrity()).isBalanced, isTrue);
  });
}
