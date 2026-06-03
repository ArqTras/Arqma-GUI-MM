import 'package:arqma_wallet_android/core/mobile/mobile_remote_nodes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isValidMobileRemoteHost accepts preset nodes', () {
    for (final String host in kMobileRemoteNodeHosts) {
      expect(isValidMobileRemoteHost(host), isTrue);
    }
  });

  test('isValidMobileRemoteHost accepts valid custom hostnames', () {
    expect(isValidMobileRemoteHost('wallet.example.com'), isTrue);
    expect(isValidMobileRemoteHost('node-a.arqma.net'), isTrue);
  });

  test('isValidMobileRemoteHost rejects traversal and unsafe hosts', () {
    expect(isValidMobileRemoteHost(''), isFalse);
    expect(isValidMobileRemoteHost('../evil'), isFalse);
    expect(isValidMobileRemoteHost('foo/bar'), isFalse);
    expect(isValidMobileRemoteHost('localhost'), isFalse);
    expect(isValidMobileRemoteHost('host.local'), isFalse);
    expect(isValidMobileRemoteHost('bad host'), isFalse);
    expect(isValidMobileRemoteHost('host:19994'), isFalse);
  });

  test('isValidMobileRemotePort accepts mainnet RPC only', () {
    expect(isValidMobileRemotePort(kArqmaMainnetRemotePort), isTrue);
    expect(isValidMobileRemotePort(18081), isFalse);
  });
}
