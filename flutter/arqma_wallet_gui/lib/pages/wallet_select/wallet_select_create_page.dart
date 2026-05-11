import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_api.dart';
import '../../i18n/locale_controller.dart';
import '../../mixins/wallet_flow_listener_mixin.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/arqma_field.dart';

/// Parity with `pages/wallet-select/create.vue`.
class WalletSelectCreatePage extends StatefulWidget {
  const WalletSelectCreatePage({super.key});

  @override
  State<WalletSelectCreatePage> createState() => _WalletSelectCreatePageState();
}

class _WalletSelectCreatePageState extends State<WalletSelectCreatePage>
    with WalletFlowListenerMixin {
  static const List<String> _seedLanguages = <String>[
    'English',
    'Deutsch',
    'Español',
    'Français',
    'Italiano',
    'Nederlands',
    'Português',
    'Русский',
    '日本語',
    '简体中文 (中国)',
    'Esperanto',
    'Lojban',
  ];

  final TextEditingController _name = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();
  String _language = 'English';
  bool _nameTouched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => attachWalletFlowListener());
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  Future<void> _confirmNoPasswordThen(void Function() onOk) async {
    final LocaleController loc = context.read<LocaleController>();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(
            loc.tr('pages.wallet_select.create.confirm_no_password_title')),
        content: Text(
            loc.tr('pages.wallet_select.create.confirm_no_password_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(loc.tr(
                'pages.wallet_select.create.confirm_no_password_cancel_label')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(loc
                .tr('pages.wallet_select.create.confirm_no_password_ok_label')),
          ),
        ],
      ),
    );
    if (ok == true) {
      onOk();
    }
  }

  Future<void> _create() async {
    final LocaleController loc = context.read<LocaleController>();
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameTouched = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                loc.tr('pages.wallet_select.create.enter_an_account_name'))),
      );
      return;
    }
    if (_password.text != _passwordConfirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                loc.tr('pages.wallet_select.create.passwords_do_not_match'))),
      );
      return;
    }
    Future<void> send() async {
      await AppLoading.show();
      await context
          .read<AppApi>()
          .send('wallet', 'create_wallet', <String, dynamic>{
        'name': name,
        'language': _language,
        'password': _password.text,
        'password_confirm': _passwordConfirm.text,
      });
    }

    if (_password.text.isEmpty) {
      await _confirmNoPasswordThen(send);
      return;
    }
    await send();
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArqmaField(
            label: loc.tr('pages.wallet_select.create.account_name'),
            error: _nameTouched && _name.text.trim().isEmpty,
            child: TextField(
              controller: _name,
              decoration: InputDecoration(
                hintText: loc
                    .tr('pages.wallet_select.create.wallet_name_placeholder'),
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
              onEditingComplete: () => setState(() => _nameTouched = true),
            ),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label: loc.tr('pages.wallet_select.create.seed_language'),
            child: DropdownButtonFormField<String>(
              value: _seedLanguages.contains(_language)
                  ? _language
                  : _seedLanguages.first,
              dropdownColor: const Color(0xFF1d1d1d),
              decoration: const InputDecoration(border: InputBorder.none),
              items: _seedLanguages
                  .map((String s) =>
                      DropdownMenuItem<String>(value: s, child: Text(s)))
                  .toList(),
              onChanged: (String? v) {
                if (v != null) {
                  setState(() => _language = v);
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label: loc.tr('pages.wallet_select.create.password'),
            optional: true,
            child: TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                hintText: loc.tr(
                    'pages.wallet_select.create.optional_password_for_account'),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label: loc.tr('pages.wallet_select.create.confirm_password'),
            child: TextField(
              controller: _passwordConfirm,
              obscureText: true,
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _create,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(loc.tr('pages.wallet_select.create.create_account')),
          ),
        ],
      ),
    );
  }
}
