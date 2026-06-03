import 'package:arqma_wallet_gui/core/desktop/arqma_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sanitizeWalletBaseName accepts safe basenames', () {
    expect(sanitizeWalletBaseName('ArqTras'), 'ArqTras');
    expect(sanitizeWalletBaseName('wallet-1.test'), 'wallet-1.test');
    expect(sanitizeWalletBaseName('  MyWallet  '), 'MyWallet');
    expect(sanitizeWalletBaseName(r'C:\wallets\ArqTras'), 'ArqTras');
    expect(sanitizeWalletBaseName('/home/user/wallets/ArqTras'), 'ArqTras');
  });

  test('sanitizeWalletBaseName rejects traversal and separators', () {
    expect(sanitizeWalletBaseName('../escape'), isNull);
    expect(sanitizeWalletBaseName('..'), isNull);
    expect(sanitizeWalletBaseName('foo/bar'), isNull);
    expect(sanitizeWalletBaseName(r'foo\bar'), isNull);
    expect(sanitizeWalletBaseName(''), isNull);
    expect(sanitizeWalletBaseName('   '), isNull);
    expect(sanitizeWalletBaseName('bad name'), isNull);
  });
}
