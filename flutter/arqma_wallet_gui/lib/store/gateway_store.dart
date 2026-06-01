import 'package:flutter/foundation.dart';

import '../core/utils/deep_merge.dart';
import '../core/wallet_daemon_tip_tolerance.dart';
import 'gateway_default_state.dart';

typedef GatewayEventListener = void Function(String event, dynamic data);

/// Avoid `target.addAll(merged)` when [target] was inferred as `Map<String, Object>`
/// from map literals (e.g. default gateway state) while [merged] is `Map<String, dynamic>`.
void _assignMergedEntries(
    Map<dynamic, dynamic> target, Map<String, dynamic> merged) {
  target.clear();
  merged.forEach((String k, dynamic v) {
    target[k] = v;
  });
}

/// Fields that drive visible wallet UI (footer/header/list scan banner).
const List<String> _kWalletInfoUiKeys = <String>[
  'height',
  'balance',
  'unlocked_balance',
  'name',
  'full_rescan_ui',
  'address',
  'view_only',
];

bool _walletInfoUiPatchChanged(
    Map<String, dynamic> patch, Map<String, dynamic> current) {
  for (final String k in _kWalletInfoUiKeys) {
    if (!patch.containsKey(k)) {
      continue;
    }
    if ('${patch[k]}' != '${current[k]}') {
      return true;
    }
  }
  return false;
}

/// Vuex `gateway` module + `receiver.js` commit paths, backed by a deep tree.
class GatewayStore extends ChangeNotifier {
  GatewayStore() : _state = defaultGatewayState();

  Map<String, dynamic> _state;

  List<dynamic>? _filteredTransactionsCache;
  Object? _filteredTransactionsCacheKey;
  int _transactionsRevision = 0;

  Map<String, dynamic> get raw => _state;

  /// Bumps on every meaningful tx-list change — drives fast, narrow UI updates.
  int get transactionsRevision => _transactionsRevision;

  Map<String, dynamic> get app => _state['app'] as Map<String, dynamic>;
  Map<String, dynamic> get wallet => _state['wallet'] as Map<String, dynamic>;
  Map<String, dynamic> get daemon => _state['daemon'] as Map<String, dynamic>;

  int get appStatusCode => (app['status'] as Map)['code'] as int? ?? 1;

  num get coinPrice => (_state['coin_price'] as num?) ?? 0;

  Map<String, dynamic> get walletInfo =>
      Map<String, dynamic>.from(wallet['info'] as Map? ?? {});

  void _notify() => notifyListeners();

  void replaceState(Map<String, dynamic> next) {
    _state = Map<String, dynamic>.from(next);
    _notify();
  }

  // --- Mutations (parity with `store/gateway/mutations.js`) ---

  void setAppData(Map<String, dynamic> data) {
    final merged = deepMergeMaps(app, data) as Map<String, dynamic>;
    _assignMergedEntries(app, merged);
    _notify();
  }

  void setDaemonData(Map<String, dynamic> data) {
    final d = daemon;
    final merged = deepMergeMaps(d, data) as Map<String, dynamic>;
    _assignMergedEntries(d, merged);
    _notify();
  }

  void resetWalletData(Map<String, dynamic> data) {
    final w = wallet;
    final merged = deepMergeMaps(w, data) as Map<String, dynamic>;
    _assignMergedEntries(w, merged);
    _transactionsRevision++;
    _invalidateFilteredTransactionsCache();
    _notify();
  }

  void _invalidateFilteredTransactionsCache() {
    _filteredTransactionsCache = null;
    _filteredTransactionsCacheKey = null;
  }

  void setWalletError(Map<String, dynamic> data) {
    resetWalletData(data);
  }

  static Object _txListChangeToken(List<dynamic> list) {
    if (list.isEmpty) {
      return 0;
    }
    int token = list.length;
    for (final Object? x in list) {
      if (x is Map) {
        token = Object.hash(
          token,
          x['txid'],
          x['type'],
          x['height'],
          x['amount'],
          x['timestamp'],
        );
      }
    }
    return token;
  }

