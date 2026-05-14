import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_api.dart';
import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/arqma_field.dart';
import '../../widgets/password_dialogs.dart';

/// Parity with `pages/wallet/send.vue`.
class SendPage extends StatefulWidget {
  const SendPage({super.key});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _paymentId = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _abName = TextEditingController();
  final TextEditingController _abDesc = TextEditingController();
  bool _saveToBook = false;

  StreamSubscription<Map<String, dynamic>>? _txSub;
  String _lastSendRouteQuerySig = '';

  @override
  void initState() {
    super.initState();
    _txSub = context
        .read<AppApi>()
        .bridge
        .backendReceive
        .listen((Map<String, dynamic> msg) {
      if (msg['event'] == 'set_tx_status') {
        _handleTx(Map<String, dynamic>.from(msg['data'] as Map));
      }
    });
  }

  @override
  void dispose() {
    _txSub?.cancel();
    try {
      final GatewayStore s = context.read<GatewayStore>();
      final Map<String, dynamic> st = Map<String, dynamic>.from(
          s.raw['tx_status'] as Map? ?? <String, dynamic>{});
      if (st['sending'] == true) {
        s.setTxStatus(
            <String, dynamic>{'code': 0, 'message': '', 'sending': false});
        AppLoading.hide();
      }
    } catch (_) {}
    _amount.dispose();
    _address.dispose();
    _paymentId.dispose();
    _note.dispose();
    _abName.dispose();
    _abDesc.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final GoRouterState r = GoRouterState.of(context);
    if (r.uri.path != '/wallet/send') {
      return;
    }
    final Map<String, String> q = r.uri.queryParameters;
    final String sig = r.uri.toString();
    if (sig == _lastSendRouteQuerySig) {
      return;
    }
    _lastSendRouteQuerySig = sig;
    final String? addr = q['address'];
    if (addr != null && addr.isNotEmpty) {
      _address.text = addr;
    }
    if (q.containsKey('payment_id')) {
      _paymentId.text = (q['payment_id'] ?? '').trim();
    } else if (q.containsKey('paymentId')) {
      _paymentId.text = (q['paymentId'] ?? '').trim();
    }
  }

