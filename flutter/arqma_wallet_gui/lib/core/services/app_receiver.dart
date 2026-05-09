import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_nav.dart';
import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
import 'native_bridge.dart';

/// Parity with `src/receiver/receiver.js` (Notify, Loading, reboot confirm).
class AppReceiver {
  AppReceiver({
    required this.bridge,
    required this.store,
    required this.router,
    required this.locale,
  });

  final NativeBridge bridge;
  final GatewayStore store;
  final GoRouter router;
  final LocaleController locale;

  bool _initRequested = false;
  bool _rebootDialogOpen = false;
  int _loadingDepth = 0;
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

  void _showNotification(dynamic data) {
    final ScaffoldMessengerState? messenger = appScaffoldMessengerKey.currentState;
    if (messenger == null) {
      return;
    }
    final Map<String, dynamic> m = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final String type = '${m['type'] ?? 'positive'}';
    final String msg = '${m['message'] ?? ''}';
    final int timeout = (m['timeout'] as num?)?.toInt() ?? 3000;
    Color? bg;
    if (type == 'negative') {
      bg = Colors.red.shade900;
    } else if (type == 'warning') {
      bg = Colors.amber.shade900;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        duration: Duration(milliseconds: timeout.clamp(800, 20000)),
      ),
    );
  }

  void _showLoading(dynamic data) {
    final BuildContext? ctx = appNavigatorKey.currentContext;
    if (ctx == null) {
      return;
    }
    if (_loadingDepth == 0) {
      unawaited(
        showDialog<void>(
          context: ctx,
          barrierDismissible: false,
          builder: (BuildContext _) => const PopScope(
            canPop: false,
            child: Material(
              color: Colors.black54,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      );
    }
    _loadingDepth++;
  }

  void _hideLoading() {
    if (_loadingDepth > 0) {
      _loadingDepth--;
    }
    if (_loadingDepth > 0) {
      return;
    }
    final BuildContext? ctx = appNavigatorKey.currentContext;
    if (ctx == null) {
      return;
    }
    final NavigatorState nav = Navigator.of(ctx, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  void _promptRestartAfterSettingsChange() {
    if (_rebootDialogOpen) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? ctx = appNavigatorKey.currentContext;
      if (ctx == null) {
        return;
      }
      _rebootDialogOpen = true;
      unawaited(
        showDialog<void>(
          context: ctx,
          builder: (BuildContext c) => AlertDialog(
            title: Text(locale.tr('receiver.restart')),
            content: Text(locale.tr('receiver.confirm_close')),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                },
                child: Text(locale.tr('receiver.cancel')),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  router.go('/quit');
                  unawaited(bridge.invoke('confirm_close', <String, dynamic>{'restart': true}));
                },
                child: Text(locale.tr('receiver.restart')),
              ),
            ],
          ),
        ).whenComplete(() {
          _rebootDialogOpen = false;
        }),
      );
    });
  }

  void _onMessage(Map<String, dynamic> message) {
    final String? event = message['event'] as String?;
    final dynamic data = message['data'];
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
      case 'show_notification':
        _showNotification(data);
        break;
      case 'show_loading':
        _showLoading(data);
        break;
      case 'hide_loading':
        _hideLoading();
        break;
      case 'settings_changed_reboot':
        _promptRestartAfterSettingsChange();
        break;
      default:
        store.applyBackendEvent(event, data);
        break;
    }
  }
}
