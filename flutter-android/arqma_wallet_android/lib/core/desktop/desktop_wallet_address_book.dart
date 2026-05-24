import 'wallet_json_rpc.dart';

/// Parity with Tauri `wallet_heartbeat::fetch_address_book_map` — parse `get_address_book`
/// RPC → `{ address_book, address_book_starred }` for `set_wallet_address_book`.
Map<String, dynamic> buildWalletAddressBookFromRpc(Map<String, dynamic>? rpc) {
  const Map<String, dynamic> empty = <String, dynamic>{
    'address_book': <dynamic>[],
    'address_book_starred': <dynamic>[],
  };
  if (rpc == null || !walletJsonRpcNoError(rpc)) {
    return empty;
  }
  final Object? res0 = rpc['result'];
  if (res0 is! Map) {
    return empty;
  }
  final Map<String, dynamic> res = Map<String, dynamic>.from(res0);
  final List<dynamic>? entries = res['entries'] as List<dynamic>?;
  if (entries == null || entries.isEmpty) {
    return empty;
  }

  final List<Map<String, dynamic>> book = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> starred = <Map<String, dynamic>>[];

  for (final Object? raw in entries) {
    if (raw is! Map) {
      continue;
    }
    final Map<String, dynamic> e = Map<String, dynamic>.from(raw);
    _normalizeAddressBookEntryDescription(e);
    _normalizeAddressBookPaymentId(e);
    if (e['starred'] == true) {
      starred.add(e);
    } else {
      book.add(e);
    }
  }

  return <String, dynamic>{
    'address_book': book,
    'address_book_starred': starred,
  };
}

void _normalizeAddressBookEntryDescription(Map<String, dynamic> e) {
  final String fulld = '${e['description'] ?? ''}';
  final List<String> p = fulld.split('::');
  if (p.length == 3) {
    e['starred'] = p[0] == 'starred';
    e['name'] = p[1];
    e['description'] = p[2];
  } else if (p.length == 2) {
    e['starred'] = false;
    e['name'] = p[0];
    e['description'] = p[1];
  } else {
    e['starred'] = false;
    e['name'] = fulld;
    e['description'] = '';
  }
}

void _normalizeAddressBookPaymentId(Map<String, dynamic> e) {
  final String pid = '${e['payment_id'] ?? ''}';
  if (pid.isEmpty) {
    return;
  }
  if (pid.split('').every((String c) => c == '0' || c == ' ')) {
    e['payment_id'] = '';
    return;
  }
  if (pid.length > 16 &&
      pid.substring(16).split('').every((String c) => c == '0' || c == ' ')) {
    e['payment_id'] = pid.substring(0, 16);
  }
}
