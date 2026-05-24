import 'package:flutter_test/flutter_test.dart';

import 'package:arqma_wallet_gui/store/gateway_default_state.dart';

void main() {
  test('default gateway state is cloneable', () {
    final a = defaultGatewayState();
    final b = defaultGatewayState();
    expect(a['app']?['status']?['code'], 1);
    expect(b['wallet']?['info']?['balance'], 0);
  });
}
