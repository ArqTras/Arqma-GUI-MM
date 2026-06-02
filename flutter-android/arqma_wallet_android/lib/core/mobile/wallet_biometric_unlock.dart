import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_nav.dart';

/// Deferred Face ID enrollment after wallet open (iOS needs a stable window).
class PendingFaceIdEnable {
  const PendingFaceIdEnable({
    required this.netType,
    required this.walletName,
    required this.password,
    required this.localizedReason,
    required this.successMessage,
    required this.failureMessage,
  });

  final String netType;
  final String walletName;
  final String password;
  final String localizedReason;
  final String successMessage;
  final String failureMessage;
}

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
  static PendingFaceIdEnable? _pendingEnable;

  static String _passwordKey(String netType, String walletName) =>
      'arqma_wallet_pwd_${netType}_$walletName';

  static String _enabledPrefKey(String netType, String walletName) =>
      'arqma_wallet_bio_${netType}_$walletName';

  static String _offerSkippedPrefKey(String netType, String walletName) =>
      'arqma_wallet_bio_skip_${netType}_$walletName';

  /// Schedule enrollment to run on the wallet screen (after navigation settles).
  static void scheduleEnable(PendingFaceIdEnable pending) {
    _pendingEnable = pending;
    debugPrint('[WalletBiometricUnlock] scheduled Face ID enable for ${pending.walletName}');
  }

  /// Runs a pending enrollment once the wallet UI is visible.
  static Future<void> flushPendingEnable() async {
    final PendingFaceIdEnable? pending = _pendingEnable;
    if (pending == null) {
      return;
    }
    _pendingEnable = null;
    if ((!Platform.isIOS && !Platform.isAndroid) || pending.password.isEmpty) {
      return;
    }
    if (await isEnabled(pending.netType, pending.walletName)) {
      return;
    }
    debugPrint('[WalletBiometricUnlock] flushing pending Face ID enable');
    await waitForModalDismiss();
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    try {
      await enable(
        netType: pending.netType,
        walletName: pending.walletName,
        password: pending.password,
        localizedReason: pending.localizedReason,
      );
      _showSnackBar(pending.successMessage);
    } catch (e, st) {
      debugPrint('[WalletBiometricUnlock] flushPendingEnable: $e\n$st');
      _showSnackBar(pending.failureMessage);
    }
  }

  static void _showSnackBar(String message) {
    final ScaffoldMessengerState? messenger =
        appScaffoldMessengerKey.currentState;
    if (messenger == null) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Hardware / OS support — [getAvailableBiometrics] is often empty on iOS release builds.
  static Future<bool> isPlatformSupported() async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return false;
    }
    try {
      final bool canBio = await _auth.canCheckBiometrics;
      final bool deviceOk = await _auth.isDeviceSupported();
      if (canBio || deviceOk) {
        return true;
      }
      if (Platform.isIOS) {
        return true;
      }
      return false;
    } catch (e, st) {
      debugPrint('[WalletBiometricUnlock] isPlatformSupported: $e\n$st');
      return Platform.isIOS;
    }
  }

  static Future<bool> wasOfferSkipped(String netType, String walletName) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_offerSkippedPrefKey(netType, walletName)) ?? false;
  }

  static Future<void> markOfferSkipped(String netType, String walletName) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offerSkippedPrefKey(netType, walletName), true);
  }

  static Future<List<BiometricType>> availableBiometrics() async {
    try {
      final List<BiometricType> types = await _auth.getAvailableBiometrics();
      if (types.isNotEmpty) {
        return types;
      }
      if (Platform.isIOS && await isPlatformSupported()) {
        return <BiometricType>[BiometricType.face];
      }
      return types;
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

  /// Pause so iOS can dismiss Flutter modals before presenting Face ID.
  static Future<void> waitForModalDismiss() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  static Future<bool> _authenticate({
    required String localizedReason,
  }) async {
    await waitForModalDismiss();
    await WidgetsBinding.instance.endOfFrame;

    Object? lastError;
    for (int attempt = 0; attempt < 3; attempt++) {
      final bool biometricOnly = attempt == 0;
      try {
        debugPrint(
            '[WalletBiometricUnlock] authenticate attempt ${attempt + 1} biometricOnly=$biometricOnly');
        final bool ok = await _auth.authenticate(
          localizedReason: localizedReason,
          biometricOnly: biometricOnly,
          sensitiveTransaction: false,
          persistAcrossBackgrounding: true,
        );
        debugPrint('[WalletBiometricUnlock] authenticate result=$ok');
        return ok;
      } on LocalAuthException catch (e, st) {
        lastError = e;
        debugPrint(
            '[WalletBiometricUnlock] authenticate LocalAuthException: ${e.code} ${e.description}\n$st');
        if (e.code == LocalAuthExceptionCode.uiUnavailable ||
            e.code == LocalAuthExceptionCode.systemCanceled) {
          await waitForModalDismiss();
          continue;
        }
        rethrow;
      } catch (e, st) {
        lastError = e;
        debugPrint('[WalletBiometricUnlock] authenticate: $e\n$st');
        await waitForModalDismiss();
      }
    }
    if (lastError != null) {
      debugPrint('[WalletBiometricUnlock] authenticate failed: $lastError');
    }
    return false;
  }

  static Future<void> enable({
    required String netType,
    required String walletName,
    required String password,
    required String localizedReason,
  }) async {
    if (!await isPlatformSupported()) {
      throw StateError('Biometrics unavailable on this device');
    }
    if (password.isEmpty) {
      throw StateError('Wallet password is required to enable Face ID');
    }
    final bool canBio = await _auth.canCheckBiometrics;
    if (!canBio && Platform.isIOS) {
      throw StateError(
          'Face ID is not available. Check Settings → Face ID and allow Arqma Wallet.');
    }
    final bool ok = await _authenticate(localizedReason: localizedReason);
    if (!ok) {
      throw StateError('Face ID confirmation was cancelled');
    }
    await _storage.write(
      key: _passwordKey(netType, walletName),
      value: password,
    );
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledPrefKey(netType, walletName), true);
    debugPrint('[WalletBiometricUnlock] enabled for $walletName');
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
      final bool ok = await _authenticate(localizedReason: localizedReason);
      if (!ok) {
        return null;
      }
      return _storage.read(key: _passwordKey(netType, walletName));
    } on LocalAuthException catch (e, st) {
      debugPrint(
          '[WalletBiometricUnlock] unlockPassword LocalAuthException: ${e.code} ${e.description}\n$st');
      return null;
    } catch (e, st) {
      debugPrint('[WalletBiometricUnlock] unlockPassword: $e\n$st');
      return null;
    }
  }
}
