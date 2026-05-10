import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Parity with `src/bridge/api.js` — native side must implement the same surface
/// (Tauri today: `invoke` + `listen("backend-receive")`).
abstract class NativeBridge {
  Stream<Map<String, dynamic>> get backendReceive;

  Future<void> start();

  Future<dynamic> invoke(String cmd, [Map<String, dynamic>? args]);

  /// [data] is usually a [Map] (RPC params); `change_remotes` passes a JSON array like Vue.
  Future<dynamic> backendSend(String module, String method, [Object? data]);
}

/// Platform [MethodChannel] (`com.arqma.wallet/native`) — primary **native** path when the
/// embedder implements `native_ping` + `backend_send` / `backend_receive` (see `native_bridge_resolver.dart`).
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
  Future<dynamic> backendSend(String module, String method, [Object? data]) {
    return invoke('backend_send', {
      'message': <String, dynamic>{
        'module': module,
        'method': method,
        'data': data ?? <String, dynamic>{},
      },
    });
  }

  void emitTestEvent(Map<String, dynamic> payload) => _controller.add(payload);
}

/// In-memory backend for tests / `ARQMA_FLUTTER_USE_STUB=1`. Prefer [resolveAppNativeBridge] for apps.
final class StubNativeBridge implements NativeBridge {
  StubNativeBridge({this.navigateWalletSelectAfterInit = true});

  /// When true, after `core::init` completes, emit `set_app_data` with `status.code == 0`
  /// so routing matches a configured wallet directory (mirrors successful init).
  final bool navigateWalletSelectAfterInit;

  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  static Map<String, dynamic> _coerceMap(Object? data) {
    if (data == null) {
      return <String, dynamic>{};
    }
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }

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
  Future<dynamic> backendSend(String module, String method,
      [Object? data]) async {
    debugPrint('[StubNativeBridge] backend_send $module::$method');
    if (module == 'core' && method == 'init' && navigateWalletSelectAfterInit) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      _controller.add({
        'event': 'set_app_data',
        'data': {
          'status': {'code': 0, 'message': 'stub-init'},
        },
      });
      _controller.add({
        'event': 'wallet_list',
        'data': {
          'list': <dynamic>[
            <String, dynamic>{
              'name': 'Demo',
              'address':
                  'arQmDemoAddress1111111111111111111111111111111111111111111111111111111111111',
              'password_protected': false,
            },
          ],
          'legacy': <dynamic>[],
          'directories': <dynamic>['/path/to/old/gui/wallets'],
        },
      });
    }
    if (module == 'wallet' && method == 'has_password') {
      _controller
          .add(<String, dynamic>{'event': 'set_has_password', 'data': false});
    }
    if (module == 'wallet' && method == 'validate_address') {
      final String addr = '${_coerceMap(data)['address'] ?? ''}';
      _controller.add(<String, dynamic>{
        'event': 'set_valid_address',
        'data': <String, dynamic>{
          'address': addr,
          'valid': addr.isNotEmpty,
          'nettype': 'mainnet'
        },
      });
    }
    if (module == 'wallet' && method == 'create_wallet') {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final String name = '${_coerceMap(data)['name'] ?? 'Demo'}';
      _controller.add(<String, dynamic>{
        'event': 'set_wallet_info',
        'data': <String, dynamic>{
          'name': name,
          'address':
              'arQmStubAddress1111111111111111111111111111111111111111111111111111111111111',
          'balance': 0,
          'unlocked_balance': 0,
        },
      });
      _controller.add(<String, dynamic>{
        'event': 'set_wallet_secret',
        'data': <String, dynamic>{
          'mnemonic': 'stub mnemonic words for ui development only do not use',
          'view_key': '0'.padRight(64, '0'),
          'spend_key': '0'.padRight(64, '0'),
        },
      });
      _controller.add(<String, dynamic>{
        'event': 'reset_wallet_status',
        'data': <String, dynamic>{'code': 0, 'message': 'stub'},
      });
    }
    if (module == 'wallet' && method == 'restore_wallet') {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      _controller.add(<String, dynamic>{
        'event': 'set_wallet_info',
        'data': <String, dynamic>{
          'name': '${_coerceMap(data)['name'] ?? 'Restored'}',
          'address':
              'arQmStubRestored1111111111111111111111111111111111111111111111111111111111',
          'balance': 0,
          'unlocked_balance': 0,
        },
      });
      _controller.add(<String, dynamic>{
        'event': 'reset_wallet_status',
        'data': <String, dynamic>{'code': 0, 'message': 'stub'},
      });
    }
    if (module == 'wallet' && method == 'import_wallet') {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      _controller.add(<String, dynamic>{
        'event': 'set_wallet_info',
        'data': <String, dynamic>{
          'name': '${_coerceMap(data)['name'] ?? 'Imported'}',
          'address':
              'arQmStubImported11111111111111111111111111111111111111111111111111111111111',
          'balance': 0,
          'unlocked_balance': 0,
        },
      });
      _controller.add(<String, dynamic>{
        'event': 'reset_wallet_status',
        'data': <String, dynamic>{'code': 0, 'message': 'stub'},
      });
    }
    if (module == 'wallet' && method == 'restore_view_wallet') {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      _controller.add(<String, dynamic>{
        'event': 'set_wallet_info',
        'data': <String, dynamic>{
          'name': '${_coerceMap(data)['name'] ?? 'ViewOnly'}',
          'address': '${_coerceMap(data)['address'] ?? 'arQmView'}',
          'balance': 0,
          'unlocked_balance': 0,
          'view_only': true,
        },
      });
      _controller.add(<String, dynamic>{
        'event': 'reset_wallet_status',
        'data': <String, dynamic>{'code': 0, 'message': 'stub'},
      });
    }
    if (module == 'wallet' && method == 'copy_old_gui_wallets') {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      _controller.add(<String, dynamic>{
        'event': 'set_old_gui_import_status',
        'data': <String, dynamic>{'code': 0, 'failed_wallets': <dynamic>[]},
      });
    }
    if (module == 'wallet' && method == 'open_wallet') {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      _controller.add(<String, dynamic>{
        'event': 'reset_wallet_status',
        'data': <String, dynamic>{'code': 0, 'message': null},
      });
    }
    if (module == 'wallet' && method == 'transfer') {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      _controller.add(<String, dynamic>{
        'event': 'set_tx_status',
        'data': <String, dynamic>{
          'code': 201,
          'message': 'stub sent',
          'sending': false
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
