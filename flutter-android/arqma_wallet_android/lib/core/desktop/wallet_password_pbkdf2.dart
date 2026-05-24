import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA512, 1000 rounds, 64-byte DK — same as `wallet_password.rs` / Node `crypto.pbkdf2Sync`.
String pbkdf2PasswordHex({required String password, required String saltHex}) {
  if (saltHex.length != 64) {
    throw ArgumentError.value(
        saltHex, 'saltHex', 'expected 64 hex chars (32 B)');
  }
  final Uint8List salt = _hexDecode(saltHex);
  if (salt.length != 32) {
    throw ArgumentError('salt decode length');
  }
  final List<int> pw = utf8.encode(password);
  final Uint8List dk = _pbkdf2HmacSha512(pw, salt, 1000, 64);
  return dk.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String? tryPbkdf2PasswordHex(
    {required String password, required String saltHex}) {
  try {
    return pbkdf2PasswordHex(password: password, saltHex: saltHex);
  } catch (_) {
    return null;
  }
}

Uint8List _hexDecode(String hex) {
  if (hex.length.isOdd) {
    throw ArgumentError('hex length');
  }
  final Uint8List out = Uint8List(hex.length ~/ 2);
  for (int i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void _xorInPlace(Uint8List a, List<int> b) {
  for (int i = 0; i < a.length; i++) {
    a[i] ^= b[i];
  }
}

/// RFC 2898 PBKDF2 with PRF = HMAC-SHA512.
Uint8List _pbkdf2HmacSha512(
    List<int> password, Uint8List salt, int iterations, int dkLen) {
  const int hLen = 64;
  final int blocks = (dkLen + hLen - 1) ~/ hLen;
  final BytesBuilder acc = BytesBuilder(copy: false);
  for (int block = 1; block <= blocks; block++) {
    final BytesBuilder saltInt = BytesBuilder(copy: false)
      ..add(salt)
      ..add(<int>[
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ]);
    Uint8List prev = Uint8List.fromList(
        Hmac(sha512, password).convert(saltInt.toBytes()).bytes);
    final Uint8List t = Uint8List.fromList(prev);
    for (int i = 1; i < iterations; i++) {
      prev = Uint8List.fromList(Hmac(sha512, password).convert(prev).bytes);
      _xorInPlace(t, prev);
    }
    acc.add(t);
  }
  final Uint8List all = Uint8List.fromList(acc.toBytes());
  return Uint8List.sublistView(all, 0, dkLen);
}
