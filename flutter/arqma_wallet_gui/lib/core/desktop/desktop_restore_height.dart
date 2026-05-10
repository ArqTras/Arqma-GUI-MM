import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'daemon_json_rpc.dart';

/// Port of `wallet_rpc_electron::timestamp_to_height` (daemon `get_block_header_by_height` / `get_last_block_header`).
Future<int?> timestampToHeight(String host, int port, int rawTs) async {
  int ts = rawTs;
  if (ts > 999999999999) {
    ts = ts ~/ 1000;
  }
  int pivotH = 137500;
  int pivotTs = 1528073506;
  for (int i = 0; i < 12; i++) {
    final int diff = (ts - pivotTs) ~/ 240;
    int estimatedHeight = math.max(0, pivotH + diff);
    final Map<String, dynamic>? r = await DaemonJsonRpc.post(
      host,
      port,
      'get_block_header_by_height',
      params: <String, dynamic>{'height': estimatedHeight},
    );
    if (r == null) {
      return null;
    }
    if (r['error'] != null) {
      final int? code = (r['error'] as Map?)?['code'] as int?;
      if (code == -2) {
        final Map<String, dynamic>? last =
            await DaemonJsonRpc.post(host, port, 'get_last_block_header');
        if (last == null || last['error'] != null) {
          return null;
        }
        final Map<String, dynamic>? bh =
            (last['result'] as Map?)?['block_header'] as Map<String, dynamic>?;
        if (bh == null) {
          return null;
        }
        final int newH = _blockHeight(bh);
        final int newTs = _blockTimestamp(bh);
        if ((ts - newTs).abs() < 3600) {
          return newH;
        }
        pivotH = newH;
        pivotTs = newTs;
        continue;
      }
      debugPrint('[restore_height] daemon error: ${r['error']}');
      return null;
    }
    final Map<String, dynamic>? bh =
        (r['result'] as Map?)?['block_header'] as Map<String, dynamic>? ??
            r['result'] as Map<String, dynamic>?;
    if (bh == null) {
      return null;
    }
    final int newH = _blockHeight(bh);
    final int newTs = _blockTimestamp(bh);
    if ((ts - newTs).abs() < 3600) {
      return newH;
    }
    pivotH = newH;
    pivotTs = newTs;
  }
  return math.max(0, pivotH);
}

int _blockHeight(Map<String, dynamic> bh) {
  final Object? h = bh['height'];
  if (h is int) {
    return h;
  }
  if (h is num) {
    return h.toInt();
  }
  return 0;
}

int _blockTimestamp(Map<String, dynamic> bh) {
  final Object? t = bh['timestamp'];
  if (t is int) {
    return t;
  }
  if (t is num) {
    return t.toInt();
  }
  return 0;
}

/// Port of `resolve_restore_refresh_height`.
Future<int?> resolveRestoreRefreshHeight({
  required String host,
  required int port,
  required Map<String, dynamic> p,
}) async {
  final String rt = '${p['refresh_type'] ?? 'height'}';
  if (rt != 'date') {
    final Object? h = p['refresh_start_height'];
    if (h is int) {
      return h;
    }
    if (h is num) {
      return h.toInt();
    }
    if (h is String) {
      return int.tryParse(h);
    }
    return null;
  }
  final String? dateStr = p['refresh_start_date'] as String?;
  if (dateStr == null || dateStr.isEmpty) {
    return null;
  }
  try {
    final List<String> parts = dateStr.split('/');
    if (parts.length != 3) {
      return null;
    }
    final int y = int.parse(parts[0]);
    final int m = int.parse(parts[1]);
    final int d = int.parse(parts[2]);
    final DateTime utc = DateTime.utc(y, m, d);
    final int ts = utc.millisecondsSinceEpoch ~/ 1000;
    return timestampToHeight(host, port, ts);
  } catch (e) {
    debugPrint('[restore_height] date parse: $e');
    return null;
  }
}
