import 'dart:math' as math;

import 'arqma_paths.dart';
import 'daemon_json_rpc.dart';
import 'wallet_json_rpc.dart';

const double _stakingShare = 18446744073709551612.0;
const double _coinUnits = 1e9;

String _enUsGroupU64(int n) {
  if (n <= 0) {
    return '0';
  }
  final String s = n.toString();
  int firstLen = s.length % 3;
  if (firstLen == 0) {
    firstLen = 3;
  }
  final StringBuffer buf = StringBuffer(s.substring(0, firstLen));
  for (int i = firstLen; i < s.length; i += 3) {
    buf.write(',');
    buf.write(s.substring(i, math.min(i + 3, s.length)));
  }
  return buf.toString();
}

String _enUsFormatAmount(double n) {
  if (!n.isFinite) {
    return '0';
  }
  final String sign = n < 0 ? '-' : '';
  double x = n.abs();
  if (x < 1e-12) {
    return '${sign}0';
  }
  x = (x * 1e9).round() / 1e9;
  String s = x.toStringAsFixed(9);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  final List<String> parts = s.split('.');
  final int intPart = int.tryParse(parts[0]) ?? 0;
  final String intS = _enUsGroupU64(intPart);
  if (parts.length < 2 || parts[1].isEmpty) {
    return '$sign$intS';
  }
  final String dec = parts[1].replaceFirst(RegExp(r'0+$'), '');
  if (dec.isEmpty) {
    return '$sign$intS';
  }
  return '$sign$intS.$dec';
}

String _enUsFormatPercent(double n) {
  if (!n.isFinite || n == 0) {
    return '';
  }
  return _enUsFormatAmount((n * 1e6).round() / 1e6);
}

Object _operatorFee(double portions) {
  if (portions == 0) {
    return 0;
  }
  if ((portions - _stakingShare).abs() < 1.0) {
    return '';
  }
  final double x = (portions / _stakingShare) * 100.0;
  if (x >= 100.0) {
    return '';
  }
  return '${x.round()} %';
}

Map<String, dynamic> _unlockTime(int requested, int height) {
  if (requested == 0) {
    return <String, dynamic>{'amount': '', 'i18n': ''};
  }
  final int br = requested - height;
  if (br <= 0) {
    return <String, dynamic>{
      'amount': '0',
      'i18n': 'components.pool_list_tabular.days'
    };
  }
  if (br < 720) {
    final double h = br / 30.0;
    return <String, dynamic>{
      'amount': h.toStringAsFixed(1),
      'i18n': 'components.pool_list_tabular.hours'
    };
  }
  final int d = ((br / 720.0).ceil());
  return <String, dynamic>{
    'amount': '$d',
    'i18n': 'components.pool_list_tabular.days'
  };
}

/// Tauri `wallet_pools` uses `/result/service_node_states`; some daemons nest another `result`.
List<dynamic>? _serviceNodeStatesFromRpc(Map<String, dynamic> sn) {
  if (!walletJsonRpcNoError(sn)) {
    return null;
  }
  Object? r = sn['result'];
  for (int i = 0; i < 4; i++) {
    if (r is! Map) {
      break;
    }
    final Map<String, dynamic> m = Map<String, dynamic>.from(r);
    final Object? states = m['service_node_states'];
    if (states is List) {
      return List<dynamic>.from(states);
    }
    // Some builds expose the array under alternate keys.
    final Object? alt = m['service_nodes'] ?? m['snodes'];
    if (alt is List) {
      return List<dynamic>.from(alt);
    }
    final Object? inner = m['result'];
    if (inner is Map) {
      r = inner;
      continue;
    }
    break;
  }
  if (r is List) {
    return List<dynamic>.from(r);
  }
  // Electron `wallet-rpc.js`: if `service_node_states` is missing, treat as empty list (still success).
  return <dynamic>[];
}

int _regHeight(Map<String, dynamic> v) {
  final Object? h = v['registration_height'];
  if (h is int) {
    return h;
  }
  if (h is num) {
    return h.toInt();
  }
  return 0;
}

void _sortOperatorPools(List<Map<String, dynamic>> pools) {
  pools.sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
      _regHeight(b).compareTo(_regHeight(a)));
}

void _sortNonoperatorPools(List<Map<String, dynamic>> pools) {
  pools.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
    final bool ac = a['is_contributor'] == true;
    final bool bc = b['is_contributor'] == true;
    if (ac && !bc) {
      return -1;
    }
    if (!ac && bc) {
      return 1;
    }
    return _regHeight(b).compareTo(_regHeight(a));
  });
}

double _asDouble(Object? v) {
  if (v == null) {
    return 0;
  }
  if (v is double) {
    return v;
  }
  if (v is int) {
    return v.toDouble();
  }
  if (v is num) {
    return v.toDouble();
  }
  return double.tryParse('$v') ?? 0;
}

