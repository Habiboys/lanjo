import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../errors/arus_exception.dart';
import '../security/secure_storage_service.dart';

class GeminiModelInfo {
  const GeminiModelInfo({
    required this.name,
    required this.displayName,
    required this.description,
    required this.supportedMethods,
    this.provider = AiProvider.gemini,
    this.apiFamily = 'generate-content',
    this.isPaid = true,
    this.supportsImages = true,
    this.supportsStructuredOutput = true,
  });

  final String name; // e.g. models/gemini-2.5-flash or kimi-k3
  final String displayName;
  final String description;
  final List<String> supportedMethods;
  final AiProvider provider;
  final String apiFamily;
  final bool isPaid;
  final bool supportsImages;
  final bool supportsStructuredOutput;

  String get shortName =>
      name.startsWith('models/') ? name.substring('models/'.length) : name;

  bool get isFlash => shortName.toLowerCase().contains('flash');

  bool get supportsGenerateContent =>
      supportedMethods.contains('generateContent');

  String get pickerLabel => provider == AiProvider.opencode
      ? '$displayName ($shortName • $apiFamily)'
      : '$displayName ($shortName)';
}

/// BYOK AI REST client supporting Google Gemini (AI Studio) and OpenCode Inference (FR-16..FR-20).
/// Never logs or persists API keys outside SecureStorage.
class GeminiClient {
  GeminiClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 90),
                headers: const {'Content-Type': 'application/json'},
              ),
            );

  static const String _openCodeBase = 'https://opencode.ai/inference';

  final Dio _dio;
  final Map<String, GeminiModelInfo> _openCodeCatalog = {};

  /// Dynamically fetches compatible models for [provider] using the provided [apiKey].
  Future<List<GeminiModelInfo>> listCompatibleModels(
    String apiKey, {
    AiProvider provider = AiProvider.gemini,
  }) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      throw GeminiApiException(
        'API Key ${provider.shortLabel} belum diisi.',
        code: GeminiErrorCode.invalidKey,
      );
    }

    if (provider == AiProvider.opencode) {
      return _listOpenCodeModels();
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/models',
        queryParameters: {'key': trimmed, 'pageSize': 100},
      );
      final data = response.data;
      if (data == null || data['models'] is! List) {
        throw const GeminiApiException(
          'Respons daftar model Gemini tidak valid.',
          code: GeminiErrorCode.invalidResponse,
        );
      }

      final models = <GeminiModelInfo>[];
      for (final raw in data['models'] as List) {
        if (raw is! Map<String, dynamic>) continue;
        final name = raw['name'] as String? ?? '';
        final methods = (raw['supportedGenerationMethods'] as List? ?? const [])
            .map((e) => e.toString())
            .toList();
        if (!methods.contains('generateContent')) continue;
        final lower = name.toLowerCase();
        if (!lower.contains('gemini')) continue;
        if (_isSpecializedNonChatModel(lower)) continue;
        models.add(
          GeminiModelInfo(
            name: name,
            displayName: raw['displayName'] as String? ?? name,
            description: raw['description'] as String? ?? '',
            supportedMethods: methods,
          ),
        );
      }

      // Prioritize general-purpose Flash models (aliases first, then stable Flash)
      models.sort((a, b) {
        final rankCmp = _geminiModelRank(a.shortName)
            .compareTo(_geminiModelRank(b.shortName));
        if (rankCmp != 0) return rankCmp;
        return b.shortName.compareTo(a.shortName);
      });

      if (models.isEmpty) {
        throw const GeminiApiException(
          'Tidak ditemukan model Gemini yang kompatibel.',
          code: GeminiErrorCode.modelUnavailable,
        );
      }

      return models;
    } on DioException catch (e) {
      throw _mapDioError(e, provider: provider);
    }
  }

  Future<List<GeminiModelInfo>> _listOpenCodeModels() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_openCodeBase/v1/models',
      );
      final data = response.data;
      if (data == null || data['data'] is! List) {
        throw const GeminiApiException(
          'Respons daftar model OpenCode tidak valid.',
          code: GeminiErrorCode.invalidResponse,
        );
      }

      final paidModels = <GeminiModelInfo>[];
      final fallbackFreeModels = <GeminiModelInfo>[];
      for (final raw in data['data'] as List) {
        if (raw is! Map<String, dynamic>) continue;
        final type = raw['type'] as String? ?? 'chat';
        if (type != 'chat') continue;

        final id = (raw['id'] as String? ?? '').trim();
        if (id.isEmpty) continue;

        final apiMap = raw['api'] as Map<String, dynamic>? ?? const {};
        final family = _pickOpenCodeApiFamily(apiMap);
        if (family == null) continue;

        final costText =
            (raw['cost'] as Map<String, dynamic>?)?['text'] as Map<String, dynamic>?;
        final inPrice =
            ((costText?['input'] as Map<String, dynamic>?)?['price'] as num?)
                    ?.toDouble() ??
                0;
        final outPrice =
            ((costText?['output'] as Map<String, dynamic>?)?['price'] as num?)
                    ?.toDouble() ??
                0;
        final isPaid =
            (inPrice > 0 || outPrice > 0) && !id.toLowerCase().endsWith('-free');

        final modalities =
            raw['modalities'] as Map<String, dynamic>? ?? const {};
        final inputs = (modalities['input'] as List? ?? const [])
            .map((e) => e.toString().toLowerCase())
            .toList();
        final supportsImages = inputs.any((m) => m.startsWith('image/'));

        final capabilities =
            raw['capabilities'] as Map<String, dynamic>? ?? const {};
        final supportsStructured = capabilities['structured_output'] == true;

        final info = GeminiModelInfo(
          name: id,
          displayName: (raw['name'] as String? ?? id).trim(),
          description: raw['description'] as String? ?? '',
          supportedMethods: [family],
          provider: AiProvider.opencode,
          apiFamily: family,
          isPaid: isPaid,
          supportsImages: supportsImages,
          supportsStructuredOutput: supportsStructured,
        );

        _openCodeCatalog[id] = info;
        if (isPaid) {
          paidModels.add(info);
        } else {
          fallbackFreeModels.add(info);
        }
      }

      // Paid models work from external clients with API keys; free-tier models
      // return 403/429 outside the OpenCode client.
      final result = paidModels.isNotEmpty ? paidModels : fallbackFreeModels;
      result.sort((a, b) {
        final rankCmp = _openCodeModelRank(a.shortName)
            .compareTo(_openCodeModelRank(b.shortName));
        if (rankCmp != 0) return rankCmp;
        return a.shortName.compareTo(b.shortName);
      });

      if (result.isEmpty) {
        throw const GeminiApiException(
          'Tidak ditemukan model OpenCode yang kompatibel.',
          code: GeminiErrorCode.modelUnavailable,
        );
      }
      return result;
    } on DioException catch (e) {
      throw _mapDioError(e, provider: AiProvider.opencode);
    }
  }

  static String? _pickOpenCodeApiFamily(Map<String, dynamic> apiMap) {
    const supported = [
      'generate-content',
      'chat-completions',
      'responses',
      'messages',
    ];
    for (final key in supported) {
      if (apiMap.containsKey(key)) return key;
    }
    return null;
  }

  static String _inferOpenCodeFamily(String modelId) {
    final s = modelId.toLowerCase();
    if (s.startsWith('gemini')) return 'generate-content';
    if (s.startsWith('claude') ||
        (s.startsWith('qwen') && !s.contains('-max'))) {
      return 'messages';
    }
    if (s.startsWith('gpt-') ||
        s.startsWith('grok-') ||
        s.startsWith('muse-')) {
      return 'responses';
    }
    return 'chat-completions';
  }

  static bool _isSpecializedNonChatModel(String lowerName) {
    return lowerName.contains('-tts') ||
        lowerName.contains('-image') ||
        lowerName.contains('transcribe') ||
        lowerName.contains('computer-use') ||
        lowerName.contains('robotics') ||
        lowerName.contains('nano-banana') ||
        lowerName.contains('customtools');
  }

  static int _geminiModelRank(String shortName) {
    final s = shortName.toLowerCase();
    if (s == 'gemini-flash-latest') return 0;
    if (s == 'gemini-flash-lite-latest') return 1;
    final isPreviewOrOmni = s.contains('preview') || s.contains('omni');
    if (s.contains('flash') && !isPreviewOrOmni) return 2;
    if (s.contains('flash')) return 3;
    if (!isPreviewOrOmni) return 4;
    return 5;
  }

  static int _openCodeModelRank(String shortName) {
    final s = shortName.toLowerCase();
    if (s.contains('gemini') && s.contains('flash')) return 0;
    if (s.contains('flash') ||
        s.contains('mini') ||
        s.contains('nano') ||
        s.contains('haiku') ||
        s.contains('lite')) {
      return 1;
    }
    if (s.contains('pro') ||
        s.contains('opus') ||
        s.contains('max') ||
        s.contains('heavy')) {
      return 3;
    }
    return 2;
  }

  /// Verifies API key and finds a working compatible model (or verifies [modelName]).
  Future<({List<GeminiModelInfo> models, String workingModel})> testConnection({
    required String apiKey,
    AiProvider provider = AiProvider.gemini,
    String? modelName,
  }) async {
    final models = await listCompatibleModels(apiKey, provider: provider);
    if (modelName != null && modelName.trim().isNotEmpty) {
      await generateText(
        apiKey: apiKey,
        provider: provider,
        modelName: modelName,
        prompt: 'Balas dengan satu kata: OK',
        temperature: 0,
        allowModelFallback: false,
      );
      return (models: models, workingModel: modelName);
    }

    GeminiApiException? lastError;
    for (final candidate in models.take(6)) {
      try {
        await generateText(
          apiKey: apiKey,
          provider: provider,
          modelName: candidate.shortName,
          apiFamily: candidate.apiFamily,
          prompt: 'Balas dengan satu kata: OK',
          temperature: 0,
          allowModelFallback: false,
        );
        return (models: models, workingModel: candidate.shortName);
      } on GeminiApiException catch (e) {
        if (e.code == GeminiErrorCode.invalidKey ||
            e.code == GeminiErrorCode.billingRequired ||
            e.code == GeminiErrorCode.noInternet) {
          rethrow;
        }
        lastError = e;
      }
    }
    throw lastError ??
        GeminiApiException(
          'Tidak ada model ${provider.shortLabel} yang berhasil merespons saat pengujian.',
          code: GeminiErrorCode.modelUnavailable,
        );
  }

  /// Calls the configured AI provider endpoint and returns raw text output.
  /// When [allowModelFallback] is true and the primary model returns 503/404/429,
  /// tries up to 2 compatible fast/Flash fallback models so transient spikes
  /// do not block the user.
  Future<String> generateText({
    required String apiKey,
    required String modelName,
    required String prompt,
    AiProvider provider = AiProvider.gemini,
    String? apiFamily,
    String? systemInstruction,
    bool jsonOutput = false,
    double temperature = 0.2,
    Uint8List? imageBytes,
    String imageMimeType = 'image/jpeg',
    bool allowModelFallback = true,
  }) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      throw GeminiApiException(
        'API Key ${provider.shortLabel} belum diisi.',
        code: GeminiErrorCode.invalidKey,
      );
    }

    final cleanModel = modelName.startsWith('models/')
        ? modelName.substring('models/'.length)
        : modelName.trim();

    GeminiModelInfo? meta;
    if (provider == AiProvider.opencode) {
      meta = await _resolveOpenCodeModelMeta(trimmed, cleanModel);
    }

    try {
      return await _postWithShortRetry(
        apiKey: trimmed,
        provider: provider,
        cleanModel: cleanModel,
        apiFamily: apiFamily ?? meta?.apiFamily ?? _inferOpenCodeFamily(cleanModel),
        supportsStructuredOutput: meta?.supportsStructuredOutput ?? false,
        supportsImages: meta?.supportsImages ?? true,
        prompt: prompt,
        systemInstruction: systemInstruction,
        jsonOutput: jsonOutput,
        temperature: temperature,
        imageBytes: imageBytes,
        imageMimeType: imageMimeType,
      );
    } on GeminiApiException catch (e) {
      final retryableModelError = allowModelFallback &&
          (e.code == GeminiErrorCode.modelUnavailable ||
              e.code == GeminiErrorCode.quotaExhausted);
      if (!retryableModelError) rethrow;

      List<GeminiModelInfo> models;
      try {
        models = await listCompatibleModels(trimmed, provider: provider);
      } catch (_) {
        rethrow;
      }

      var tried = 0;
      for (final candidate in models) {
        if (candidate.shortName == cleanModel) continue;
        if (provider == AiProvider.gemini && !candidate.isFlash) continue;
        if (imageBytes != null && !candidate.supportsImages) continue;
        if (tried >= 2) break;
        tried++;
        try {
          return await _postWithShortRetry(
            apiKey: trimmed,
            provider: provider,
            cleanModel: candidate.shortName,
            apiFamily: candidate.apiFamily,
            supportsStructuredOutput: candidate.supportsStructuredOutput,
            supportsImages: candidate.supportsImages,
            prompt: prompt,
            systemInstruction: systemInstruction,
            jsonOutput: jsonOutput,
            temperature: temperature,
            imageBytes: imageBytes,
            imageMimeType: imageMimeType,
          );
        } on GeminiApiException catch (inner) {
          if (inner.code == GeminiErrorCode.invalidKey ||
              inner.code == GeminiErrorCode.billingRequired ||
              inner.code == GeminiErrorCode.noInternet) {
            rethrow;
          }
        }
      }
      rethrow;
    }
  }

  Future<GeminiModelInfo?> _resolveOpenCodeModelMeta(
    String apiKey,
    String modelId,
  ) async {
    final cached = _openCodeCatalog[modelId];
    if (cached != null) return cached;
    try {
      await listCompatibleModels(apiKey, provider: AiProvider.opencode);
      return _openCodeCatalog[modelId];
    } catch (_) {
      return null;
    }
  }

  Future<String> _postWithShortRetry({
    required String apiKey,
    required AiProvider provider,
    required String cleanModel,
    required String apiFamily,
    required bool supportsStructuredOutput,
    required bool supportsImages,
    required String prompt,
    String? systemInstruction,
    required bool jsonOutput,
    required double temperature,
    Uint8List? imageBytes,
    required String imageMimeType,
  }) async {
    if (imageBytes != null && !supportsImages) {
      throw GeminiApiException(
        'Model $cleanModel tidak mendukung input gambar/foto struk. Pilih model multimodal seperti gemini-3.8-flash atau kimi-k3.',
        code: GeminiErrorCode.modelUnavailable,
      );
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (provider == AiProvider.gemini) {
          final response = await _dio.post<Map<String, dynamic>>(
            '/models/$cleanModel:generateContent',
            queryParameters: {'key': apiKey},
            data: _buildGeminiBody(
              prompt: prompt,
              systemInstruction: systemInstruction,
              jsonOutput: jsonOutput,
              temperature: temperature,
              imageBytes: imageBytes,
              imageMimeType: imageMimeType,
            ),
          );
          return _extractGeminiText(response.data);
        }

        return await _postOpenCodeRequest(
          apiKey: apiKey,
          cleanModel: cleanModel,
          apiFamily: apiFamily,
          supportsStructuredOutput: supportsStructuredOutput,
          prompt: prompt,
          systemInstruction: systemInstruction,
          jsonOutput: jsonOutput,
          temperature: temperature,
          imageBytes: imageBytes,
          imageMimeType: imageMimeType,
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        final transient = status == 503 || status == 500;
        if (transient && attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          continue;
        }
        throw _mapDioError(e, provider: provider);
      }
    }
    throw GeminiApiException(
      'Gagal menghubungi server ${provider.shortLabel}.',
      code: GeminiErrorCode.unknown,
    );
  }

  Future<String> _postOpenCodeRequest({
    required String apiKey,
    required String cleanModel,
    required String apiFamily,
    required bool supportsStructuredOutput,
    required String prompt,
    String? systemInstruction,
    required bool jsonOutput,
    required double temperature,
    Uint8List? imageBytes,
    required String imageMimeType,
  }) async {
    final options = Options(
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
    );

    switch (apiFamily) {
      case 'generate-content':
        final response = await _dio.post<Map<String, dynamic>>(
          '$_openCodeBase/google/v1beta/models/$cleanModel:generateContent',
          options: options,
          data: _buildGeminiBody(
            prompt: prompt,
            systemInstruction: systemInstruction,
            jsonOutput: jsonOutput,
            temperature: temperature,
            imageBytes: imageBytes,
            imageMimeType: imageMimeType,
          ),
        );
        return _extractGeminiText(response.data);

      case 'responses':
        final response = await _dio.post<Map<String, dynamic>>(
          '$_openCodeBase/openai/v1/responses',
          options: options,
          data: <String, dynamic>{
            'model': cleanModel,
            if (systemInstruction != null && systemInstruction.trim().isNotEmpty)
              'instructions': systemInstruction,
            'input': imageBytes == null
                ? prompt
                : [
                    {
                      'role': 'user',
                      'content': [
                        {'type': 'input_text', 'text': prompt},
                        {
                          'type': 'input_image',
                          'image_url':
                              'data:$imageMimeType;base64,${base64Encode(imageBytes)}',
                        },
                      ],
                    },
                  ],
          },
        );
        return _extractResponsesText(response.data);

      case 'messages':
        final response = await _dio.post<Map<String, dynamic>>(
          '$_openCodeBase/anthropic/v1/messages',
          options: options,
          data: <String, dynamic>{
            'model': cleanModel,
            'max_tokens': 4096,
            'temperature': temperature,
            if (systemInstruction != null && systemInstruction.trim().isNotEmpty)
              'system': systemInstruction,
            'messages': [
              {
                'role': 'user',
                'content': imageBytes == null
                    ? prompt
                    : [
                        {
                          'type': 'image',
                          'source': {
                            'type': 'base64',
                            'media_type': imageMimeType,
                            'data': base64Encode(imageBytes),
                          },
                        },
                        {'type': 'text', 'text': prompt},
                      ],
              },
            ],
          },
        );
        return _extractAnthropicText(response.data);

      case 'chat-completions':
      default:
        final response = await _dio.post<Map<String, dynamic>>(
          '$_openCodeBase/openai/v1/chat/completions',
          options: options,
          data: <String, dynamic>{
            'model': cleanModel,
            'temperature': temperature,
            if (jsonOutput && supportsStructuredOutput)
              'response_format': const {'type': 'json_object'},
            'messages': [
              if (systemInstruction != null && systemInstruction.trim().isNotEmpty)
                {'role': 'system', 'content': systemInstruction},
              {
                'role': 'user',
                'content': imageBytes == null
                    ? prompt
                    : [
                        {'type': 'text', 'text': prompt},
                        {
                          'type': 'image_url',
                          'image_url': {
                            'url':
                                'data:$imageMimeType;base64,${base64Encode(imageBytes)}',
                          },
                        },
                      ],
              },
            ],
          },
        );
        return _extractChatCompletionsText(response.data);
    }
  }

  Map<String, dynamic> _buildGeminiBody({
    required String prompt,
    String? systemInstruction,
    required bool jsonOutput,
    required double temperature,
    Uint8List? imageBytes,
    required String imageMimeType,
  }) {
    final parts = <Map<String, dynamic>>[
      {'text': prompt},
    ];
    if (imageBytes != null) {
      parts.add({
        'inlineData': {
          'mimeType': imageMimeType,
          'data': base64Encode(imageBytes),
        },
      });
    }

    return <String, dynamic>{
      'contents': [
        {
          'role': 'user',
          'parts': parts,
        },
      ],
      'generationConfig': {
        'temperature': temperature,
        if (jsonOutput) 'responseMimeType': 'application/json',
      },
      if (systemInstruction != null && systemInstruction.trim().isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction},
          ],
        },
    };
  }

  String _extractGeminiText(Map<String, dynamic>? data) {
    final candidates = data?['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw const GeminiApiException(
        'Model AI tidak mengembalikan respons.',
        code: GeminiErrorCode.invalidResponse,
      );
    }

    final first = candidates.first as Map<String, dynamic>;
    final content = first['content'] as Map<String, dynamic>?;
    final respParts = content?['parts'] as List?;
    if (respParts == null || respParts.isEmpty) {
      throw const GeminiApiException(
        'Format respons AI tidak lengkap.',
        code: GeminiErrorCode.invalidResponse,
      );
    }

    final textBuffer = StringBuffer();
    for (final p in respParts) {
      if (p is Map<String, dynamic> && p['text'] is String) {
        textBuffer.write(p['text'] as String);
      }
    }
    return _requireNonEmptyText(textBuffer.toString());
  }

  String _extractChatCompletionsText(Map<String, dynamic>? data) {
    final choices = data?['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw const GeminiApiException(
        'OpenCode tidak mengembalikan respons.',
        code: GeminiErrorCode.invalidResponse,
      );
    }
    final first = choices.first as Map<String, dynamic>?;
    final msg = first?['message'] as Map<String, dynamic>?;
    final content = msg?['content'];
    if (content is String) {
      return _requireNonEmptyText(content);
    }
    if (content is List) {
      final buf = StringBuffer();
      for (final item in content) {
        if (item is Map<String, dynamic> && item['text'] is String) {
          buf.write(item['text'] as String);
        }
      }
      return _requireNonEmptyText(buf.toString());
    }
    throw const GeminiApiException(
      'Format respons chat completion tidak dikenali.',
      code: GeminiErrorCode.invalidResponse,
    );
  }

  String _extractResponsesText(Map<String, dynamic>? data) {
    final direct = data?['output_text'];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.trim();
    }
    final output = data?['output'] as List?;
    if (output != null) {
      final buf = StringBuffer();
      for (final item in output) {
        if (item is! Map<String, dynamic>) continue;
        final content = item['content'] as List?;
        if (content == null) continue;
        for (final part in content) {
          if (part is Map<String, dynamic> && part['text'] is String) {
            buf.write(part['text'] as String);
          }
        }
      }
      if (buf.toString().trim().isNotEmpty) {
        return buf.toString().trim();
      }
    }
    throw const GeminiApiException(
      'Respons OpenAI Responses API kosong atau tidak lengkap.',
      code: GeminiErrorCode.invalidResponse,
    );
  }

  String _extractAnthropicText(Map<String, dynamic>? data) {
    final content = data?['content'] as List?;
    if (content != null) {
      final buf = StringBuffer();
      for (final block in content) {
        if (block is Map<String, dynamic> &&
            block['type'] == 'text' &&
            block['text'] is String) {
          buf.write(block['text'] as String);
        }
      }
      if (buf.toString().trim().isNotEmpty) {
        return buf.toString().trim();
      }
    }
    throw const GeminiApiException(
      'Respons Messages API kosong atau tidak lengkap.',
      code: GeminiErrorCode.invalidResponse,
    );
  }

  String _requireNonEmptyText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const GeminiApiException(
        'Respons AI kosong.',
        code: GeminiErrorCode.invalidResponse,
      );
    }
    return trimmed;
  }

  /// Parses JSON response safely, stripping markdown fences or surrounding text if needed.
  Future<Map<String, dynamic>> generateJsonObject({
    required String apiKey,
    required String modelName,
    required String prompt,
    AiProvider provider = AiProvider.gemini,
    String? systemInstruction,
    Uint8List? imageBytes,
    String imageMimeType = 'image/jpeg',
  }) async {
    final raw = await generateText(
      apiKey: apiKey,
      provider: provider,
      modelName: modelName,
      prompt: prompt,
      systemInstruction: systemInstruction,
      jsonOutput: true,
      temperature: 0.1,
      imageBytes: imageBytes,
      imageMimeType: imageMimeType,
    );

    var cleaned = raw.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }

    final decoded = _tryDecodeJsonObject(cleaned);
    if (decoded != null) return decoded;

    // Some reasoning/chat models wrap JSON in prose; extract outermost {...}
    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      final slice = _tryDecodeJsonObject(cleaned.substring(firstBrace, lastBrace + 1));
      if (slice != null) return slice;
    }

    throw const GeminiApiException(
      'Gagal membaca format JSON dari AI.',
      code: GeminiErrorCode.invalidResponse,
    );
  }

  Map<String, dynamic>? _tryDecodeJsonObject(String input) {
    try {
      final decoded = jsonDecode(input);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      return null;
    }
    return null;
  }

  GeminiApiException _mapDioError(
    DioException e, {
    required AiProvider provider,
  }) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return GeminiApiException(
        'Koneksi ke ${provider.shortLabel} timeout. Coba lagi atau catat manual.',
        code: GeminiErrorCode.timeout,
      );
    }

    if (e.type == DioExceptionType.connectionError ||
        (e.error?.toString().contains('SocketException') ?? false)) {
      if (kIsWeb && provider == AiProvider.opencode) {
        return const GeminiApiException(
          'Endpoint OpenCode Inference diblokir CORS saat dijalankan di browser Web. Gunakan di APK Android atau pilih provider Google Gemini di Web.',
          code: GeminiErrorCode.noInternet,
        );
      }
      return const GeminiApiException(
        'Tidak ada koneksi internet. Fitur pencatatan manual tetap tersedia.',
        code: GeminiErrorCode.noInternet,
      );
    }

    final status = e.response?.statusCode;
    final msg = _extractErrorMessage(e.response?.data);
    final lower = msg.toLowerCase();

    if (status == 401 ||
        (status == 400 &&
            (lower.contains('api key') ||
                lower.contains('credential') ||
                lower.contains('invalid')))) {
      return GeminiApiException(
        'API Key ${provider.shortLabel} tidak valid.',
        code: GeminiErrorCode.invalidKey,
      );
    }
    if (status == 402 || lower.contains('insufficient balance')) {
      return const GeminiApiException(
        'Saldo / kredit OpenCode Models tidak mencukupi (402). Top up kredit di console OpenCode (paket Go hanya untuk coding agent internal) atau gunakan Google Gemini.',
        code: GeminiErrorCode.billingRequired,
      );
    }
    if (status == 403) {
      if (lower.contains('billing')) {
        return const GeminiApiException(
          'Billing API belum aktif untuk akun ini.',
          code: GeminiErrorCode.billingRequired,
        );
      }
      return GeminiApiException(
        provider == AiProvider.opencode
            ? 'Model ini tidak diizinkan dari klien eksternal (403). Gunakan model berbayar OpenCode dengan saldo kredit.'
            : 'API Key tidak memiliki izin untuk model ini.',
        code: GeminiErrorCode.permissionDenied,
      );
    }
    if (status == 404) {
      return GeminiApiException(
        'Model ${provider.shortLabel} yang dipilih tidak tersedia (404). Pilih model lain.',
        code: GeminiErrorCode.modelUnavailable,
      );
    }
    if (status == 429) {
      if (lower.contains('free usage limit') || lower.contains('freeusagelimit')) {
        return const GeminiApiException(
          'Batas model gratis OpenCode tercapai (429). Pilih model berbayar OpenCode dengan kredit aktif atau gunakan Google Gemini.',
          code: GeminiErrorCode.quotaExhausted,
        );
      }
      if (lower.contains('quota')) {
        return GeminiApiException(
          'Kuota model ini habis atau tidak tersedia di tier gratis (429). Coba ganti model lain.',
          code: GeminiErrorCode.quotaExhausted,
        );
      }
      return const GeminiApiException(
        'Terlalu banyak permintaan (rate limit). Tunggu sebentar.',
        code: GeminiErrorCode.rateLimited,
      );
    }
    if (status == 503 || status == 500) {
      return GeminiApiException(
        'Server model ${provider.shortLabel} sedang sibuk / tidak tersedia sementara (503). Coba pilih model lain.',
        code: GeminiErrorCode.modelUnavailable,
      );
    }

    return GeminiApiException(
      msg.isEmpty ? 'Terjadi kesalahan saat menghubungi ${provider.shortLabel}.' : msg,
      code: GeminiErrorCode.unknown,
    );
  }

  String _extractErrorMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final err = data['error'];
      if (err is Map<String, dynamic> && err['message'] is String) {
        return err['message'] as String;
      }
      if (data['message'] is String) {
        return data['message'] as String;
      }
    }
    return '';
  }
}
