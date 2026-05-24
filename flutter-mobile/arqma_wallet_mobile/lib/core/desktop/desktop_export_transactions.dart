import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';

import 'wallet_json_rpc.dart';

const double _coinUnits = 1e9;

bool _allZerosOrWhitespace(String t) =>
    t.isEmpty || RegExp(r'^[0\s]+$').hasMatch(t);

/// Same `payment_id` rules as `wallet_handler::normalize_payment_id_for_export`.
String normalizePaymentIdForExport(String pid) {
  final String t = pid.trim();
  if (_allZerosOrWhitespace(t)) {
    return '';
  }
  if (t.length >= 16) {
    final String tail = t.substring(16);
    if (tail.split('').every((String c) => c == '0' || c.trim().isEmpty)) {
      return t.substring(0, 16);
    }
  }
  return t;
}

/// `wallet_heartbeat::merge_transfers_list`
List<Map<String, dynamic>> mergeTransfersList(Map<String, dynamic> result) {
  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  const List<String> keys = <String>[
    'in',
    'out',
    'pending',
    'failed',
    'pool',
    'miner',
    'snode',
    'gov',
    'stake',
  ];
  for (final String k in keys) {
    final Object? arr = result[k];
    if (arr is List) {
      for (final Object? x in arr) {
        if (x is Map) {
          out.add(Map<String, dynamic>.from(x));
        }
      }
    }
  }
  out.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
    final int ta = (a['timestamp'] as num?)?.toInt() ?? 0;
    final int tb = (b['timestamp'] as num?)?.toInt() ?? 0;
    return tb.compareTo(ta);
  });
  for (final Map<String, dynamic> x in out) {
    final String? s = x['payment_id'] as String?;
    if (s != null && _allZerosOrWhitespace(s.trim())) {
      x['payment_id'] = '';
    }
  }
  return out;
}

String _formatTimestampUtc(int ts) {
  final DateTime dt =
      DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
  return DateFormat('MM/dd/yy hh:mm:ss a')
      .format(dt.toLocal())
      .replaceAll(',', '');
}

String _csvCell(Object? v) {
  if (v == null) {
    return '';
  }
  if (v is String) {
    return v;
  }
  if (v is num || v is bool) {
    return '$v';
  }
  return jsonEncode(v);
}

/// `wallet_export_transactions` — writes `transactions.csv` under [exportDir].
Future<void> exportWalletTransactionsToCsv({
  required Future<Map<String, dynamic>?> Function(
          String method, Map<String, dynamic> params)
      walletCall,
  required String exportDir,
}) async {
  final Map<String, dynamic>? gt = await walletCall(
    'get_transfers',
    <String, dynamic>{
      'in': true,
      'out': true,
      'pending': true,
      'failed': true,
      'pool': false,
      'filter_by_height': true,
      'min_height': 0,
    },
  );
  if (!walletJsonRpcNoError(gt) || gt == null) {
    throw StateError('get_transfers failed: ${gt?['error']}');
  }
  final Object? res = gt['result'];
  if (res is! Map) {
    throw StateError('get_transfers: missing result');
  }
  final List<Map<String, dynamic>> list =
      mergeTransfersList(Map<String, dynamic>.from(res));
  for (final Map<String, dynamic> tx in list) {
    final Object? pid = tx['payment_id'];
    if (pid is String) {
      tx['payment_id'] = normalizePaymentIdForExport(pid);
    }
  }
  if (list.isEmpty) {
    final File f = File('$exportDir${Platform.pathSeparator}transactions.csv');
    await f.parent.create(recursive: true);
    await f.writeAsString('');
    return;
  }

  final Map<String, dynamic> first = Map<String, dynamic>.from(list.first);
  first.remove('subaddr_index');
  first.remove('subaddr_indices');
  first.remove('suggested_confirmations_threshold');

  final List<String> headerKeys = first.keys.toList();
  if (!headerKeys.contains('destinations')) {
    final int idx = headerKeys.length >= 3 ? 3 : headerKeys.length;
    headerKeys.insert(idx, 'destinations');
  }

  final File csvPath =
      File('$exportDir${Platform.pathSeparator}transactions.csv');
  await csvPath.parent.create(recursive: true);
  final StringBuffer bw = StringBuffer();
  bw.writeln(headerKeys.join('|'));

  for (final Map<String, dynamic> item in list) {
    final Map<String, dynamic> raw = Map<String, dynamic>.from(item);
    raw.remove('subaddr_index');
    raw.remove('subaddr_indices');
    raw.remove('suggested_confirmations_threshold');

    final Object? am = raw['amount'];
    if (am is num) {
      raw['amount'] = am.toInt() / _coinUnits;
    }
    final Object? fee = raw['fee'];
    if (fee is num && fee.toInt() > 0) {
      raw['fee'] = fee.toInt() / _coinUnits;
    }
    final Object? dest = raw['destinations'];
    if (dest is List && dest.isNotEmpty) {
      raw['destinations'] = jsonEncode(dest);
    }
    final Object? ts = raw['timestamp'];
    if (ts is num) {
      raw['timestamp'] = _formatTimestampUtc(ts.toInt());
    }

    final List<String> vals = <String>[];
    for (final String k in headerKeys) {
      vals.add(_csvCell(raw[k]));
    }
    if (vals.length == 13) {
      vals.insert(3, '[]');
    }
    bw.writeln(vals.join('|'));
  }
  await csvPath.writeAsString(bw.toString());
}
