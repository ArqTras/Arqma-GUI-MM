import 'package:arqma_wallet_gui/core/desktop/wallet_password_pbkdf2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PBKDF2-HMAC-SHA512 matches Node/Rust (password test, salt 0x41*32)', () {
    const salt = '4141414141414141414141414141414141414141414141414141414141414141';
    final h = pbkdf2PasswordHex(password: 'test', saltHex: salt);
    expect(
      h,
      '454a244ed7a6c07ada8d8a5c1838e61f2664e6912e584483cedd2470327ee42d34b66a867d1f362727e21ffd665cdd0ac5db3400adf7e48363da4f28fa33ff40',
    );
  });
}
