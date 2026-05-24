import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/app_api.dart';
import '../../core/theme/arqma_colors.dart';
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

class _StakingPoolsPageState extends State<StakingPoolsPage>
    with WidgetsBindingObserver {
  bool _started = false;
  AppApi? _api;
  GatewayStore? _store;
  StreamSubscription<Map<String, dynamic>>? _bridgeSub;

  static const double _coinUnits = 1e9;
  static const int _minStakeArq = 100;

  /// Min width for the tabular pool list (parity with Quasar `pool_list_tabular.vue` columns).
  static const double _kPoolTableMinWidth = 1188;

  /// Horizontal padding inside the pool [SingleChildScrollView] (must match [Padding] below).
  static const double _kPoolTableScrollHPadding = 12 + 18;

  static const List<Map<String, dynamic>> _nodeFilterOptions =
      <Map<String, dynamic>>[
    <String, dynamic>{
      'index': 0,
      'label': 'pages.wallet.staking_pools.all',
      'description': 'pages.wallet.staking_pools.all_description'
    },
    <String, dynamic>{
      'index': 1,
      'label': 'pages.wallet.staking_pools.open',
      'description': 'pages.wallet.staking_pools.open_description'
    },
    <String, dynamic>{
      'index': 2,
      'label': 'pages.wallet.staking_pools.closed',
      'description': 'pages.wallet.staking_pools.closed_description'
    },
    <String, dynamic>{
      'index': 3,
      'label': 'pages.wallet.staking_pools.operator',
      'description': 'pages.wallet.staking_pools.operator_description'
    },
    <String, dynamic>{
      'index': 4,
      'label': 'pages.wallet.staking_pools.contributor',
      'description': 'pages.wallet.staking_pools.contributor_description'
    },
  ];

  late final TextEditingController _nodeId;
  late final TextEditingController _operatorId;
  Timer? _debounceNode;
  Timer? _debounceOp;
  Timer? _uptimeTick;

  /// Tied to [Scrollbar] + nested [SingleChildScrollView]s (desktop needs explicit controllers).
  final ScrollController _poolHorizontalScroll = ScrollController();
  final ScrollController _poolVerticalScroll = ScrollController();

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
    unawaited(
        _api!.send('wallet', 'begin_Stake_Acquisition', <String, dynamic>{}));
    unawaited(_api!.send('wallet', 'get_coin_price', <String, dynamic>{}));
    _bootstrapPoolsFilterFromStore();
    final Map<String, dynamic>? nid =
        _store!.raw['node_id_filter'] as Map<String, dynamic>?;
    final Map<String, dynamic>? oid =
        _store!.raw['operator_id_filter'] as Map<String, dynamic>?;
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
    final Map<String, dynamic> pf = Map<String, dynamic>.from(
        s.raw['pools_filter'] as Map? ?? <String, dynamic>{});
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
    _poolHorizontalScroll.dispose();
    _poolVerticalScroll.dispose();
    final GatewayStore? store = _store;
    if (store != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        store.resetPoolsData();
      });
    }
    if (_api != null) {
      unawaited(
          _api!.send('wallet', 'end_Stake_Acquisition', <String, dynamic>{}));
    }
    super.dispose();
  }

  void _onBackendMessage(Map<String, dynamic> msg) {
    if (!mounted) {
      return;
    }
    final String? ev = msg['event'] as String?;
    if (ev == 'set_tx_status') {
      final Map<String, dynamic> d =
          Map<String, dynamic>.from(msg['data'] as Map? ?? <String, dynamic>{});
      final int code = d['code'] as int? ?? 0;
      if (code == 300 || code == -300) {
        unawaited(_handleStakeTxStatus(d));
      }
    } else if (ev == 'set_snode_status_unlock') {
      final Map<String, dynamic> d =
          Map<String, dynamic>.from(msg['data'] as Map? ?? <String, dynamic>{});
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
              child: Text(loc
                  .tr('components.pool_list_tabular.tx_status_cancel_label')),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                context
                    .read<AppApi>()
                    .send('wallet', 'relay_stake', <String, dynamic>{});
              },
              child: Text(
                  loc.tr('components.pool_list_tabular.tx_status_ok_label')),
            ),
          ],
        ),
      );
    } else if (code == -300) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _handleUnlockStatus(Map<String, dynamic> d) async {
    final int code = d['code'] as int? ?? 0;
    final String message = '${d['message'] ?? ''}';
    if (code == 0 && message.isEmpty) {
      return;
    }
    if (code == 400) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message.isEmpty ? 'OK' : message)));
    } else if (code == -400) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text(message.isEmpty ? 'Error' : message)));
    }
  }

  Map<String, dynamic> _currentPoolsFilter(GatewayStore store) {
    return Map<String, dynamic>.from(
        store.raw['pools_filter'] as Map? ?? _nodeFilterOptions[1]);
  }

  /// Parity with Vue `staking-pools.vue` / `pool_list_tabular` — short explanation under the status filter.
  String _poolsFilterDescription(LocaleController loc, GatewayStore store) {
    final String key =
        '${_currentPoolsFilter(store)['description'] ?? ''}'.trim();
    if (key.isEmpty) {
      return '';
    }
    return loc.tr(key);
  }

  void _pushNodeFilter() {
    _debounceNode?.cancel();
    _debounceNode = Timer(const Duration(milliseconds: 120), () {
      _store?.setNodeIdFilterState(<String, dynamic>{
        'index': 3,
        'label': 'Transaction',
        'value': _nodeId.text.trim()
      });
    });
  }

  void _pushOperatorFilter() {
    _debounceOp?.cancel();
    _debounceOp = Timer(const Duration(milliseconds: 120), () {
      _store?.setOperatorIdFilterState(<String, dynamic>{
        'index': 4,
        'label': 'Operator',
        'value': _operatorId.text.trim()
      });
    });
  }

  List<Map<String, dynamic>> _addressBookEntries(GatewayStore store) {
    final List<dynamic> ab = ((store.wallet['address_list']
            as Map?)?['address_book'] as List<dynamic>?) ??
        const <dynamic>[];
    return ab.map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  String _poolTypeLabel(LocaleController loc, Map<String, dynamic> item) {
    final num tc = num.tryParse('${item['total_contributed'] ?? 0}') ?? 0;
    final num sr = num.tryParse('${item['staking_requirement'] ?? 0}') ?? 0;
    final String status = tc < sr
        ? loc.tr('pages.wallet.staking_pools.open')
        : loc.tr('pages.wallet.staking_pools.closed');
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
    final DateTime dt =
        DateTime.fromMillisecondsSinceEpoch(unixSec * 1000, isUtc: true)
            .toLocal();
    return timeago.format(dt,
        locale: _timeagoLocaleFor(loc), allowFromNow: true);
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

  String? _fiatUsdApprox(
      LocaleController loc, num coinPrice, Object? arqDisplay) {
    if (coinPrice <= 0) {
      return null;
    }
    final num n =
        num.tryParse('${arqDisplay ?? 0}'.toString().replaceAll(',', '')) ?? 0;
    if (!n.isFinite || n <= 0) {
      return null;
    }
    final String usd = (n * coinPrice).toStringAsFixed(2);
    return loc.tr('components.pool_list_tabular.fiat_usd_approx',
        named: {'amount': usd});
  }

  Future<void> _copyNodeId(String nodeId) async {
    await context.read<AppApi>().writeText(nodeId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(context.read<LocaleController>().tr(
              'components.pool_list_tabular.copied_oracle_nodeid_to_clipboard'))),
    );
  }

  Future<void> _openExplorer(String nodeId) async {
    await context.read<AppApi>().send('core', 'open_explorer',
        <String, dynamic>{'type': 'service_node', 'id': nodeId});
  }

  Future<void> _addOperatorToBook(Map<String, dynamic> item) async {
    final LocaleController loc = context.read<LocaleController>();
    final String addr = '${item['operator_address'] ?? ''}';
    if (addr.isEmpty) {
      return;
    }
    final int r = math.Random().nextInt(50001);
    await context
        .read<AppApi>()
        .send('wallet', 'add_address_book', <String, dynamic>{
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
      title:
          loc.tr('components.pool_list_tabular.deregister_service_node_title'),
      noPasswordMessage: loc
          .tr('components.pool_list_tabular.deregister_service_node_message'),
      okLabel: loc
          .tr('components.pool_list_tabular.deregister_service_node_ok_label'),
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
        SnackBar(
            content: Text(context
                .read<LocaleController>()
                .tr('components.pool_list_tabular.invalid_stake_amount'))),
      );
      return;
    }
    final LocaleController loc = context.read<LocaleController>();
    final GatewayStore store = context.read<GatewayStore>();
    final AppApi api = context.read<AppApi>();
    final String oracleKey = '${item['service_node_pubkey'] ?? ''}';
    final num unlockedAtoms =
        num.tryParse('${store.walletInfo['unlocked_balance'] ?? 0}') ?? 0;
    final double unlockedArq = unlockedAtoms / _coinUnits;
    final double cap = maxArq < unlockedArq ? maxArq : unlockedArq;
    final String initialAmount =
        '${_minStakeArq > cap ? cap.toStringAsFixed(0) : _minStakeArq}';
    final String? amountEntered = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => _StakeAmountDialog(
        loc: loc,
        oracleKey: oracleKey,
        cap: cap,
        unlockedArq: unlockedArq,
        minStakeArq: _minStakeArq,
        initialAmount: initialAmount,
      ),
    );
    if (amountEntered == null || !mounted) {
      return;
    }
    final String cleaned = amountEntered.trim().replaceAll(',', '');
    final double? parsed = double.tryParse(cleaned);
    if (parsed == null || parsed < _minStakeArq || parsed > cap) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              loc.tr('components.pool_list_tabular.invalid_stake_amount'))));
      return;
    }
    if ((parsed - parsed.round()).abs() > 1e-6) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              loc.tr('components.pool_list_tabular.invalid_stake_amount'))));
      return;
    }
    final String? password = await PasswordDialogs.showPasswordConfirmation(
      context: context,
      api: api,
      locale: loc,
      title: loc
          .tr('components.pool_list_tabular.show_password_confirmation_title'),
      noPasswordMessage: loc.tr(
          'components.pool_list_tabular.show_password_confirmation_message'),
      okLabel: loc.tr(
          'components.pool_list_tabular.show_password_confirmation_ok_label'),
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

  TextStyle _poolMetaStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ArqmaColors.textMuted,
            fontSize: 11,
            height: 1.15,
          ) ??
      const TextStyle(
        fontSize: 11,
        color: ArqmaColors.textMuted,
        height: 1.15,
      );

  static const TextStyle _poolValueStyle = TextStyle(
    fontSize: 12,
    height: 1.2,
    color: ArqmaColors.textSecondary,
  );

  Widget _poolMain1Block({
    required BuildContext context,
    required LocaleController loc,
    required double width,
    required String labelKey,
    required Widget value,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              loc.tr(labelKey),
              textAlign: TextAlign.center,
              style: _poolMetaStyle(context),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            DefaultTextStyle.merge(
              textAlign: TextAlign.center,
              style: _poolValueStyle,
              child: value,
            ),
          ],
        ),
      ),
    );
  }

  Widget _poolStakedAvailValue(
    LocaleController loc,
    num price,
    Object? arqAmount,
  ) {
    final String base = '${arqAmount ?? '-'} ARQ';
    final String? fiat = _fiatUsdApprox(loc, price, arqAmount);
    if (fiat == null) {
      return Text(
        base,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text.rich(
      TextSpan(
        style: _poolValueStyle,
        children: <InlineSpan>[
          TextSpan(text: base),
          TextSpan(
            text: ' $fiat',
            style: const TextStyle(
              fontSize: 10,
              color: ArqmaColors.textMuted,
              height: 1.2,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// [PopupMenuButton] inside nested scroll + clipped cards can paint the menu
  /// with a tiny max width on Windows; [showMenu] on the root overlay avoids that.
  Future<void> _showPoolRowOverflowMenu({
    required BuildContext anchor,
    required List<PopupMenuEntry<String>> items,
    required Future<void> Function(String value) onChosen,
  }) async {
    final RenderObject? ro = anchor.findRenderObject();
    if (ro is! RenderBox) {
      return;
    }
    final RenderBox button = ro;
    final OverlayState? overlayState =
        Overlay.maybeOf(anchor, rootOverlay: true);
    if (overlayState == null) {
      return;
    }
    final RenderBox overlayBox =
        overlayState.context.findRenderObject()! as RenderBox;
    final Offset topLeft =
        button.localToGlobal(Offset.zero, ancestor: overlayBox);
    final Rect rect = Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      button.size.width,
      button.size.height,
    );
    final RelativeRect position = RelativeRect.fromRect(
      rect,
      Offset.zero & overlayBox.size,
    );
    final String? picked = await showMenu<String>(
      context: anchor,
      position: position,
      items: items,
      useRootNavigator: true,
      constraints: const BoxConstraints(minWidth: 260),
      color: ArqmaColors.darkPanel,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: ArqmaColors.outlineSubtle.withValues(alpha: 0.55),
        ),
      ),
    );
    if (picked != null && anchor.mounted) {
      await onChosen(picked);
    }
  }

  Widget _poolRow({
    required LocaleController loc,
    required GatewayStore store,
    required Map<String, dynamic> item,
    required bool operatorSection,
  }) {
    final String pubkey = '${item['service_node_pubkey'] ?? ''}';
    final Map<String, dynamic> lockup = Map<String, dynamic>.from(
        item['lockup'] as Map? ?? <String, dynamic>{});
    final int lastProof =
        (num.tryParse('${item['last_uptime_proof'] ?? 0}') ?? 0).toInt();
    final num price = store.coinPrice;
    final num reqUnlock =
        num.tryParse('${item['requested_unlock_height'] ?? 0}') ?? 0;
    final bool canDeregisterOperator =
        operatorSection && item['is_operator'] == true && reqUnlock == 0;
    final bool canDeregisterContributor =
        !operatorSection && item['is_contributor'] == true && reqUnlock == 0;
    final double maxStake = _maxStakeArq(item);
    final bool canTapStake = !operatorSection && maxStake > 0;
    final String stakers =
        NumberFormat.decimalPattern().format(
            num.tryParse('${item['contributors'] ?? 0}') ?? 0);
    final String fee = '${item['operator_fee'] ?? '-'}';
    final String lockAmount = '${lockup['amount'] ?? ''}';
    final bool lockEmpty = lockAmount.isEmpty;
    final String lockI18nKey = '${lockup['i18n'] ?? ''}';
    final String lastReward = '${item['last_reward_block_height'] ?? '-'}';
    final Object? eq = item['equity'];
    final bool hasEquity = eq != null && '$eq'.trim().isNotEmpty;
    final String lockMetaLabel = lockEmpty
        ? loc.tr('components.pool_list_tabular.lock_up')
        : loc.tr('components.pool_list_tabular.expiring');

    /// Operator vs contributor — both roles use gold-toned greens (lighter / darker).
    final Color typeColor = operatorSection
        ? ArqmaColors.arqmaGreenSolid
        : ArqmaColors.arqmaGreenDarkSolid;

    PopupMenuItem<String> menuEntry(String value, String label) {
      return PopupMenuItem<String>(
        value: value,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            color: ArqmaColors.arqmaGreenSolid,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final List<PopupMenuEntry<String>> poolOverflowItems =
        <PopupMenuEntry<String>>[];
    if (!operatorSection) {
      poolOverflowItems.add(menuEntry(
          'book',
          loc.tr(
              'components.pool_list_tabular.add_operator_to_addressbook')));
    }
    poolOverflowItems.add(menuEntry(
        'copy',
        loc.tr('components.pool_list_tabular.copy_oracle_node_id')));
    if (canDeregisterOperator || canDeregisterContributor) {
      poolOverflowItems.add(menuEntry(
          'deregister',
          loc.tr('components.pool_list_tabular.deregister_oracle_node')));
    }
    poolOverflowItems.add(menuEntry(
        'explorer',
        loc.tr('components.pool_list_tabular.view_on_explorer')));

    // Parity with `app.scss` `.pool-list-tabular .arqma-list-item.transaction` + `pool_list_tabular.vue`.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: Material(
        color: ArqmaColors.black90,
        borderRadius: BorderRadius.circular(3),
        clipBehavior: Clip.none,
        child: InkWell(
          hoverColor: ArqmaColors.selection,
          splashColor: ArqmaColors.arqmaGreenSolid.withValues(alpha: 0.18),
          onTap: canTapStake ? () => _openStakeDialog(item) : null,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 100,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        _poolTypeLabel(loc, item),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.2,
                          color: typeColor,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: ArqmaColors.outlineSubtle),
                      ),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          loc.tr('components.pool_list_tabular.oracle_node_id'),
                          style: _poolMetaStyle(context),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pubkey,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            height: 1.25,
                            color: ArqmaColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                _poolMain1Block(
                  context: context,
                  loc: loc,
                  width: 76,
                  labelKey: 'components.pool_list_tabular.stakers',
                  value: Text(
                    stakers,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _poolMain1Block(
                  context: context,
                  loc: loc,
                  width: 72,
                  labelKey: 'components.pool_list_tabular.operator_fee',
                  value: Text(
                    fee,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _poolMain1Block(
                  context: context,
                  loc: loc,
                  width: 92,
                  labelKey: 'components.pool_list_tabular.last_reward_height',
                  value: Text(
                    lastReward,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 128,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          lockMetaLabel,
                          textAlign: TextAlign.center,
                          style: _poolMetaStyle(context),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          !lockEmpty && lockI18nKey.isNotEmpty
                              ? '$lockAmount ${loc.tr(lockI18nKey)}'
                              : lockAmount,
                          textAlign: TextAlign.center,
                          style: _poolValueStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                _poolMain1Block(
                  context: context,
                  loc: loc,
                  width: 118,
                  labelKey: 'components.pool_list_tabular.last_uptime_proof',
                  value: Text(
                    _relativeUptime(loc, lastProof),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _poolMain1Block(
                  context: context,
                  loc: loc,
                  width: 138,
                  labelKey: 'components.pool_list_tabular.staked',
                  value: _poolStakedAvailValue(loc, price, item['staked']),
                ),
                _poolMain1Block(
                  context: context,
                  loc: loc,
                  width: 138,
                  labelKey: 'components.pool_list_tabular.available',
                  value: _poolStakedAvailValue(loc, price, item['available']),
                ),
                _poolMain1Block(
                  context: context,
                  loc: loc,
                  width: 72,
                  labelKey: 'components.pool_list_tabular.equity',
                  value: hasEquity
                      ? Text(
                          '$eq %',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : const Text(''),
                ),
                SizedBox(
                  width: 48,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Builder(
                      builder: (BuildContext btnCtx) {
                        return IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 36,
                          ),
                          tooltip: '',
                          onPressed: () async {
                            await _showPoolRowOverflowMenu(
                              anchor: btnCtx,
                              items: poolOverflowItems,
                              onChosen: (String v) async {
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
                            );
                          },
                          icon: Icon(
                            Icons.more_vert,
                            size: 20,
                            color: ArqmaColors.textPrimary
                                .withValues(alpha: 0.85),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final Map<String, dynamic> stake = Map<String, dynamic>.from(
        ((store.poolsRoot['staker'] as Map?)?['stake'] as Map?) ??
            <String, dynamic>{});
    final num totalStaked = num.tryParse('${stake['total_staked'] ?? 0}') ?? 0;
    final int numOperating = (stake['num_operating'] as num?)?.toInt() ?? 0;
    final num price = store.coinPrice;
    final Map<String, dynamic> conv = Map<String, dynamic>.from(
        store.raw['conversion_data'] as Map? ?? <String, dynamic>{});
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
      nodeReward =
          _round2((blocksPerDay / apc) * serviceNodeReward * nodeDuration);
    }
    double monthlyYield = 0;
    if (apc > 0) {
      monthlyYield = _round2(
          (((blocksPerDay / apc) * operatorReward * nodeDuration) /
                  stakingRequirement) *
              100);
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
    final String poolFilterDesc = _poolsFilterDescription(loc, store);

    final List<Map<String, dynamic>> operatorPools =
        store.filteredPools('operator_pools');
    final List<Map<String, dynamic>> nonOpPools =
        store.filteredPools('nonoperator_pools');
    final List<Map<String, dynamic>> book = _addressBookEntries(store);

    final bool poolsEmpty = operatorPools.isEmpty && nonOpPools.isEmpty;
    final List<Widget> poolRows = <Widget>[
      ...operatorPools.map(
        (Map<String, dynamic> item) => _poolRow(
            loc: loc, store: store, item: item, operatorSection: true),
      ),
      if (operatorPools.isNotEmpty && nonOpPools.isNotEmpty)
        const SizedBox(height: 8),
      ...nonOpPools.map(
        (Map<String, dynamic> item) => _poolRow(
            loc: loc, store: store, item: item, operatorSection: false),
      ),
    ];

    /// Parity with `staking-pools.vue`: stats + filters scroll; `.scroller` holds the tabular list.
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 8, 18, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            Text(loc.tr('pages.wallet.staking_pools.network_stats')),
            Text(
                '${loc.tr('pages.wallet.staking_pools.total_nodes')} ${NumberFormat.decimalPattern().format(store.poolCount)}'),
            Text(
                '${loc.tr('pages.wallet.staking_pools.monthly_yield')} $monthlyYield%'),
            Text(
                '${loc.tr('pages.wallet.staking_pools.node_reward')} ($nodeDuration days): $nodeReward ARQ'),
            Text(
                '${loc.tr('pages.wallet.staking_pools.tvl')} \$${NumberFormat.decimalPattern().format(tvl)}'),
            if (price > 0)
              Text(
                  '${loc.tr('pages.wallet.staking_pools.arq_spot_price')} \$${_formatSpotUsd(price)}'),
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
                '${operatorStakedUsd != null ? ' (${loc.tr('pages.wallet.staking_pools.fiat_approx', named: {
                        'amount': NumberFormat.decimalPattern()
                            .format(operatorStakedUsd)
                      })})' : ''}',
              ),
              Text(
                  '${loc.tr('pages.wallet.staking_pools.percentage_of_pool')} $percentageOfPool%'),
              Text(
                  '${loc.tr('pages.wallet.staking_pools.nodes_operating')} ${NumberFormat.decimalPattern().format(numOperating)}'),
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
              hintText: loc.tr(
                  'pages.wallet.staking_pools.filter_by_oracle_nodeid_placeholder'),
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
          label:
              loc.tr('pages.wallet.staking_pools.filter_by_operator_address'),
          disableMenu: false,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _operatorId,
                  decoration: InputDecoration(
                    hintText: loc.tr(
                        'pages.wallet.staking_pools.filter_by_operator_address_placeholder'),
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
                          (Map<String, dynamic> e) =>
                              PopupMenuItem<Map<String, dynamic>>(
                            value: e,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${e['name'] ?? ''}',
                                    style:
                                        Theme.of(ctx).textTheme.labelSmall),
                                Text('${e['address'] ?? ''}',
                                    style: const TextStyle(fontSize: 11)),
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
          label: loc
              .tr('pages.wallet.staking_pools.filter_by_oracle_node_status'),
          child: InputDecorator(
            decoration: const InputDecoration(border: InputBorder.none),
            child: DropdownButton<int>(
              isExpanded: true,
              value: filterIndex.clamp(0, 4),
              itemHeight: 88,
              underline: const SizedBox.shrink(),
              selectedItemBuilder: (BuildContext ctx) {
                return _nodeFilterOptions.map((Map<String, dynamic> o) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      loc.tr(o['label'] as String),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  );
                }).toList();
              },
              dropdownColor: ArqmaColors.darkPanel,
              items: _nodeFilterOptions
                  .map(
                    (Map<String, dynamic> o) => DropdownMenuItem<int>(
                      value: o['index'] as int,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(loc.tr(o['label'] as String),
                              overflow: TextOverflow.ellipsis),
                          Text(
                            loc.tr(o['description'] as String? ?? ''),
                            style: const TextStyle(
                                fontSize: 10,
                                color: ArqmaColors.textMuted,
                                height: 1.2),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (int? v) {
                if (v == null) {
                  return;
                }
                final Map<String, dynamic> opt = Map<String, dynamic>.from(
                  _nodeFilterOptions.firstWhere(
                      (Map<String, dynamic> e) => e['index'] == v),
                );
                store.setPoolsFilterState(opt);
              },
            ),
          ),
        ),
        if (poolFilterDesc.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4, right: 4),
            child: Text(
              poolFilterDesc,
              style: const TextStyle(
                  fontSize: 11,
                  color: ArqmaColors.textMuted,
                  height: 1.3),
            ),
          ),
        const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        if (poolsEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 18, 24),
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  loc.tr('components.pool_list_tabular.no_staked_pools_found'),
                ),
              ),
            ),
          )
        else
          SliverFillRemaining(
            hasScrollBody: true,
            child: LayoutBuilder(
              builder: (BuildContext ctx, BoxConstraints c) {
                final double availW = c.maxWidth.isFinite && c.maxWidth > 0
                    ? c.maxWidth
                    : _kPoolTableMinWidth;
                final double tableW = math.max(
                  _kPoolTableMinWidth,
                  math.max(0.0, availW - _kPoolTableScrollHPadding),
                );
                return Scrollbar(
                  controller: _poolHorizontalScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _poolHorizontalScroll,
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Scrollbar(
                      controller: _poolVerticalScroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _poolVerticalScroll,
                        clipBehavior: Clip.none,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 18, 24),
                          child: SizedBox(
                            width: tableW,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: poolRows,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _StakeAmountDialog extends StatefulWidget {
  const _StakeAmountDialog({
    required this.loc,
    required this.oracleKey,
    required this.cap,
    required this.unlockedArq,
    required this.minStakeArq,
    required this.initialAmount,
  });

  final LocaleController loc;
  final String oracleKey;
  final double cap;
  final double unlockedArq;
  final int minStakeArq;
  final String initialAmount;

  @override
  State<_StakeAmountDialog> createState() => _StakeAmountDialogState();
}

class _StakeAmountDialogState extends State<_StakeAmountDialog> {
  late final TextEditingController _amount =
      TextEditingController(text: widget.initialAmount);

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.loc
          .tr('components.pool_list_tabular.confirm_amount_to_stake')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.loc.tr('components.pool_list_tabular.oracle_id')),
            SelectableText(widget.oracleKey,
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Text(
                '${widget.loc.tr('components.pool_list_tabular.max_amount')}${widget.cap.toStringAsFixed(9)}'),
            Text(
                '${widget.loc.tr('components.pool_list_tabular.min_amount')}${widget.minStakeArq}'),
            const SizedBox(height: 8),
            ArqmaField(
              label: widget.loc.tr('components.pool_list_tabular.amount'),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                          border: InputBorder.none, hintText: '100'),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _amount.text = widget.cap
                            .toStringAsFixed(9)
                            .replaceAll(RegExp(r'\.?0+$'), '');
                        if (_amount.text.isEmpty) {
                          _amount.text = widget.cap.toStringAsFixed(0);
                        }
                      });
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
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.loc.tr('composables.cancel'))),
        if (widget.unlockedArq >= widget.minStakeArq)
          TextButton(
            onPressed: () => Navigator.pop(
                context, _amount.text.trim().replaceAll(',', '')),
            child: Text(
                widget.loc.tr('components.pool_list_tabular.confirm_stake')),
          )
        else
          TextButton(
              onPressed: null,
              child: Text(widget.loc
                  .tr('components.pool_list_tabular.not_enough_coins'))),
      ],
    );
  }
}
