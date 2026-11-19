import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../providers/core_providers.dart';
import 'lanjo_ui.dart';

/// App Lock overlay supporting PIN, Biometric, Auto-lock timeout, and Recovery Code (PRD 15.2).
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  final _pinController = TextEditingController();
  final _recoveryController = TextEditingController();
  String? _error;
  bool _showRecovery = false;
  bool _triedBiometric = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pinController.dispose();
    _recoveryController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lockSvc = ref.read(appLockServiceProvider);
    final settings = ref.read(appSettingsProvider).valueOrNull;
    if (settings == null || !settings.appLockEnabled) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      lockSvc.markBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      if (lockSvc.shouldLockOnResume(settings.autoLockTimeoutSeconds)) {
        ref.read(sessionUnlockedProvider.notifier).state = false;
        _triedBiometric = false;
      }
      lockSvc.clearBackgroundTimestamp();
    }
  }

  Future<void> _tryBiometric() async {
    if (_triedBiometric) return;
    _triedBiometric = true;
    final ok = await ref.read(appLockServiceProvider).authenticateWithBiometrics();
    if (ok && mounted) {
      ref.read(sessionUnlockedProvider.notifier).state = true;
    }
  }

  Future<void> _submitPin() async {
    final ok = await ref
        .read(appLockServiceProvider)
        .verifyPin(_pinController.text.trim());
    if (!mounted) return;
    if (ok) {
      _pinController.clear();
      setState(() => _error = null);
      ref.read(sessionUnlockedProvider.notifier).state = true;
    } else {
      setState(() => _error = 'PIN salah. Coba lagi.');
    }
  }

  Future<void> _submitRecovery() async {
    final ok = await ref
        .read(appLockServiceProvider)
        .verifyRecoveryCode(_recoveryController.text);
    if (!mounted) return;
    if (ok) {
      _recoveryController.clear();
      setState(() {
        _error = null;
        _showRecovery = false;
      });
      ref.read(sessionUnlockedProvider.notifier).state = true;
    } else {
      setState(() => _error = 'Kode pemulihan lokal tidak cocok.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final unlocked = ref.watch(sessionUnlockedProvider);

    if (settings == null || !settings.appLockEnabled || unlocked) {
      return widget.child;
    }

    if (settings.biometricEnabled && !_triedBiometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }

    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LanjoIconBox(
                    icon: LucideIcons.lock,
                    color: theme.colorScheme.primary,
                    size: 64,
                    iconSize: 28,
                    radius: 20,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Lanjo Terkunci',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _showRecovery
                        ? 'Masukkan kode pemulihan lokal untuk membuka kunci.'
                        : 'Masukkan PIN untuk mengakses data keuanganmu.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!_showRecovery) ...[
                    TextField(
                      controller: _pinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        labelText: 'PIN (4-6 digit)',
                        errorText: _error,
                      ),
                      onSubmitted: (_) => _submitPin(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submitPin,
                        child: const Text('Buka Kunci'),
                      ),
                    ),
                    if (settings.biometricEnabled) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          _triedBiometric = false;
                          _tryBiometric();
                        },
                        icon: const Icon(LucideIcons.fingerprint, size: 18),
                        label: const Text('Gunakan Biometrik'),
                      ),
                    ],
                    TextButton(
                      onPressed: () => setState(() {
                        _showRecovery = true;
                        _error = null;
                      }),
                      child: const Text('Lupa PIN? Gunakan Kode Pemulihan'),
                    ),
                  ] else ...[
                    TextField(
                      controller: _recoveryController,
                      decoration: InputDecoration(
                        labelText: 'Kode Pemulihan Lokal',
                        errorText: _error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submitRecovery,
                        child: const Text('Verifikasi Kode Pemulihan'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _showRecovery = false;
                        _error = null;
                      }),
                      child: const Text('Kembali ke PIN'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
