import 'arqma_wallet_rpc_session.dart';
import 'wallet_json_rpc.dart';

/// Same numeric coercion as Tauri `wallet_heartbeat::index_u64`.
int? walletAddressIndexU64(Object? v) {
  if (v == null) {
    return null;
  }
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.toInt();
  }
  return int.tryParse('$v');
}

/// Parity with Tauri `wallet_heartbeat::build_address_list_object` — `get_address` + `getbalance`
/// JSON-RPC payloads → `{ primary, used, unused }` for `gateway/set_wallet_address_list`.
Map<String, dynamic>? buildWalletAddressListFromRpc(
  Map<String, dynamic>? gaRpc,
  Map<String, dynamic>? gbRpc,
) {
  if (gaRpc == null || gbRpc == null) {
    return null;
  }
  if (!walletJsonRpcNoError(gaRpc) || !walletJsonRpcNoError(gbRpc)) {
    return null;
  }
  final Object? ra0 = gaRpc['result'];
  final Object? rb0 = gbRpc['result'];
  if (ra0 is! Map || rb0 is! Map) {
    return null;
  }
  final Map<String, dynamic> ra = Map<String, dynamic>.from(ra0);
  final Map<String, dynamic> rb = Map<String, dynamic>.from(rb0);

  final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
  final List<dynamic>? addrArr = ra['addresses'] as List<dynamic>?;
  if (addrArr != null && addrArr.isNotEmpty) {
    for (final Object? e in addrArr) {
      if (e is Map) {
        rows.add(Map<String, dynamic>.from(e));
      }
    }
  } else {
    final String a = '${ra['address'] ?? ''}'.trim();
    if (a.isEmpty) {
      return null;
    }
    rows.add(<String, dynamic>{
      'address': a,
      'address_index': 0,
      'used': true,
    });
  }

  for (final Map<String, dynamic> m in rows) {
    m['balance'] = null;
    m['unlocked_balance'] = null;
    m['num_unspent_outputs'] = null;
  }

  final List<dynamic>? parr = rb['per_subaddress'] as List<dynamic>?;
  if (parr != null) {
    for (final Map<String, dynamic> m in rows) {
      final int? idx = walletAddressIndexU64(m['address_index']);
      if (idx == null) {
        continue;
      }
      for (final Object? ps in parr) {
        if (ps is! Map) {
          continue;
        }
        final Map<String, dynamic> pm = Map<String, dynamic>.from(ps);
        if (walletAddressIndexU64(pm['address_index']) == idx) {
          m['balance'] = pm['balance'];
          m['unlocked_balance'] = pm['unlocked_balance'] ?? pm['unlocked'];
          m['num_unspent_outputs'] = pm['num_unspent_outputs'];
          break;
        }
      }
    }
  }

  final List<Map<String, dynamic>> primary = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> usedL = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> unused = <Map<String, dynamic>>[];
  for (final Map<String, dynamic> a in rows) {
    final int? idx = walletAddressIndexU64(a['address_index']);
    final bool? isUsed = a['used'] as bool?;
    if (idx == 0) {
      primary.add(a);
    } else if (isUsed == true) {
      usedL.add(a);
    } else {
      unused.add(a);
    }
  }
  if (unused.length > 10) {
    unused.removeRange(10, unused.length);
  }
  return <String, dynamic>{
    'primary': primary,
    'used': usedL,
    'unused': unused,
  };
}

/// Parity with Tauri `wallet_heartbeat::top_up_unused_subaddresses` (pad to 10 unused rows).
Future<Map<String, dynamic>> topUpUnusedWalletAddresses(
  ArqmaWalletRpcSession w,
  Map<String, dynamic> al,
) async {
  const int limit = 10;
  final List<dynamic> primary =
      List<dynamic>.from(al['primary'] as List<dynamic>? ?? const <dynamic>[]);
  final List<dynamic> used =
      List<dynamic>.from(al['used'] as List<dynamic>? ?? const <dynamic>[]);
  final List<dynamic> unused =
      List<dynamic>.from(al['unused'] as List<dynamic>? ?? const <dynamic>[]);
  if (unused.length > limit) {
    unused.removeRange(limit, unused.length);
  }
  if (primary.isEmpty) {
    return al;
  }
  final Object? p0 = (primary[0] as Map)['address'];
  final String p0a = p0 is String ? p0.trim() : '';
  if (p0a.isEmpty) {
    return al;
  }
  if (p0a.startsWith('RYoK') || p0a.startsWith('RYoH')) {
    return <String, dynamic>{
      'primary': primary,
      'used': used,
      'unused': unused,
    };
  }
  while (unused.length < limit) {
    final Map<String, dynamic>? r = await w
        .call('create_address', <String, dynamic>{'account_index': 0});
    if (!walletJsonRpcNoError(r) || r == null || r['result'] == null) {
      break;
    }
    final Object? res = r['result'];
    if (res is Map) {
      unused.add(Map<String, dynamic>.from(res));
    } else {
      break;
    }
  }
  return <String, dynamic>{
    'primary': primary,
    'used': used,
    'unused': unused,
  };
}
