import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/network/gemini_client.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/security/secure_storage_service.dart';

/// BYOK AI configuration page supporting Google Gemini & OpenCode Inference (FR-16, PRD 15.3 & 15.4).
class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final _keyCtrl = TextEditingController();
  AiProvider _provider = AiProvider.gemini;
  String? _maskedStoredKey;
  List<GeminiModelInfo> _models = const [];
  bool _testing = false;
  String? _connectionStatus;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    final storage = ref.read(secureStorageProvider);
    final provider = await storage.getAiProvider();
    final stored = await storage.getApiKeyFor(provider);
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _maskedStoredKey = SecureStorageService.maskApiKey(stored);
    });
  }

  Future<void> _switchProvider(AiProvider next) async {
    if (next == _provider) return;
    final storage = ref.read(secureStorageProvider);
    final db = ref.read(appDatabaseProvider);

    setState(() {
      _provider = next;
      _keyCtrl.clear();
      _models = const [];
      _connectionStatus = null;
      _maskedStoredKey = 'Memuat...';
    });

    await storage.saveAiProvider(next);
    final storedKey = await storage.getApiKeyFor(next);
    final savedModel = await storage.getModelFor(next);

    await (db.update(db.appSettings)..where((s) => s.id.equals('default')))
        .write(
      AppSettingsCompanion(
        aiModel: Value(savedModel),
        updatedAt: Value(DateTime.now()),
      ),
    );
    ref.invalidate(aiProviderTypeProvider);

    if (!mounted) return;
    setState(() {
      _maskedStoredKey = SecureStorageService.maskApiKey(storedKey);
    });
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final storage = ref.read(secureStorageProvider);
    final db = ref.read(appDatabaseProvider);
    final client = ref.read(geminiClientProvider);
    final activeProvider = _provider;

    var keyToUse = _keyCtrl.text.trim();
    if (keyToUse.isNotEmpty) {
      await storage.saveApiKeyFor(activeProvider, keyToUse);
      _keyCtrl.clear();
    } else {
      keyToUse = (await storage.getApiKeyFor(activeProvider)) ?? '';
    }

    if (keyToUse.isEmpty) {
      setState(
        () => _connectionStatus =
            'Masukkan API Key ${activeProvider.shortLabel} terlebih dahulu.',
      );
      return;
    }

    setState(() {
      _testing = true;
      _connectionStatus =
          'Menguji koneksi ${activeProvider.shortLabel} & mengambil daftar model...';
    });

    try {
      await storage.saveAiProvider(activeProvider);
      ref.invalidate(aiProviderTypeProvider);

      final models = await client.listCompatibleModels(
        keyToUse,
        provider: activeProvider,
      );
      if (mounted) {
        setState(() => _models = models);
      }

      final currentModel = ref.read(appSettingsProvider).valueOrNull?.aiModel;
      final preferredModel = (currentModel != null &&
              models.any((m) => m.shortName == currentModel))
          ? currentModel
          : null;

      final result = await client.testConnection(
        apiKey: keyToUse,
        provider: activeProvider,
        modelName: preferredModel,
      );

      await storage.saveModelFor(activeProvider, result.workingModel);
      await (db.update(db.appSettings)..where((s) => s.id.equals('default')))
          .write(
        AppSettingsCompanion(
          aiEnabled: const Value(true),
          aiModel: Value(result.workingModel),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _loadKeyMaskOnly();
      if (mounted) {
        setState(() {
          _models = result.models;
          _connectionStatus =
              'Terhubung ✅ (${result.workingModel} aktif, ${result.models.length} model ${activeProvider.shortLabel} tersedia)';
        });
      }
    } catch (e) {
      await _loadKeyMaskOnly();
      if (mounted) {
        setState(() => _connectionStatus = 'Gagal: $e');
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _loadKeyMaskOnly() async {
    final stored =
        await ref.read(secureStorageProvider).getApiKeyFor(_provider);
    if (!mounted) return;
    setState(() {
      _maskedStoredKey = SecureStorageService.maskApiKey(stored);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final db = ref.watch(appDatabaseProvider);
    final storage = ref.read(secureStorageProvider);
    final isOpenCode = _provider == AiProvider.opencode;

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Asisten AI')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                Card(
                  child: SwitchListTile(
                    title: const Text('Aktifkan Fitur AI (Opsional)'),
                    subtitle: const Text(
                      'Lanjo tetap berfungsi 100% tanpa AI.',
                    ),
                    value: settings.aiEnabled,
                    onChanged: (v) async {
                      await (db.update(db.appSettings)
                            ..where((s) => s.id.equals('default')))
                          .write(
                        AppSettingsCompanion(
                          aiEnabled: Value(v),
                          updatedAt: Value(DateTime.now()),
                        ),
                      );
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
                          'Pilih Penyedia AI (BYOK)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<AiProvider>(
                            segments: const [
                              ButtonSegment(
                                value: AiProvider.gemini,
                                label: Text(
                                  'Google Gemini',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ButtonSegment(
                                value: AiProvider.opencode,
                                label: Text(
                                  'OpenCode',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            selected: {_provider},
                            onSelectionChanged: _testing
                                ? null
                                : (sel) => _switchProvider(sel.first),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isOpenCode
                              ? 'OpenCode Inference API (opencode.ai/inference)'
                              : 'Google AI Studio (Gemini API)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isOpenCode
                              ? 'Mendukung endpoint OpenAI Chat Completions, OpenAI Responses, Anthropic Messages, dan Gemini melalui API Key Console OpenCode (oc_sk_...). Membutuhkan saldo kredit OpenCode Models untuk klien eksternal (model -free hanya untuk klien OpenCode internal).${kIsWeb ? ' Catatan Web: browser dapat membatasi request POST OpenCode via CORS; gunakan APK Android atau Google Gemini untuk preview Web.' : ''}'
                              : 'Key tersimpan aman di Secure Storage perangkat (tidak masuk SQLite, log, atau backup). Penggunaan API Key pribadi tunduk pada kuota dan biaya Google AI Studio milikmu.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Key ${_provider.shortLabel} tersimpan: ${_maskedStoredKey ?? '-'}',
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _keyCtrl,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: isOpenCode
                                ? 'Tempel OpenCode API Key baru'
                                : 'Tempel Gemini API Key baru',
                            hintText: isOpenCode ? 'oc_sk_...' : 'AIza...',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _testing ? null : _saveAndTest,
                                icon: const Icon(LucideIcons.radio, size: 17),
                                label: Text(
                                  _testing
                                      ? 'Menguji...'
                                      : 'Simpan & Test Koneksi',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _testing
                                  ? null
                                  : () async {
                                      await storage.deleteApiKeyFor(_provider);
                                      await storage.saveModelFor(
                                        _provider,
                                        null,
                                      );
                                      await (db.update(db.appSettings)
                                            ..where(
                                                (s) => s.id.equals('default')))
                                          .write(
                                        AppSettingsCompanion(
                                          aiEnabled: const Value(false),
                                          aiModel: const Value(null),
                                          updatedAt: Value(DateTime.now()),
                                        ),
                                      );
                                      await _loadKeyMaskOnly();
                                      if (!mounted) return;
                                      setState(() {
                                        _models = const [];
                                        _connectionStatus =
                                            'API Key ${_provider.shortLabel} dihapus.';
                                      });
                                    },
                              child: const Text('Hapus Key'),
                            ),
                          ],
                        ),
                        if (_connectionStatus != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _connectionStatus!,
                            style: TextStyle(
                              color: _connectionStatus!.contains('Gagal')
                                  ? ArusColors.expense
                                  : ArusColors.income,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_models.isNotEmpty || settings.aiModel != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(
                          '${_provider.name}_${settings.aiModel}_${_models.length}',
                        ),
                        isExpanded: true,
                        initialValue: _models.any(
                                (m) => m.shortName == settings.aiModel)
                            ? settings.aiModel
                            : (_models.isNotEmpty
                                ? _models.first.shortName
                                : settings.aiModel),
                        decoration: InputDecoration(
                          labelText: isOpenCode
                              ? 'Model OpenCode (OpenAI / Claude / Gemini)'
                              : 'Model Gemini (prioritas Flash)',
                        ),
                        items: [
                          if (_models.isEmpty && settings.aiModel != null)
                            DropdownMenuItem(
                              value: settings.aiModel,
                              child: Text(
                                settings.aiModel!,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          for (final m in _models)
                            DropdownMenuItem(
                              value: m.shortName,
                              child: Text(
                                m.pickerLabel,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          await storage.saveModelFor(_provider, v);
                          await (db.update(db.appSettings)
                                ..where((s) => s.id.equals('default')))
                              .write(
                            AppSettingsCompanion(
                              aiModel: Value(v),
                              updatedAt: Value(DateTime.now()),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Izinkan konteks ringkasan keuangan'),
                        subtitle: const Text(
                          'Mengirim angka agregat terhitung ke AI aktif untuk tanya-jawab asisten.',
                        ),
                        value: settings.aiIncludeContext,
                        onChanged: (v) async {
                          await (db.update(db.appSettings)
                                ..where((s) => s.id.equals('default')))
                              .write(
                            AppSettingsCompanion(
                              aiIncludeContext: Value(v),
                              updatedAt: Value(DateTime.now()),
                            ),
                          );
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Simpan histori chat lokal'),
                        value: settings.aiSaveHistory,
                        onChanged: (v) async {
                          await (db.update(db.appSettings)
                                ..where((s) => s.id.equals('default')))
                              .write(
                            AppSettingsCompanion(
                              aiSaveHistory: Value(v),
                              updatedAt: Value(DateTime.now()),
                            ),
                          );
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Izinkan kirim foto struk ke AI'),
                        subtitle: const Text(
                          'Hanya dikirim setelah kamu menekan setuju pada preview struk.',
                        ),
                        value: settings.aiAllowImages,
                        onChanged: (v) async {
                          await (db.update(db.appSettings)
                                ..where((s) => s.id.equals('default')))
                              .write(
                            AppSettingsCompanion(
                              aiAllowImages: Value(v),
                              updatedAt: Value(DateTime.now()),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
