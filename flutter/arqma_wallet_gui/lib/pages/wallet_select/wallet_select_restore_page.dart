import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_api.dart';
import '../../i18n/locale_controller.dart';
import '../../mixins/wallet_flow_listener_mixin.dart';
import '../../store/gateway_store.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/arqma_field.dart';

/// Parity with `pages/wallet-select/restore.vue`.
class WalletSelectRestorePage extends StatefulWidget {
  const WalletSelectRestorePage({super.key});

  @override
  State<WalletSelectRestorePage> createState() =>
      _WalletSelectRestorePageState();
}

class _WalletSelectRestorePageState extends State<WalletSelectRestorePage>
    with WalletFlowListenerMixin {
  static const String _kFirstBlockDate = '2018/10/31';

  final TextEditingController _name = TextEditingController();
  final TextEditingController _seed = TextEditingController();
  final TextEditingController _refreshHeight = TextEditingController(text: '0');
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();

  String _refreshType = 'date';
  String _refreshStartDate = _kFirstBlockDate;
  bool _nameTouched = false;
  bool _seedTouched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => attachWalletFlowListener());
  }

  @override
  void dispose() {
    _name.dispose();
    _seed.dispose();
    _refreshHeight.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  String _formatYmd(DateTime d) {
    final String y = d.year.toString().padLeft(4, '0');
    final String m = d.month.toString().padLeft(2, '0');
    final String day = d.day.toString().padLeft(2, '0');
    return '$y/$m/$day';
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

  Future<void> _pickDate(LocaleController loc) async {
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

  Future<void> _confirmNoPasswordThen(void Function() onOk) async {
    final LocaleController loc = context.read<LocaleController>();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(
            loc.tr('pages.wallet_select.restore.confirm_no_password_title')),
        content: Text(
            loc.tr('pages.wallet_select.restore.confirm_no_password_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(loc.tr(
                'pages.wallet_select.restore.confirm_no_password_cancel_label')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(loc.tr(
                'pages.wallet_select.restore.confirm_no_password_ok_label')),
          ),
        ],
      ),
    );
    if (ok == true) {
      onOk();
    }
  }

  Future<void> _restore() async {
    final LocaleController loc = context.read<LocaleController>();
    final String name = _name.text.trim();
    final String seedRaw = _seed.text.trim();
    if (name.isEmpty && seedRaw.isEmpty) {
      setState(() {
        _nameTouched = true;
        _seedTouched = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                loc.tr('pages.wallet_select.restore.restore_wallet_message'))),
      );
      return;
    }
    if (name.isEmpty) {
      setState(() => _nameTouched = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(loc.tr('pages.wallet_select.restore.enter_wallet_name'))),
      );
      return;
    }
    if (seedRaw.isEmpty) {
      setState(() => _seedTouched = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(loc.tr('pages.wallet_select.restore.enter_seed_words'))),
      );
      return;
    }
    final List<String> words = seedRaw
        .replaceAll('\n', ' ')
        .replaceAll('\t', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .split(' ')
        .where((String w) => w.isNotEmpty)
        .toList();
    final int n = words.length;
    if (n != 14 && n != 24 && n != 25 && n != 26) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(loc.tr('pages.wallet_select.restore.invalid_seed_words'))),
      );
      return;
    }
    if (_refreshType == 'height') {
      if (int.tryParse(_refreshHeight.text.trim()) == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(loc
                  .tr('pages.wallet_select.restore.invalid_restore_height'))),
        );
        return;
      }
    }
    if (_password.text != _passwordConfirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                loc.tr('pages.wallet_select.restore.passwords_dont_match'))),
      );
      return;
    }
    Future<void> send() async {
      AppLoading.show();
      await context
          .read<AppApi>()
          .send('wallet', 'restore_wallet', <String, dynamic>{
        'name': name,
        'seed': seedRaw,
        'refresh_type': _refreshType,
        'refresh_start_height': int.tryParse(_refreshHeight.text.trim()) ?? 0,
        'refresh_start_date': _refreshStartDate,
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
            label: loc.tr('pages.wallet_select.restore.account_name'),
            error: _nameTouched && _name.text.trim().isEmpty,
            child: TextField(
              controller: _name,
              decoration: InputDecoration(
                hintText: loc
                    .tr('pages.wallet_select.restore.wallet_name_placeholder'),
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label: loc.tr('pages.wallet_select.restore.mnemonic_seed'),
            error: _seedTouched && _seed.text.trim().isEmpty,
            child: TextField(
              controller: _seed,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: loc.tr(
                    'pages.wallet_select.restore.mnemonic_seed_placeholder'),
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _refreshType == 'date'
                    ? ArqmaField(
                        label:
                            loc.tr('pages.wallet_select.restore.restore_date'),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(_refreshStartDate),
                            ),
                            IconButton(
                              icon: const Icon(Icons.calendar_today),
                              onPressed: () => _pickDate(loc),
                            ),
                          ],
                        ),
                      )
                    : ArqmaField(
                        label: loc.tr(
                            'pages.wallet_select.restore.restore_from_block_height_label'),
                        child: TextField(
                          controller: _refreshHeight,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(border: InputBorder.none),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              if (_refreshType == 'date')
                ElevatedButton(
                  onPressed: () => setState(() => _refreshType = 'height'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4caf50),
                    foregroundColor: Colors.black87,
                  ),
                  child: Text(
                      loc.tr(
                          'pages.wallet_select.restore.switch_to_height_select'),
                      textAlign: TextAlign.center),
                )
              else
                ElevatedButton(
                  onPressed: () => setState(() => _refreshType = 'date'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4caf50),
                    foregroundColor: Colors.black87,
                  ),
                  child: Text(
                      loc.tr(
                          'pages.wallet_select.restore.switch_to_date_select'),
                      textAlign: TextAlign.center),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label: loc.tr('pages.wallet_select.restore.password_label'),
            child: TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                hintText: loc.tr('pages.wallet_select.restore.password'),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _restore(),
            ),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label: loc.tr('pages.wallet_select.restore.confirm_password'),
            child: TextField(
              controller: _passwordConfirm,
              obscureText: true,
              decoration: const InputDecoration(border: InputBorder.none),
              onSubmitted: (_) => _restore(),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _restore,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4caf50),
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(loc.tr('pages.wallet_select.restore.restore_account')),
          ),
        ],
      ),
    );
  }
}
