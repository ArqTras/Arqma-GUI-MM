import 'package:flutter/material.dart';

import '../core/app_api.dart';
import '../i18n/locale_controller.dart';

/// Parity with `composables/wallet_password.js` + Quasar `dialog` prompt.
class PasswordDialogs {
  PasswordDialogs._();

  /// Returns password string or null if cancelled. Empty string means no password (cached RPC).
  static Future<String?> showPasswordConfirmation({
    required BuildContext context,
    required AppApi api,
    required LocaleController locale,
    required String title,
    required String noPasswordMessage,
    required String okLabel,
    bool dark = true,
  }) async {
    final bool has = await api.hasPasswordRpc();
    if (!context.mounted) {
      return null;
    }
    if (has) {
      return showDialog<String>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          backgroundColor: dark ? const Color(0xFF1d1d1d) : null,
          title: Text(title),
          content: Text(noPasswordMessage),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(locale.tr('composables.cancel'))),
            TextButton(
                onPressed: () => Navigator.pop(c, ''), child: Text(okLabel)),
          ],
        ),
      );
    }
    final TextEditingController pw = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        backgroundColor: dark ? const Color(0xFF1d1d1d) : null,
        title: Text(title),
        content: TextField(
          controller: pw,
          autofocus: true,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(c, pw.text),
          decoration: InputDecoration(
            labelText:
                locale.tr('composables.enter_wallet_password_to_continue'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(locale.tr('composables.cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(c, pw.text), child: Text(okLabel)),
        ],
      ),
    );
  }
}
