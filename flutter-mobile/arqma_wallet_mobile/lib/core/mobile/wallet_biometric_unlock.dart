import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores wallet passwords in the iOS Keychain / Android Keystore and unlocks via biometrics.
class WalletBiometricUnlock {
  WalletBiometricUnlock._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    aOptions: AndroidOptions(),
  );

  static final LocalAuthentication _auth = LocalAuthentication();

  static String _passwordKey(String netType, String walletName) =>
      'arqma_wallet_pwd_${netType}_$walletName';

  static String _enabledPrefKey(String netType, String walletName) =>
      'arqma_wallet_bio_${netType}_$walletName';

  static Future<bool> isPlatformSupported() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return false;
    }
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (e, st) {
      debugPrint('[WalletBiometricUnlock] isPlatformSupported: $e\n$st');
      return false;
    }
  }

  static Future<List<BiometricType>> availableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return <BiometricType>[];
    }
  }

  /// User-facing label: Face ID, Touch ID, or generic biometrics.
  static String biometricLabel(
    List<BiometricType> types, {
    required String faceIdLabel,
    required String touchIdLabel,
    required String genericLabel,
  }) {
    if (types.contains(BiometricType.face)) {
      return faceIdLabel;
    }
    if (types.contains(BiometricType.fingerprint) ||
        types.contains(BiometricType.strong) ||
        types.contains(BiometricType.weak)) {
      return touchIdLabel;
    }
    return genericLabel;
  }

  static Future<bool> isEnabled(String netType, String walletName) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_enabledPrefKey(netType, walletName)) ?? false)) {
      return false;
    }
    final String? stored =
        await _storage.read(key: _passwordKey(netType, walletName));
    return stored != null && stored.isNotEmpty;
  }

  static Future<void> enable({
    required String netType,
    required String walletName,
    required String password,
    required String localizedReason,
  }) async {
    if (!await isPlatformSupported()) {
      throw StateError('Biometrics unavailable');
    }
    final bool ok = await _auth.authenticate(
      localizedReason: localizedReason,
      biometricOnly: true,
      persistAcrossBackgrounding: true,
    );
    if (!ok) {
      throw StateError('Biometric authentication cancelled');
    }
    await _storage.write(
      key: _passwordKey(netType, walletName),
      value: password,
    );
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledPrefKey(netType, walletName), true);
  }

  static Future<void> disable(String netType, String walletName) async {
    await _storage.delete(key: _passwordKey(netType, walletName));
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledPrefKey(netType, walletName), false);
  }

  /// Returns wallet password after a successful biometric prompt, or null if cancelled.
  static Future<String?> unlockPassword({
    required String netType,
    required String walletName,
    required String localizedReason,
  }) async {
    if (!await isEnabled(netType, walletName)) {
      return null;
    }
    try {
      final bool ok = await _auth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (!ok) {
        return null;
      }
      return _storage.read(key: _passwordKey(netType, walletName));
    } catch (e, st) {
      debugPrint('[WalletBiometricUnlock] unlockPassword: $e\n$st');
      return null;
    }
  }
}
