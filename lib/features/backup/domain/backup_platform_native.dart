import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/arus_exception.dart';

Future<Uint8List> snapshotDatabaseBytesImpl(AppDatabase db) async {
  Directory tempDir;
  try {
    tempDir = await getTemporaryDirectory();
  } catch (_) {
    tempDir = Directory.systemTemp;
  }
  final snapshotFile = File(
    p.join(tempDir.path, 'snapshot_${DateTime.now().millisecondsSinceEpoch}.sqlite'),
  );
  if (await snapshotFile.exists()) {
    await snapshotFile.delete();
  }
  final escapedPath = snapshotFile.path.replaceAll("'", "''");
  await db.customStatement("VACUUM INTO '$escapedPath'");
  final dbBytes = await snapshotFile.readAsBytes();
  await snapshotFile.delete();
  return dbBytes;
}

Future<List<({String relativePath, Uint8List bytes})>>
    collectAttachmentEntriesImpl() async {
  final attPath = await AppDatabase.getAttachmentsDirectoryPath();
  final attDir = Directory(attPath);
  if (!await attDir.exists()) return const [];
  final entries = <({String relativePath, Uint8List bytes})>[];
  await for (final entity in attDir.list(recursive: true)) {
    if (entity is File) {
      final rel = p.relative(entity.path, from: attDir.path);
      entries.add((relativePath: rel, bytes: await entity.readAsBytes()));
    }
  }
  return entries;
}

Future<XFile> writeBackupOutputImpl(
  Uint8List payload, {
  String? destinationPath,
}) async {
  final outPath = destinationPath ??
      p.join(
        (await getApplicationDocumentsDirectory()).path,
        'arus_backup_${DateTime.now().millisecondsSinceEpoch}.arusbackup',
      );
  final outFile = File(outPath);
  await outFile.writeAsBytes(payload, flush: true);
  return XFile(outFile.path, name: p.basename(outFile.path));
}

Future<void> restoreDatabaseAndAttachmentsImpl({
  required AppDatabase db,
  required Uint8List dbBytes,
  required List<({String relativePath, Uint8List bytes})> attachments,
  required Future<void> Function() onReopenDatabase,
}) async {
  final dbFile = await AppDatabase.getDatabaseFile() as File;
  final safetySnapshot = File('${dbFile.path}.pre_restore_bak');
  if (await dbFile.exists()) {
    await dbFile.copy(safetySnapshot.path);
  }
  try {
    await db.close();
    await dbFile.writeAsBytes(dbBytes, flush: true);

    final attPath = await AppDatabase.getAttachmentsDirectoryPath();
    for (final entry in attachments) {
      final target = File(p.join(attPath, entry.relativePath));
      await target.parent.create(recursive: true);
      await target.writeAsBytes(entry.bytes, flush: true);
    }
    await onReopenDatabase();
  } catch (e) {
    if (await safetySnapshot.exists()) {
      await safetySnapshot.copy(dbFile.path);
    }
    await onReopenDatabase();
    throw BackupException(
      'Restore gagal dan database dikembalikan ke kondisi semula: $e',
    );
  }
}
