import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/app_api.dart';
import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
import '../../widgets/arqma_field.dart';
import '../../widgets/password_dialogs.dart';

/// Parity with `pages/wallet/staking-pools.vue` + `components/pool_list_tabular.vue`.
class StakingPoolsPage extends StatefulWidget {
  const StakingPoolsPage({super.key});

  @override
  State<StakingPoolsPage> createState() => _StakingPoolsPageState();
}

class _StakingPoolsPageState extends State<StakingPoolsPage> with WidgetsBindingObserver {
  bool _started = false;
  AppApi? _api;
  GatewayStore? _store;
  StreamSubscription<Map<String, dynamic>>? _bridgeSub;

  static const double _coinUnits = 1e9;
  static const int _minStakeArq = 100;

  static const List<Map<String, dynamic>> _nodeFilterOptions = <Map<String, dynamic>>[
    <String, dynamic>{'index': 0, 'label': 'pages.wallet.staking_pools.all', 'description': 'pages.wallet.staking_pools.all_description'},
    <String, dynamic>{'index': 1, 'label': 'pages.wallet.staking_pools.open', 'description': 'pages.wallet.staking_pools.open_description'},
    <String, dynamic>{'index': 2, 'label': 'pages.wallet.staking_pools.closed', 'description': 'pages.wallet.staking_pools.closed_description'},
    <String, dynamic>{'index': 3, 'label': 'pages.wallet.staking_pools.operator', 'description': 'pages.wallet.staking_pools.operator_description'},
    <String, dynamic>{'index': 4, 'label': 'pages.wallet.staking_pools.contributor', 'description': 'pages.wallet.staking_pools.contributor_description'},
  ];

  late final TextEditingController _nodeId;
  late final TextEditingController _operatorId;
  Timer? _debounceNode;
  Timer? _debounceOp;
  Timer? _uptimeTick;

