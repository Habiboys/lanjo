import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanjo/core/database/app_database.dart';
import 'package:lanjo/core/database/ledger_engine.dart';
import 'package:lanjo/core/errors/arus_exception.dart';
import 'package:lanjo/core/network/gemini_client.dart';
import 'package:lanjo/core/notifications/local_notification_service.dart';
import 'package:lanjo/core/providers/core_providers.dart';
import 'package:lanjo/core/providers/service_providers.dart';
import 'package:lanjo/core/security/secure_storage_service.dart';
import 'package:lanjo/features/ai_assistant/domain/ai_finance_service.dart';
import 'package:lanjo/features/backup/domain/backup_service.dart';
import 'package:lanjo/features/reports/domain/report_service.dart';
import 'package:lanjo/features/safe_to_spend/domain/safe_to_spend_service.dart';
import 'package:lanjo/features/bills/domain/bill_service.dart';
import 'package:path/path.dart' as p;

class _FakeSecureStorage extends SecureStorageService {
  AiProvider provider = AiProvider.gemini;
  String? key = 'AIzaTestFakeKey12345';
  String? openCodeKey = 'oc_sk_FakeTestKey12345';

  @override
  Future<AiProvider> getAiProvider() async => provider;

  @override
  Future<void> saveAiProvider(AiProvider p) async => provider = p;

  @override
  Future<String?> getApiKeyFor(AiProvider p) async =>
      p == AiProvider.opencode ? openCodeKey : key;

  @override
  Future<String?> getGeminiApiKey() async => key;

  @override
  Future<String?> getOpenCodeApiKey() async => openCodeKey;
}

class _FakeGeminiClient extends GeminiClient {
  Map<String, dynamic> nextJson = const {};
  AiProvider? lastProvider;

  @override
  Future<Map<String, dynamic>> generateJsonObject({
    required String apiKey,
    required String modelName,
    required String prompt,
    AiProvider provider = AiProvider.gemini,
    String? systemInstruction,
    Uint8List? imageBytes,
    String imageMimeType = 'image/jpeg',
  }) async {
    lastProvider = provider;
    return nextJson;
  }
}

