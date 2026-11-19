import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/ledger_engine.dart';
import '../native/native_bridge_service.dart';
import '../network/gemini_client.dart';
import '../notifications/fcm_service.dart';
import '../notifications/local_notification_service.dart';
import '../security/app_lock_service.dart';
import '../security/secure_storage_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final ledgerEngineProvider = Provider<LedgerEngine>((ref) {
  return LedgerEngine(ref.watch(appDatabaseProvider));
});

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService(ref.watch(secureStorageProvider));
});

final geminiClientProvider = Provider<GeminiClient>((ref) {
  return GeminiClient();
});

final aiProviderTypeProvider = FutureProvider<AiProvider>((ref) async {
  return ref.watch(secureStorageProvider).getAiProvider();
});

final localNotificationServiceProvider = Provider<LocalNotificationService>((ref) {
  return LocalNotificationService(ref.watch(appDatabaseProvider));
});

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService(ref.watch(localNotificationServiceProvider));
});

final appSettingsProvider = StreamProvider<AppSettingRecord>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.appSettings)..where((s) => s.id.equals('default')))
      .watchSingle();
});

final walletsProvider = StreamProvider<List<AccountRecord>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.accounts)
        ..where((a) => a.isSystem.equals(false))
        ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
      .watch();
});

final activeWalletsProvider = Provider<List<AccountRecord>>((ref) {
  final wallets = ref.watch(walletsProvider).valueOrNull ?? const [];
  return wallets.where((w) => !w.isArchived).toList();
});

final categoriesProvider = StreamProvider<List<CategoryRecord>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.categories)
        ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
      .watch();
});

final transactionsStreamProvider = StreamProvider<List<TransactionRecord>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.transactions)
        ..where((t) => t.status.equals('posted'))
        ..orderBy([
          (t) => OrderingTerm.desc(t.occurredAt),
          (t) => OrderingTerm.desc(t.createdAt),
        ]))
      .watch();
});

final templatesStreamProvider =
    StreamProvider<List<TransactionTemplateRecord>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.transactionTemplates)
        ..orderBy([
          (t) => OrderingTerm.desc(t.isPinned),
          (t) => OrderingTerm.desc(t.useCount),
        ]))
      .watch();
});

final sessionUnlockedProvider = StateProvider<bool>((ref) => false);

final nativeBridgeServiceProvider = Provider<NativeBridgeService>((ref) {
  return NativeBridgeService();
});

final smartInboxRevisionProvider = StateProvider<int>((ref) => 0);

final smartInboxProvider = FutureProvider<List<SmartInboxItem>>((ref) async {
  ref.watch(smartInboxRevisionProvider);
  return ref.watch(nativeBridgeServiceProvider).getSmartInboxItems();
});

final tagsStreamProvider = StreamProvider<List<TagRecord>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tags)..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();
});

final transactionTagsMapProvider =
    StreamProvider<Map<String, List<String>>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final query = db.select(db.transactionTags).join([
    innerJoin(db.tags, db.tags.id.equalsExp(db.transactionTags.tagId)),
  ]);
  return query.watch().map((rows) {
    final map = <String, List<String>>{};
    for (final row in rows) {
      final txTag = row.readTable(db.transactionTags);
      final tag = row.readTable(db.tags);
      map.putIfAbsent(txTag.transactionId, () => <String>[]).add(tag.name);
    }
    return map;
  });
});