  static double _round2(num v) => double.parse((v + 1e-12).toStringAsFixed(2));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nodeId = TextEditingController();
    _operatorId = TextEditingController();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    _api = context.read<AppApi>();
    _store = context.read<GatewayStore>();
    _bridgeSub = _api!.bridge.backendReceive.listen(_onBackendMessage);
    unawaited(_api!.send('wallet', 'begin_Stake_Acquisition', <String, dynamic>{}));
    unawaited(_api!.send('wallet', 'get_coin_price', <String, dynamic>{}));
    _bootstrapPoolsFilterFromStore();
    final Map<String, dynamic>? nid = _store!.raw['node_id_filter'] as Map<String, dynamic>?;
    final Map<String, dynamic>? oid = _store!.raw['operator_id_filter'] as Map<String, dynamic>?;
    if (nid?['value'] != null && '${nid!['value']}'.isNotEmpty) {
      _nodeId.text = '${nid['value']}';
    }
    if (oid?['value'] != null && '${oid!['value']}'.isNotEmpty) {
      _operatorId.text = '${oid['value']}';
    }
    setState(() {});
    _uptimeTick?.cancel();
    _uptimeTick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// Parity with `staking-pools.vue` `onBeforeMount` — only standard filter indices 0–4; resolve label to canonical option.
  void _bootstrapPoolsFilterFromStore() {
    final GatewayStore s = _store!;
    final Map<String, dynamic> pf = Map<String, dynamic>.from(s.raw['pools_filter'] as Map? ?? <String, dynamic>{});
    final int idx = pf['index'] as int? ?? 1;
    const Set<int> standard = <int>{0, 1, 2, 3, 4};
    if (!standard.contains(idx)) {
      s.setPoolsFilterState(Map<String, dynamic>.from(_nodeFilterOptions[1]));
      return;
    }
    final String? label = pf['label'] as String?;
    Map<String, dynamic>? canonical;
    if (label != null && label.isNotEmpty) {
      for (final Map<String, dynamic> o in _nodeFilterOptions) {
        if (o['label'] == label) {
          canonical = Map<String, dynamic>.from(o);
          break;
        }
      }
    }
    if (canonical == null) {
      Map<String, dynamic>? byIndex;
      for (final Map<String, dynamic> o in _nodeFilterOptions) {
        if (o['index'] == idx) {
          byIndex = Map<String, dynamic>.from(o);
          break;
        }
      }
      canonical = byIndex ?? Map<String, dynamic>.from(_nodeFilterOptions[1]);
    }
    if (canonical['index'] != idx || canonical['label'] != pf['label']) {
      s.setPoolsFilterState(canonical);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceNode?.cancel();
    _debounceOp?.cancel();
    _uptimeTick?.cancel();
    _bridgeSub?.cancel();
    _nodeId.dispose();
    _operatorId.dispose();
    _store?.resetPoolsData();
    if (_api != null) {
      unawaited(_api!.send('wallet', 'end_Stake_Acquisition', <String, dynamic>{}));
    }
    super.dispose();
  }

  void _onBackendMessage(Map<String, dynamic> msg) {
    if (!mounted) {
      return;
    }
    final String? ev = msg['event'] as String?;
    if (ev == 'set_tx_status') {
      final Map<String, dynamic> d = Map<String, dynamic>.from(msg['data'] as Map? ?? <String, dynamic>{});
      final int code = d['code'] as int? ?? 0;
      if (code == 300 || code == -300) {
        unawaited(_handleStakeTxStatus(d));
      }
    } else if (ev == 'set_snode_status_unlock') {
      final Map<String, dynamic> d = Map<String, dynamic>.from(msg['data'] as Map? ?? <String, dynamic>{});
      unawaited(_handleUnlockStatus(d));
    }
  }

  Future<void> _handleStakeTxStatus(Map<String, dynamic> st) async {
    final LocaleController loc = context.read<LocaleController>();
    final int code = st['code'] as int? ?? 0;
    final String message = '${st['message'] ?? ''}';
    if (code == 300) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          title: Text(loc.tr('components.pool_list_tabular.tx_status_title')),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(loc.tr('components.pool_list_tabular.tx_status_cancel_label')),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                context.read<AppApi>().send('wallet', 'relay_stake', <String, dynamic>{});
              },
              child: Text(loc.tr('components.pool_list_tabular.tx_status_ok_label')),
            ),
          ],
        ),
      );
    } else if (code == -300) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _handleUnlockStatus(Map<String, dynamic> d) async {
    final int code = d['code'] as int? ?? 0;
    final String message = '${d['message'] ?? ''}';
    if (code == 0 && message.isEmpty) {
      return;
    }
    if (code == 400) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message.isEmpty ? 'OK' : message)));
    } else if (code == -400) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red.shade900, content: Text(message.isEmpty ? 'Error' : message)));
    }
  }

  Map<String, dynamic> _currentPoolsFilter(GatewayStore store) {
    return Map<String, dynamic>.from(store.raw['pools_filter'] as Map? ?? _nodeFilterOptions[1]);
  }

  void _pushNodeFilter() {
    _debounceNode?.cancel();
    _debounceNode = Timer(const Duration(milliseconds: 120), () {
      _store?.setNodeIdFilterState(<String, dynamic>{'index': 3, 'label': 'Transaction', 'value': _nodeId.text.trim()});
    });
  }

  void _pushOperatorFilter() {
    _debounceOp?.cancel();
    _debounceOp = Timer(const Duration(milliseconds: 120), () {
      _store?.setOperatorIdFilterState(<String, dynamic>{'index': 4, 'label': 'Operator', 'value': _operatorId.text.trim()});
    });
  }

  List<Map<String, dynamic>> _addressBookEntries(GatewayStore store) {
    final List<dynamic> ab =
        ((store.wallet['address_list'] as Map?)?['address_book'] as List<dynamic>?) ?? const <dynamic>[];
    return ab.map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  String _poolTypeLabel(LocaleController loc, Map<String, dynamic> item) {
    final num tc = num.tryParse('${item['total_contributed'] ?? 0}') ?? 0;
    final num sr = num.tryParse('${item['staking_requirement'] ?? 0}') ?? 0;
    final String status = tc < sr ? loc.tr('pages.wallet.staking_pools.open') : loc.tr('pages.wallet.staking_pools.closed');
    if (item['is_operator'] == true) {
      return '$status / ${loc.tr('components.pool_list_tabular.operator')}';
    }
    if (item['is_contributor'] == true) {
      return '$status / ${loc.tr('components.pool_list_tabular.contributor')}';
    }
    return status;
  }

  /// Parity with `pool_list_tabular.vue` `<timeago :datetime="…" :auto-update="60" />`.
  String _relativeUptime(LocaleController loc, int unixSec) {
    if (unixSec <= 0) {
      return loc.tr('components.pool_list_tabular.notreceived');
    }
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000, isUtc: true).toLocal();
    return timeago.format(dt, locale: _timeagoLocaleFor(loc), allowFromNow: true);
  }

  static String _timeagoLocaleFor(LocaleController loc) {
    final String primary = loc.locale.split('-').first.toLowerCase();
    switch (primary) {
      case 'pl':
        return 'pl';
      case 'fr':
        return 'fr';
      case 'es':
        return 'es';
      case 'de':
        return 'de';
      case 'ru':
        return 'ru';
      case 'pt':
        return 'pt_BR';
      case 'ja':
      case 'jp':
        return 'ja';
      case 'zh':
      case 'cn':
        return 'zh_CN';
      default:
        return 'en';
    }
  }

  static String _formatSpotUsd(num price) {
    if (price <= 0) {
      return '';
    }
    final NumberFormat f = NumberFormat.decimalPattern()
      ..minimumFractionDigits = 2
      ..maximumFractionDigits = 6;
    return f.format(price);
  }

  String? _fiatUsdApprox(LocaleController loc, num coinPrice, Object? arqDisplay) {
    if (coinPrice <= 0) {
      return null;
    }
    final num n = num.tryParse('${arqDisplay ?? 0}'.toString().replaceAll(',', '')) ?? 0;
    if (!n.isFinite || n <= 0) {
      return null;
    }
    final String usd = (n * coinPrice).toStringAsFixed(2);
    return loc.tr('components.pool_list_tabular.fiat_usd_approx', named: {'amount': usd});
  }

  Future<void> _copyNodeId(String nodeId) async {
    await context.read<AppApi>().writeText(nodeId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.read<LocaleController>().tr('components.pool_list_tabular.copied_oracle_nodeid_to_clipboard'))),
    );
  }

  Future<void> _openExplorer(String nodeId) async {
    await context.read<AppApi>().send('core', 'open_explorer', <String, dynamic>{'type': 'service_node', 'id': nodeId});
  }

  Future<void> _addOperatorToBook(Map<String, dynamic> item) async {
    final LocaleController loc = context.read<LocaleController>();
    final String addr = '${item['operator_address'] ?? ''}';
    if (addr.isEmpty) {
      return;
    }
    final int r = math.Random().nextInt(50001);
    await context.read<AppApi>().send('wallet', 'add_address_book', <String, dynamic>{
      'address': addr,
      'description': loc.tr('components.pool_list_tabular.favourite_operator'),
      'name': 'service_node_operator$r',
      'starred': true,
    });
  }

  Future<void> _deregisterNode(String nodeId) async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final String? password = await PasswordDialogs.showPasswordConfirmation(
      context: context,
      api: api,
      locale: loc,
      title: loc.tr('components.pool_list_tabular.deregister_service_node_title'),
      noPasswordMessage: loc.tr('components.pool_list_tabular.deregister_service_node_message'),
      okLabel: loc.tr('components.pool_list_tabular.deregister_service_node_ok_label'),
    );
    if (password == null || !mounted) {
      return;
    }
    await api.send('wallet', 'unlock_stake', <String, dynamic>{
      'password': password,
      'service_node_key': nodeId,
      'confirmed': true,
    });
  }

  double _maxStakeArq(Map<String, dynamic> item) {
    final num req = num.tryParse('${item['staking_requirement'] ?? 0}') ?? 0;
    final num tc = num.tryParse('${item['total_contributed'] ?? 0}') ?? 0;
    final double left = (req - tc) / _coinUnits;
    if (!left.isFinite || left < 0) {
      return 0;
    }
    return left;
  }

  Future<void> _openStakeDialog(Map<String, dynamic> item) async {
    final double maxArq = _maxStakeArq(item);
    if (maxArq <= 0) {
      return;
    }
    if (maxArq < _minStakeArq) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<LocaleController>().tr('components.pool_list_tabular.invalid_stake_amount'))),
      );
      return;
    }
    final LocaleController loc = context.read<LocaleController>();
    final GatewayStore store = context.read<GatewayStore>();
    final AppApi api = context.read<AppApi>();
    final String oracleKey = '${item['service_node_pubkey'] ?? ''}';
    final num unlockedAtoms = num.tryParse('${store.walletInfo['unlocked_balance'] ?? 0}') ?? 0;
    final double unlockedArq = unlockedAtoms / _coinUnits;
    final double cap = maxArq < unlockedArq ? maxArq : unlockedArq;
    final TextEditingController amount = TextEditingController(text: '${_minStakeArq > cap ? cap.toStringAsFixed(0) : _minStakeArq}');

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(loc.tr('components.pool_list_tabular.confirm_amount_to_stake')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.tr('components.pool_list_tabular.oracle_id')),
                SelectableText(oracleKey, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Text('${loc.tr('components.pool_list_tabular.max_amount')}${cap.toStringAsFixed(9)}'),
                Text('${loc.tr('components.pool_list_tabular.min_amount')}$_minStakeArq'),
                const SizedBox(height: 8),
                ArqmaField(
                  label: loc.tr('components.pool_list_tabular.amount'),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: amount,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(border: InputBorder.none, hintText: '100'),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          amount.text = cap.toStringAsFixed(9).replaceAll(RegExp(r'\.?0+$'), '');
                          if (amount.text.isEmpty) {
                            amount.text = cap.toStringAsFixed(0);
                          }
                        },
                        child: const Text('Max'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.tr('composables.cancel'))),
            if (unlockedArq >= _minStakeArq)
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(loc.tr('components.pool_list_tabular.confirm_stake')),
              )
            else
              TextButton(onPressed: null, child: Text(loc.tr('components.pool_list_tabular.not_enough_coins'))),
          ],
        );
      },
    );
    if (ok != true || !mounted) {
      amount.dispose();
      return;
    }
    final double? parsed = double.tryParse(amount.text.trim().replaceAll(',', ''));
    amount.dispose();
    if (parsed == null || parsed < _minStakeArq || parsed > cap) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.tr('components.pool_list_tabular.invalid_stake_amount'))));
      return;
    }
    if ((parsed - parsed.round()).abs() > 1e-6) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.tr('components.pool_list_tabular.invalid_stake_amount'))));
      return;
    }
    final String? password = await PasswordDialogs.showPasswordConfirmation(
      context: context,
      api: api,
      locale: loc,
      title: loc.tr('components.pool_list_tabular.show_password_confirmation_title'),
      noPasswordMessage: loc.tr('components.pool_list_tabular.show_password_confirmation_message'),
      okLabel: loc.tr('components.pool_list_tabular.show_password_confirmation_ok_label'),
    );
    if (password == null || !mounted) {
      return;
    }
    await api.send('wallet', 'stake', <String, dynamic>{
      'password': password,
      'amount': parsed,
      'key': oracleKey,
      'destination': '${store.walletInfo['address'] ?? ''}',
    });
  }

  Widget _lockupHeader(LocaleController loc, Map<String, dynamic> lockup) {
    final String amount = '${lockup['amount'] ?? ''}';
    if (amount.isEmpty) {
      return Text(loc.tr('components.pool_list_tabular.lock_up'));
    }
    return Text(loc.tr('components.pool_list_tabular.expiring'));
  }

  String _lockupSub(LocaleController loc, Map<String, dynamic> lockup) {
    final String amount = '${lockup['amount'] ?? ''}';
    final String i18nKey = '${lockup['i18n'] ?? ''}';
    if (amount.isEmpty) {
      return '';
    }
    if (i18nKey.isNotEmpty) {
      return '$amount ${loc.tr(i18nKey)}';
    }
    return amount;
  }

  Widget _poolCard({
    required LocaleController loc,
    required GatewayStore store,
    required Map<String, dynamic> item,
    required bool operatorSection,
  }) {
    final String pubkey = '${item['service_node_pubkey'] ?? ''}';
    final Map<String, dynamic> lockup = Map<String, dynamic>.from(item['lockup'] as Map? ?? <String, dynamic>{});
    final int lastProof = (num.tryParse('${item['last_uptime_proof'] ?? 0}') ?? 0).toInt();
    final num price = store.coinPrice;
    final num reqUnlock = num.tryParse('${item['requested_unlock_height'] ?? 0}') ?? 0;
    final bool canDeregisterOperator = operatorSection && item['is_operator'] == true && reqUnlock == 0;
    final bool canDeregisterContributor = !operatorSection && item['is_contributor'] == true && reqUnlock == 0;
    final double maxStake = _maxStakeArq(item);
    final bool canTapStake = !operatorSection && maxStake > 0;
    final String? fiatStaked = _fiatUsdApprox(loc, price, item['staked']);
    final String? fiatAvail = _fiatUsdApprox(loc, price, item['available']);

    return Card(
      color: const Color(0xFF1a1a1a),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: canTapStake ? () => _openStakeDialog(item) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_poolTypeLabel(loc, item), style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 4),
                    Text(loc.tr('components.pool_list_tabular.oracle_node_id'), style: Theme.of(context).textTheme.labelSmall),
                    SelectableText(pubkey, style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 6),
                    _kv(loc.tr('components.pool_list_tabular.stakers'),
                        NumberFormat.decimalPattern().format(num.tryParse('${item['contributors'] ?? 0}') ?? 0)),
                    _kv(loc.tr('components.pool_list_tabular.operator_fee'), '${item['operator_fee'] ?? '-'}'),
                    _kv(loc.tr('components.pool_list_tabular.last_reward_height'), '${item['last_reward_block_height'] ?? '-'}'),
                    _kvRow(
                      _lockupHeader(loc, lockup),
                      Text(_lockupSub(loc, lockup)),
                    ),
                    _kv(loc.tr('components.pool_list_tabular.last_uptime_proof'), _relativeUptime(loc, lastProof)),
                    _kv(
                      loc.tr('components.pool_list_tabular.staked'),
                      '${item['staked'] ?? '-'} ARQ${fiatStaked != null ? ' $fiatStaked' : ''}',
                    ),
                    _kv(
                      loc.tr('components.pool_list_tabular.available'),
                      '${item['available'] ?? '-'} ARQ${fiatAvail != null ? ' $fiatAvail' : ''}',
                    ),
                    if (item['equity'] != null && '${item['equity']}'.isNotEmpty)
                      _kv(loc.tr('components.pool_list_tabular.equity'), '${item['equity']} %'),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (String v) async {
                  switch (v) {
                    case 'copy':
                      await _copyNodeId(pubkey);
                      break;
                    case 'explorer':
                      await _openExplorer(pubkey);
                      break;
                    case 'book':
                      await _addOperatorToBook(item);
                      break;
                    case 'deregister':
                      await _deregisterNode(pubkey);
                      break;
                  }
                },
                itemBuilder: (BuildContext ctx) {
                  return <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(value: 'copy', child: Text(loc.tr('components.pool_list_tabular.copy_oracle_node_id'))),
                    if (!operatorSection)
                      PopupMenuItem<String>(value: 'book', child: Text(loc.tr('components.pool_list_tabular.add_operator_to_addressbook'))),
                    if (canDeregisterOperator || canDeregisterContributor)
                      PopupMenuItem<String>(
                        value: 'deregister',
                        child: Text(loc.tr('components.pool_list_tabular.deregister_oracle_node')),
                      ),
                    PopupMenuItem<String>(value: 'explorer', child: Text(loc.tr('components.pool_list_tabular.view_on_explorer'))),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(k, style: Theme.of(context).textTheme.labelSmall)),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _kvRow(Widget label, Widget value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: DefaultTextStyle.merge(style: Theme.of(context).textTheme.labelSmall!, child: label)),
          Expanded(child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 12), child: value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final Map<String, dynamic> stake =
        Map<String, dynamic>.from(((store.poolsRoot['staker'] as Map?)?['stake'] as Map?) ?? <String, dynamic>{});
    final num totalStaked = num.tryParse('${stake['total_staked'] ?? 0}') ?? 0;
    final int numOperating = (stake['num_operating'] as num?)?.toInt() ?? 0;
    final num price = store.coinPrice;
    final Map<String, dynamic> conv = Map<String, dynamic>.from(store.raw['conversion_data'] as Map? ?? <String, dynamic>{});
    final num sats = num.tryParse('${conv['sats'] ?? 0}') ?? 0;
    final num curP = num.tryParse('${conv['currentPrice'] ?? 0}') ?? 0;
    num tvl = 0;
    final num sumXeq = store.totalContributedStake;
    final num viaBtc = sumXeq * curP * sats;
    if (viaBtc.isFinite && viaBtc > 0) {
      tvl = _round2(viaBtc);
    } else if (sumXeq.isFinite && price > 0) {
      tvl = _round2(sumXeq * price);
    }
    final int blocksPerDay = 720;
    const double operatorReward = 7.8076;
    const double contributorReward = 3.6035;
    const int nodeDuration = 28;
    const int stakingRequirement = 100000;
    final double serviceNodeReward = operatorReward + contributorReward;
    final int apc = store.activePoolCount;
    double nodeReward = 0;
    if (apc > 0) {
      nodeReward = _round2((blocksPerDay / apc) * serviceNodeReward * nodeDuration);
    }
    double monthlyYield = 0;
    if (apc > 0) {
      monthlyYield = _round2((((blocksPerDay / apc) * operatorReward * nodeDuration) / stakingRequirement) * 100);
    }
    double percentageOfPool = 0;
    if (totalStaked > 0 && sumXeq > 0) {
      percentageOfPool = _round2((totalStaked / sumXeq) * 100);
    }
    num? operatorStakedUsd;
    if (price > 0 && totalStaked > 0) {
      operatorStakedUsd = _round2(totalStaked * price);
    }

    final Map<String, dynamic> curPf = _currentPoolsFilter(store);
    final int filterIndex = curPf['index'] as int? ?? 1;

    final List<Map<String, dynamic>> operatorPools = store.filteredPools('operator_pools');
    final List<Map<String, dynamic>> nonOpPools = store.filteredPools('nonoperator_pools');
    final List<Map<String, dynamic>> book = _addressBookEntries(store);

    final List<Widget> poolListChildren = <Widget>[
      if (operatorPools.isEmpty && nonOpPools.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(loc.tr('components.pool_list_tabular.no_staked_pools_found')),
        )
      else ...<Widget>[
        ...operatorPools.map(
          (Map<String, dynamic> item) => _poolCard(loc: loc, store: store, item: item, operatorSection: true),
        ),
        ...nonOpPools.map(
          (Map<String, dynamic> item) => _poolCard(loc: loc, store: store, item: item, operatorSection: false),
        ),
      ],
    ];

    // Pool list: same idea as `.scroller` in `staking-pools.vue` — `max-height: viewport - 425px`, overflow auto.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(loc.tr('pages.wallet.staking_pools.network_stats')),
              Text('${loc.tr('pages.wallet.staking_pools.total_nodes')} ${NumberFormat.decimalPattern().format(store.poolCount)}'),
              Text('${loc.tr('pages.wallet.staking_pools.monthly_yield')} $monthlyYield%'),
              Text('${loc.tr('pages.wallet.staking_pools.node_reward')} ($nodeDuration days): $nodeReward ARQ'),
              Text('${loc.tr('pages.wallet.staking_pools.tvl')} \$${NumberFormat.decimalPattern().format(tvl)}'),
              if (price > 0)
                Text('${loc.tr('pages.wallet.staking_pools.arq_spot_price')} \$${_formatSpotUsd(price)}'),
            ],
          ),
          if (totalStaked > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(loc.tr('pages.wallet.staking_pools.operator_stats')),
                Text(
                  '${loc.tr('pages.wallet.staking_pools.total_staked')} ${NumberFormat.decimalPattern().format(totalStaked)} ARQ'
                  '${operatorStakedUsd != null ? ' (${loc.tr('pages.wallet.staking_pools.fiat_approx', named: {'amount': NumberFormat.decimalPattern().format(operatorStakedUsd)})})' : ''}',
                ),
                Text('${loc.tr('pages.wallet.staking_pools.percentage_of_pool')} $percentageOfPool%'),
                Text('${loc.tr('pages.wallet.staking_pools.nodes_operating')} ${NumberFormat.decimalPattern().format(numOperating)}'),
              ],
            ),
          ],
          const SizedBox(height: 12),
          ArqmaField(
            label: loc.tr('pages.wallet.staking_pools.filter_by_oracle_nodeid'),
            disableMenu: false,
            child: TextField(
              controller: _nodeId,
              decoration: InputDecoration(
                hintText: loc.tr('pages.wallet.staking_pools.filter_by_oracle_nodeid_placeholder'),
                border: InputBorder.none,
                suffixIcon: _nodeId.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _nodeId.clear();
                          _pushNodeFilter();
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (_) {
                setState(() {});
                _pushNodeFilter();
              },
            ),
          ),
          const SizedBox(height: 8),
          ArqmaField(
            label: loc.tr('pages.wallet.staking_pools.filter_by_operator_address'),
            disableMenu: false,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _operatorId,
                    decoration: InputDecoration(
                      hintText: loc.tr('pages.wallet.staking_pools.filter_by_operator_address_placeholder'),
                      border: InputBorder.none,
                      suffixIcon: _operatorId.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _operatorId.clear();
                                _pushOperatorFilter();
                                setState(() {});
                              },
                            ),
                    ),
                    onChanged: (_) {
                      setState(() {});
                      _pushOperatorFilter();
                    },
                  ),
                ),
                if (book.isNotEmpty)
                  PopupMenuButton<Map<String, dynamic>>(
                    icon: const Icon(Icons.bookmark_outline, size: 22),
                    tooltip: loc.tr('layouts.wallet.main.address_book'),
                    itemBuilder: (BuildContext ctx) {
                      return book
                          .map(
                            (Map<String, dynamic> e) => PopupMenuItem<Map<String, dynamic>>(
                              value: e,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${e['name'] ?? ''}', style: Theme.of(ctx).textTheme.labelSmall),
                                  Text('${e['address'] ?? ''}', style: const TextStyle(fontSize: 11)),
                                ],
                              ),
                            ),
                          )
                          .toList();
                    },
                    onSelected: (Map<String, dynamic> e) {
                      _operatorId.text = '${e['address'] ?? ''}';
                      _pushOperatorFilter();
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ArqmaField(
            label: loc.tr('pages.wallet.staking_pools.filter_by_oracle_node_status'),
            child: DropdownButtonFormField<int>(
              value: filterIndex.clamp(0, 4),
              dropdownColor: const Color(0xFF1d1d1d),
              decoration: const InputDecoration(border: InputBorder.none),
              items: _nodeFilterOptions
                  .map(
                    (Map<String, dynamic> o) => DropdownMenuItem<int>(
                      value: o['index'] as int,
                      child: Text(loc.tr(o['label'] as String), overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (int? v) {
                if (v == null) {
                  return;
                }
                final Map<String, dynamic> opt = Map<String, dynamic>.from(
                  _nodeFilterOptions.firstWhere((Map<String, dynamic> e) => e['index'] == v),
                );
                store.setPoolsFilterState(opt);
              },
            ),
          ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: LayoutBuilder(
              builder: (BuildContext listContext, BoxConstraints inner) {
                final double viewportH = MediaQuery.sizeOf(listContext).height;
                final double capByVue = (viewportH - 425).clamp(200.0, 9000.0);
                final double maxListH = math.min(inner.maxHeight, capByVue);
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxListH),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    children: poolListChildren,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
