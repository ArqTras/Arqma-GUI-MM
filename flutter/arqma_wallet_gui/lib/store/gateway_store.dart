import 'package:flutter/foundation.dart';

import '../core/utils/deep_merge.dart';
import 'gateway_default_state.dart';

typedef GatewayEventListener = void Function(String event, dynamic data);

/// Vuex `gateway` module + `receiver.js` commit paths, backed by a deep tree.
class GatewayStore extends ChangeNotifier {
  GatewayStore() : _state = defaultGatewayState();

  Map<String, dynamic> _state;

  Map<String, dynamic> get raw => _state;

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
    app.clear();
    app.addAll(merged);
    _notify();
  }

  void setDaemonData(Map<String, dynamic> data) {
    final d = daemon;
    final merged = deepMergeMaps(d, data) as Map<String, dynamic>;
    d.clear();
    d.addAll(merged);
    _notify();
  }

  void resetWalletData(Map<String, dynamic> data) {
    final w = wallet;
    final merged = deepMergeMaps(w, data) as Map<String, dynamic>;
    w.clear();
    w.addAll(merged);
    _notify();
  }

  void setWalletError(Map<String, dynamic> data) {
    resetWalletData(data);
  }

  void setWalletTransactions(Map<String, dynamic> data) {
    wallet['transactions'] = data;
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
    _notify();
  }

  void setWalletAddressList(Map<String, dynamic> data) {
    final al = wallet['address_list'] as Map<String, dynamic>;
    final merged = deepMergeMaps(al, data) as Map<String, dynamic>;
    al.clear();
    al.addAll(merged);
    _notify();
  }

  void setWalletAddressBook(Map<String, dynamic> data) {
    setWalletAddressList(data);
  }

  void setWalletInfo(Map<String, dynamic> data) {
    final patch = Map<String, dynamic>.from(data);
    if (patch['height'] != null && patch['height'] != '') {
      final incoming = num.tryParse('${patch['height']}') ?? 0;
      final cur = num.tryParse('${(wallet['info'] as Map)['height']}') ?? 0;
      final sameWallet = patch['name'] == null ||
          patch['name'] == '' ||
          (wallet['info'] as Map)['name'] == null ||
          (wallet['info'] as Map)['name'] == '' ||
          patch['name'] == (wallet['info'] as Map)['name'];
      if (sameWallet && cur > 0 && incoming < cur) {
        patch['height'] = cur;
      } else {
        patch['height'] = incoming;
      }
    }
    if (patch['balance'] != null && patch['balance'] != '') {
      patch['balance'] = num.tryParse('${patch['balance']}') ?? 0;
    }
    if (patch['unlocked_balance'] != null && patch['unlocked_balance'] != '') {
      patch['unlocked_balance'] = num.tryParse('${patch['unlocked_balance']}') ?? 0;
    }
    if (patch['scan_poll_ts'] != null && patch['scan_poll_ts'] != '') {
      patch['scan_poll_ts'] = num.tryParse('${patch['scan_poll_ts']}') ?? 0;
    }
    final wi = wallet['info'] as Map<String, dynamic>;
    final merged = deepMergeMaps(wi, patch) as Map<String, dynamic>;
    wi.clear();
    wi.addAll(merged);
    _notify();
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
    p.clear();
    p.addAll(merged);
    _notify();
  }

  void setCoinPrice(dynamic data) {
    _state['coin_price'] = data;
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
    u.clear();
    u.addAll(merged);
    _notify();
  }

  void setEthereumData(Map<String, dynamic> data) {
    final e = _state['ethereum'] as Map<String, dynamic>;
    final merged = deepMergeMaps(e, data) as Map<String, dynamic>;
    e.clear();
    e.addAll(merged);
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
    final dataSigs = data.map((e) => (e as Map)['signature'].toString()).toSet();
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
        if ((_state['signature_data'] as List).isEmpty && (data as List).isEmpty) {
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
        setDaemonVersion((data as Map)['version'] as String? ?? '');
        break;
      default:
        break;
    }
  }

  // --- Getters (`store/gateway/getters.js`) ---

  int _daemonChainTip() {
    final info = daemon['info'] as Map<String, dynamic>? ?? {};
    final h = num.tryParse('${info['height']}') ?? 0;
    final th = num.tryParse('${info['target_height']}') ?? 0;
    return h > th ? h.toInt() : th.toInt();
  }

  bool get isReady {
    final targetHeight = _daemonChainTip();
    if (targetHeight == 0) {
      return false;
    }
    final wh = num.tryParse('${walletInfo['height']}') ?? 0;
    if (wh != targetHeight) {
      return false;
    }
    final cfg = app['config'] as Map<String, dynamic>?;
    final net = (cfg?['app'] as Map?)?['net_type'] as String?;
    final dt = (cfg?['daemons'] as Map?)?[net] as Map?;
    final dtype = dt?['type'] as String?;
    if (dtype == 'local' || dtype == 'local_remote') {
      final hwo = num.tryParse('${(daemon['info'] as Map)['height_without_bootstrap']}') ?? 0;
      if (hwo < targetHeight) {
        return false;
      }
    }
    return true;
  }

  bool get isAbleToSend {
    final cfg = app['config'] as Map<String, dynamic>?;
    final net = (cfg?['app'] as Map?)?['net_type'] as String?;
    final daemons = cfg?['daemons'] as Map<String, dynamic>?;
    final configDaemon = daemons?[net] as Map<String, dynamic>? ?? {'type': 'local'};
    final targetHeight = _daemonChainTip();
    if (targetHeight == 0) {
      return false;
    }
    final walletAtTip = (num.tryParse('${walletInfo['height']}') ?? 0) == targetHeight;
    if (configDaemon['type'] == 'local_remote') {
      final hwo = num.tryParse('${(daemon['info'] as Map)['height_without_bootstrap']}') ?? 0;
      return hwo >= targetHeight && walletAtTip;
    }
    return walletAtTip;
  }

  List<dynamic> get filteredTransactions {
    final txList =
        ((wallet['transactions'] as Map?)?['tx_list'] as List<dynamic>?) ?? const <dynamic>[];
    final tf = _state['transactions_filter'] as Map<String, dynamic>;
    final tid = _state['transaction_id_filter'] as Map<String, dynamic>;
    final tidVal = '${tid['value'] ?? ''}';
    if ((tf['index'] as int? ?? 0) == 0 && tidVal.isEmpty) {
      return List<dynamic>.from(txList);
    }
    // Predicate from JS not serializable — list unfiltered when custom filter is set until per-screen logic lands.
    if (tidVal.isNotEmpty) {
      return txList.where((c) => '${(c as Map)['txid']}'.startsWith(tidVal)).toList();
    }
    return List<dynamic>.from(txList);
  }
}