  static bool _validPaymentId(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) {
      return true;
    }
    final RegExp hex = RegExp(r'^[0-9A-Fa-f]+$');
    return hex.hasMatch(s) && (s.length == 16 || s.length == 64);
  }

  Future<void> _handleTx(Map<String, dynamic> st) async {
    if (!mounted) {
      return;
    }
    if ('${st['origin']}' == 'wallet_settings') {
      return;
    }
    final LocaleController loc = context.read<LocaleController>();
    final int code = st['code'] as int? ?? 0;
    final String message = '${st['message'] ?? ''}';
    if (code == 200) {
      final int parts =
          (st['transfer_split_parts'] as num?)?.toInt() ?? 1;
      final bool isSplit = st['transfer_split_is_split'] == true || parts > 1;
      final bool under1000 =
          st['transfer_split_any_part_under_1000_arq'] == true;
      final int minAtoms =
          (st['transfer_split_min_part_atoms'] as num?)?.toInt() ?? 0;
      final double minArq = minAtoms / 1e9;
      final String minArqStr = minArq.toStringAsFixed(9);
      await showDialog<void>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          title: Text(loc.tr('pages.wallet.send.tx_status_title')),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message),
                if (isSplit) ...[
                  const SizedBox(height: 12),
                  Text(
                    loc.tr('pages.wallet.send.split_fee_parts_info',
                        named: <String, String>{'n': '$parts'}),
                  ),
                  if (st['transfer_split_part_amounts_arq'] is List &&
                      (st['transfer_split_part_amounts_arq'] as List)
                          .isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(loc.tr('pages.wallet.send.split_fee_parts_amounts_intro')),
                    const SizedBox(height: 8),
                    ...List<Widget>.generate(
                      (st['transfer_split_part_amounts_arq'] as List).length,
                      (int i) {
                        final Object? raw =
                            (st['transfer_split_part_amounts_arq'] as List)[i];
                        final String amt = '$raw';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            loc.tr(
                              'pages.wallet.send.split_fee_part_amount_line',
                              named: <String, String>{
                                'index': '${i + 1}',
                                'amount': amt,
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
                if (under1000) ...[
                  const SizedBox(height: 12),
                  Text(
                    loc.tr('pages.wallet.send.split_fee_under_1000',
                        named: <String, String>{'min': minArqStr}),
                  ),
                  const SizedBox(height: 8),
                  Text(loc.tr('pages.wallet.send.split_fee_sweep_hint')),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                context.read<AppApi>().send('wallet', 'cancelTransaction',
                    <String, dynamic>{'type': 'transfer_split'});
              },
              child: Text(loc.tr('pages.wallet.send.tx_status_cancel_label')),
            ),
            if (under1000)
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  context.read<AppApi>().send('wallet', 'cancelTransaction',
                      <String, dynamic>{'type': 'transfer_split'});
                  GoRouter.of(context).go('/wallet');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          loc.tr('pages.wallet.send.split_fee_sweep_snackbar')),
                    ),
                  );
                },
                child: Text(
                    loc.tr('pages.wallet.send.tx_status_sweep_all_label')),
              ),
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                context
                    .read<AppApi>()
                    .send('wallet', 'relay_transfer', <String, dynamic>{});
              },
              child: Text(loc.tr('pages.wallet.send.tx_status_ok_label')),
            ),
          ],
        ),
      );
    } else if (code == 201) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      setState(() {
        _amount.clear();
        _address.clear();
        _paymentId.clear();
        _note.clear();
        _abName.clear();
        _abDesc.clear();
        _saveToBook = false;
      });
    } else if (code == -200) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  bool _validate(LocaleController loc, GatewayStore store) {
    final num unlocked =
        num.tryParse('${store.walletInfo['unlocked_balance'] ?? 0}') ?? 0;
    final double maxArq = unlocked / 1e9;
    final double? amt = double.tryParse(_amount.text.trim());
    final String addr = _address.text.trim();
    if ((amt == null || amt <= 0 || amt > maxArq) && addr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(loc.tr('pages.wallet.send.invalid_amount_address'))));
      return false;
    }
    if (amt == null || amt < 0.0001 || amt > maxArq) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.tr('pages.wallet.send.invalid_amount'))));
      return false;
    }
    if (addr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.tr('pages.wallet.send.invalid_address'))));
      return false;
    }
    if (!_validPaymentId(_paymentId.text)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(loc.tr('pages.wallet.send.invalid_payment_id'))));
      return false;
    }
    return true;
  }

  Future<void> _send() async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final GatewayStore store = context.read<GatewayStore>();
    if (!_validate(loc, store)) {
      return;
    }
    final String? pw = await PasswordDialogs.showPasswordConfirmation(
      context: context,
      api: api,
      locale: loc,
      title: loc.tr('pages.wallet.send.show_password_confirmation_title'),
      noPasswordMessage:
          loc.tr('pages.wallet.send.show_password_confirmation_message'),
      okLabel: loc.tr('pages.wallet.send.show_password_confirmation_ok_label'),
    );
    if (pw == null) {
      return;
    }
    final Map<String, dynamic> copy = <String, dynamic>{
      'amount': _amount.text.trim(),
      'address': _address.text.trim(),
      'payment_id': _paymentId.text.trim(),
      'priority': 0,
      'currency': 0,
      'note': _note.text,
      'address_book': <String, dynamic>{
        'save': _saveToBook,
        'name': _abName.text,
        'description': _abDesc.text,
      },
      'password': pw,
    };
    store.setTxStatus(
        <String, dynamic>{'code': 0, 'message': '', 'sending': true});
    await AppLoading.show();
    // Native `transfer_split` blocks this isolate until Rust returns — yield so the
    // loading overlay and spinner can paint at least one frame before the long FFI call.
    if (mounted) {
      await WidgetsBinding.instance.endOfFrame;
    }
    await api.send('wallet', 'transfer', copy);
    AppLoading.hide();
    store.setTxStatus(
        <String, dynamic>{'code': 0, 'message': '', 'sending': false});
  }

  void _all() {
    final GatewayStore store = context.read<GatewayStore>();
    final num u =
        num.tryParse('${store.walletInfo['unlocked_balance'] ?? 0}') ?? 0;
    setState(() => _amount.text = '${u / 1e9}');
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final bool viewOnly = store.walletInfo['view_only'] == true;
    final String prefix =
        (store.walletInfo['address']?.toString().isNotEmpty == true)
            ? store.walletInfo['address'].toString().substring(0, 1)
            : 'L';
    final Map<String, dynamic> txStatus =
        store.raw['tx_status'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final bool sending = txStatus['sending'] == true;

    if (viewOnly) {
      return Center(child: Text(loc.tr('pages.wallet.send.view_only_mode')));
    }

    final bool narrow = MediaQuery.sizeOf(context).width < 640;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Match `send.vue`: amount + address row (stack on narrow viewports like Quasar col-6).
            if (narrow)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ArqmaField(
                    label: loc.tr('pages.wallet.send.amount'),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amount,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                hintText: '0', border: InputBorder.none),
                          ),
                        ),
                        TextButton(
                            onPressed: _all,
                            child: Text(loc.tr('pages.wallet.send.all'))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ArqmaField(
                    label: loc.tr('pages.wallet.send.address'),
                    disableMenu: false,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _address,
                            decoration: InputDecoration(
                                hintText: '$prefix..',
                                border: InputBorder.none),
                          ),
                        ),
                        TextButton(
                            onPressed: () =>
                                context.push('/wallet/addressbook'),
                            child: Text(loc.tr('pages.wallet.send.contacts'))),
                      ],
                    ),
                  ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ArqmaField(
                      label: loc.tr('pages.wallet.send.amount'),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _amount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  hintText: '0', border: InputBorder.none),
                            ),
                          ),
                          TextButton(
                              onPressed: _all,
                              child: Text(loc.tr('pages.wallet.send.all'))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ArqmaField(
                      label: loc.tr('pages.wallet.send.address'),
                      disableMenu: false,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _address,
                              decoration: InputDecoration(
                                  hintText: '$prefix..',
                                  border: InputBorder.none),
                            ),
                          ),
                          TextButton(
                              onPressed: () =>
                                  context.push('/wallet/addressbook'),
                              child:
                                  Text(loc.tr('pages.wallet.send.contacts'))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            // Vue template: notes next, then optional address-book name/description when save is on.
            ArqmaField(
              label: loc.tr('pages.wallet.send.notes'),
              optional: true,
              disableMenu: false,
              child: TextField(
                controller: _note,
                maxLines: 4,
                decoration: InputDecoration(
                    hintText: loc.tr('pages.wallet.send.notes_placeholder'),
                    border: InputBorder.none),
              ),
            ),
            ArqmaField(
              label: loc.tr('pages.wallet.send.payment_id'),
              optional: true,
              disableMenu: false,
              child: TextField(
                controller: _paymentId,
                decoration: InputDecoration(
                  hintText: loc.tr('pages.wallet.send.payment_id_hint'),
                  border: InputBorder.none,
                ),
              ),
            ),
            if (_saveToBook) ...[
              ArqmaField(
                label: loc.tr('pages.wallet.send.name'),
                optional: true,
                child: TextField(
                  controller: _abName,
                  decoration: InputDecoration(
                      hintText: loc.tr('pages.wallet.send.name_placeholder'),
                      border: InputBorder.none),
                ),
              ),
              ArqmaField(
                label: loc.tr('pages.wallet.send.notes'),
                optional: true,
                child: TextField(
                  controller: _abDesc,
                  maxLines: 2,
                  decoration: InputDecoration(
                      hintText: loc
                          .tr('pages.wallet.send.additional_notes_placeholder'),
                      border: InputBorder.none),
                ),
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Checkbox(
                  value: _saveToBook,
                  onChanged: (bool? v) =>
                      setState(() => _saveToBook = v ?? false),
                ),
                Text(loc.tr('pages.wallet.send.save_to_addressbook')),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: store.isAbleToSend && !sending ? _send : null,
                  child: Text(loc.tr('pages.wallet.send.send')),
                ),
              ],
            ),
          ],
        ),
        if (sending)
          Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(loc.tr('pages.wallet.send.calculating_fee')),
              ],
            ),
          ),
      ],
    );
  }
}
