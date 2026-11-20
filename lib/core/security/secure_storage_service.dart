import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Supported BYOK AI providers for Lanjo.
enum AiProvider {
  gemini,
  opencode;

  String get storageValue => name;

  String get shortLabel => switch (this) {
        AiProvider.gemini => 'Gemini',
        AiProvider.opencode => 'OpenCode',
      };

  String get label => switch (this) {
        AiProvider.gemini => 'Google Gemini (AI Studio)',
        AiProvider.opencode => 'OpenCode Inference',
      };

  static AiProvider fromString(String? value) {
    return value == 'opencode' ? AiProvider.opencode : AiProvider.gemini;
  }
}

/// Stores sensitive secrets (API keys, salted PIN hash) outside SQLite and backups.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _kAiProvider = 'arus_ai_provider';
  static const _kGeminiApiKey = 'arus_gemini_api_key';
  static const _kOpenCodeApiKey = 'arus_opencode_api_key';
  static const _kGeminiModel = 'arus_gemini_model';
  static const _kOpenCodeModel = 'arus_opencode_model';
  static const _kPinHash = 'arus_pin_hash';
  static const _kPinSalt = 'arus_pin_salt';
  static const _kRecoveryPhraseHash = 'arus_recovery_hash';
  static const _kThemeAccent = 'arus_theme_accent';

  Future<String?> getThemeAccentRaw() async {
    try {
      return await _storage.read(key: _kThemeAccent);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveThemeAccentRaw(String value) async {
    try {
      await _storage.write(key: _kThemeAccent, value: value);
    } catch (_) {
      // Ignore on unsupported test environments without secure storage plugin.
    }
  }

  Future<void> saveAiProvider(AiProvider provider) =>
      _storage.write(key: _kAiProvider, value: provider.storageValue);

  Future<AiProvider> getAiProvider() async =>
      AiProvider.fromString(await _storage.read(key: _kAiProvider));

  Future<void> saveGeminiApiKey(String key) =>
      saveApiKeyFor(AiProvider.gemini, key);

  Future<String?> getGeminiApiKey() => getApiKeyFor(AiProvider.gemini);

  Future<void> deleteGeminiApiKey() => deleteApiKeyFor(AiProvider.gemini);

  Future<void> saveOpenCodeApiKey(String key) =>
      saveApiKeyFor(AiProvider.opencode, key);

  Future<String?> getOpenCodeApiKey() => getApiKeyFor(AiProvider.opencode);

  Future<void> deleteOpenCodeApiKey() => deleteApiKeyFor(AiProvider.opencode);

  String _keySlotFor(AiProvider provider) => switch (provider) {
        AiProvider.gemini => _kGeminiApiKey,
        AiProvider.opencode => _kOpenCodeApiKey,
      };

  String _modelSlotFor(AiProvider provider) => switch (provider) {
        AiProvider.gemini => _kGeminiModel,
        AiProvider.opencode => _kOpenCodeModel,
      };

  Future<void> saveApiKeyFor(AiProvider provider, String key) async {
    final slot = _keySlotFor(provider);
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: slot);
      return;
    }
    await _storage.write(key: slot, value: trimmed);
  }

  Future<String?> getApiKeyFor(AiProvider provider) =>
      _storage.read(key: _keySlotFor(provider));

  Future<void> deleteApiKeyFor(AiProvider provider) =>
      _storage.delete(key: _keySlotFor(provider));

  Future<void> saveModelFor(AiProvider provider, String? modelName) async {
    final slot = _modelSlotFor(provider);
    final trimmed = modelName?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _storage.delete(key: slot);
      return;
    }
    await _storage.write(key: slot, value: trimmed);
  }

  Future<String?> getModelFor(AiProvider provider) =>
      _storage.read(key: _modelSlotFor(provider));

  static String maskApiKey(String? key) {
    if (key == null || key.isEmpty) return 'Belum diatur';
    if (key.length <= 8) return '••••••••';
    return '${key.substring(0, 4)}••••••••${key.substring(key.length - 4)}';
  }

  Future<void> savePin(String pin) async {
    final saltBytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final salt = base64Encode(saltBytes);
    final hash = _hashWithSalt(pin, salt);
    await _storage.write(key: _kPinSalt, value: salt);
    await _storage.write(key: _kPinHash, value: hash);
  }

  Future<bool> hasPin() async {
    final hash = await _storage.read(key: _kPinHash);
    return hash != null && hash.isNotEmpty;
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _kPinSalt);
    final storedHash = await _storage.read(key: _kPinHash);
    if (salt == null || storedHash == null) return false;
    return _hashWithSalt(pin, salt) == storedHash;
  }

  Future<void> clearPin() async {
    await _storage.delete(key: _kPinSalt);
    await _storage.delete(key: _kPinHash);
  }

  Future<void> saveRecoveryCode(String code) async {
    final normalized = code.trim().toLowerCase();
    final hash = sha256.convert(utf8.encode('arus_recovery:$normalized')).toString();
    await _storage.write(key: _kRecoveryPhraseHash, value: hash);
  }

  Future<bool> verifyRecoveryCode(String code) async {
    final stored = await _storage.read(key: _kRecoveryPhraseHash);
    if (stored == null) return false;
    final normalized = code.trim().toLowerCase();
    final hash = sha256.convert(utf8.encode('arus_recovery:$normalized')).toString();
    return hash == stored;
  }

  String _hashWithSalt(String value, String salt) {
    final bytes = utf8.encode('$salt:$value');
    return sha256.convert(bytes).toString();
  }
}
