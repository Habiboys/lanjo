import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'secure_storage_service.dart';

class AppLockService {
  AppLockService(this._secureStorage, {LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final SecureStorageService _secureStorage;
  final LocalAuthentication _localAuth;

  DateTime? _lastBackgroundedAt;

  void markBackgrounded() {
    _lastBackgroundedAt = DateTime.now();
  }

  bool shouldLockOnResume(int timeoutSeconds) {
    if (_lastBackgroundedAt == null) return false;
    final elapsed = DateTime.now().difference(_lastBackgroundedAt!).inSeconds;
    return elapsed >= timeoutSeconds;
  }

  void clearBackgroundTimestamp() {
    _lastBackgroundedAt = null;
  }

  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      return canCheck || supported;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Buka kunci aplikasi Lanjo',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  Future<bool> verifyPin(String pin) => _secureStorage.verifyPin(pin);
  Future<void> setPin(String pin) => _secureStorage.savePin(pin);
  Future<void> removePin() => _secureStorage.clearPin();
  Future<bool> hasPin() => _secureStorage.hasPin();
  Future<void> setRecoveryCode(String code) =>
      _secureStorage.saveRecoveryCode(code);
  Future<bool> verifyRecoveryCode(String code) =>
      _secureStorage.verifyRecoveryCode(code);
}
