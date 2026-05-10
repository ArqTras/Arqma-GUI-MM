import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'wallet_json_rpc.dart';

/// Minimal JSON-RPC client for `arqmad` (`get_info`), same wire format as Tauri `daemon_post`.
///
/// **Tauri parity:** `tauri-app/src-tauri/src/lib.rs` builds the shared `reqwest::Client` with
/// **`.timeout(Duration::from_secs(120))`** for daemon + wallet HTTP. The daemon heartbeat uses
/// `get_info` only (see `daemon_heartbeat.rs`). Wallet **`getheight`** is **wallet-rpc**, not `arqmad`.
class DaemonJsonRpc {
  DaemonJsonRpc._();

  /// Default for heartbeat / footer polling — matches Tauri reqwest total request budget.
  static const Duration defaultDaemonConnectTimeout = Duration(seconds: 30);
  static const Duration defaultDaemonRequestTimeout = Duration(seconds: 120);

  /// Short probes: `checkDaemonReachable`, `daemon_version_probe`, remote scan (explicit overrides).
  static const Duration probeConnectTimeout = Duration(seconds: 6);
  static const Duration probeRequestTimeout = Duration(seconds: 20);

  /// Same rule as Tauri `json_rpc_client::daemon_post`: omit `params` when null, empty map, or
  /// empty list — `arqmad` rejects some methods with `-32600 Invalid Request` if `"params": {}`.
  static Map<String, dynamic> _daemonJsonRpcBody(
      String method, Object? params) {
    final Map<String, dynamic> m = <String, dynamic>{
      'jsonrpc': '2.0',
      // Monero docs / `remote_scan.rs` use string `"0"`; epee stores `id` as `std::string` on wire.
      'id': '0',
      'method': method,
    };
    if (params == null) {
      return m;
    }
    if (params is Map && params.isEmpty) {
      return m;
    }
    if (params is List && params.isEmpty) {
      return m;
    }
    if (params is Map<String, dynamic>) {
      m['params'] = params;
    } else if (params is Map) {
      m['params'] = Map<String, dynamic>.from(params);
    } else {
      m['params'] = params;
    }
    return m;
  }

  static Future<Map<String, dynamic>?> post(
    String host,
    int port,
    String method, {
    Object? params,
    Duration? connectTimeout,
    Duration? requestTimeout,
  }) async {
    final Duration ct = connectTimeout ?? defaultDaemonConnectTimeout;
    final Duration rt = requestTimeout ?? defaultDaemonRequestTimeout;
    final HttpClient client = HttpClient();
    client.connectionTimeout = ct;
    client.idleTimeout = ct;
    try {
      Future<Map<String, dynamic>?> run() async {
        final Uri uri =
            Uri(scheme: 'http', host: host, port: port, path: '/json_rpc');
        final HttpClientRequest req = await client.postUrl(uri);
        // Monero `invoke_http_json` uses `application/json; charset=utf-8`. Some daemons mis-parse
        // chunked bodies — set Content-Length explicitly (avoids Transfer-Encoding: chunked).
        final List<int> bytes = utf8.encode(
          jsonEncode(_daemonJsonRpcBody(method, params)),
        );
        req.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        req.headers.contentLength = bytes.length;
        req.add(bytes);
        final HttpClientResponse resp = await req.close();
        final String text = await utf8.decoder.bind(resp).join();
        if (resp.statusCode != 200) {
          debugPrint('[DaemonJsonRpc] HTTP ${resp.statusCode} $text');
          return null;
        }
        final Object? decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
        return null;
      }

      return await run().timeout(
        rt,
        onTimeout: () {
          debugPrint(
            '[DaemonJsonRpc] $method timed out after $rt — tried http://$host:$port/json_rpc',
          );
          return null;
        },
      );
    } catch (e, st) {
      debugPrint('[DaemonJsonRpc] $method failed: $e\n$st');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// When [connectTimeout] / [requestTimeout] are null, uses [defaultDaemonConnectTimeout] /
  /// [defaultDaemonRequestTimeout] (Tauri `reqwest` 120s-style budget for slow `get_info`).
  static Future<Map<String, dynamic>?> getInfo(
    String host,
    int port, {
    Duration? connectTimeout,
    Duration? requestTimeout,
  }) async {
    return post(
      host,
      port,
      'get_info',
      connectTimeout: connectTimeout ?? defaultDaemonConnectTimeout,
      requestTimeout: requestTimeout ?? defaultDaemonRequestTimeout,
    );
  }

  static Map<String, dynamic>? result(Map<String, dynamic>? response) {
    if (response == null || !walletJsonRpcNoError(response)) {
      return null;
    }
    final Object? r = response['result'];
    if (r is Map<String, dynamic>) {
      return r;
    }
    if (r is Map) {
      return Map<String, dynamic>.from(r);
    }
    return null;
  }

  /// Some `arqmad` builds return `height` only under `result.info` or nested `result.result`
  /// (Rust code uses `/result/nettype` with fallback to `/result/result/nettype`).
  static Map<String, dynamic> normalizeGetInfoMap(Map<String, dynamic> r) {
    Map<String, dynamic> m = Map<String, dynamic>.from(r);
    for (int i = 0; i < 6 && m['height'] == null; i++) {
      final Object? inner = m['result'];
      if (inner is! Map) {
        break;
      }
      final Map<String, dynamic> innerMap = Map<String, dynamic>.from(inner);
      if (innerMap['height'] != null) {
        m = innerMap;
        continue;
      }
      final Object? bc = innerMap['blockchain'];
      if (bc is Map) {
        final Map<String, dynamic> bcm = Map<String, dynamic>.from(bc);
        if (bcm['height'] != null) {
          m = bcm;
          continue;
        }
      }
      if (innerMap['result'] is Map) {
        m = innerMap;
        continue;
      }
      break;
    }
    final Object? info = m['info'];
    if (info is Map) {
      final Map<String, dynamic> infoMap = Map<String, dynamic>.from(info);
      final Map<String, dynamic> merged = Map<String, dynamic>.from(m);
      merged.remove('info');
      infoMap.forEach((String k, dynamic v) {
        merged[k] = v;
      });
      return merged;
    }
    return m;
  }

  /// Like [result] but flattens `get_info`-specific nesting so `height` / `target_height` match Vue.
  static Map<String, dynamic>? getInfoPayload(Map<String, dynamic>? response) {
    final Map<String, dynamic>? base = result(response);
    if (base == null) {
      return null;
    }
    return normalizeGetInfoMap(base);
  }
}
