import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Last known open-wallet snapshot for iOS resume (not the wallet file itself).
class WalletSessionCheckpoint {
  WalletSessionCheckpoint({
    required this.walletName,
    required this.netType,
    required this.height,
    required this.balance,
    required this.unlockedBalance,
    required this.fullRescanUi,
    required this.savedAtMs,
    this.txMaxHeight = 0,
    this.trustedScanHeight = 0,
  });

  final String walletName;
  final String netType;
  final int height;
  final int balance;
  final int unlockedBalance;
  final bool fullRescanUi;
  final int savedAtMs;

  /// Newest tx block height from the last successful tx list emit.
  final int txMaxHeight;

  /// Monotonic scan progress (ignores one-shot RPC jumps to daemon tip).
  final int trustedScanHeight;

  static const String _prefsKey = 'arqma_wallet_session_checkpoint_v1';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'walletName': walletName,
        'netType': netType,
        'height': height,
        'balance': balance,
        'unlockedBalance': unlockedBalance,
        'fullRescanUi': fullRescanUi,
        'savedAtMs': savedAtMs,
        'txMaxHeight': txMaxHeight,
        'trustedScanHeight': trustedScanHeight,
      };

  static WalletSessionCheckpoint? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Map<String, dynamic> m = Map<String, dynamic>.from(raw);
    final String name = '${m['walletName'] ?? ''}'.trim();
    if (name.isEmpty) {
      return null;
    }
    return WalletSessionCheckpoint(
      walletName: name,
      netType: '${m['netType'] ?? 'mainnet'}',
      height: (m['height'] as num?)?.toInt() ?? 0,
      balance: (m['balance'] as num?)?.toInt() ?? 0,
      unlockedBalance: (m['unlockedBalance'] as num?)?.toInt() ?? 0,
      fullRescanUi: m['fullRescanUi'] == true,
      savedAtMs: (m['savedAtMs'] as num?)?.toInt() ?? 0,
      txMaxHeight: (m['txMaxHeight'] as num?)?.toInt() ?? 0,
      trustedScanHeight: (m['trustedScanHeight'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<void> save(WalletSessionCheckpoint checkpoint) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(checkpoint.toJson()));
  }

  static Future<WalletSessionCheckpoint?> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      return fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
