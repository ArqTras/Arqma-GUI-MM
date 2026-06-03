import 'package:arqma_wallet_mobile/core/desktop/bridge_log_redact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redactBridgeArgs masks sensitive keys', () {
    final Map<String, dynamic> out = redactBridgeArgs(<String, dynamic>{
      'name': 'ArqTras',
      'password': 'secret',
      'mnemonic': 'word word',
      'view_key': 'abc',
    });
    expect(out['name'], 'ArqTras');
    expect(out['password'], '***');
    expect(out['mnemonic'], '***');
    expect(out['view_key'], '***');
  });

  test('redactBridgeArgs handles null and empty', () {
    expect(redactBridgeArgs(null), isEmpty);
    expect(redactBridgeArgs(<String, dynamic>{}), isEmpty);
  });
}
