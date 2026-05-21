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
    return showDialog<String>(
      context: context,
      builder: (BuildContext _) => _RpcPasswordPromptDialog(
        locale: locale,
        title: title,
        okLabel: okLabel,
        dark: dark,
      ),
    );
  }
}

class _RpcPasswordPromptDialog extends StatefulWidget {
  const _RpcPasswordPromptDialog({
    required this.locale,
    required this.title,
    required this.okLabel,
    required this.dark,
  });

  final LocaleController locale;
  final String title;
  final String okLabel;
  final bool dark;

  @override
  State<_RpcPasswordPromptDialog> createState() =>
      _RpcPasswordPromptDialogState();
}

class _RpcPasswordPromptDialogState extends State<_RpcPasswordPromptDialog> {
  late final TextEditingController _pw = TextEditingController();

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.dark ? const Color(0xFF1d1d1d) : null,
      title: Text(widget.title),
      content: TextField(
        controller: _pw,
        autofocus: true,
        obscureText: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => Navigator.pop(context, _pw.text),
        decoration: InputDecoration(
          labelText:
              widget.locale.tr('composables.enter_wallet_password_to_continue'),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.locale.tr('composables.cancel'))),
        TextButton(
            onPressed: () => Navigator.pop(context, _pw.text),
            child: Text(widget.okLabel)),
      ],
    );
  }
}
