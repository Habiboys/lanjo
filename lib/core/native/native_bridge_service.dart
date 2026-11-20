import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../features/safe_to_spend/domain/safe_to_spend_service.dart';
import '../money/money_formatter.dart';

/// Item detected automatically from Android banking / e-wallet notifications
/// or simulated locally.
class SmartInboxItem {
  const SmartInboxItem({
    required this.id,
    required this.sourceApp,
    required this.packageName,
    required this.title,
    required this.body,
    required this.amount,
    required this.type,
    required this.detectedAtMs,
  });

  final String id;
  final String sourceApp;
  final String packageName;
  final String title;
  final String body;
  final int amount;
  final String type; // 'expense' | 'income'
  final int detectedAtMs;

  DateTime get detectedAt =>
      DateTime.fromMillisecondsSinceEpoch(detectedAtMs);

  factory SmartInboxItem.fromJson(Map<String, dynamic> json) {
    return SmartInboxItem(
      id: (json['id'] ?? const Uuid().v4()).toString(),
      sourceApp: (json['sourceApp'] ?? 'Notifikasi Bank').toString(),
      packageName: (json['packageName'] ?? '').toString(),
      title: (json['title'] ?? 'Transaksi Terdeteksi').toString(),
      body: (json['body'] ?? '').toString(),
      amount: (json['amount'] is num)
          ? (json['amount'] as num).toInt()
          : (int.tryParse(json['amount']?.toString() ?? '0') ?? 0),
      type: (json['type'] ?? 'expense').toString(),
      detectedAtMs: (json['detectedAtMs'] is num)
          ? (json['detectedAtMs'] as num).toInt()
          : DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceApp': sourceApp,
        'packageName': packageName,
        'title': title,
        'body': body,
        'amount': amount,
        'type': type,
        'detectedAtMs': detectedAtMs,
      };
}

/// Bridge connecting Flutter with Android native features:
/// - Home Screen Widget (`LanjoWidgetProvider`)
/// - Launcher App Shortcuts & Quick Settings Tile (`LanjoQuickTileService`)
/// - Share Target (`ACTION_SEND` image/text & `ACTION_PROCESS_TEXT`)
/// - Smart Notification Auto-Detector (`LanjoNotificationListener`)
class NativeBridgeService {
  NativeBridgeService({this.useNativeChannel = true});

  final bool useNativeChannel;

  static const MethodChannel _channel =
      MethodChannel('com.habiboys.lanjo/native');

  final List<SmartInboxItem> _fallbackQueue = [];
  bool _fallbackAutoDetectEnabled = true;
  String? _lastClipboardScanned;

