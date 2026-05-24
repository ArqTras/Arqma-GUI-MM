import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_api.dart';
import '../../core/theme/arqma_colors.dart';
import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/arqma_field.dart';
import '../../widgets/format_arqma.dart';
import '../../widgets/password_dialogs.dart';
import '../../widgets/swap_signature_list.dart';

/// Parity with `pages/wallet/swap.vue` (disclaimers, network, connect/subscribe, tabs, list on native panel).
class SwapPage extends StatefulWidget {
  const SwapPage({super.key});

  @override
  State<SwapPage> createState() => _SwapPageState();
}

class _SwapPageState extends State<SwapPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs;
  int _netIndex = 0;
  bool _subscribed = false;

  final TextEditingController _ethAddress = TextEditingController();
  final TextEditingController _nativeAmount = TextEditingController();
  final TextEditingController _nativeMemo = TextEditingController();
  final TextEditingController _wrappedTokenAmount = TextEditingController();
  final TextEditingController _wrappedTokenAddress = TextEditingController();
  final TextEditingController _wrappedArqAddress = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_subscribed) {
      try {
        unawaited(
          context.read<AppApi>().send(
              'wallet', 'unsubscribe_for_signature_data', <String, dynamic>{}),
        );
      } catch (_) {
        // Context / Provider may be unavailable during teardown.
      }
    }
    _tabs.dispose();
    _ethAddress.dispose();
    _nativeAmount.dispose();
    _nativeMemo.dispose();
    _wrappedTokenAmount.dispose();
    _wrappedTokenAddress.dispose();
    _wrappedArqAddress.dispose();
    super.dispose();
  }

  bool _validEth0x(String s) {
    final String t = s.trim();
    return t.startsWith('0x') && t.length >= 42;
  }

  dynamic _walletNetworkCode(Map<String, dynamic> sel) {
    final dynamic c = sel['code'];
    if (c is int) {
      return c;
    }
    if (c is num) {
      return c.toInt();
    }
    final String s = '$c'.toLowerCase();
    if (s == 'eth' || s == 'ethereum') {
      return 0;
    }
    if (s == 'bnb' || s == 'bsc') {
      return 3;
    }
    return 0;
  }

  Future<void> _connectOrDisconnect(BuildContext context) async {
    final AppApi api = context.read<AppApi>();
    final LocaleController loc = context.read<LocaleController>();
    if (_subscribed) {
      await api.send(
          'wallet', 'unsubscribe_for_signature_data', <String, dynamic>{});
      if (mounted) {
        setState(() => _subscribed = false);
      }
      return;
    }
    if (!_validEth0x(_ethAddress.text)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.tr('pages.wallet.swap.invalid_address'))),
        );
      }
      return;
    }
    await AppLoading.show();
    await api.send('wallet', 'subscribe_for_signature_data', <String, dynamic>{
      'ethereumAddress': _ethAddress.text.trim().toLowerCase(),
    });
    AppLoading.hide();
    if (mounted) {
      setState(() {
        _subscribed = true;
        if (_wrappedTokenAddress.text.trim().isEmpty) {
          _wrappedTokenAddress.text = _ethAddress.text.trim();
        }
      });
    }
  }

  Future<void> _addAsset(BuildContext context) async {
    final LocaleController loc = context.read<LocaleController>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.tr('pages.wallet.swap.add_asset_web3_only'))),
    );
  }

  Future<void> _nativeSend(
    BuildContext context,
    LocaleController loc,
    GatewayStore store,
    Map<String, dynamic> selected,
  ) async {
    final AppApi api = context.read<AppApi>();
    final String gov = '${selected['governance'] ?? ''}'.trim();
    if (gov.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.tr('pages.wallet.swap.governance_missing'))),
      );
      return;
    }
    final num amt = num.tryParse(_nativeAmount.text.trim()) ?? 0;
    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.tr('pages.wallet.swap.invalid_amount'))),
      );
      return;
    }
    if (!_validEth0x(_nativeMemo.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.tr('pages.wallet.swap.invalid_address'))),
      );
      return;
    }
    final num u =
        num.tryParse('${store.walletInfo['unlocked_balance'] ?? 0}') ?? 0;
    if (amt > u / 1e9) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(loc.tr('pages.wallet.swap.not_enough_unlocked_balance'))),
      );
      return;
    }
    final String sym = '${selected['symbol'] ?? 'eXEQ'}';
    final String title = loc
        .tr('pages.wallet.swap.show_password_confirmation_title')
        .replaceAll('eXEQ', sym);
    final String? pw = await PasswordDialogs.showPasswordConfirmation(
      context: context,
      api: api,
      locale: loc,
      title: title,
      noPasswordMessage:
          loc.tr('pages.wallet.swap.show_password_confirmation_message'),
      okLabel: loc.tr('pages.wallet.swap.show_password_confirmation_ok_label'),
    );
    if (pw == null || !context.mounted) {
      return;
    }
    final Map<String, dynamic> copy = <String, dynamic>{
      'amount': _nativeAmount.text.trim(),
      'memo': _nativeMemo.text.trim(),
      'address': gov,
      'currency': 0,
      'network': <String, dynamic>{'code': _walletNetworkCode(selected)},
      'payment_id': '',
      'priority': 0,
      'note': '',
      'address_book': <String, dynamic>{
        'save': false,
        'name': '',
        'description': ''
      },
      'password': pw,
    };
    store.setTxStatus(<String, dynamic>{
      'code': 1,
      'message':
          loc.tr('pages.wallet.swap.show_password_confirmation_ok_message'),
      'sending': true,
    });
    await AppLoading.show();
    await api.send('wallet', 'transfer', copy);
    AppLoading.hide();
    store.setTxStatus(
        <String, dynamic>{'code': 0, 'message': '', 'sending': false});
  }

  Future<void> _wrappedSend(BuildContext context) async {
    final loc = context.read<LocaleController>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(loc.tr('pages.wallet.swap.web3_signing_not_available'))),
    );
  }

  Future<void> _onSwapListAction(
      BuildContext context, Map<String, dynamic> _) async {
    final loc = context.read<LocaleController>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(loc.tr('pages.wallet.swap.web3_signing_not_available'))),
    );
  }

  void _nativeAll(GatewayStore store) {
    final num u =
        num.tryParse('${store.walletInfo['unlocked_balance'] ?? 0}') ?? 0;
    setState(() => _nativeAmount.text = '${u / 1e9}');
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final bool viewOnly = store.walletInfo['view_only'] == true;
    final Map<String, dynamic> eth = Map<String, dynamic>.from(
        store.raw['ethereum'] as Map? ?? <String, dynamic>{});
    final List<dynamic> nets =
        eth['networks'] as List<dynamic>? ?? const <dynamic>[];
    if (nets.isNotEmpty && _netIndex >= nets.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _netIndex = 0);
        }
      });
    }
    final Map<String, dynamic> selected = nets.isEmpty
        ? <String, dynamic>{'name': '—', 'symbol': '—'}
        : Map<String, dynamic>.from(
            nets[_netIndex.clamp(0, nets.isEmpty ? 0 : nets.length - 1)]
                as Map);

    if (_wrappedArqAddress.text.isEmpty &&
        '${store.walletInfo['address'] ?? ''}'.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _wrappedArqAddress.text.isEmpty) {
          _wrappedArqAddress.text = store.walletInfo['address'].toString();
        }
      });
    }

    final String connectLabel = _subscribed
        ? loc.tr('pages.wallet.swap.connected_wallet')
        : loc.tr('pages.wallet.swap.connect_wallet');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ${loc.tr('pages.wallet.swap.disclaimer1')}'),
              Text('• ${loc.tr('pages.wallet.swap.disclaimer2')}'),
              Text(
                  '• ${loc.tr('pages.wallet.swap.disclaimer3')} ${loc.tr('pages.wallet.swap.disclaimer4')}'),
              Text('• ${loc.tr('pages.wallet.swap.disclaimer5')}'),
            ],
          ),
        ),
        if (viewOnly)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(loc.tr('pages.wallet.swap.view_only')),
          )
        else
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ArqmaField(
                    label: loc.tr('pages.wallet.swap.ethereum_address_hint'),
                    child: TextField(
                      controller: _ethAddress,
                      enabled: !_subscribed,
                      style: const TextStyle(color: ArqmaColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: '0x…',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () => _connectOrDisconnect(context),
                        child: Text(connectLabel),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed:
                            !_subscribed ? null : () => _addAsset(context),
                        child: Text(
                            loc.tr('pages.wallet.swap.add_asset_to_wallet')),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ArqmaField(
                    label: loc.tr('pages.wallet.swap.network'),
                    child: Row(
                      children: [
                        Text('${selected['name']} (${selected['symbol']})'),
                        const Spacer(),
                        if (nets.isNotEmpty)
                          PopupMenuButton<int>(
                            onSelected: (int i) =>
                                setState(() => _netIndex = i),
                            itemBuilder: (BuildContext c) =>
                                List<PopupMenuEntry<int>>.generate(
                              nets.length,
                              (int i) => PopupMenuItem<int>(
                                value: i,
                                child: Text('${(nets[i] as Map)['name']}'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('eXEQ balance: ',
                          style: TextStyle(fontSize: 12)),
                      const FormatArqma(amount: 0, digits: 4),
                      Text(' ${selected['symbol'] ?? ''}',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                TabBar(
                  controller: _tabs,
                  tabs: [
                    Tab(
                        text:
                            loc.tr('pages.wallet.swap.tab_native_to_wrapped')),
                    Tab(
                        text:
                            loc.tr('pages.wallet.swap.tab_wrapped_to_native')),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _nativeTab(context, loc, store, selected),
                      _wrappedTab(context, loc, store, selected),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _nativeTab(
    BuildContext context,
    LocaleController loc,
    GatewayStore store,
    Map<String, dynamic> selected,
  ) {
    final Map<String, dynamic> txStatus =
        store.raw['tx_status'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final bool sending = txStatus['sending'] == true;
    // Native tab: `.scroller` in `swap.vue` wraps the swap list — `max-height: viewport - 600px`.
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints bc) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      minWidth: bc.maxWidth >= 560 ? bc.maxWidth : 560),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        flex: 2,
                        child: ArqmaField(
                          label:
                              '${loc.tr('pages.wallet.swap.amount_of_xeq_to_swap')} ${selected['symbol']}',
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: TextField(
                                  controller: _nativeAmount,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  style: const TextStyle(
                                      color: ArqmaColors.textPrimary),
                                  decoration: const InputDecoration(
                                      hintText: '0',
                                      border: InputBorder.none,
                                      isDense: true),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _nativeAll(store),
                                child: Text(loc.tr('pages.wallet.send.all')),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: ArqmaField(
                          label:
                              '${selected['name']} ${loc.tr('pages.wallet.swap.address')}',
                          child: TextField(
                            controller: _nativeMemo,
                            style:
                                const TextStyle(color: ArqmaColors.textPrimary),
                            decoration: const InputDecoration(
                                hintText: '0x…',
                                border: InputBorder.none,
                                isDense: true),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 28),
                        child: ElevatedButton(
                          onPressed: store.isAbleToSend && !sending
                              ? () => _nativeSend(context, loc, store, selected)
                              : null,
                          child: Text(loc.tr('pages.wallet.swap.send')),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext ctx, BoxConstraints inner) {
                final double viewportH = MediaQuery.sizeOf(ctx).height;
                final double capByVue = (viewportH - 600).clamp(150.0, 9000.0);
                final double maxListH = math.min(inner.maxHeight, capByVue);
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxListH),
                  child: SwapSignatureList(
                    onActionTap: (Map<String, dynamic> m) =>
                        _onSwapListAction(context, m),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrappedTab(
    BuildContext context,
    LocaleController loc,
    GatewayStore store,
    Map<String, dynamic> selected,
  ) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints bc) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minWidth: bc.maxWidth >= 720 ? bc.maxWidth : 720),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: ArqmaField(
                        label: '${loc.tr('pages.wallet.swap.amount_of')} eXEQ',
                        child: TextField(
                          controller: _wrappedTokenAmount,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style:
                              const TextStyle(color: ArqmaColors.textPrimary),
                          decoration: const InputDecoration(
                              hintText: '0',
                              border: InputBorder.none,
                              isDense: true),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ArqmaField(
                        label:
                            '${selected['name']} ${loc.tr('pages.wallet.swap.address')}',
                        child: TextField(
                          controller: _wrappedTokenAddress,
                          enabled: !_subscribed,
                          style:
                              const TextStyle(color: ArqmaColors.textPrimary),
                          decoration: const InputDecoration(
                              hintText: '0x…',
                              border: InputBorder.none,
                              isDense: true),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: ArqmaField(
                        label: 'ARQ ${loc.tr('pages.wallet.swap.address')}',
                        child: TextField(
                          controller: _wrappedArqAddress,
                          style:
                              const TextStyle(color: ArqmaColors.textPrimary),
                          decoration: const InputDecoration(
                              hintText: 'Tw…',
                              border: InputBorder.none,
                              isDense: true),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 28),
                      child: ElevatedButton(
                        onPressed:
                            _subscribed ? () => _wrappedSend(context) : null,
                        child: Text(loc.tr('pages.wallet.swap.send')),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
