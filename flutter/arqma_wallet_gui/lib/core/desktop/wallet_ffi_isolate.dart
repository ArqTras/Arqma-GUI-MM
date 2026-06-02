import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'wallet_native_ffi.dart';

/// Runs [WalletNativeFfi] on a background isolate so desktop UI stays responsive during
/// long `wallet2` FFI calls (open, scan, refresh, close_wallet).
final class WalletFfiIsolateClient {
  WalletFfiIsolateClient._(this._commands, this._isolate, this._replies);

  final SendPort _commands;
  final Isolate _isolate;
  final ReceivePort _replies;
  final Map<int, Completer<Map<String, dynamic>>> _pending =
      <int, Completer<Map<String, dynamic>>>{};
  int _nextId = 0;
  StreamSubscription<dynamic>? _sub;

  static Future<WalletFfiIsolateClient?> start() async {
    final ReceivePort replies = ReceivePort();
    try {
      final Isolate isolate = await Isolate.spawn<SendPort>(
        _walletFfiIsolateMain,
        replies.sendPort,
        errorsAreFatal: false,
        debugName: 'arqma_wallet_ffi',
      );
      final Completer<SendPort> handshake = Completer<SendPort>();
      WalletFfiIsolateClient? client;
      final StreamSubscription<dynamic> sub = replies.listen((Object? message) {
        if (client == null) {
          if (message is SendPort) {
            if (!handshake.isCompleted) {
              handshake.complete(message);
            }
          } else if (!handshake.isCompleted) {
            handshake.completeError(
              StateError('FFI isolate handshake expected SendPort, got $message'),
            );
          }
          return;
        }
        client!._onWorkerMessage(message);
      });
      final SendPort commands = await handshake.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('FFI isolate handshake');
        },
      );
      client = WalletFfiIsolateClient._(commands, isolate, replies);
      client._sub = sub;
      return client;
    } catch (e, st) {
      debugPrint('[WalletFfiIsolate] start failed: $e\n$st');
      return null;
    }
  }

  void _onWorkerMessage(Object? message) {
    if (message is! Map) {
      return;
    }
    final int? id = (message['id'] as num?)?.toInt();
    if (id == null) {
      return;
    }
    final Completer<Map<String, dynamic>>? c = _pending.remove(id);
    if (c == null) {
      return;
    }
    final Object? err = message['error'];
    if (err != null) {
      c.completeError(err);
      return;
    }
    final Map<String, dynamic> payload = Map<String, dynamic>.from(message);
    payload.remove('id');
    c.complete(payload);
  }

  Future<Map<String, dynamic>> _request(
    String op, {
    Map<String, dynamic>? extra,
  }) async {
    final int id = _nextId++;
    final Completer<Map<String, dynamic>> c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    final Map<String, dynamic> msg = <String, dynamic>{'id': id, 'op': op};
    if (extra != null) {
      msg.addAll(extra);
    }
    _commands.send(msg);
    return c.future;
  }

  Future<bool> load() async {
    final Map<String, dynamic> r = await _request('load');
    return r['ok'] == true;
  }

  Future<int> configure(
    String walletDir,
    String daemonAddress,
    int network,
  ) async {
    final Map<String, dynamic> r = await _request(
      'configure',
      extra: <String, dynamic>{
        'walletDir': walletDir,
        'daemonAddress': daemonAddress,
        'network': network,
      },
    );
    return (r['code'] as num?)?.toInt() ?? -1;
  }

  Future<Map<String, dynamic>?> callJsonRpc(
    String method,
    Object params,
  ) async {
    final Map<String, dynamic> r = await _request(
      'call',
      extra: <String, dynamic>{
        'method': method,
        'params': params,
      },
    );
    final Object? result = r['result'];
    if (result == null) {
      return null;
    }
    if (result is Map<String, dynamic>) {
      return result;
    }
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return null;
  }

  Future<void> reset() async {
    await _request('reset');
  }

  Future<void> dispose() async {
    try {
      await _request('shutdown').timeout(const Duration(seconds: 5));
    } catch (_) {}
    await _sub?.cancel();
    _sub = null;
    for (final Completer<Map<String, dynamic>> c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('WalletFfiIsolate disposed'));
      }
    }
    _pending.clear();
    _replies.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

/// One wallet2 FFI op at a time — overlapping `call`/`close`/`open` corrupts native state.
final class _WalletFfiWorker {
  _WalletFfiWorker(this._replyToMain);

  final SendPort _replyToMain;
  WalletNativeFfi? _ffi;
  Future<void> _chain = Future<void>.value();

  void handle(Object? raw) {
    if (raw is! Map) {
      return;
    }
    _chain = _chain.then((_) => _handleOne(raw));
  }

  Future<void> _handleOne(Map raw) async {
    final int id = (raw['id'] as num?)?.toInt() ?? -1;
    final String op = '${raw['op'] ?? ''}';
    final Map<String, dynamic> reply = <String, dynamic>{'id': id};
    try {
      switch (op) {
        case 'load':
          _ffi = WalletNativeFfi.tryLoad();
          reply['ok'] = _ffi != null;
          break;
        case 'configure':
          _ffi ??= WalletNativeFfi.tryLoad();
          if (_ffi == null) {
            reply['code'] = -1;
          } else {
            reply['code'] = _ffi!.configure(
              '${raw['walletDir']}',
              '${raw['daemonAddress']}',
              (raw['network'] as num?)?.toInt() ?? 0,
            );
          }
          break;
        case 'call':
          _ffi ??= WalletNativeFfi.tryLoad();
          if (_ffi == null) {
            reply['result'] = null;
          } else {
            final Object? params = raw['params'];
            reply['result'] = await _ffi!.callJsonRpc(
              '${raw['method']}',
              params ?? <String, dynamic>{},
            );
          }
          break;
        case 'reset':
          _ffi?.reset();
          _ffi = null;
          break;
        case 'shutdown':
          _ffi?.reset();
          _ffi = null;
          break;
        default:
          reply['error'] = 'unknown op: $op';
      }
    } catch (e, st) {
      reply['error'] = '$e\n$st';
    }
    _replyToMain.send(reply);
  }
}

void _walletFfiIsolateMain(SendPort replyToMain) {
  WalletNativeFfi.prepareWindowsDllSearchPath();
  final ReceivePort commands = ReceivePort();
  replyToMain.send(commands.sendPort);
  final _WalletFfiWorker worker = _WalletFfiWorker(replyToMain);
  commands.listen(worker.handle);
}
