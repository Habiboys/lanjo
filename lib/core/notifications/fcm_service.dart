import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'local_notification_service.dart';

@pragma('vm:entry-point')
Future<void> arusFcmBackgroundHandler(RemoteMessage message) async {
  // Never store financial data in Firebase; background handler only logs safely in debug.
  debugPrint('FCM background message received: ${message.messageId}');
}

/// Optional Firebase Cloud Messaging foundation (FR-24).
/// Gracefully becomes a no-op if Firebase config (google-services.json) is absent
/// or if user disables external push notifications.
class FcmService {
  FcmService(this._localNotifications);

  final LocalNotificationService _localNotifications;
  bool _available = false;
  String? _lastStatus;

  bool get isAvailable => _available;
  String get statusLabel =>
      _lastStatus ?? (_available ? 'Terhubung' : 'Tidak dikonfigurasi / Nonaktif');

  Future<void> initialize({required bool enabled}) async {
    if (!enabled) {
      _lastStatus = 'Dinonaktifkan pengguna';
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _available = true;
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      FirebaseMessaging.onBackgroundMessage(arusFcmBackgroundHandler);

      // Subscribe to general announcement topic (never sends financial data)
      await messaging.subscribeToTopic('arus_general');

      FirebaseMessaging.onMessage.listen((message) {
        final title = message.notification?.title ?? 'Info Lanjo';
        final body = message.notification?.body ?? '';
        if (body.isNotEmpty) {
          _localNotifications.showImmediateAlert(
            kind: 'fcm',
            title: title,
            body: body,
          );
        }
      });

      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        debugPrint('FCM cold start message: ${initial.messageId}');
      }

      _lastStatus = 'Aktif (topik: arus_general)';
    } catch (e) {
      // Expected when google-services.json / GoogleService-Info.plist is not yet provisioned
      _available = false;
      _lastStatus = 'Siap (menunggu konfigurasi Firebase proyek)';
      debugPrint('FCM init skipped cleanly: $e');
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (!enabled) {
      if (_available) {
        try {
          await FirebaseMessaging.instance.unsubscribeFromTopic('arus_general');
        } catch (_) {}
      }
      _lastStatus = 'Dinonaktifkan pengguna';
      return;
    }
    await initialize(enabled: true);
  }
}
