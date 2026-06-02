import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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

/// Human-readable JSON-RPC error for snackbars and dialogs.
String walletJsonRpcErrorMessage(Map<String, dynamic>? v, {String fallback = 'Unknown error'}) {
  if (v == null) {
    return fallback;
  }
  final Object? e = v['error'];
  if (e is Map) {
    final String? m = e['message'] as String?;
    if (m != null && m.isNotEmpty) {
      return m;
    }
  }
  if (e is String && e.isNotEmpty) {
    return e;
  }
  return fallback;
}

int? walletHeightFromGetheight(Map<String, dynamic>? v) {
  if (v == null || !walletJsonRpcNoError(v)) {
    return null;
  }
  final Object? r = v['result'];
  if (r is Map) {
    final Map<String, dynamic> rm = Map<String, dynamic>.from(r);
    final Object? h = rm['height'];
    return jsonRpcLooseInt(h);
  }
  return null;
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
        debugPrint('[WalletJsonRpc] HTTP ${resp.statusCode} $text');
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
