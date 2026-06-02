import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_api.dart';
import '../../i18n/locale_controller.dart';
import '../../mixins/wallet_flow_listener_mixin.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/arqma_field.dart';
import '../../widgets/wallet_restore_refresh_controls.dart';

/// Parity with `pages/wallet-select/import-view-only.vue`.
class WalletSelectImportViewOnlyPage extends StatefulWidget {
  const WalletSelectImportViewOnlyPage({super.key});

  @override
  State<WalletSelectImportViewOnlyPage> createState() =>
      _WalletSelectImportViewOnlyPageState();
}

class _WalletSelectImportViewOnlyPageState
    extends State<WalletSelectImportViewOnlyPage> with WalletFlowListenerMixin {
  static const String _kFirstBlockDate = '2018/10/31';

  final TextEditingController _name = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _viewkey = TextEditingController();
  final TextEditingController _refreshHeight = TextEditingController(text: '0');
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();

  String _refreshType = 'date';
  String _refreshStartDate = _kFirstBlockDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => attachWalletFlowListener());
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _viewkey.dispose();
    _refreshHeight.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  String _formatYmd(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  DateTime? _parseYmd(String s) {
    final List<String> p = s.split('/');
    if (p.length != 3) {
      return null;
    }
    final int? y = int.tryParse(p[0]);
    final int? m = int.tryParse(p[1]);
    final int? d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) {
      return null;
    }
    return DateTime(y, m, d);
  }

  Future<void> _pickDate() async {
    final DateTime? first = _parseYmd(_kFirstBlockDate);
    final DateTime now = DateTime.now();
    final DateTime initial = _parseYmd(_refreshStartDate) ?? first ?? now;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first ?? DateTime(2018, 10, 31),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _refreshStartDate = _formatYmd(picked));
    }
  }

  Future<void> _submit() async {
    final LocaleController loc = context.read<LocaleController>();
    final String name = _name.text.trim();
    final String address = _address.text.trim();
    final String viewkey = _viewkey.text.trim();
    if (name.isEmpty && address.isEmpty && viewkey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.tr(
                'pages.wallet_select.import_view_only.enter_an_account_name_address_viewkey'))),
      );
      return;
    }
    if (name.isEmpty && address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.tr(
                'pages.wallet_select.import_view_only.enter_an_account_name_address'))),
      );
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.tr(
                'pages.wallet_select.import_view_only.enter_an_account_name'))),
      );
      return;
    }
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.tr(
                'pages.wallet_select.import_view_only.invalid_account_address'))),
      );
      return;
    }
    if (viewkey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.tr(
                'pages.wallet_select.import_view_only.invalid_private_viewkey'))),
      );
      return;
    }
    if (_refreshType == 'height' &&
        int.tryParse(_refreshHeight.text.trim()) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.tr(
                'pages.wallet_select.import_view_only.invalid_restore_height'))),
      );
      return;
    }
    if (_password.text != _passwordConfirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.tr(
                'pages.wallet_select.import_view_only.passwords_do_not_match'))),
      );
      return;
    }
    final AppApi api = context.read<AppApi>();
    await AppLoading.show();
    await api.send('wallet', 'restore_view_wallet', <String, dynamic>{
      'name': name,
      'address': address,
      'viewkey': viewkey,
      'refresh_type': _refreshType,
      'refresh_start_height': int.tryParse(_refreshHeight.text.trim()) ?? 0,
      'refresh_start_date': _refreshStartDate,
      'password': _password.text,
      'password_confirm': _passwordConfirm.text,
    });
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
            label: loc.tr('pages.wallet_select.import_view_only.account_name'),
            child: TextField(
              controller: _name,
              decoration: InputDecoration(
                hintText: loc.tr(
                    'pages.wallet_select.import_view_only.account_name_placeholder'),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label:
                loc.tr('pages.wallet_select.import_view_only.account_address'),
            child: TextField(
              controller: _address,
              decoration: InputDecoration(
                hintText: loc.tr(
                    'pages.wallet_select.import_view_only.account_address_placeholder'),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label:
                loc.tr('pages.wallet_select.import_view_only.private_view_key'),
            child: TextField(
              controller: _viewkey,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: loc.tr(
                    'pages.wallet_select.import_view_only.private_view_key_placeholder'),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          WalletRestoreRefreshControls(
            refreshType: _refreshType,
            refreshStartDate: _refreshStartDate,
            refreshHeightController: _refreshHeight,
            dateLabel: loc.tr(
                'pages.wallet_select.import_view_only.restore_from_date'),
            heightLabel: loc.tr(
                'pages.wallet_select.import_view_only.restore_from_height'),
            switchToHeightLabel: loc.tr(
                'pages.wallet_select.import_view_only.switch_to_height_select'),
            switchToDateLabel: loc.tr(
                'pages.wallet_select.import_view_only.switch_to_date_select'),
            onPickDate: _pickDate,
            onSwitchToHeight: () => setState(() => _refreshType = 'height'),
            onSwitchToDate: () => setState(() => _refreshType = 'date'),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label: loc.tr('pages.wallet_select.import_view_only.password'),
            child: TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                hintText: loc.tr(
                    'pages.wallet_select.import_view_only.password_placeholder'),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label:
                loc.tr('pages.wallet_select.import_view_only.confirm_password'),
            child: TextField(
              controller: _passwordConfirm,
              obscureText: true,
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(loc.tr(
                'pages.wallet_select.import_view_only.restore_view_only_account')),
          ),
        ],
      ),
    );
  }
}
