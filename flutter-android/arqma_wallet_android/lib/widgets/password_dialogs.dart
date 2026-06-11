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
        useRootNavigator: true,
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
    return showWalletPasswordEntry(
      context: context,
      locale: locale,
      title: title,
      okLabel: okLabel,
      dark: dark,
    );
  }

  /// Always prompts for the wallet password (iOS Face ID enrollment; shared dialog shape).
  static Future<String?> showWalletPasswordEntry({
    required BuildContext context,
    required LocaleController locale,
    required String title,
    required String okLabel,
    String? message,
    bool dark = true,
  }) {
    return showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (BuildContext _) => _RpcPasswordPromptDialog(
        locale: locale,
        title: title,
        okLabel: okLabel,
        dark: dark,
        message: message,
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
    this.message,
  });

  final LocaleController locale;
  final String title;
  final String okLabel;
  final bool dark;
  final String? message;

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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.message != null && widget.message!.isNotEmpty) ...[
            Text(widget.message!),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _pw,
            autofocus: true,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.pop(context, _pw.text),
            decoration: InputDecoration(
              labelText: widget.locale
                  .tr('composables.enter_wallet_password_to_continue'),
            ),
          ),
        ],
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
