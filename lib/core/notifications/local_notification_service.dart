import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

/// Local Notification Scheduler & Ledger (FR-23).
/// Works 100% offline without Firebase.
class LocalNotificationService {
  LocalNotificationService(
    this.db, {
    FlutterLocalNotificationsPlugin? plugin,
    Uuid? uuid,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _uuid = uuid ?? const Uuid();

  final AppDatabase db;
  final FlutterLocalNotificationsPlugin _plugin;
  final Uuid _uuid;

  bool _initialized = false;
  void Function(String? deepLink)? onNotificationTap;

  Future<void> initialize({void Function(String? deepLink)? onTap}) async {
    onNotificationTap = onTap;
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
    } catch (_) {
      // Fallback to UTC if timezone lookup fails on host test environment
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (resp) {
          onNotificationTap?.call(resp.payload);
        },
      );
      _initialized = true;
    } catch (e) {
      debugPrint('LocalNotification init skipped: $e');
    }
  }

  Future<bool> requestPermissions() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Adjusts [scheduled] if it falls inside quiet hours.
  DateTime applyQuietHours(
    DateTime scheduled,
    int? quietStartMinute,
    int? quietEndMinute,
  ) {
    if (quietStartMinute == null || quietEndMinute == null) return scheduled;
    final currentMinute = scheduled.hour * 60 + scheduled.minute;
    final wrapsMidnight = quietStartMinute > quietEndMinute;
    final inQuiet = wrapsMidnight
        ? (currentMinute >= quietStartMinute || currentMinute < quietEndMinute)
        : (currentMinute >= quietStartMinute && currentMinute < quietEndMinute);

    if (!inQuiet) return scheduled;
    final endHour = quietEndMinute ~/ 60;
    final endMin = quietEndMinute % 60;
    var adjusted = DateTime(
      scheduled.year,
      scheduled.month,
      scheduled.day,
      endHour,
      endMin,
    );
    if (adjusted.isBefore(scheduled)) {
      adjusted = adjusted.add(const Duration(days: 1));
    }
    return adjusted;
  }

  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
    required bool enabled,
  }) async {
    const platformId = 1001;
    await cancelByPlatformId(platformId);
    if (!enabled) return;

    final now = tz.TZDateTime.now(tz.local);
    var target = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
    }

    await _upsertNotificationRecord(
      platformId: platformId,
      kind: 'daily',
      title: 'Sudah catat transaksi hari ini?',
      body: 'Luangkan 5 detik untuk menjaga arus keuanganmu tetap rapi.',
      deepLink: '/transactions/new',
      scheduledAt: target,
    );

    if (!_initialized) return;
    try {
      await _plugin.zonedSchedule(
        platformId,
        'Sudah catat transaksi hari ini?',
        'Luangkan 5 detik untuk menjaga arus keuanganmu tetap rapi.',
        target,
        _defaultDetails(hideOnLockScreen: true),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: '/transactions/new',
      );
    } catch (e) {
      debugPrint('Failed scheduling daily reminder: $e');
    }
  }

  Future<void> scheduleReminder({
    required String kind,
    required String title,
    required String body,
    required DateTime scheduledAt,
    String? deepLink,
    String? referenceId,
    bool hideAmountOnLockScreen = true,
  }) async {
    final settings = await (db.select(db.appSettings)
          ..where((s) => s.id.equals('default')))
        .getSingleOrNull();
    if (settings != null && !settings.localNotificationsEnabled) return;

    final adjusted = applyQuietHours(
      scheduledAt,
      settings?.quietHoursStartMinute,
      settings?.quietHoursEndMinute,
    );
    if (adjusted.isBefore(DateTime.now())) return;

    final platformId =
        '${kind}_${referenceId ?? adjusted.millisecondsSinceEpoch}'.hashCode &
            0x7FFFFFFF;

    await _upsertNotificationRecord(
      platformId: platformId,
      kind: kind,
      title: title,
      body: body,
      deepLink: deepLink,
      referenceId: referenceId,
      scheduledAt: adjusted,
    );

    if (!_initialized) return;
    try {
      final tzDate = tz.TZDateTime.from(adjusted, tz.local);
      await _plugin.zonedSchedule(
        platformId,
        title,
        body,
        tzDate,
        _defaultDetails(hideOnLockScreen: hideAmountOnLockScreen),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: deepLink,
      );
    } catch (e) {
      debugPrint('Failed scheduling reminder: $e');
    }
  }

  Future<void> showImmediateAlert({
    required String kind,
    required String title,
    required String body,
    String? deepLink,
  }) async {
    final settings = await (db.select(db.appSettings)
          ..where((s) => s.id.equals('default')))
        .getSingleOrNull();
    if (settings != null && !settings.localNotificationsEnabled) return;

    final platformId = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
    if (!_initialized) return;
    try {
      await _plugin.show(
        platformId,
        title,
        body,
        _defaultDetails(
          hideOnLockScreen: settings?.hideAmountInNotifications ?? true,
        ),
        payload: deepLink,
      );
    } catch (e) {
      debugPrint('Failed showing immediate alert: $e');
    }
  }

  Future<void> cancelForReference(String referenceId) async {
    final rows = await (db.select(db.notifications)
          ..where((n) =>
              n.referenceId.equals(referenceId) & n.status.equals('scheduled')))
        .get();
    for (final row in rows) {
      await cancelByPlatformId(row.platformId);
    }
  }

  Future<void> cancelByPlatformId(int platformId) async {
    await (db.update(db.notifications)
          ..where((n) => n.platformId.equals(platformId)))
        .write(const NotificationsCompanion(status: Value('cancelled')));
    if (_initialized) {
      try {
        await _plugin.cancel(platformId);
      } catch (_) {}
    }
  }

  /// Re-schedules all active future reminders (e.g. after database restore, FR-27).
  Future<void> rescheduleAllFromDatabase() async {
    final now = DateTime.now();
    final rows = await (db.select(db.notifications)
          ..where((n) =>
              n.status.equals('scheduled') & n.scheduledAt.isBiggerThanValue(now)))
        .get();
    for (final row in rows) {
      if (!_initialized) continue;
      try {
        await _plugin.zonedSchedule(
          row.platformId,
          row.title,
          row.body,
          tz.TZDateTime.from(row.scheduledAt, tz.local),
          _defaultDetails(hideOnLockScreen: true),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: row.deepLink,
        );
      } catch (_) {}
    }
  }

  Future<void> _upsertNotificationRecord({
    required int platformId,
    required String kind,
    required String title,
    required String body,
    required DateTime scheduledAt,
    String? deepLink,
    String? referenceId,
  }) async {
    await db.into(db.notifications).insert(
          NotificationsCompanion.insert(
            id: _uuid.v4(),
            platformId: platformId,
            kind: kind,
            title: title,
            body: body,
            deepLink: Value(deepLink),
            referenceId: Value(referenceId),
            scheduledAt: scheduledAt,
          ),
        );
  }

  NotificationDetails _defaultDetails({required bool hideOnLockScreen}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'arus_finance_reminders',
        'Pengingat Keuangan Lanjo',
        channelDescription: 'Pengingat tagihan, budget, target tabungan, dan pencatatan harian',
        importance: Importance.high,
        priority: Priority.high,
        visibility: hideOnLockScreen
            ? NotificationVisibility.private
            : NotificationVisibility.public,
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }
}
