import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../store/gateway_store.dart';
import 'native_bridge.dart';

/// Parity with `src/receiver/receiver.js` (minus Quasar `Dialog`/`Loading` — use Flutter equivalents later).
class AppReceiver {
  AppReceiver({
    required this.bridge,
    required this.store,
    required this.router,
  });

  final NativeBridge bridge;
  final GatewayStore store;
  final GoRouter router;

  bool _initRequested = false;
  StreamSubscription<Map<String, dynamic>>? _sub;

  Future<void> start() async {
    await bridge.start();
    _sub = bridge.backendReceive.listen(_onMessage, onError: (Object e, StackTrace st) {
      debugPrint('[AppReceiver] stream error $e\n$st');
    });
    unawaited(Future<void>.delayed(const Duration(milliseconds: 1200), () {
      unawaited(_runInitialize('fallback'));
    }));
  }

  Future<void> dispose() async {
    await _sub?.cancel();
  }

  Future<void> _runInitialize(String source) async {
    if (_initRequested) {
      return;
    }
    _initRequested = true;
    store.setAppData({
      'status': {'code': 2},
    });
    await bridge.invoke('app_log_info', {
      'module': 'receiver',
      'method': 'initialize',
      'message': 'before core init ($source)',
    });
    await bridge.backendSend('core', 'init', {});
  }

  void _onMessage(Map<String, dynamic> message) {
    final event = message['event'] as String?;
    final data = message['data'];
    if (event == null) {
      return;
    }
    switch (event) {
      case 'initialize':
        unawaited(_runInitialize('event'));
        break;
      case 'return_to_wallet_select':
        store.resetWalletDataDispatch();
        router.go('/wallet-select');
        break;
      case 'settings_changed_reboot':
      case 'show_loading':
      case 'hide_loading':
      case 'show_notification':
      case 'set_has_password':
      case 'set_valid_address':
        debugPrint('[AppReceiver] unhandled UI event: $event');
        break;
      default:
        store.applyBackendEvent(event, data);
        break;
    }
  }
}
