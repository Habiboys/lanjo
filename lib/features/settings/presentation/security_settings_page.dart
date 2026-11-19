import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/core_providers.dart';

/// App Lock settings: PIN (hashed+salted in SecureStorage), Biometric,
/// Auto-lock timeout, and Local Recovery Code (PRD 15.2).
class SecuritySettingsPage extends ConsumerStatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  ConsumerState<SecuritySettingsPage> createState() =>
      _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends ConsumerState<SecuritySettingsPage> {
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBio();
  }

  Future<void> _checkBio() async {
    final avail = await ref.read(appLockServiceProvider).isBiometricAvailable();
    if (mounted) setState(() => _biometricAvailable = avail);
  }

  Future<void> _setupPinDialog() async {
    final pinCtrl = TextEditingController();
    final recoveryCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Atur PIN Aplikasi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'PIN (4-6 digit)'),
            ),
            TextField(
              controller: recoveryCtrl,
              decoration: const InputDecoration(
                labelText: 'Kode pemulihan lokal (opsional)',
                hintText: 'Kata rahasia untuk reset PIN',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              final pin = pinCtrl.text.trim();
              if (pin.length < 4) return;
              final lock = ref.read(appLockServiceProvider);
              final db = ref.read(appDatabaseProvider);
              await lock.setPin(pin);
              if (recoveryCtrl.text.trim().isNotEmpty) {
                await lock.setRecoveryCode(recoveryCtrl.text.trim());
              }
              await (db.update(db.appSettings)
                    ..where((s) => s.id.equals('default')))
                  .write(
                AppSettingsCompanion(
                  appLockEnabled: const Value(true),
                  updatedAt: Value(DateTime.now()),
                ),
              );
              ref.read(sessionUnlockedProvider.notifier).state = true;
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final db = ref.watch(appDatabaseProvider);
    final lock = ref.read(appLockServiceProvider);

    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Keamanan & Privasi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Kunci Aplikasi (PIN)'),
                  subtitle: const Text(
                    'PIN disimpan sebagai hash ter-salt di Secure Storage perangkat.',
                  ),
                  value: settings.appLockEnabled,
                  onChanged: (v) async {
                    if (v) {
                      await _setupPinDialog();
                    } else {
                      await lock.removePin();
                      await (db.update(db.appSettings)
                            ..where((s) => s.id.equals('default')))
                          .write(
                        AppSettingsCompanion(
                          appLockEnabled: const Value(false),
                          biometricEnabled: const Value(false),
                          updatedAt: Value(DateTime.now()),
                        ),
                      );
                    }
                  },
                ),
                if (settings.appLockEnabled) ...[
                  ListTile(
                    title: const Text('Ubah PIN / Kode Pemulihan'),
                    trailing: const Icon(LucideIcons.chevronRight, size: 16),
                    onTap: _setupPinDialog,
                  ),
                  if (_biometricAvailable)
                    SwitchListTile(
                      title: const Text('Autentikasi Biometrik'),
                      value: settings.biometricEnabled,
                      onChanged: (v) async {
                        await (db.update(db.appSettings)
                              ..where((s) => s.id.equals('default')))
                            .write(
                          AppSettingsCompanion(
                            biometricEnabled: Value(v),
                            updatedAt: Value(DateTime.now()),
                          ),
                        );
                      },
                    ),
                  ListTile(
                    title: const Text('Auto-Lock Timeout'),
                    trailing: DropdownButton<int>(
                      value: settings.autoLockTimeoutSeconds,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Langsung')),
                        DropdownMenuItem(value: 30, child: Text('30 detik')),
                        DropdownMenuItem(value: 60, child: Text('1 menit')),
                        DropdownMenuItem(value: 300, child: Text('5 menit')),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        await (db.update(db.appSettings)
                              ..where((s) => s.id.equals('default')))
                            .write(
                          AppSettingsCompanion(
                            autoLockTimeoutSeconds: Value(v),
                            updatedAt: Value(DateTime.now()),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
