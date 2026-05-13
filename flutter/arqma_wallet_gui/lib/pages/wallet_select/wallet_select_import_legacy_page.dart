import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_api.dart';
import '../../i18n/locale_controller.dart';
import '../../mixins/wallet_flow_listener_mixin.dart';
import '../../store/gateway_store.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/arqma_field.dart';

/// Parity with `pages/wallet-select/import-legacy.vue`.
class WalletSelectImportLegacyPage extends StatefulWidget {
  const WalletSelectImportLegacyPage({super.key});

  @override
  State<WalletSelectImportLegacyPage> createState() =>
      _WalletSelectImportLegacyPageState();
}

class _WalletSelectImportLegacyPageState
    extends State<WalletSelectImportLegacyPage> with WalletFlowListenerMixin {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _path = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();
  String _legacyType = '0';
  bool _nameTouched = false;
  bool _pathTouched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => attachWalletFlowListener());
  }

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final FilePickerResult? r = await FilePicker.platform.pickFiles();
    final String? p = r?.files.single.path;
    if (p != null) {
      setState(() => _path.text = p);
    }
  }

  Future<void> _import() async {
    final LocaleController loc = context.read<LocaleController>();
    final String name = _name.text.trim();
    final String path = _path.text.trim();
    if (name.isEmpty && path.isEmpty) {
      setState(() {
        _nameTouched = true;
        _pathTouched = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.tr(
                'pages.wallet_select.import_legacy.import_file_path_message'))),
      );
      return;
    }
    if (name.isEmpty) {
      setState(() => _nameTouched = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc
                .tr('pages.wallet_select.import_legacy.enter_account_name'))),
      );
      return;
    }
    if (path.isEmpty) {
      setState(() => _pathTouched = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                loc.tr('pages.wallet_select.import_legacy.enter_path_file'))),
      );
      return;
    }
    if (_password.text != _passwordConfirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc
                .tr('pages.wallet_select.import_legacy.passwords_dont_match'))),
      );
      return;
    }
    final AppApi api = context.read<AppApi>();
    await AppLoading.show();
    await api.send('wallet', 'import_wallet', <String, dynamic>{
      'name': name,
      'path': path,
      'password': _password.text,
      'password_confirm': _passwordConfirm.text,
      'legacy_type': _legacyType,
    });
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final List<dynamic> legacy =
        (store.raw['wallets'] as Map?)?['legacy'] as List<dynamic>? ??
            const <dynamic>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (legacy.length == 2) ...[
            RadioGroup<String>(
              groupValue: _legacyType,
              onChanged: (String? v) {
                if (v != null) {
                  setState(() => _legacyType = v);
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  RadioListTile<String>(
                    title: Text(
                        loc.tr('pages.wallet_select.import_legacy.full_wallet')),
                    value: '0',
                  ),
                  RadioListTile<String>(
                    title: Text(
                        loc.tr('pages.wallet_select.import_legacy.lite_wallet')),
                    value: '1',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          ArqmaField(
            label: loc.tr('pages.wallet_select.import_legacy.new_account_name'),
            error: _nameTouched && _name.text.trim().isEmpty,
            child: TextField(
              controller: _name,
              decoration: InputDecoration(
                hintText: loc.tr(
                    'pages.wallet_select.import_legacy.new_account_name_placeholder'),
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label: loc.tr('pages.wallet_select.import_legacy.account_file'),
            disableHover: true,
            error: _pathTouched && _path.text.trim().isEmpty,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _path,
                  readOnly: true,
                  decoration: InputDecoration(
                    hintText: loc.tr(
                        'pages.wallet_select.import_legacy.account_file_placeholder'),
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _pickFile,
                  child: Text(loc.tr(
                      'pages.wallet_select.import_legacy.select_account_file')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label: loc.tr('pages.wallet_select.import_legacy.password'),
            child: TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                hintText: loc.tr(
                    'pages.wallet_select.import_legacy.password_placeholder'),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label: loc.tr('pages.wallet_select.import_legacy.confirm_password'),
            child: TextField(
              controller: _passwordConfirm,
              obscureText: true,
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _import,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
                loc.tr('pages.wallet_select.import_legacy.import_account')),
          ),
        ],
      ),
    );
  }
}
