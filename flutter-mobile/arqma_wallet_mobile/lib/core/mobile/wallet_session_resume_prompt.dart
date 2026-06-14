import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_nav.dart';
import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
import '../../widgets/password_dialogs.dart';
import '../services/mobile_native_bridge.dart';
import 'wallet_biometric_unlock.dart';

/// Prompts for the wallet password when the native FFI session must reopen after iOS resume.
class WalletSessionResumePrompt {
  WalletSessionResumePrompt._();

  static bool _dialogOpen = false;

  static String _netType(GatewayStore store) {
    final Map<String, dynamic>? cfg = store.app['config'] as Map<String, dynamic>?;
    return (cfg?['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  }

  static Future<void> showForBridgeEvent({
    required MobileNativeBridge bridge,
    required GatewayStore store,
    required LocaleController locale,
    required Map<String, dynamic> data,
  }) async {
    if (_dialogOpen) {
      return;
    }
    final String walletName = '${data['wallet_name'] ?? ''}'.trim();
    if (walletName.isEmpty) {
      bridge.clearResumePasswordUiPending();
      return;
    }
    final BuildContext? ctx = appNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      bridge.clearResumePasswordUiPending();
      return;
    }
    final String path = GoRouterState.of(ctx).uri.path;
    if (!path.startsWith('/wallet')) {
      bridge.clearResumePasswordUiPending();
      return;
    }

    _dialogOpen = true;
    var resumed = false;
    try {
      await WalletBiometricUnlock.waitForModalDismiss();
      await WidgetsBinding.instance.endOfFrame;

      if (Platform.isIOS) {
        final String netType = _netType(store);
        if (await WalletBiometricUnlock.isEnabled(netType, walletName)) {
          final String? bio = await WalletBiometricUnlock.unlockPassword(
            netType: netType,
            walletName: walletName,
            localizedReason:
                locale.tr('layouts.wallet.main.session_resume_biometric_reason'),
          );
          if (bio != null && bio.isNotEmpty) {
            await bridge.resumeWalletSessionAfterPassword(bio);
            resumed = true;
            return;
          }
        }
      }

      final BuildContext? dialogCtx = appNavigatorKey.currentContext;
      if (dialogCtx == null || !dialogCtx.mounted) {
        return;
      }
      final String? password = await PasswordDialogs.showWalletPasswordEntry(
        context: dialogCtx,
        locale: locale,
        title: locale.tr('layouts.wallet.main.session_resume_password_title'),
        message: locale.tr('layouts.wallet.main.session_resume_password_message'),
        okLabel: locale.tr('layouts.wallet.main.session_resume_password_ok'),
      );
      if (password == null || password.isEmpty) {
        return;
      }
      await bridge.resumeWalletSessionAfterPassword(password);
      resumed = true;
    } finally {
      _dialogOpen = false;
      if (!resumed) {
        bridge.clearResumePasswordUiPending();
      }
    }
  }
}
