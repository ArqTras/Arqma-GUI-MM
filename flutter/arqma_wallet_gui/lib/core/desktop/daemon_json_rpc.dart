import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Minimal JSON-RPC client for `arqmad` (`get_info`), same wire format as Tauri `daemon_post`.
class DaemonJsonRpc {
  DaemonJsonRpc._();

  static Future<Map<String, dynamic>?> post(
    String host,
    int port,
    String method,
    Object params,
  ) async {
    final HttpClient client = HttpClient();
    try {
      final Uri uri = Uri(scheme: 'http', host: host, port: port, path: '/json_rpc');
      final HttpClientRequest req = await client.postUrl(uri);
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
    } catch (e, st) {
      debugPrint('[DaemonJsonRpc] $method failed: $e\n$st');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>?> getInfo(String host, int port) async {
    return post(host, port, 'get_info', <String, dynamic>{});
  }

  static Map<String, dynamic>? result(Map<String, dynamic>? response) {
    if (response == null) {
      return null;
    }
    if (response['error'] != null) {
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
}