  void setWalletTransactions(Map<String, dynamic> data) {
    final List<dynamic> next =
        (data['tx_list'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> cur =
        ((wallet['transactions'] as Map?)?['tx_list'] as List<dynamic>?) ??
            const <dynamic>[];
    if (_txListChangeToken(next) == _txListChangeToken(cur)) {
      return;
    }
    wallet['transactions'] = data;
    _transactionsRevision++;
    _invalidateFilteredTransactionsCache();
    _notify();
  }

  void setWalletTransaction(Map<String, dynamic> data) {
    final txid = data['txid'] as String?;
    final list = (wallet['transactions'] as Map)['tx_list'] as List<dynamic>;
    final next = list.map((dynamic p) {
      final m = p as Map<String, dynamic>;
      if (txid != null && m['txid'] == txid) {
        return {...m, 'note': data['note']};
      }
      return p;
    }).toList();
    (wallet['transactions'] as Map)['tx_list'] = next;
    _transactionsRevision++;
    _invalidateFilteredTransactionsCache();
    _notify();
  }

  void setWalletAddressList(Map<String, dynamic> data) {
    final al = wallet['address_list'] as Map<String, dynamic>;
    final merged = deepMergeMaps(al, data) as Map<String, dynamic>;
    _assignMergedEntries(al, merged);
    _notify();
  }

  void setWalletAddressBook(Map<String, dynamic> data) {
    setWalletAddressList(data);
  }

  void setWalletInfo(Map<String, dynamic> data) {
    final patch = Map<String, dynamic>.from(data);
    final bool allowLowerHeight = patch.remove('allow_lower_height') == true;
    if (patch['height'] != null && patch['height'] != '') {
      final incoming = num.tryParse('${patch['height']}') ?? 0;
      final cur = num.tryParse('${(wallet['info'] as Map)['height']}') ?? 0;
      final sameWallet = patch['name'] == null ||
          patch['name'] == '' ||
          (wallet['info'] as Map)['name'] == null ||
          (wallet['info'] as Map)['name'] == '' ||
          patch['name'] == (wallet['info'] as Map)['name'];
      if (sameWallet &&
          cur > 0 &&
          incoming < cur &&
          !allowLowerHeight) {
        patch['height'] = cur;
      } else {
        patch['height'] = incoming;
      }
    }
    if (patch['balance'] != null && patch['balance'] != '') {
      patch['balance'] = num.tryParse('${patch['balance']}') ?? 0;
    }
    if (patch['unlocked_balance'] != null && patch['unlocked_balance'] != '') {
      patch['unlocked_balance'] =
          num.tryParse('${patch['unlocked_balance']}') ?? 0;
    }
    if (patch['scan_poll_ts'] != null && patch['scan_poll_ts'] != '') {
      patch['scan_poll_ts'] = num.tryParse('${patch['scan_poll_ts']}') ?? 0;
    }
    final wi = wallet['info'] as Map<String, dynamic>;
    final bool uiChanged = _walletInfoUiPatchChanged(patch, wi);
    final merged = deepMergeMaps(wi, patch) as Map<String, dynamic>;
    _assignMergedEntries(wi, merged);
    if (uiChanged) {
      _notify();
    }
  }

  void setWalletSecret(Map<String, dynamic> data) {
    wallet['secret'] = data;
    _notify();
  }

  void resetWalletStatus(Map<String, dynamic> data) {
    wallet['status'] = data;
    _notify();
  }

  void setPoolsData(Map<String, dynamic> data) {
    _state['pools'] = data;
    _notify();
  }

  void setPoolData(Map<String, dynamic> data) {
    final p = _state['pool'] as Map<String, dynamic>;
    final merged = deepMergeMaps(p, data) as Map<String, dynamic>;
    _assignMergedEntries(p, merged);
    _notify();
  }

  void setCoinPrice(dynamic data) {
    final num? next =
        data is num ? data : num.tryParse(data == null ? '' : '$data');
    if (next != null && next == coinPrice) {
      return;
    }
    _state['coin_price'] = next ?? data;
    _notify();
  }

  void setConversionData(Map<String, dynamic> data) {
    _state['conversion_data'] = data;
    _notify();
  }

  void setWalletList(Map<String, dynamic> data) {
    _state['wallets'] = data;
    _notify();
  }

  void setOldGuiImportStatus(Map<String, dynamic> data) {
    _state['old_gui_import_status'] = data;
    _notify();
  }

  void setTxStatus(Map<String, dynamic> data) {
    _state['tx_status'] = data;
    _notify();
  }

  void setSweepAllProgress(dynamic data) {
    _state['sweep_all_progress'] = data;
    _notify();
  }

  void setSnodeStatus(Map<String, dynamic> data) {
    _state['service_node_status'] = data;
    _notify();
  }

  void setSnodeStatusUnlock(Map<String, dynamic> data) {
    final sn = _state['service_node_status'] as Map<String, dynamic>;
    final u = sn['unlock'] as Map<String, dynamic>;
    final merged = deepMergeMaps(u, data) as Map<String, dynamic>;
    _assignMergedEntries(u, merged);
    _notify();
  }

  void setEthereumData(Map<String, dynamic> data) {
    final e = _state['ethereum'] as Map<String, dynamic>;
    final merged = deepMergeMaps(e, data) as Map<String, dynamic>;
    _assignMergedEntries(e, merged);
    _notify();
  }

  void setDaemonVersion(String version) {
    _state['daemon_version'] = version;
    _notify();
  }

  void resetWalletDataDispatch() {
    resetWalletData({
      'status': {'code': 1, 'message': null},
      'info': {
        'name': '',
        'address': '',
        'height': 0,
        'balance': 0,
        'unlocked_balance': 0,
        'view_only': false,
      },
      'secret': {'mnemonic': '', 'view_key': '', 'spend_key': ''},
      'transactions': {'tx_list': <dynamic>[]},
      'address_list': {
        'primary': <dynamic>[],
        'used': <dynamic>[],
        'unused': <dynamic>[],
        'address_book': <dynamic>[],
        'address_book_starred': <dynamic>[],
      },
    });
    setSweepAllProgress(null);
  }

  void _calculateSignatureData(List<dynamic> data) {
    final proc = (_state['processing_signature_data'] as List).cast<dynamic>();
    final dataSigs =
        data.map((e) => (e as Map)['signature'].toString()).toSet();
    final next = data.where((item) {
      final sig = (item as Map)['signature'].toString();
      if (proc.contains(sig)) {
        return false;
      }
      return true;
    }).toList();
    proc.removeWhere((sig) => !dataSigs.contains(sig));
    _state['signature_data'] = next;
  }

  void setProcessingSignatureData(String data) {
    final proc = _state['processing_signature_data'] as List<dynamic>;
    if (!proc.contains(data)) {
      proc.add(data);
    }
    _calculateSignatureData((_state['signature_data'] as List?) ?? <dynamic>[]);
    _notify();
  }

  void setSignatureData(List<dynamic> data) {
    final proc = _state['processing_signature_data'] as List<dynamic>;
    if (proc.isNotEmpty) {
      _calculateSignatureData(data);
    } else {
      _state['signature_data'] = data;
    }
    _notify();
  }

  /// `receiver.js` `api.receive` switch body.
  void applyBackendEvent(String event, dynamic data) {
    switch (event) {
      case 'set_app_data':
        setAppData(Map<String, dynamic>.from(data as Map));
        break;
      case 'set_ethereum_data':
        setEthereumData(Map<String, dynamic>.from(data as Map));
        break;
      case 'set_daemon_data':
        setDaemonData(Map<String, dynamic>.from(data as Map));
        break;
      case 'reset_wallet_data':
        resetWalletData(Map<String, dynamic>.from(data as Map));
        break;
      case 'set_wallet_error':
        setWalletError(Map<String, dynamic>.from(data as Map));
        break;
      case 'set_wallet_transactions':
        setWalletTransactions(Map<String, dynamic>.from(data as Map));
        break;
      case 'set_wallet_transaction':
        setWalletTransaction(Map<String, dynamic>.from(data as Map));
        break;
      case 'reset_wallet_status':
        resetWalletStatus(Map<String, dynamic>.from(data as Map));
        break;
      case 'set_wallet_address_list':
        setWalletAddressList(Map<String, dynamic>.from(data as Map));
        break;
      case 'set_wallet_address_book':
        setWalletAddressBook(Map<String, dynamic>.from(data as Map));
        break;
      case 'set_wallet_info':
        final d = Map<String, dynamic>.from(data as Map);
        if (d['name'] == null || '${d['name']}' == '') {
          final curName = walletInfo['name'];
          if (curName == null || '$curName' == '') {
            break;
          }
        }
        setWalletInfo(d);
        break;
      case 'set_wallet_secret':
        setWalletSecret(Map<String, dynamic>.from(data as Map));
        break;
      case 'set_pools_data':
        setPoolsData(Map<String, dynamic>.from(data as Map));
        break;
      case 'set_pool_data':
        setPoolData(Map<String, dynamic>.from(data as Map));
        break;
      case 'set_coin_price':
        setCoinPrice(data);
        break;
      case 'set_conversion_data':
        setConversionData(Map<String, dynamic>.from(data as Map));
        break;
      case 'set_signature_data':
        if ((_state['signature_data'] as List).isEmpty &&
            (data as List).isEmpty) {
          return;
        }
        setSignatureData(List<dynamic>.from(data as List));
        break;
      case 'set_tx_status':
        setTxStatus(Map<String, dynamic>.from(data as Map));
        break;
      case 'sweep_all_progress':
        setSweepAllProgress(data);
        break;
      case 'set_snode_status':
        setSnodeStatus(Map<String, dynamic>.from(data as Map));
        break;
      case 'set_snode_status_unlock':
        setSnodeStatusUnlock(Map<String, dynamic>.from(data as Map));
        break;
      case 'set_old_gui_import_status':
        setOldGuiImportStatus(Map<String, dynamic>.from(data as Map));
        break;
      case 'wallet_list':
        setWalletList(Map<String, dynamic>.from(data as Map));
        break;
      case 'daemon_version':
        final Map<String, dynamic> dv = Map<String, dynamic>.from(data as Map);
        final Object? v = dv['version'];
        setDaemonVersion(v is String ? v : '');
        break;
      case 'reset_wallet_error':
        resetWalletStatus({'code': 1, 'message': null});
        break;
      default:
        break;
    }
  }

  Map<String, dynamic> get notifierMap => Map<String, dynamic>.from(
      _state['notifier'] as Map<String, dynamic>? ?? <String, dynamic>{});

  void setNotifier(Map<String, dynamic> n) {
    _state['notifier'] = n;
    _notify();
  }

  /// Vuex `save_pending_config`: merge `{ config: pending }` into `app`.
  void savePendingConfig(Map<String, dynamic> pending) {
    final Map<String, dynamic> mergedApp =
        deepMergeMaps(app, <String, dynamic>{'config': pending})
            as Map<String, dynamic>;
    _assignMergedEntries(app, mergedApp);
    _notify();
  }

  // --- Getters (`store/gateway/getters.js`) ---

  int _daemonChainTip() {
    final info = daemon['info'] as Map<String, dynamic>? ?? {};
    final h = num.tryParse('${info['height']}') ?? 0;
    final th = num.tryParse('${info['target_height']}') ?? 0;
    return h > th ? h.toInt() : th.toInt();
  }

  /// Wallet height vs chain tip — match [kWalletDaemonTipToleranceBlocks] with footer / desktop bridge.
  bool _walletRpcNearTip(num wh, int targetHeight) {
    if (targetHeight <= 0) {
      return false;
    }
    final int w = wh.round();
    if (w >= targetHeight) {
      return true;
    }
    return targetHeight - w <= kWalletDaemonTipToleranceBlocks;
  }

  bool _daemonBootstrapNearTip(num hwo, int targetHeight) {
    if (targetHeight <= 0) {
      return false;
    }
    final int h = hwo.round();
    if (h >= targetHeight) {
      return true;
    }
    return targetHeight - h <= kWalletDaemonTipToleranceBlocks;
  }

  /// Wallet session has a display name (parity: RPC is for an opened wallet),
  /// independent of [isReady]. Used for **rescan** while still scanning chain.
  bool get hasOpenWallet {
    final String n = '${walletInfo['name'] ?? ''}'.trim();
    return n.isNotEmpty;
  }

  bool get isReady {
    final targetHeight = _daemonChainTip();
    if (targetHeight == 0) {
      return false;
    }
    final wh = num.tryParse('${walletInfo['height']}') ?? 0;
    if (!_walletRpcNearTip(wh, targetHeight)) {
      return false;
    }
    final cfg = app['config'] as Map<String, dynamic>?;
    final String net =
        (cfg?['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final dt = (cfg?['daemons'] as Map?)?[net] as Map?;
    final dtype = dt?['type'] as String?;
    if (dtype == 'local' || dtype == 'local_remote') {
      final hwo = num.tryParse(
              '${(daemon['info'] as Map)['height_without_bootstrap']}') ??
          0;
      if (!_daemonBootstrapNearTip(hwo, targetHeight)) {
        return false;
      }
    }
    return true;
  }

  bool get isAbleToSend {
    final cfg = app['config'] as Map<String, dynamic>?;
    final String net =
        (cfg?['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final daemons = cfg?['daemons'] as Map<String, dynamic>?;
    final configDaemon =
        daemons?[net] as Map<String, dynamic>? ?? {'type': 'local'};
    final targetHeight = _daemonChainTip();
    if (targetHeight == 0) {
      return false;
    }
    final walletAtTip = _walletRpcNearTip(
        num.tryParse('${walletInfo['height']}') ?? 0, targetHeight);
    if (configDaemon['type'] == 'local_remote') {
      final hwo = num.tryParse(
              '${(daemon['info'] as Map)['height_without_bootstrap']}') ??
          0;
      return _daemonBootstrapNearTip(hwo, targetHeight) && walletAtTip;
    }
    return walletAtTip;
  }

  void setTransactionsFilter(Map<String, dynamic> data) {
    _state['transactions_filter'] = Map<String, dynamic>.from(data);
    _notify();
  }

  void setTransactionIdFilter(Map<String, dynamic> data) {
    _state['transaction_id_filter'] = Map<String, dynamic>.from(data);
    _notify();
  }

  bool _txTypeMatch(Map<String, dynamic> c, int index) {
    final String ty = '${c['type'] ?? ''}';
    switch (index) {
      case 0:
        return true;
      case 1:
        return ty == 'in';
      case 2:
        return ty == 'out';
      case 3:
        return ty == 'pending' || ty == 'pool';
      case 4:
        return ty == 'snode';
      case 5:
        return ty == 'stake';
      case 6:
        return ty == 'failed';
      default:
        return true;
    }
  }

  List<dynamic> get filteredTransactions {
    final txList =
        ((wallet['transactions'] as Map?)?['tx_list'] as List<dynamic>?) ??
            const <dynamic>[];
    final Map<String, dynamic> tf =
        _state['transactions_filter'] as Map<String, dynamic>;
    final Map<String, dynamic> tid =
        _state['transaction_id_filter'] as Map<String, dynamic>;
    final String tidVal = '${tid['value'] ?? ''}';
    final int idx = tf['index'] as int? ?? 0;
    final Object cacheKey = Object.hash(_transactionsRevision, idx, tidVal);
    if (_filteredTransactionsCacheKey == cacheKey &&
        _filteredTransactionsCache != null) {
      return _filteredTransactionsCache!;
    }
    Iterable<dynamic> out = txList.where(
        (dynamic x) => _txTypeMatch(Map<String, dynamic>.from(x as Map), idx));
    if (tidVal.isNotEmpty) {
      out =
          out.where((dynamic x) => '${(x as Map)['txid']}'.startsWith(tidVal));
    }
    final List<dynamic> result = out.toList();
    _filteredTransactionsCacheKey = cacheKey;
    _filteredTransactionsCache = result;
    return result;
  }

  Map<String, dynamic> get poolsRoot =>
      Map<String, dynamic>.from(_state['pools'] as Map? ?? <String, dynamic>{});

  int get poolCount {
    final Map<String, dynamic> p = poolsRoot;
    final List<dynamic> op =
        p['operator_pools'] as List<dynamic>? ?? const <dynamic>[];
    final List<dynamic> nop =
        p['nonoperator_pools'] as List<dynamic>? ?? const <dynamic>[];
    return op.length + nop.length;
  }

  int get activePoolCount {
    final Map<String, dynamic>? st =
        (poolsRoot['staker'] as Map?)?.cast<String, dynamic>();
    final Map<String, dynamic>? stake = st?['stake'] as Map<String, dynamic>?;
    return (stake?['active_pool_count'] as num?)?.toInt() ?? 0;
  }

  num get totalContributedStake {
    final Map<String, dynamic>? st =
        (poolsRoot['staker'] as Map?)?.cast<String, dynamic>();
    final Map<String, dynamic>? stake = st?['stake'] as Map<String, dynamic>?;
    return stake?['total_contributed'] as num? ?? 0;
  }

  static bool _poolPassesPoolsFilterIndex(Map<String, dynamic> c, int index) {
    final num tc = num.tryParse('${c['total_contributed']}') ?? 0;
    final num sr = num.tryParse('${c['staking_requirement']}') ?? 0;
    switch (index) {
      case 0:
        return true;
      case 1:
        return tc < sr;
      case 2:
        return tc == sr;
      case 3:
        return c['is_operator'] == true;
      case 4:
        return c['is_contributor'] == true;
      default:
        return true;
    }
  }

  /// Same filtering rules as `store/gateway/getters.js` `filterPools`.
  List<Map<String, dynamic>> filteredPools(String poolType) {
    final Map<String, dynamic> p = poolsRoot;
    final List<dynamic> raw = poolType == 'operator_pools'
        ? (p['operator_pools'] as List<dynamic>? ?? const <dynamic>[])
        : (p['nonoperator_pools'] as List<dynamic>? ?? const <dynamic>[]);
    final Map<String, dynamic> pf =
        _state['pools_filter'] as Map<String, dynamic>;
    final int idx = pf['index'] as int? ?? 0;
    final String nid =
        '${(_state['node_id_filter'] as Map<String, dynamic>)['value'] ?? ''}';
    final String oid =
        '${(_state['operator_id_filter'] as Map<String, dynamic>)['value'] ?? ''}';
    final bool isDefault = idx == 0 && nid.isEmpty && oid.isEmpty;
    Iterable<Map<String, dynamic>> it =
        raw.map((dynamic e) => Map<String, dynamic>.from(e as Map));
    if (!isDefault) {
      it = it.where(
          (Map<String, dynamic> c) => _poolPassesPoolsFilterIndex(c, idx));
      if (nid.isNotEmpty) {
        it = it.where((Map<String, dynamic> c) =>
            '${c['service_node_pubkey']}'.startsWith(nid));
      }
      if (oid.isNotEmpty) {
        it = it.where((Map<String, dynamic> c) =>
            '${c['operator_address']}'.startsWith(oid));
      }
    }
    return it.toList();
  }

  void setPoolsFilterState(Map<String, dynamic> data) {
    _state['pools_filter'] = Map<String, dynamic>.from(data);
    _notify();
  }

  void setNodeIdFilterState(Map<String, dynamic> data) {
    _state['node_id_filter'] = Map<String, dynamic>.from(data);
    _notify();
  }

  void setOperatorIdFilterState(Map<String, dynamic> data) {
    _state['operator_id_filter'] = Map<String, dynamic>.from(data);
    _notify();
  }

  void resetPoolsData() {
    setPoolsData(<String, dynamic>{
      'operator_pools': <dynamic>[],
      'nonoperator_pools': <dynamic>[],
      'staker': <String, dynamic>{
        'stake': <String, dynamic>{
          'burnt_xeq': 0,
          'total_staked': 0,
          'staked_nodes': 0,
          'num_operating': 0,
          'total_contributed': 0,
          'active_pool_count': 0,
        },
      },
    });
  }
}
