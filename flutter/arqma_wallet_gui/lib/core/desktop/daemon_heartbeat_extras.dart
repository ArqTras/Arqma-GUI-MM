import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'daemon_json_rpc.dart' show DaemonJsonRpc, readHttpResponseBodyUtf8;

/// `daemon_heartbeat::explorer_clock_skew` — returns `true` if local clock skew vs explorer is large.
Future<bool?> explorerClockSkewArqma({required bool testnet}) async {
  final Uri uri = Uri.parse(
    testnet
        ? 'https://stageblocks.arqma.com/api/networkinfo'
        : 'https://explorer.arqma.com/api/networkinfo',
  );
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final HttpClientResponse resp =
        await req.close().timeout(const Duration(seconds: 12));
    final String text = await readHttpResponseBodyUtf8(resp);
    if (resp.statusCode != 200) {
      return null;
    }
    final Object? decoded = jsonDecode(text);
    if (decoded is! Map) {
      return null;
    }
    final Object? data = decoded['data'];
    if (data is! Map) {
      return null;
    }
    final Object? st = data['server_time'];
    final int? serverTime = st is num ? st.toInt() : int.tryParse('$st');
    if (serverTime == null) {
      return null;
    }
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const int allowed = 15 * 60;
    return (now - serverTime).abs() > allowed;
  } catch (e, st) {
    debugPrint('[daemon_hb] explorerClockSkew: $e\n$st');
    return null;
  } finally {
    client.close(force: true);
  }
}

/// `daemon_heartbeat::tick_slow` — merge RPC snippets into one `set_daemon_data` payload.
Future<Map<String, dynamic>> collectSlowDaemonHeartbeat(
    String host, int port) async {
  final Map<String, dynamic> out = <String, dynamic>{};
  final Map<String, dynamic>? c1 = await DaemonJsonRpc.post(
    host,
    port,
    'get_connections',
    quiet: true,
    connectTimeout: DaemonJsonRpc.probeConnectTimeout,
    requestTimeout: DaemonJsonRpc.probeRequestTimeout,
  );
  final Map<String, dynamic>? c2 = await DaemonJsonRpc.post(
    host,
    port,
    'get_bans',
    quiet: true,
    connectTimeout: DaemonJsonRpc.probeConnectTimeout,
    requestTimeout: DaemonJsonRpc.probeRequestTimeout,
  );
  final Map<String, dynamic>? c3 = await DaemonJsonRpc.post(
    host,
    port,
    'get_txpool_backlog',
    quiet: true,
    connectTimeout: DaemonJsonRpc.probeConnectTimeout,
    requestTimeout: DaemonJsonRpc.probeRequestTimeout,
  );
  final Object? con = DaemonJsonRpc.result(c1)?['connections'];
  if (con != null) {
    out['connections'] = con;
  }
  final Object? bans = DaemonJsonRpc.result(c2)?['bans'];
  if (bans != null) {
    out['bans'] = bans;
  }
  final Object? backlog = DaemonJsonRpc.result(c3)?['backlog'];
  if (backlog != null) {
    out['tx_pool_backlog'] = backlog;
  }
  return out;
}