  bool get _isAndroidNative =>
      useNativeChannel &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  /// Returns runtime permission states: notifications, camera, microphone.
  Future<Map<String, bool>> getPermissionStatuses() async {
    if (!_isAndroidNative) {
      return const {
        'notifications': true,
        'camera': true,
        'microphone': true,
      };
    }
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('getPermissionStatuses');
      if (raw == null) return const {};
      return {
        'notifications': raw['notifications'] == true,
        'camera': raw['camera'] == true,
        'microphone': raw['microphone'] == true,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Requests Android runtime permission(s) cleanly (`notifications`, `camera`,
  /// `microphone`, or `all`). Returns true if granted.
  Future<bool> requestPermission(String key) async {
    if (!_isAndroidNative) return true;
    try {
      return await _channel.invokeMethod<bool>(
            'requestPermission',
            {'key': key},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAppSettings() async {
    if (!_isAndroidNative) return;
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } catch (_) {}
  }

  Future<void> initialize({
    required void Function(String route) onNavigateRoute,
    required void Function(String sharedText) onSharedText,
    required void Function(String imagePath) onSharedImage,
    required VoidCallback onSmartInboxChanged,
  }) async {
    if (!_isAndroidNative) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNativeAction') {
        final map = (call.arguments as Map?)?.cast<String, dynamic>();
        if (map != null) {
          _dispatchAction(
            map,
            onNavigateRoute: onNavigateRoute,
            onSharedText: onSharedText,
            onSharedImage: onSharedImage,
          );
        }
      } else if (call.method == 'onSmartInboxUpdated') {
        onSmartInboxChanged();
      }
    });

    try {
      final initial = await _channel
          .invokeMapMethod<String, dynamic>('getInitialNativeAction');
      if (initial != null) {
        _dispatchAction(
          initial,
          onNavigateRoute: onNavigateRoute,
          onSharedText: onSharedText,
          onSharedImage: onSharedImage,
        );
      }
    } catch (_) {
      // Ignore on unsupported environments or tests.
    }
  }

  void _dispatchAction(
    Map<String, dynamic> action, {
    required void Function(String route) onNavigateRoute,
    required void Function(String sharedText) onSharedText,
    required void Function(String imagePath) onSharedImage,
  }) {
    final kind = action['kind']?.toString();
    if (kind == 'route') {
      final route = action['route']?.toString();
      if (route != null && route.isNotEmpty) {
        onNavigateRoute(route);
      }
    } else if (kind == 'shared_text') {
      final text = action['text']?.toString();
      if (text != null && text.isNotEmpty) {
        onSharedText(text);
      }
    } else if (kind == 'shared_image') {
      final path = action['path']?.toString();
      if (path != null && path.isNotEmpty) {
        onSharedImage(path);
      }
    }
  }

  /// Pushes the latest Safe-to-Spend & daily spending summary to the Android Home Screen Widget.
  Future<void> syncHomeWidget({
    required SafeToSpendBreakdown sts,
    required int todayExpense,
    required bool privacyMode,
  }) async {
    if (!_isAndroidNative) return;
    try {
      final title = sts.isShortfall
          ? 'KOMITMEN MELEBIHI KAS'
          : 'AMAN DIBELANJAKAN / HARI';
      final safeText =
          MoneyFormatter.format(sts.dailySafeSpend, hidden: privacyMode);
      final todayText =
          MoneyFormatter.formatCompact(todayExpense, hidden: privacyMode);
      final cashText = MoneyFormatter.formatCompact(
        sts.spendableLiquidBalance,
        hidden: privacyMode,
      );
      final subtitle = 'Hari ini: $todayText • Kas: $cashText';
      final badge = '${sts.remainingDays} hari lagi';

      await _channel.invokeMethod<void>('updateWidget', {
        'title': title,
        'safeToSpend': safeText,
        'subtitle': subtitle,
        'badge': badge,
      });
    } catch (_) {
      // Ignore if widget provider is unavailable.
    }
  }

  Future<List<SmartInboxItem>> getSmartInboxItems() async {
    if (!_isAndroidNative) {
      return List.unmodifiable(_fallbackQueue);
    }
    try {
      final raw =
          await _channel.invokeMethod<String>('getSmartInboxItems') ?? '[]';
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => SmartInboxItem.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.amount > 0)
          .toList();
    } catch (_) {
      return List.unmodifiable(_fallbackQueue);
    }
  }

  Future<void> removeSmartInboxItem(String id) async {
    _fallbackQueue.removeWhere((e) => e.id == id);
    if (!_isAndroidNative) return;
    try {
      await _channel.invokeMethod<void>('removeSmartInboxItem', {'id': id});
    } catch (_) {}
  }

  Future<void> clearSmartInbox() async {
    _fallbackQueue.clear();
    if (!_isAndroidNative) return;
    try {
      await _channel.invokeMethod<void>('clearSmartInbox');
    } catch (_) {}
  }

  Future<bool> isNotificationListenerEnabled() async {
    if (!_isAndroidNative) return true;
    try {
      return await _channel
              .invokeMethod<bool>('isNotificationListenerEnabled') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openNotificationListenerSettings() async {
    if (!_isAndroidNative) return;
    try {
      await _channel.invokeMethod<void>('openNotificationListenerSettings');
    } catch (_) {}
  }

  Future<bool> getAutoDetectEnabled() async {
    if (!_isAndroidNative) return _fallbackAutoDetectEnabled;
    try {
      return await _channel.invokeMethod<bool>('getAutoDetectEnabled') ?? true;
    } catch (_) {
      return _fallbackAutoDetectEnabled;
    }
  }

  Future<void> setAutoDetectEnabled(bool enabled) async {
    _fallbackAutoDetectEnabled = enabled;
    if (!_isAndroidNative) return;
    try {
      await _channel
          .invokeMethod<void>('setAutoDetectEnabled', {'enabled': enabled});
    } catch (_) {}
  }

  Future<SmartInboxItem?> enqueueFinancialText({
    required String body,
    String title = 'Deteksi Transaksi',
    String app = '',
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;

    if (_isAndroidNative) {
      try {
        final raw = await _channel.invokeMethod<String>(
          'enqueueSmartText',
          {'app': app, 'title': title, 'body': trimmed},
        );
        if (raw != null && raw.isNotEmpty) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          return SmartInboxItem.fromJson(map);
        }
      } catch (_) {}
    }

    final parsed = parseFinancialNotificationLocal(
      packageName: app,
      title: title,
      body: trimmed,
    );
    if (parsed != null) {
      _fallbackQueue.insert(0, parsed);
    }
    return parsed;
  }

  /// Checks clipboard text once per unique payload for banking / e-wallet mutation text.
  Future<SmartInboxItem?> scanClipboardForBankTransaction({
    bool force = false,
  }) async {
    final enabled = await getAutoDetectEnabled();
    if (!enabled && !force) return null;

    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clip?.text?.trim() ?? '';
      if (text.isEmpty || text.length > 800) return null;
      if (!force && text == _lastClipboardScanned) return null;

      final lower = text.toLowerCase();
      const cues = [
        'bca',
        'mandiri',
        'livin',
        'bri',
        'brimo',
        'bni',
        'wondr',
        'jago',
        'seabank',
        'blu',
        'gopay',
        'ovo',
        'dana',
        'shopeepay',
        'qris',
        'transfer',
        'pembayaran',
        'berhasil',
        'diterima',
        'uang masuk',
        'debit',
      ];
      if (!cues.any(lower.contains)) return null;

      _lastClipboardScanned = text;
      return await enqueueFinancialText(
        title: 'Terdeteksi dari Clipboard',
        body: text,
      );
    } catch (_) {
      return null;
    }
  }

  /// Simulates an incoming bank / e-wallet notification so users can test
  /// Smart Auto-Detect immediately on Android, Web, or tests.
  Future<SmartInboxItem?> simulateBankNotification({
    String app = 'com.gojek.app',
    String title = 'Pembayaran QRIS Berhasil',
    String body =
        'Kamu berhasil membayar Rp28.500 di Kopi Kenangan menggunakan GoPay.',
  }) async {
    if (_isAndroidNative) {
      try {
        final raw = await _channel.invokeMethod<String>(
          'simulateBankNotification',
          {'app': app, 'title': title, 'body': body},
        );
        if (raw != null && raw.isNotEmpty) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          return SmartInboxItem.fromJson(map);
        }
      } catch (_) {}
    }

    // Offline deterministic Dart fallback parser (used on Web & tests)
    final parsed = parseFinancialNotificationLocal(
      packageName: app,
      title: title,
      body: body,
    );
    if (parsed != null) {
      _fallbackQueue.insert(0, parsed);
    }
    return parsed;
  }

  /// Pure-Dart offline financial notification parser mirroring Kotlin's LanjoNotificationListener.
  static SmartInboxItem? parseFinancialNotificationLocal({
    required String packageName,
    required String title,
    required String body,
  }) {
    final combined = '$title $body'.trim();
    final regex = RegExp(
      r'(?:Rp\.?|IDR)\s*([0-9]{1,3}(?:[.,][0-9]{3})+(?:[.,][0-9]{1,2})?|[0-9]{4,12})',
      caseSensitive: false,
    );
    final match = regex.firstMatch(combined);
    if (match == null) return null;

    var raw = match.group(1)!.trim();
    if (raw.length >= 3) {
      final sep = raw[raw.length - 3];
      if (sep == ',' || sep == '.') {
        raw = raw.substring(0, raw.length - 3);
      }
    }
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final amount = int.tryParse(digits) ?? 0;
    if (amount <= 0) return null;

    final lower = combined.toLowerCase();
    final isIncome = [
      'diterima',
      'uang masuk',
      'transfer masuk',
      'kredit',
      'top up berhasil',
      'refund',
      'gaji',
    ].any(lower.contains);

    final sourceApp = switch (packageName) {
      'com.bca' || 'com.bca.mybca.omni.android' => 'BCA mobile',
      'id.bmri.livin' => "Livin' Mandiri",
      'id.co.bri.brimo' => 'BRImo',
      'id.bni.wondr' || 'src.com.bni' => 'wondr BNI',
      'com.jago.digitalBanking' => 'Bank Jago',
      'id.co.bankbkemobile.digitalbank' => 'SeaBank',
      'com.gojek.app' || 'com.gojek.gopay' => 'GoPay',
      'id.dana' => 'DANA',
      'ovo.id' => 'OVO',
      'com.shopee.id' => 'ShopeePay',
      _ => _inferSourceAppFromText(lower),
    };

    return SmartInboxItem(
      id: const Uuid().v4(),
      sourceApp: sourceApp,
      packageName: packageName,
      title: title.isEmpty ? 'Transaksi $sourceApp' : title,
      body: body,
      amount: amount,
      type: isIncome ? 'income' : 'expense',
      detectedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static final _sourcePatterns = <(RegExp, String)>[
    (RegExp(r'qris'), 'QRIS'),
    (RegExp(r'brimo|\bbri\b'), 'BRImo'),
    (RegExp(r'mybca|\bbca\b'), 'BCA mobile'),
    (RegExp(r'livin|mandiri'), "Livin' Mandiri"),
    (RegExp(r'wondr|\bbni\b'), 'wondr BNI'),
    (RegExp(r'gopay'), 'GoPay'),
    (RegExp(r'\bdana\b'), 'DANA'),
    (RegExp(r'\bovo\b'), 'OVO'),
    (RegExp(r'shopee'), 'ShopeePay'),
    (RegExp(r'\bjago\b'), 'Bank Jago'),
    (RegExp(r'seabank'), 'SeaBank'),
    (RegExp(r'linkaja'), 'LinkAja'),
  ];

  static String _inferSourceAppFromText(String lower) {
    for (final (pattern, label) in _sourcePatterns) {
      if (pattern.hasMatch(lower)) return label;
    }
    return 'Notifikasi Bank';
  }
}
