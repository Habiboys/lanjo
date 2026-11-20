import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:share_plus/share_plus.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/arus_exception.dart';
import '../../../core/notifications/local_notification_service.dart';
import 'backup_platform.dart';

class BackupManifest {
  const BackupManifest({
    required this.formatVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.dbSha256,
    required this.attachmentCount,
  });

  final int formatVersion;
  final int schemaVersion;
  final DateTime createdAt;
  final String dbSha256;
  final int attachmentCount;

  Map<String, dynamic> toJson() => {
        'format_version': formatVersion,
        'schema_version': schemaVersion,
        'created_at': createdAt.toIso8601String(),
        'db_sha256': dbSha256,
        'attachment_count': attachmentCount,
        'excludes': ['gemini_api_key', 'raw_pin', 'fcm_token'],
      };

  static BackupManifest fromJson(Map<String, dynamic> json) {
    return BackupManifest(
      formatVersion: (json['format_version'] as num?)?.toInt() ?? 1,
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.parse(json['created_at'] as String),
      dbSha256: json['db_sha256'] as String,
      attachmentCount: (json['attachment_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Encrypted `.arusbackup` builder and restorer (FR-27).
/// Secrets (Gemini API Key, raw PIN, FCM token) live in SecureStorage and
/// are NEVER included in the backup archive.
class BackupService {
  BackupService(this.db, this._notifications);

  final AppDatabase db;
  final LocalNotificationService _notifications;

  static const int currentFormatVersion = 1;
  static const _magicHeader = 'ARUSBK01';

  Future<XFile> createEncryptedBackup({
    required String password,
    bool includeAttachments = true,
    String? destinationPath,
  }) async {
    if (password.length < 6) {
      throw const BackupException('Password backup minimal 6 karakter.');
    }

    final dbBytes = await snapshotDatabaseBytesImpl(db);
    final dbHash = sha256.convert(dbBytes).toString();
    final archive = Archive();
    archive.addFile(ArchiveFile('database.sqlite', dbBytes.length, dbBytes));

    var attCount = 0;
    if (includeAttachments) {
      final atts = await collectAttachmentEntriesImpl();
      for (final a in atts) {
        archive.addFile(
          ArchiveFile('attachments/${a.relativePath}', a.bytes.length, a.bytes),
        );
        attCount++;
      }
    }

    final manifest = BackupManifest(
      formatVersion: currentFormatVersion,
      schemaVersion: db.schemaVersion,
      createdAt: DateTime.now(),
      dbSha256: dbHash,
      attachmentCount: attCount,
    );
    final manifestBytes = utf8.encode(jsonEncode(manifest.toJson()));
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
    final encryptedPayload = _encryptBytes(zipBytes, password);

    final outFile = await writeBackupOutputImpl(
      encryptedPayload,
      destinationPath: destinationPath,
    );

    await (db.update(db.appSettings)..where((s) => s.id.equals('default')))
        .write(
      AppSettingsCompanion(
        lastBackupAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    return outFile;
  }

  /// Decrypts and validates `.arusbackup` bytes before prompting confirmation.
  Future<BackupManifest> inspectBackupBytes({
    required Uint8List bytes,
    required String password,
  }) async {
    final archive = _decryptAndVerifyArchive(bytes, password);
    final manifestFile = archive.findFile('manifest.json')!;
    final json =
        jsonDecode(utf8.decode(manifestFile.content as List<int>))
            as Map<String, dynamic>;
    return BackupManifest.fromJson(json);
  }

  /// Restores database & attachments atomically after creating a safety snapshot.
  ///
  /// Because [restoreDatabaseAndAttachmentsImpl] closes [db] before overwriting
  /// the SQLite file, callers using Riverpod / lazy isolate databases must
  /// pass [resolveNotifications] so reminder rescheduling runs against the
  /// newly reopened database connection rather than the closed instance.
  Future<BackupManifest> restoreFromBytes({
    required Uint8List bytes,
    required String password,
    required Future<void> Function() onReopenDatabase,
    LocalNotificationService Function()? resolveNotifications,
  }) async {
    final archive = _decryptAndVerifyArchive(bytes, password);
    final manifestFile = archive.findFile('manifest.json')!;
    final manifest = BackupManifest.fromJson(
      jsonDecode(utf8.decode(manifestFile.content as List<int>))
          as Map<String, dynamic>,
    );

    if (manifest.schemaVersion > db.schemaVersion) {
      throw BackupException(
        'Versi database backup (${manifest.schemaVersion}) lebih baru daripada aplikasi (${db.schemaVersion}). Perbarui aplikasi terlebih dahulu.',
      );
    }

    final dbEntry = archive.findFile('database.sqlite')!;
    final dbBytes = Uint8List.fromList(dbEntry.content as List<int>);
    final attachments = <({String relativePath, Uint8List bytes})>[
      for (final file in archive.files)
        if (file.isFile && file.name.startsWith('attachments/'))
          (
            relativePath: file.name.substring('attachments/'.length),
            bytes: Uint8List.fromList(file.content as List<int>),
          ),
    ];

    await restoreDatabaseAndAttachmentsImpl(
      db: db,
      dbBytes: dbBytes,
      attachments: attachments,
      onReopenDatabase: onReopenDatabase,
    );
    final targetNotifications = resolveNotifications?.call();
    if (targetNotifications != null) {
      await targetNotifications.initialize(
        onTap: _notifications.onNotificationTap,
      );
      await targetNotifications.rescheduleAllFromDatabase();
    }
    return manifest;
  }

  Archive _decryptAndVerifyArchive(Uint8List raw, String password) {
    final zipBytes = _decryptBytes(raw, password);

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (_) {
      throw const BackupException('Password salah atau file backup rusak.');
    }

    final manifestFile = archive.findFile('manifest.json');
    final dbEntry = archive.findFile('database.sqlite');
    if (manifestFile == null || dbEntry == null) {
      throw const BackupException('Struktur file backup tidak lengkap.');
    }

    final manifest = BackupManifest.fromJson(
      jsonDecode(utf8.decode(manifestFile.content as List<int>))
          as Map<String, dynamic>,
    );
    final actualSha = sha256.convert(dbEntry.content as List<int>).toString();
    if (actualSha != manifest.dbSha256) {
      throw const BackupException('Checksum database tidak cocok. File korup.');
    }
    return archive;
  }

  Uint8List _encryptBytes(Uint8List plain, String password) {
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final ivBytes = Uint8List.fromList(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final keyBytes = _deriveKey(password, salt);
    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(plain, iv: enc.IV(ivBytes));

    final header = utf8.encode(_magicHeader);
    final builder = BytesBuilder()
      ..add(header)
      ..add(salt)
      ..add(ivBytes)
      ..add(encrypted.bytes);
    return builder.toBytes();
  }

  Uint8List _decryptBytes(Uint8List payload, String password) {
    final headerLen = _magicHeader.length;
    if (payload.length < headerLen + 33) {
      throw const BackupException('Format file backup tidak valid.');
    }
    final magic =
        utf8.decode(payload.sublist(0, headerLen), allowMalformed: true);
    if (magic != _magicHeader) {
      throw const BackupException('File ini bukan backup Lanjo yang valid.');
    }
    final salt = payload.sublist(headerLen, headerLen + 16);
    final ivBytes = payload.sublist(headerLen + 16, headerLen + 32);
    final cipher = payload.sublist(headerLen + 32);

    try {
      final keyBytes = _deriveKey(password, salt);
      final encrypter =
          enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc));
      final decrypted =
          encrypter.decryptBytes(enc.Encrypted(cipher), iv: enc.IV(ivBytes));
      return Uint8List.fromList(decrypted);
    } catch (_) {
      throw const BackupException(
        'Password backup salah atau file telah berubah.',
      );
    }
  }

  Uint8List _deriveKey(String password, Uint8List salt) {
    var digest = sha256.convert([...salt, ...utf8.encode(password)]).bytes;
    for (var i = 0; i < 10000; i++) {
      digest = sha256.convert([...digest, ...salt]).bytes;
    }
    return Uint8List.fromList(digest);
  }
}
