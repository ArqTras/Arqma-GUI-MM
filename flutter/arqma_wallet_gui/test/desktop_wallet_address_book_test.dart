import 'package:flutter_test/flutter_test.dart';

import 'package:arqma_wallet_gui/core/desktop/desktop_wallet_address_book.dart';

void main() {
  test('buildWalletAddressBookFromRpc splits starred::name::notes', () {
    final Map<String, dynamic> rpc = <String, dynamic>{
      'result': <String, dynamic>{
        'entries': <Map<String, dynamic>>[
          <String, dynamic>{
            'address': 'arq1a',
            'description': 'starred::Alice::note',
            'payment_id': '0000000000000000',
          },
          <String, dynamic>{
            'address': 'arq1b',
            'description': 'Bob::hello',
            'payment_id': '',
          },
        ],
      },
    };
    final Map<String, dynamic> out = buildWalletAddressBookFromRpc(rpc);
    final List<dynamic> starred =
        out['address_book_starred'] as List<dynamic>;
    final List<dynamic> book = out['address_book'] as List<dynamic>;
    expect(starred.length, 1);
    expect(book.length, 1);
    expect(starred.first['name'], 'Alice');
    expect(starred.first['starred'], true);
    expect(starred.first['payment_id'], '');
    expect(book.first['name'], 'Bob');
    expect(book.first['starred'], false);
  });
}