/// Port of `wallet_pools::run_pool_tick` — emits `set_pools_data` like Tauri.
Future<void> runDesktopStakePoolsTick({
  required void Function(Map<String, dynamic>) emit,
  required Map<String, dynamic> configData,
  required Future<Map<String, dynamic>?> Function(
          String method, Map<String, dynamic> params)
      walletCall,
}) async {
  final ({String host, int port})? ep = daemonRpcHostPort(configData);
  if (ep == null) {
    return;
  }
  final Map<String, dynamic>? ginfo =
      await DaemonJsonRpc.getInfo(ep.host, ep.port);
  final Map<String, dynamic>? infoRes = DaemonJsonRpc.getInfoPayload(ginfo);
  if (infoRes == null) {
    return;
  }
  final int height = (infoRes['height'] as num?)?.toInt() ?? 0;

  final Map<String, dynamic>? addrR =
      await walletCall('get_address', <String, dynamic>{'account_index': 0});
  if (!walletJsonRpcNoError(addrR) || addrR == null) {
    return;
  }
  final Object? res = addrR['result'];
  final String my =
      (res is Map && res['address'] != null) ? '${res['address']}' : '';
  if (my.isEmpty) {
    return;
  }

  final Map<String, dynamic>? sn =
      await DaemonJsonRpc.post(ep.host, ep.port, 'get_service_nodes');
  if (sn == null) {
    return;
  }
  final List<dynamic>? states = _serviceNodeStatesFromRpc(sn);
  if (states == null) {
    return;
  }

  double totalContributedSum = 0;
  int activeCount = 0;
  int stakedNodesN = 0;
  int numOper = 0;
  double totalStakedAmt = 0;
  final List<Map<String, dynamic>> op = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> nOp = <Map<String, dynamic>>[];

  for (final Object? poolObj in states) {
    if (poolObj is! Map) {
      continue;
    }
    final Map<String, dynamic> pool = Map<String, dynamic>.from(poolObj);
    final double totalC = _asDouble(pool['total_contributed']);
    totalContributedSum += totalC / _coinUnits;
    if (pool['funded'] == true) {
      activeCount++;
    }
    final String stakedS = _enUsFormatAmount(totalC / _coinUnits);
    final double req = _asDouble(pool['staking_requirement']);
    final String avail = _enUsFormatAmount(
        ((req - totalC) / _coinUnits).clamp(0.0, double.infinity));
    final int runl = (pool['requested_unlock_height'] as num?)?.toInt() ?? 0;
    final Map<String, dynamic> lock = _unlockTime(runl, height);
    final double portions = _asDouble(pool['portions_for_operator']);
    final Object opFee = _operatorFee(portions);
    final String opAddr = '${pool['operator_address'] ?? ''}';

    final Map<String, dynamic> fpool = <String, dynamic>{
      'service_node_pubkey': pool['service_node_pubkey'],
      'operator_address': opAddr,
      'registration_height': pool['registration_height'],
      'funded': pool['funded'],
      'staked': stakedS,
      'equity': '',
      'lockup': lock,
      'available': avail,
      'operator_fee': opFee,
      'is_contributor': false,
      'is_operator': false,
      'contributors': (pool['contributors'] is List)
          ? (pool['contributors'] as List).length
          : 0,
      'requested_unlock_height': pool['requested_unlock_height'],
      'last_reward_block_height': pool['last_reward_block_height'],
      'last_uptime_proof': pool['last_uptime_proof'],
      'staking_requirement': pool['staking_requirement'],
      'total_contributed': pool['total_contributed'],
    };

    if (opAddr != my) {
      final List<dynamic>? cont = pool['contributors'] as List<dynamic>?;
      if (cont != null && cont.isNotEmpty) {
        final bool anyMe = cont.any((Object? k) {
          if (k is! Map) {
            return false;
          }
          return '${k['address']}' == my;
        });
        if (anyMe) {
          double amount = 0;
          for (final Object? c in cont) {
            if (c is! Map) {
              continue;
            }
            final Map<String, dynamic> cm = Map<String, dynamic>.from(c);
            if ('${cm['address']}' == my) {
              amount += _asDouble(cm['amount']);
            }
          }
          final double eq = totalC > 0 ? (amount / totalC) * 100.0 : 0.0;
          fpool['equity'] = _enUsFormatPercent(eq);
          fpool['is_contributor'] = true;
          fpool['is_operator'] = false;
          nOp.add(fpool);
          stakedNodesN++;
        } else {
          nOp.add(fpool);
        }
      } else {
        nOp.add(fpool);
      }
    } else {
      double amount = 0;
      final List<dynamic>? cont = pool['contributors'] as List<dynamic>?;
      if (cont != null) {
        for (final Object? c in cont) {
          if (c is! Map) {
            continue;
          }
          final Map<String, dynamic> cm = Map<String, dynamic>.from(c);
          if ('${cm['address']}' == my) {
            amount += _asDouble(cm['amount']);
          }
        }
      }
      final double eq = totalC > 0 ? (amount / totalC) * 100.0 : 0.0;
      fpool['equity'] = _enUsFormatPercent(eq);
      fpool['is_contributor'] = false;
      fpool['is_operator'] = true;
      op.add(fpool);
      numOper++;
      totalStakedAmt += amount / _coinUnits;
    }
  }

  _sortOperatorPools(op);
  _sortNonoperatorPools(nOp);

  emit(<String, dynamic>{
    'event': 'set_pools_data',
    'data': <String, dynamic>{
      'operator_pools': op,
      'nonoperator_pools': nOp,
      'staker': <String, dynamic>{
        'stake': <String, dynamic>{
          'burnt_xeq': 0,
          'total_staked': totalStakedAmt,
          'staked_nodes': stakedNodesN,
          'num_operating': numOper,
          'total_contributed': totalContributedSum,
          'active_pool_count': activeCount,
        },
      },
    },
  });
}
