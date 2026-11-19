import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/core_providers.dart';

/// Local Notification & optional FCM settings (FR-23, FR-24).
class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final db = ref.watch(appDatabaseProvider);
    final localNotif = ref.read(localNotificationServiceProvider);
    final fcm = ref.read(fcmServiceProvider);

    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final reminderTime = TimeOfDay(
      hour: settings.dailyReminderHour,
      minute: settings.dailyReminderMinute,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Notifikasi & Pengingat')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Notifikasi Lokal (Offline)'),
                  subtitle: const Text(
                    'Pengingat catat harian, jatuh tempo tagihan, anggaran 80%/100%, dan wishlist.',
                  ),
                  value: settings.localNotificationsEnabled,
                  onChanged: (v) async {
                    if (v) await localNotif.requestPermissions();
                    await (db.update(db.appSettings)
                          ..where((s) => s.id.equals('default')))
                        .write(
                      AppSettingsCompanion(
                        localNotificationsEnabled: Value(v),
                        updatedAt: Value(DateTime.now()),
                      ),
                    );
                    await localNotif.scheduleDailyReminder(
                      hour: settings.dailyReminderHour,
                      minute: settings.dailyReminderMinute,
                      enabled: v,
                    );
                  },
                ),
                ListTile(
                  title: const Text('Jam Pengingat Harian'),
                  subtitle: Text(reminderTime.format(context)),
                  trailing: const Icon(LucideIcons.clock, size: 18),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: reminderTime,
                    );
                    if (picked == null) return;
                    await (db.update(db.appSettings)
                          ..where((s) => s.id.equals('default')))
                        .write(
                      AppSettingsCompanion(
                        dailyReminderHour: Value(picked.hour),
                        dailyReminderMinute: Value(picked.minute),
                        updatedAt: Value(DateTime.now()),
                      ),
                    );
                    await localNotif.scheduleDailyReminder(
                      hour: picked.hour,
                      minute: picked.minute,
                      enabled: settings.localNotificationsEnabled,
                    );
                  },
                ),
                SwitchListTile(
                  title: const Text('Sembunyikan nominal di layar kunci'),
                  value: settings.hideAmountInNotifications,
                  onChanged: (v) async {
                    await (db.update(db.appSettings)
                          ..where((s) => s.id.equals('default')))
                        .write(
                      AppSettingsCompanion(
                        hideAmountInNotifications: Value(v),
                        updatedAt: Value(DateTime.now()),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Notifikasi Push Eksternal (FCM)'),
                  subtitle: Text(
                    'Hanya untuk pengumuman update & tips aplikasi. Data keuangan TIDAK pernah dikirim ke Firebase.\nStatus: ${fcm.statusLabel}',
                  ),
                  value: settings.fcmEnabled,
                  onChanged: (v) async {
                    await (db.update(db.appSettings)
                          ..where((s) => s.id.equals('default')))
                        .write(
                      AppSettingsCompanion(
                        fcmEnabled: Value(v),
                        updatedAt: Value(DateTime.now()),
                      ),
                    );
                    await fcm.setEnabled(v);
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
