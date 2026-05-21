import 'dart:async';

import '../store/gateway_store.dart';
import 'services/native_bridge.dart';

/// Parity with `src/bridge/api.js` + common `api.send` usage from Vue pages.
class AppApi {
  AppApi(this._bridge, this._store);

  final NativeBridge _bridge;
  final GatewayStore _store;

  NativeBridge get bridge => _bridge;

  Future<dynamic> invoke(String cmd, [Map<String, dynamic>? args]) =>
      _bridge.invoke(cmd, args);

  Future<dynamic> send(String module, String method, [Object? data]) =>
      _bridge.backendSend(module, method, data);

  Future<void> logError(String module, String method, String message) async {
    await invoke('app_log_error',
        {'module': module, 'method': method, 'message': message});
  }

  Future<void> logInfo(String module, String method, String message) async {
    await invoke('app_log_info',
        {'module': module, 'method': method, 'message': message});
  }

  Future<void> writeText(String text) async {
    await invoke('clip_write_text', {'text': text});
  }

  Future<void> saveLoggingLevelToEnvironmentFile(String value) async {
    await invoke('app_save_log_level', {'value': value});
  }

  /// Tauri returns `String?`; Electron-compat code sometimes expects `{ canceled, filePath }`.
  Future<dynamic> openDirectory(String defaultPath) async {
    return invoke('dialog_open_dir', {'defaultPath': defaultPath});
  }

  Future<String?> pickDirectory(String defaultPath) async {
    final Object? r = await openDirectory(defaultPath);
    if (r == null) {
      return null;
    }
    if (r is String) {
      return r.isEmpty ? null : r;
    }
    if (r is Map) {
      final Map<String, dynamic> m = Map<String, dynamic>.from(r);
      if (m['canceled'] == true || m['cancelled'] == true) {
        return null;
      }
      final Object? fp = m['filePath'] ??
          (m['filePaths'] is List && (m['filePaths'] as List).isNotEmpty
              ? (m['filePaths'] as List).first
              : null);
      return fp?.toString();
    }
    return r.toString();
  }

  Future<bool> hasPasswordRpc() async {
    final Completer<bool> c = Completer<bool>();
    late final StreamSubscription<Map<String, dynamic>> sub;
    sub = _bridge.backendReceive.listen((Map<String, dynamic> msg) {
      final String? ev = msg['event'] as String?;
      if (ev == 'set_has_password') {
        final Object? d = msg['data'];
        if (!c.isCompleted) {
          c.complete(d == true);
        }
        sub.cancel();
      }
    });
    await send('wallet', 'has_password', {});
    try {
      return await c.future.timeout(const Duration(seconds: 45));
    } on TimeoutException {
      await sub.cancel();
      return false;
    }
  }

  Future<Map<String, dynamic>> waitValidAddress(String address) async {
    final Completer<Map<String, dynamic>> c = Completer<Map<String, dynamic>>();
    late final StreamSubscription<Map<String, dynamic>> sub;
    sub = _bridge.backendReceive.listen((Map<String, dynamic> msg) {
      if (msg['event'] == 'set_valid_address') {
        final Object? d = msg['data'];
        if (d is Map) {
          final Map<String, dynamic> m = Map<String, dynamic>.from(d);
          if ('${m['address']}' == address && !c.isCompleted) {
            c.complete(m);
            sub.cancel();
          }
        }
      }
    });
    await send('wallet', 'validate_address', {'address': address});
    try {
      return await c.future.timeout(const Duration(seconds: 30), onTimeout: () {
        return <String, dynamic>{'address': address, 'valid': false};
      });
    } finally {
      await sub.cancel();
    }
  }

  /// Vue `gateway/savePendingConfig` + merge `{ config: value }` into `app`.
  Future<void> savePendingConfigToStore(Map<String, dynamic> pending) async {
    _store.savePendingConfig(pending);
  }

  Future<void> notifierSave(String method) async {
    _store.setNotifier(<String, dynamic>{'save': true, 'method': method});
  }

  Future<void> notifierClear() async {
    _store.setNotifier(<String, dynamic>{'save': false});
  }
}