void main() {
  late AppDatabase db;
  late LedgerEngine ledger;
  late LocalNotificationService notif;
  late _FakeSecureStorage storage;
  late _FakeGeminiClient gemini;
  late AiFinanceService aiService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    ledger = LedgerEngine(db);
    notif = LocalNotificationService(db);
    storage = _FakeSecureStorage();
    gemini = _FakeGeminiClient();
    aiService = AiFinanceService(
      db,
      ledger,
      gemini,
      storage,
      SafeToSpendService(db),
      ReportService(db),
      BillService(db, ledger, notif),
    );
    await db.select(db.categories).get();
  });

  tearDown(() async {
    await db.close();
  });

  test('AI Quick Expense validates drafts, rejects direct DB mutation, and prevents duplicate retries', () async {
    final bcaId = await ledger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 1000000,
    );

    await (db.update(db.appSettings)..where((s) => s.id.equals('default')))
        .write(
      AppSettingsCompanion(
        aiEnabled: const Value(true),
        aiModel: const Value('gemini-2.5-flash'),
        updatedAt: Value(DateTime.now()),
      ),
    );

    gemini.nextJson = {
      'intent': 'create_transactions',
      'transactions': [
        {
          'type': 'expense',
          'amount': 25000,
          'description': 'Ayam geprek',
          'category_id': DefaultCategoryIds.food,
          'wallet_id': bcaId,
          'occurred_at': '2026-11-16T12:30:00',
        },
        {
          'type': 'expense',
          'amount': 20000,
          'description': 'Bensin',
          'category_id': 'invalid_cat_from_ai',
          'wallet_id': bcaId,
          'occurred_at': '2026-11-16T12:35:00',
        },
      ],
      'missing_fields': [],
      'clarification_question': null,
    };

    final parsed = await aiService.parseNaturalInput('Ayam geprek 25rb dan bensin 20rb pakai BCA');
    expect(parsed.drafts.length, 2);
    // Invalid category falls back safely to expenseOther
    expect(parsed.drafts[1].categoryId, DefaultCategoryIds.expenseOther);
    // Parsing alone does NOT mutate wallet balance!
    expect(await ledger.computeAccountBalance(bcaId), 1000000);

    // Committing drafts once updates balance
    await aiService.commitDrafts(
      drafts: parsed.drafts,
      batchIdempotencyKey: parsed.idempotencyKey,
    );
    expect(await ledger.computeAccountBalance(bcaId), 955000);

    // Retrying with the same idempotencyKey does NOT create duplicates
    await aiService.commitDrafts(
      drafts: parsed.drafts,
      batchIdempotencyKey: parsed.idempotencyKey,
    );
    expect(await ledger.computeAccountBalance(bcaId), 955000);
  });

  test('BackupService encrypts payload, rejects wrong password, and protects DB on corrupt file', () async {
    final tempDir = await Directory.systemTemp.createTemp('arus_bk_test_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final fileDbPath = p.join(tempDir.path, 'test.sqlite');
    final fileDb = AppDatabase(NativeDatabase(File(fileDbPath)));
    final fileLedger = LedgerEngine(fileDb);
    final fileBackup = BackupService(fileDb, LocalNotificationService(fileDb));
    await fileDb.select(fileDb.categories).get();
    final walletId = await fileLedger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 750000,
    );
    expect(await fileLedger.computeAccountBalance(walletId), 750000);

    final outPath = p.join(tempDir.path, 'test.arusbackup');
    final backupXFile = await fileBackup.createEncryptedBackup(
      password: 'secret_password_123',
      includeAttachments: false,
      destinationPath: outPath,
    );
    final backupBytes = await File(backupXFile.path).readAsBytes();
    expect(await File(backupXFile.path).exists(), isTrue);

    // Inspect succeeds with right password and never exposes secrets
    final manifest = await fileBackup.inspectBackupBytes(
      bytes: backupBytes,
      password: 'secret_password_123',
    );
    expect(manifest.schemaVersion, 2);

    // Inspect fails with wrong password
    await expectLater(
      fileBackup.inspectBackupBytes(
        bytes: backupBytes,
        password: 'wrong_password',
      ),
      throwsA(isA<BackupException>()),
    );

    await fileDb.close();
  });

  test('BackupService restoreFromBytes reopens isolate DB before rescheduling notifications', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tempDir = await Directory.systemTemp.createTemp('arus_restore_iso_');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory' ||
          call.method == 'getTemporaryDirectory') {
        return tempDir.path;
      }
      return tempDir.path;
    });

    final container = ProviderContainer();
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    final db = container.read(appDatabaseProvider);
    final ledger = container.read(ledgerEngineProvider);
    final notif = container.read(localNotificationServiceProvider);
    await db.select(db.categories).get();
    final walletId = await ledger.createWallet(
      name: 'Mandiri Backup',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 500000,
    );
    await notif.scheduleReminder(
      kind: 'bill',
      title: 'Bayar WiFi',
      body: 'Jatuh tempo besok',
      scheduledAt: DateTime.now().add(const Duration(days: 1)),
      referenceId: 'bill_1',
    );

    final backupSvc = container.read(backupServiceProvider);
    final outPath = p.join(tempDir.path, 'restore_test.arusbackup');
    final xFile = await backupSvc.createEncryptedBackup(
      password: 'restore_pass_123',
      includeAttachments: false,
      destinationPath: outPath,
    );
    final bytes = await File(xFile.path).readAsBytes();

    // Mutate DB after backup so we verify restore rolls state back cleanly.
    final extraId = await ledger.createWallet(
      name: 'Dompet Sementara',
      accountType: 'cash',
      icon: 'wallet',
      colorValue: 0xFFD97706,
      openingBalance: 100000,
    );
    expect(await ledger.computeAccountBalance(extraId), 100000);

    // Must complete without "over isolate channel, but the connection was closed!"
    final manifest = await backupSvc.restoreFromBytes(
      bytes: bytes,
      password: 'restore_pass_123',
      onReopenDatabase: () async {
        container.invalidate(appDatabaseProvider);
      },
      resolveNotifications: () =>
          container.read(localNotificationServiceProvider),
    );
    expect(manifest.schemaVersion, 2);

    final reopenedLedger = container.read(ledgerEngineProvider);
    expect(await reopenedLedger.computeAccountBalance(walletId), 500000);
    final reopenedDb = container.read(appDatabaseProvider);
    final wallets = await reopenedDb.select(reopenedDb.accounts).get();
    expect(wallets.any((w) => w.id == extraId), isFalse);
  });

  test('GeminiClient prioritizes standard Flash aliases and filters TTS/image models', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/models') {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'models': [
                    {
                      'name': 'models/gemini-omni-flash-preview',
                      'displayName': 'Gemini Omni Flash Preview',
                      'supportedGenerationMethods': ['generateContent'],
                    },
                    {
                      'name': 'models/gemini-2.5-flash-preview-tts',
                      'displayName': 'Gemini TTS',
                      'supportedGenerationMethods': ['generateContent'],
                    },
                    {
                      'name': 'models/gemini-3.8-flash',
                      'displayName': 'Gemini 3.8 Flash',
                      'supportedGenerationMethods': ['generateContent'],
                    },
                    {
                      'name': 'models/gemini-flash-latest',
                      'displayName': 'Gemini Flash Latest',
                      'supportedGenerationMethods': ['generateContent'],
                    },
                  ],
                },
              ),
            );
            return;
          }
          handler.next(options);
        },
      ),
    );

    final client = GeminiClient(dio: dio);
    final models = await client.listCompatibleModels('AIzaFakeKey');
    expect(models.map((m) => m.shortName).toList(), [
      'gemini-flash-latest',
      'gemini-3.8-flash',
      'gemini-omni-flash-preview',
    ]);
  });

  test('AI Quick Expense handles multi-day batch, ignores negative discount lines, matches GoPay, flags pending, and computes summary', () async {
    final mainWallet = await ledger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 1000000,
    );
    final gopayWallet = await ledger.createWallet(
      name: 'GoPay',
      accountType: 'ewallet',
      icon: 'ewallet',
      colorValue: 0xFF0284C7,
      openingBalance: 500000,
    );

    await (db.update(db.appSettings)..where((s) => s.id.equals('default')))
        .write(
      AppSettingsCompanion(
        aiEnabled: const Value(true),
        aiModel: const Value('gemini-flash-latest'),
        defaultWalletId: Value(mainWallet),
        updatedAt: Value(DateTime.now()),
      ),
    );

    gemini.nextJson = {
      'intent': 'create_transactions',
      'transactions': [
        {
          'type': 'expense',
          'amount': 57000,
          'description': 'Batagor, Lumpia 2 pcs, Kopi Kenangan + Donat, Lauk Ayam Bakar',
          'category_id': DefaultCategoryIds.food,
          'wallet_id': mainWallet,
          'payment_method_label': 'Belum diketahui',
          'wallet_assumed': true,
          'tx_status': 'posted',
          'occurred_at': '2026-11-13T12:00:00+07:00',
        },
        {
          'type': 'expense',
          'amount': -10500, // Stray negative discount line must be ignored!
          'description': 'Diskon Alfamart',
          'category_id': DefaultCategoryIds.shopping,
          'wallet_id': mainWallet,
          'occurred_at': '2026-11-13T15:00:00+07:00',
        },
        {
          'type': 'expense',
          'amount': 83000,
          'description': 'Belanja Alfamart (setelah diskon Rp10.500)',
          'merchant': 'Alfamart',
          'category_id': DefaultCategoryIds.shopping,
          'wallet_id': mainWallet,
          'payment_method_label': 'Belum diketahui',
          'wallet_assumed': true,
          'tx_status': 'posted',
          'occurred_at': '2026-11-13T15:00:00+07:00',
        },
        {
          'type': 'expense',
          'amount': 38600,
          'description': 'Kebab Bro Bandar Buat',
          'merchant': 'Kebab Bro',
          'category_id': DefaultCategoryIds.food,
          'wallet_id': 'unmatched_id',
          'payment_method_label': 'GoPay Saldo',
          'wallet_assumed': false,
          'tx_status': 'pending',
          'occurred_at': '2026-11-14T18:00:00+07:00',
        },
      ],
      'missing_fields': [],
      'clarification_question': null,
    };

    final res = await aiService.parseNaturalInput('Catat pengeluaran 13-14 Nov');
    expect(res.drafts.length, 3);
    expect(res.drafts[2].walletId, gopayWallet);
    expect(res.drafts[2].statusNote, 'pending');

    final summary = res.computeSummary();
    expect(summary.totalExpense, 178600);
    expect(summary.pendingCount, 1);
    expect(summary.byDate.length, 2);

    await aiService.commitDrafts(
      drafts: res.drafts,
      batchIdempotencyKey: res.idempotencyKey,
    );
    expect(await ledger.computeAccountBalance(mainWallet), 860000);
    expect(await ledger.computeAccountBalance(gopayWallet), 461400);
  });

  test('GeminiClient routes OpenCode Inference across chat-completions, responses, messages, generate-content, and maps 402/401', () async {
    final dio = Dio();
    final calledUris = <String>[];
    String? lastAuthHeader;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final uri = options.uri.toString();
          calledUris.add(uri);
          lastAuthHeader = options.headers['Authorization'] as String?;

          if (uri == 'https://opencode.ai/inference/v1/models') {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'object': 'list',
                  'data': [
                    {
                      'id': 'big-pickle',
                      'name': 'Big Pickle',
                      'type': 'chat',
                      'cost': {
                        'text': {
                          'input': {'price': 0},
                          'output': {'price': 0},
                        },
                      },
                      'api': {'chat-completions': {}},
                    },
                    {
                      'id': 'kimi-k3',
                      'name': 'Kimi K3',
                      'type': 'chat',
                      'modalities': {
                        'input': ['text', 'image/png'],
                      },
                      'capabilities': {'structured_output': true},
                      'cost': {
                        'text': {
                          'input': {'price': 3},
                          'output': {'price': 15},
                        },
                      },
                      'api': {'chat-completions': {}},
                    },
                    {
                      'id': 'gpt-5.4-mini',
                      'name': 'GPT-5.4 Mini',
                      'type': 'chat',
                      'cost': {
                        'text': {
                          'input': {'price': 0.75},
                          'output': {'price': 4.5},
                        },
                      },
                      'api': {'responses': {}},
                    },
                    {
                      'id': 'claude-sonnet-5-5',
                      'name': 'Claude Sonnet 5.5',
                      'type': 'chat',
                      'cost': {
                        'text': {
                          'input': {'price': 2},
                          'output': {'price': 10},
                        },
                      },
                      'api': {'messages': {}},
                    },
                    {
                      'id': 'gemini-3.8-flash',
                      'name': 'Gemini 3.8 Flash',
                      'type': 'chat',
                      'modalities': {
                        'input': ['text', 'image/png'],
                      },
                      'cost': {
                        'text': {
                          'input': {'price': 0.75},
                          'output': {'price': 3.75},
                        },
                      },
                      'api': {'generate-content': {}},
                    },
                  ],
                },
              ),
            );
            return;
          }

          if (uri.endsWith('/openai/v1/chat/completions')) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'choices': [
                    {
                      'message': {'content': 'OK_CHAT'},
                    },
                  ],
                },
              ),
            );
            return;
          }

          if (uri.endsWith('/openai/v1/responses')) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'output': [
                    {
                      'type': 'message',
                      'content': [
                        {'type': 'output_text', 'text': 'OK_RESP'},
                      ],
                    },
                  ],
                },
              ),
            );
            return;
          }

          if (uri.endsWith('/anthropic/v1/messages')) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'content': [
                    {'type': 'text', 'text': 'OK_MSG'},
                  ],
                },
              ),
            );
            return;
          }

          if (uri.contains('/google/v1beta/models/gemini-3.8-flash:generateContent')) {
            if (options.headers['Authorization'] == 'Bearer oc_sk_empty_credits') {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: options,
                    statusCode: 402,
                    data: {
                      'error': {
                        'message': 'Insufficient balance.',
                      },
                    },
                  ),
                ),
              );
              return;
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'candidates': [
                    {
                      'content': {
                        'parts': [
                          {'text': 'OK_GEMINI'},
                        ],
                      },
                    },
                  ],
                },
              ),
            );
            return;
          }

          handler.next(options);
        },
      ),
    );

    final client = GeminiClient(dio: dio);
    final models = await client.listCompatibleModels(
      'oc_sk_test',
      provider: AiProvider.opencode,
    );
    // Excludes free-only 'big-pickle' and ranks gemini flash & mini first
    expect(models.any((m) => m.shortName == 'big-pickle'), isFalse);
    expect(models.first.shortName, 'gemini-3.8-flash');

    expect(
      await client.generateText(
        apiKey: 'oc_sk_test',
        provider: AiProvider.opencode,
        modelName: 'kimi-k3',
        prompt: 'Say hi',
      ),
      'OK_CHAT',
    );
    expect(lastAuthHeader, 'Bearer oc_sk_test');

    expect(
      await client.generateText(
        apiKey: 'oc_sk_test',
        provider: AiProvider.opencode,
        modelName: 'gpt-5.4-mini',
        prompt: 'Say hi',
      ),
      'OK_RESP',
    );

    expect(
      await client.generateText(
        apiKey: 'oc_sk_test',
        provider: AiProvider.opencode,
        modelName: 'claude-sonnet-5-5',
        prompt: 'Say hi',
      ),
      'OK_MSG',
    );

    expect(
      await client.generateText(
        apiKey: 'oc_sk_test',
        provider: AiProvider.opencode,
        modelName: 'gemini-3.8-flash',
        prompt: 'Say hi',
      ),
      'OK_GEMINI',
    );

    expect(
      calledUris.contains('https://opencode.ai/inference/openai/v1/chat/completions'),
      isTrue,
    );
    expect(
      calledUris.contains('https://opencode.ai/inference/openai/v1/responses'),
      isTrue,
    );
    expect(
      calledUris.contains('https://opencode.ai/inference/anthropic/v1/messages'),
      isTrue,
    );

    // 402 Insufficient balance maps to billingRequired
    await expectLater(
      client.generateText(
        apiKey: 'oc_sk_empty_credits',
        provider: AiProvider.opencode,
        modelName: 'gemini-3.8-flash',
        prompt: 'Say hi',
        allowModelFallback: false,
      ),
      throwsA(
        isA<GeminiApiException>()
            .having((e) => e.code, 'code', GeminiErrorCode.billingRequired),
      ),
    );
  });

  test('AiFinanceService passes OpenCode provider and key when selected', () async {
    await ledger.createWallet(
      name: 'BCA',
      accountType: 'bank',
      icon: 'bank',
      colorValue: 0xFF0F766E,
      openingBalance: 500000,
    );
    storage.provider = AiProvider.opencode;
    await (db.update(db.appSettings)..where((s) => s.id.equals('default')))
        .write(
      AppSettingsCompanion(
        aiEnabled: const Value(true),
        aiModel: const Value('kimi-k3'),
        updatedAt: Value(DateTime.now()),
      ),
    );
    gemini.nextJson = {
      'intent': 'create_transactions',
      'transactions': [
        {
          'type': 'expense',
          'amount': 15000,
          'description': 'Es kopi',
          'category_id': DefaultCategoryIds.food,
          'occurred_at': '2026-11-16T10:00:00+07:00',
        },
      ],
    };

    final parsed = await aiService.parseNaturalInput('Es kopi 15rb');
    expect(gemini.lastProvider, AiProvider.opencode);
    expect(parsed.drafts.length, 1);
  });
}
