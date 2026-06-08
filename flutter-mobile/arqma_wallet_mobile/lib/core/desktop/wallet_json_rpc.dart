import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'bridge_log_redact.dart';

/// Same success rule as `json_util::json_rpc_no_error`.
bool walletJsonRpcNoError(Map<String, dynamic>? v) {
  if (v == null) {
    return false;
  }
  final Object? e = v['error'];
  if (e == null) {
    return true;
  }
  if (e == false) {
    return true;
  }
  if (e is Map && e.isEmpty) {
    return true;
  }
  return false;
}

/// Maps opaque C++ exception labels to user-facing text.
String _sanitizeWalletRpcErrorMessage(String raw) {
  final String m = raw.trim();
  if (m.isEmpty) {
    return raw;
  }
  if (m.contains('basic_string') ||
      m.endsWith(': std::exception') ||
      m == 'std::exception') {
    return 'Wallet operation failed after sleep or background sync — close the app and try again, or reopen the account.';
  }
  return m;
}

/// Human-readable JSON-RPC error for snackbars and dialogs.
String walletJsonRpcErrorMessage(Map<String, dynamic>? v, {String fallback = 'Unknown error'}) {
  if (v == null) {
    return fallback;
  }
  final Object? e = v['error'];
  if (e is Map) {
    final String? m = e['message'] as String?;
    if (m != null && m.isNotEmpty) {
      return _sanitizeWalletRpcErrorMessage(m);
    }
  }
  if (e is String && e.isNotEmpty) {
    return _sanitizeWalletRpcErrorMessage(e);
  }
  return fallback;
}

Map<String, dynamic>? _walletGetheightResult(Map<String, dynamic>? v) {
  if (v == null || !walletJsonRpcNoError(v)) {
    return null;
  }
  final Object? r = v['result'];
  if (r is Map) {
    return Map<String, dynamic>.from(r);
  }
  return null;
}

int? walletHeightFromGetheight(Map<String, dynamic>? v) {
  final Map<String, dynamic>? rm = _walletGetheightResult(v);
  if (rm == null) {
    return null;
  }
  return jsonRpcLooseInt(rm['height']);
}

int? walletDaemonHeightFromGetheight(Map<String, dynamic>? v) {
  final Map<String, dynamic>? rm = _walletGetheightResult(v);
  if (rm == null) {
    return null;
  }
  return jsonRpcLooseInt(rm['daemon_height']);
}

bool walletBackgroundBusyFromGetheight(Map<String, dynamic>? v) {
  final Map<String, dynamic>? rm = _walletGetheightResult(v);
  if (rm == null) {
    return false;
  }
  return rm['background_busy'] == true;
}

/// Integer fields from JSON-RPC (`height`, fee counts, …) — often `int`, `num`, or decimal string.
int? jsonRpcLooseInt(Object? v) {
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.toInt();
  }
  if (v is String) {
    return int.tryParse(v);
  }
  return null;
}

/// HTTP JSON-RPC to `arqma-wallet-rpc` with `--rpc-login` Basic auth.
final class WalletJsonRpcClient {
  WalletJsonRpcClient({
    required this.host,
    required this.port,
    required this.user,
    required this.pass,
  });

  final String host;
  final int port;
  final String user;
  final String pass;

  Future<Map<String, dynamic>?> call(String method, Object params) async {
    final HttpClient client = HttpClient();
    try {
      final Uri uri =
          Uri(scheme: 'http', host: host, port: port, path: '/json_rpc');
      final HttpClientRequest req = await client.postUrl(uri);
      final String token = base64Encode(utf8.encode('$user:$pass'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Basic $token');
      req.headers.contentType = ContentType.json;
      req.add(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': '0',
            'method': method,
            'params': params,
          }),
        ),
      );
      final HttpClientResponse resp = await req.close();
      final String text = await utf8.decoder.bind(resp).join();
      if (resp.statusCode != 200) {
        debugPrint(
          '[WalletJsonRpc] HTTP ${resp.statusCode} ${truncateLogText(text)}',
        );
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
    } catch (e, st) {
      debugPrint('[WalletJsonRpc] $method: $e\n$st');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
