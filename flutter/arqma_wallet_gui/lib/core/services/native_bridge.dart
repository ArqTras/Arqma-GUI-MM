import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Parity with `src/bridge/api.js` — native side must implement the same surface
/// (Tauri today: `invoke` + `listen("backend-receive")`).
abstract class NativeBridge {
  Stream<Map<String, dynamic>> get backendReceive;

  Future<void> start();

  Future<dynamic> invoke(String cmd, [Map<String, dynamic>? args]);

  Future<dynamic> backendSend(String module, String method, [Map<String, dynamic>? data]);
}

/// Optional [MethodChannel] integration (`com.arqma.wallet/native`) for a future
/// Flutter desktop embedder that wraps the existing Rust `backend_send` path.
final class MethodChannelNativeBridge implements NativeBridge {
  MethodChannelNativeBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.arqma.wallet/native');

  final MethodChannel _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get backendReceive => _controller.stream;

  @override
  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'backend_receive') {
        final m = Map<String, dynamic>.from(call.arguments as Map);
        _controller.add(m);
      }
    });
  }

  @override
  Future<dynamic> invoke(String cmd, [Map<String, dynamic>? args]) async {
    try {
      return await _channel.invokeMethod(cmd, args);
    } on MissingPluginException catch (e) {
      debugPrint('[NativeBridge] $e');
      return null;
    }
  }

  @override
  Future<dynamic> backendSend(String module, String method, [Map<String, dynamic>? data]) {
    return invoke('backend_send', {
      'message': {'module': module, 'method': method, 'data': data ?? <String, dynamic>{}},
    });
  }

  void emitTestEvent(Map<String, dynamic> payload) => _controller.add(payload);
}

/// UI development / tests without native code: drives the same event stream the
/// Vue `Receiver` consumes. Replace with [MethodChannelNativeBridge] once the
/// Rust shell exposes `backend_send` + `backend-receive` to Flutter.
final class StubNativeBridge implements NativeBridge {
  StubNativeBridge({this.navigateWalletSelectAfterInit = true});

  /// When true, after `core::init` completes, emit `set_app_data` with `status.code == 0`
  /// so routing matches a configured wallet directory (mirrors successful init).
  final bool navigateWalletSelectAfterInit;

  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get backendReceive => _controller.stream;

  @override
  Future<void> start() async {
    unawaited(Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (!_controller.isClosed) {
        _controller.add({'event': 'initialize', 'data': <String, dynamic>{}});
      }
    }));
  }

  @override
  Future<dynamic> invoke(String cmd, [Map<String, dynamic>? args]) async {
    debugPrint('[StubNativeBridge] invoke $cmd $args');
    return null;
  }

  @override
  Future<dynamic> backendSend(String module, String method, [Map<String, dynamic>? data]) async {
    debugPrint('[StubNativeBridge] backend_send $module::$method');
    if (module == 'core' && method == 'init' && navigateWalletSelectAfterInit) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      _controller.add({
        'event': 'set_app_data',
        'data': {
          'status': {'code': 0, 'message': 'stub-init'},
        },
      });
    }
    if (module == 'wallet' && method == 'get_coin_price') {
      _controller.add({'event': 'set_coin_price', 'data': 0});
      _controller.add({
        'event': 'set_conversion_data',
        'data': {'sats': 0.0, 'currentPrice': 0.0},
      });
    }
    return <String, dynamic>{};
  }
}
