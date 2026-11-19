import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/arus_exception.dart';

Future<Uint8List> snapshotDatabaseBytesImpl(AppDatabase db) async {
  throw const BackupException(
    'Backup file SQLite (.arusbackup) tersedia pada aplikasi mobile Android/iOS.',
  );
}

Future<List<({String relativePath, Uint8List bytes})>>
    collectAttachmentEntriesImpl() async => const [];

Future<XFile> writeBackupOutputImpl(
  Uint8List payload, {
  String? destinationPath,
}) async =>
    XFile.fromData(payload, name: 'arus_backup.arusbackup');

Future<void> restoreDatabaseAndAttachmentsImpl({
  required AppDatabase db,
  required Uint8List dbBytes,
  required List<({String relativePath, Uint8List bytes})> attachments,
  required Future<void> Function() onReopenDatabase,
}) async {
  throw const BackupException(
    'Restore file SQLite (.arusbackup) tersedia pada aplikasi mobile Android/iOS.',
  );
}
