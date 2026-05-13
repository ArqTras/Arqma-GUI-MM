import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../desktop/arqma_daemon_launcher.dart';
import '../desktop/arqma_desktop_defaults.dart';
import '../desktop/arqma_executable_resolve.dart';
import '../desktop/arqma_paths.dart';
import '../desktop/daemon_heartbeat_extras.dart';
import '../desktop/desktop_export_transactions.dart';
import '../desktop/config_validate.dart';
import '../desktop/desktop_startup_parity.dart';
import '../desktop/arqma_wallet_rpc_session.dart';
import '../desktop/daemon_json_rpc.dart';
import '../desktop/desktop_coin_price.dart';
import '../desktop/desktop_old_gui_wallets.dart';
import '../desktop/desktop_restore_height.dart';
import '../desktop/desktop_stake_pools.dart';
import '../desktop/wallet_json_rpc.dart';
import '../desktop/wallet_list_fs.dart';
import '../desktop/wallet_password_pbkdf2.dart';
import '../utils/deep_merge.dart';
import 'native_bridge.dart';

/// Timeline logs for “open wallet” / post-open RPCs. Enable in **release** with:
/// `ARQMA_FLUTTER_DEBUG_WALLET=1` (PowerShell: `$env:ARQMA_FLUTTER_DEBUG_WALLET='1'`).
/// Always on in **debug** (`flutter run`). Capture: console or `flutter run -d windows -v`.
bool _walletOpenTraceEnabled() =>
    kDebugMode ||
    (!kIsWeb && Platform.environment['ARQMA_FLUTTER_DEBUG_WALLET'] == '1');

void _traceWalletOpen(String phase, {Stopwatch? sw}) {
  if (!_walletOpenTraceEnabled()) {
    return;
  }
  final String elapsed =
      sw != null ? ' (+${sw.elapsedMilliseconds}ms)' : '';
  final String msg = '[Arqma WalletOpen]$elapsed $phase';
  debugPrint(msg);
  developer.log(msg, name: 'ArqmaWallet');
}

/// Tauri `write_config_file` + `validate_config_against_defaults` + `strip_trusted_daemon_from_config`
/// (+ optional `strip_legacy_uniform_pool_option` on `save_config_init`).
Map<String, dynamic> _finalizeConfigForDiskWrite(
  ArqmaPaths paths,
  Map<String, dynamic> cfg, {
  required bool stripPoolLegacy,
}) {
  final Map<String, dynamic> m =
      Map<String, dynamic>.from(jsonDecode(jsonEncode(cfg)) as Map);
  if (stripPoolLegacy) {
    stripLegacyUniformPoolOption(m);
  }
  final Map<String, dynamic> validated =
      validateConfigAgainstDefaults(m, buildDefaultsOnly(paths));
  final Map<String, dynamic> norm = normalizeConfigStoragePaths(validated);
  stripTrustedDaemonFromConfig(norm);
  return norm;
}

Map<String, dynamic> _coerceMap(Object? data) {
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

bool _walletCaughtDaemonTip(int walletHeight, int daemonTip) {
  if (daemonTip <= 0) {
    return false;
  }
  return walletHeight >= daemonTip;
}

/// User-visible text when [ArqmaWalletRpcSession.tryStart] fails (missing FFI / load error).
String _walletFfiMissedStartHint() {
  const String rpc =
      'Legacy: set `ARQMA_FLUTTER_WALLET_RPC_MODE=subprocess` and use `arqma-wallet-rpc`.';
  if (Platform.isWindows) {
    return 'Missing or unloadable `arqma_wallet_flutter_ffi.dll` next to `Arqma-Wallet.exe` (legacy: `lib\\`). '
        'If the `.dll` is present but still error **126**, missing **dependencies** (Boost, OpenSSL, libsodium, '
        'unbound, ICU, …) from MSYS2 `mingw64\\bin` — rebuild with `ARQMA_WALLET2_MSYS_ROOT` set or run '
        '`tool\\package_flutter_release.ps1` which copies those DLLs. Minimum runtime: `libgcc_s_seh-1.dll`, '
        '`libstdc++-6.dll`, `libwinpthread-1.dll`. '
        'Build (CI-style): from `rust/`, '
        '`cargo build -p arqma-wallet-flutter-ffi --release --target x86_64-pc-windows-gnu`, then '
        '`flutter build windows --release` (see `rust/tool/build_native_wallet_flutter_ffi_windows.ps1`). '
        'Optional: `ARQMA_FLUTTER_WALLET_FFI` = absolute path to the DLL. $rpc';
  }
  if (Platform.isMacOS) {
    return 'Missing `libarqma_wallet_flutter_ffi.dylib` in the app bundle (e.g. `Arqma-Wallet.app/Contents/Frameworks/`). '
        'Build: `bash rust/tool/build_wallet_flutter_ffi.sh`, then `flutter build macos --release`. '
        'Optional: `ARQMA_FLUTTER_WALLET_FFI` = absolute path to the dylib. $rpc';
  }
  if (Platform.isLinux) {
    return 'Missing `libarqma_wallet_flutter_ffi.so` in the bundle (next to the app, often under `lib/`). '
        'Build: `bash rust/tool/build_wallet_flutter_ffi.sh`, then `flutter build linux --release`. '
        'Optional: `ARQMA_FLUTTER_WALLET_FFI` = absolute path to the `.so`. $rpc';
  }
  return 'Native wallet FFI library not found or failed to load. $rpc';
}

String _walletFfiBackendOfflineHint() {
  if (Platform.isWindows) {
    return 'Wallet backend is not running (embed `arqma_wallet_flutter_ffi.dll` next to the exe, or legacy `lib\\`, or '
        '`ARQMA_FLUTTER_WALLET_RPC_MODE=subprocess` + `arqma-wallet-rpc`). '
        'Optional: `ARQMA_FLUTTER_WALLET_FFI` for a custom DLL path.';
  }
  if (Platform.isMacOS) {
    return 'Wallet backend is not running (embed `libarqma_wallet_flutter_ffi.dylib`, or '
        '`ARQMA_FLUTTER_WALLET_RPC_MODE=subprocess` + `arqma-wallet-rpc`). '
        'Optional: `ARQMA_FLUTTER_WALLET_FFI` for a custom dylib path.';
  }
  if (Platform.isLinux) {
    return 'Wallet backend is not running (embed `libarqma_wallet_flutter_ffi.so`, or '
        '`ARQMA_FLUTTER_WALLET_RPC_MODE=subprocess` + `arqma-wallet-rpc`). '
        'Optional: `ARQMA_FLUTTER_WALLET_FFI` for a custom `.so` path.';
  }
  return 'Wallet backend is not running (embed the FFI library or use `ARQMA_FLUTTER_WALLET_RPC_MODE=subprocess` + `arqma-wallet-rpc`).';
}

String _walletFfiCreateRestoreHint() {
  if (Platform.isWindows) {
    return 'Wallet backend is not running (copy `arqma_wallet_flutter_ffi.dll` into `runner/Release/` next to the exe, or '
        '`ARQMA_FLUTTER_WALLET_RPC_MODE=subprocess` with `arqma-wallet-rpc`).';
  }
  if (Platform.isMacOS) {
    return 'Wallet backend is not running (embed `libarqma_wallet_flutter_ffi.dylib` in the `.app`, or '
        '`ARQMA_FLUTTER_WALLET_RPC_MODE=subprocess` with `arqma-wallet-rpc`).';
  }
  if (Platform.isLinux) {
    return 'Wallet backend is not running (embed `libarqma_wallet_flutter_ffi.so` in the Linux bundle, or '
        '`ARQMA_FLUTTER_WALLET_RPC_MODE=subprocess` with `arqma-wallet-rpc`).';
  }
  return 'Wallet backend is not running (`ARQMA_FLUTTER_WALLET_RPC_MODE=subprocess` + `arqma-wallet-rpc`, or embed the FFI library).';
}

/// Desktop (macOS/Linux/Windows): load GUI `config.json` under [ArqmaPaths.configDir], scan wallet dir like Tauri,
/// start local `arqmad` when daemon type is not `remote`, poll `get_info` for footer sync state.
final class DesktopNativeBridge implements NativeBridge {
  DesktopNativeBridge();

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  Future<void>? _startupFuture;
  Map<String, dynamic>? _runtimeConfig;
  Process? _daemonProcess;
  Timer? _heartbeat;
  Timer? _heartbeatSlow;
  ArqmaWalletRpcSession? _walletRpc;
  String _openedWalletDisplayName = '';

  /// PBKDF2-HMAC-SHA512 hash of the session password (Tauri `wallet_password_hash_hex`); null when no wallet is open.
  String? _walletPasswordHashHex;
  Timer? _stakePoolsTimer;
  final List<Map<String, dynamic>> _pendingTxRelay = <Map<String, dynamic>>[];
  Process? _soloPoolProcess;
  StreamSubscription<String>? _soloPoolOutSub;
  StreamSubscription<String>? _soloPoolErrSub;

  /// Parity with Tauri `wallet_heartbeat` / Electron `wallet-rpc.js` — `getheight` + balance + `get_transfers`.
  Timer? _walletHeartbeat;
  int _daemonChainTipHeight = 0;
  int _whStoredHeight = 0;
  int _whStoredBalance = 0;
  int _whStoredUnlocked = 0;
  bool _whFetchTxPending = false;
  bool _walletXferBusy = false;

  /// Limits `get_transfers` rate while [inScanRhythm] — height advances every tick during sync.
  DateTime? _walletXferScanThrottleUntil;

  /// True after [rescan_blockchain] UI priming until the wallet height reaches the daemon tip band again.
  bool _walletFullRescanUi = false;

  void _emit(Map<String, dynamic> msg) {
    if (!_controller.isClosed) {
      _controller.add(msg);
    }
  }

  void _showNotification(String kind, String message, [int timeoutMs = 3000]) {
    _emit(<String, dynamic>{
      'event': 'show_notification',
      'data': <String, dynamic>{
        'type': kind,
        'message': message,
        'timeout': timeoutMs
      },
    });
  }

  Future<void> _stopSoloPoolSidecar() async {
    await _soloPoolOutSub?.cancel();
    _soloPoolOutSub = null;
    await _soloPoolErrSub?.cancel();
    _soloPoolErrSub = null;
    final Process? p = _soloPoolProcess;
    _soloPoolProcess = null;
    if (p != null) {
      try {
        p.kill(ProcessSignal.sigterm);
      } catch (_) {}
      try {
        await p.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  }

  /// Clears sidecar handles when the child exits on its own (crash, SIGKILL, etc.).
  void _onSoloPoolChildEnded(Process proc) {
    if (_soloPoolProcess != proc) {
      return;
    }
    _soloPoolProcess = null;
    _soloPoolOutSub = null;
    _soloPoolErrSub = null;
  }

  /// Runs the Rust `arqma_flutter_solo_pool` binary (Stratum solo pool); stdout JSON lines → [`_emit`].
  Future<void> _syncSoloPoolSidecar(Map<String, dynamic> configData) async {
    await _stopSoloPoolSidecar();
    if (Platform.environment['ARQMA_FLUTTER_NO_SOLO_POOL'] == '1') {
      return;
    }
    if (!poolServerEnabled(configData)) {
      return;
    }
    final String? exe =
        resolveArqmaExecutable(ArqmaExecutableKind.flutterSoloPool);
    if (exe == null) {
      debugPrint(
        '[DesktopNative] arqma_flutter_solo_pool not found (cargo build in rust/tauri-app/src-tauri or set ARQMA_FLUTTER_SOLO_POOL)',
      );
      return;
    }
    final ArqmaPaths paths = ArqmaPaths.defaultForPlatform();
    try {
      final Process proc = await Process.start(
        exe,
        <String>[paths.configDir],
        environment: <String, String>{
          ...Platform.environment,
          'ARQMA_CONFIG_DIR': paths.configDir,
        },
      );
      _soloPoolProcess = proc;
      _soloPoolOutSub = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (String line) {
          final String t = line.trim();
          if (t.isEmpty) {
            return;
          }
          try {
            final Object? v = jsonDecode(t);
            if (v is! Map) {
              return;
            }
            final Map<String, dynamic> m = Map<String, dynamic>.from(v);
            final Object? ev = m['event'];
            if (ev is! String) {
              return;
            }
            final Object? raw = m['data'];
            final Map<String, dynamic> payload =
                raw is Map<String, dynamic> ? raw : _coerceMap(raw);
            _emit(<String, dynamic>{'event': ev, 'data': payload});
          } catch (e) {
            debugPrint('[DesktopNative] solo pool stdout JSON: $e');
          }
        },
        onError: (Object e, StackTrace st) =>
            debugPrint('[DesktopNative] solo pool stdout: $e $st'),
        onDone: () => _onSoloPoolChildEnded(proc),
      );
      _soloPoolErrSub = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (String line) {
          final String s = line.trim();
          if (s.isNotEmpty) {
            debugPrint('[solo-pool] $s');
          }
        },
        onError: (Object e, StackTrace st) =>
            debugPrint('[DesktopNative] solo pool stderr: $e $st'),
        onDone: () => _onSoloPoolChildEnded(proc),
      );
    } catch (e) {
      debugPrint('[DesktopNative] solo pool Process.start failed: $e');
    }
  }

  Future<void> _ensureStartupDone() async {
    _startupFuture ??= _runCoreStartup();
    await _startupFuture;
  }

  /// Keep `app.data_dir` / `app.wallet_data_dir` absolute (expand `~`) like a shell/Tauri runtime.
  void _setRuntimeConfig(Map<String, dynamic> raw) {
    _runtimeConfig =
        normalizeConfigStoragePaths(Map<String, dynamic>.from(raw));
    _emitWalletListForConfig(_runtimeConfig!);
  }

  /// Merge [merged] into a finalized snapshot, write `gui/config.json`, and `set_app_data` like `save_config`.
  ///
  /// Used for `change_ethereum` / `change_scan` / `set_daysOfTransactions` / `set_inactivityTimeout` so the
  /// Flutter backend matches **persisted** Tauri/Electron behaviour (Vue `txhistory` relies on this for days).
  Future<void> _persistConfigSnapshot(
    ArqmaPaths paths,
    Map<String, dynamic> merged, {
    required bool stripPoolLegacy,
    Map<String, dynamic>? extraSetAppData,
  }) async {
    try {
      final Map<String, dynamic> out = _finalizeConfigForDiskWrite(
          paths, merged,
          stripPoolLegacy: stripPoolLegacy);
      _setRuntimeConfig(out);
      await File(paths.configPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(_runtimeConfig),
      );
      final Map<String, dynamic> payload = <String, dynamic>{
        'config': _runtimeConfig,
        'pending_config': _runtimeConfig,
      };
      if (extraSetAppData != null) {
        payload.addAll(extraSetAppData);
      }
      _emit(<String, dynamic>{'event': 'set_app_data', 'data': payload});
    } catch (e, st) {
      debugPrint('[DesktopNative] persistConfigSnapshot: $e\n$st');
      _showNotification(
          'negative', 'Could not write ${paths.configPath}', 5000);
    }
  }

  /// Same directory rule as Tauri [`arqma_paths_config::wallet_files_dir`] + Rust [`list_wallet_files`].
  void _emitWalletListForConfig(Map<String, dynamic> fullConfig) {
    final String? wdir = walletFilesDir(fullConfig);
    final Map<String, dynamic> wallets = wdir != null
        ? listWalletFiles(wdir)
        : <String, dynamic>{
            'list': <dynamic>[],
            'directories': <dynamic>[],
            'legacy': <dynamic>[]
          };
    _emit(<String, dynamic>{'event': 'wallet_list', 'data': wallets});
  }

  @override
  Stream<Map<String, dynamic>> get backendReceive => _controller.stream;

  @override
  Future<void> start() async {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (!_controller.isClosed) {
          _controller.add(<String, dynamic>{
            'event': 'initialize',
            'data': <String, dynamic>{}
          });
        }
      }),
    );
  }

  Future<void> _runConfirmCloseShutdown(ArqmaWalletRpcSession? w) async {
    try {
      await _stopSoloPoolSidecar();
    } catch (e, st) {
      debugPrint('[DesktopNative] confirm_close solo pool: $e\n$st');
    }
    try {
      await w?.shutdown().timeout(const Duration(seconds: 3));
    } catch (e, st) {
      debugPrint('[DesktopNative] confirm_close shutdown: $e\n$st');
    }
    try {
      exit(0);
    } catch (_) {}
  }

  @override
  Future<dynamic> invoke(String cmd, [Map<String, dynamic>? args]) async {
    if (cmd == 'app_log_info' || cmd == 'app_log_error') {
      debugPrint('[$cmd] ${args ?? {}}');
      return null;
    }
    if (cmd == 'clip_write_text') {
      final Map<String, dynamic> a = _coerceMap(args);
      final String text = '${a['text'] ?? ''}';
      await Clipboard.setData(ClipboardData(text: text));
      return null;
    }
    if (cmd == 'app_save_log_level') {
      final Map<String, dynamic> a = _coerceMap(args);
      final String value = '${a['value'] ?? ''}'.trim();
      if (value.isNotEmpty) {
        try {
          final String dir = ArqmaPaths.defaultForPlatform().configDir;
          await Directory(dir).create(recursive: true);
          final String path = '$dir${Platform.pathSeparator}.env';
          final File f = File(path);
          List<String> lines;
          if (await f.exists()) {
            final String s = await f.readAsString();
            lines = s.split(RegExp(r'\r?\n'));
            if (lines.isEmpty ||
                (lines.length == 1 && lines[0].trim().isEmpty)) {
              lines = <String>['LOG_LEVEL=$value'];
            } else {
              bool found = false;
              for (int i = 0; i < lines.length; i++) {
                if (lines[i].trim().startsWith('LOG_LEVEL')) {
                  lines[i] = 'LOG_LEVEL=$value';
                  found = true;
                  break;
                }
              }
              if (!found) {
                lines.insert(0, 'LOG_LEVEL=$value');
              }
            }
          } else {
            lines = <String>['LOG_LEVEL=$value'];
          }
          await f.writeAsString(lines.join('\n'));
        } catch (e) {
          debugPrint('[DesktopNative] app_save_log_level: $e');
        }
      }
      return null;
    }
    if (cmd == 'app_version_str') {
      return '5.1.0';
    }
    if (cmd == 'daemon_version_probe') {
      final Map<String, dynamic>? c = _runtimeConfig;
      if (c == null) {
        return 'unknown';
      }
      final ({String host, int port})? ep = daemonRpcHostPort(c);
      if (ep == null) {
        return 'unknown';
      }
      final Map<String, dynamic>? r = await DaemonJsonRpc.getInfo(
        ep.host,
        ep.port,
        connectTimeout: DaemonJsonRpc.probeConnectTimeout,
        requestTimeout: DaemonJsonRpc.probeRequestTimeout,
      );
      final Map<String, dynamic>? info = DaemonJsonRpc.getInfoPayload(r);
      return '${info?['version'] ?? 'unknown'}';
    }
    if (cmd == 'app_is_dev') {
      return kDebugMode;
    }
    if (cmd == 'confirm_close') {
      // Stop timers synchronously; do not await wallet shutdown here — a stuck FFI
      // blocks this isolate and the window close future never completes.
      _stopWalletHeartbeat();
      _stakePoolsTimer?.cancel();
      _stakePoolsTimer = null;
      _heartbeat?.cancel();
      _heartbeat = null;
      _heartbeatSlow?.cancel();
      _heartbeatSlow = null;
      _walletPasswordHashHex = null;
      _openedWalletDisplayName = '';
      final ArqmaWalletRpcSession? w = _walletRpc;
      _walletRpc = null;
      try {
        _daemonProcess?.kill();
      } catch (_) {}
      _daemonProcess = null;
      unawaited(_runConfirmCloseShutdown(w));
      return null;
    }
    if (cmd == 'dialog_open_dir') {
      final Map<String, dynamic> a = _coerceMap(args);
      String initial = '${a['defaultPath'] ?? ''}'.trim();
      if (initial.isNotEmpty) {
        try {
          final Directory d = Directory(initial);
          if (!d.existsSync()) {
            initial = '';
          }
        } catch (_) {
          initial = '';
        }
      }
      try {
        String? path = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Select folder',
          initialDirectory: initial.isEmpty ? null : initial,
        );
        // macOS sandbox / invalid `initialDirectory` can yield null — retry without a starting folder.
        path ??= await FilePicker.platform
            .getDirectoryPath(dialogTitle: 'Select folder');
        if (path == null) {
          debugPrint(
              '[DesktopNative] dialog_open_dir: user cancelled or picker returned null');
        }
        return path;
      } catch (e, st) {
        debugPrint('[DesktopNative] dialog_open_dir failed: $e\n$st');
        return null;
      }
    }
    return null;
  }

  @override
  Future<dynamic> backendSend(String module, String method,
      [Object? data]) async {
    if (module == 'core' && method == 'init') {
      _startupFuture ??= _runCoreStartup();
      await _startupFuture;
      return <String, dynamic>{};
    }
    await _ensureStartupDone();
    if (module == 'core' && method == 'open_url') {
      final Map<String, dynamic> m = _coerceMap(data);
      final String url = '${m['url'] ?? ''}';
      if (url.isEmpty) {
        return <String, dynamic>{};
      }
      if (Platform.isMacOS) {
        await Process.run('open', <String>[url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', <String>[url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', <String>['/c', 'start', '', url]);
      }
      return <String, dynamic>{};
    }
    if (module == 'core' && method == 'open_explorer') {
      await _coreOpenExplorer(_coerceMap(data));
      return <String, dynamic>{};
    }
    if (module == 'core' && (method == 'save_svg' || method == 'save_png')) {
      await _coreSaveImage(method, _coerceMap(data));
      return <String, dynamic>{};
    }
    if (module == 'core') {
      if (await _handleCoreRest(method, data)) {
        return <String, dynamic>{};
      }
    }
    if (module == 'daemon' && method == 'ban_peer') {
      await _daemonBanPeer(_coerceMap(data));
      return <String, dynamic>{};
    }
    if (module == 'wallet' && method == 'list_wallets') {
      Map<String, dynamic>? cfg;
      if (data != null) {
        final Map<String, dynamic> m = _coerceMap(data);
        if (m.isNotEmpty && (m['app'] is Map || m['daemons'] is Map)) {
          cfg = normalizeConfigStoragePaths(Map<String, dynamic>.from(m));
        }
      }
      cfg ??= _runtimeConfig;
      if (cfg != null) {
        _emitWalletListForConfig(cfg);
      }
      return <String, dynamic>{};
    }
    return _walletStubBackendSend(module, method, data);
  }

  Future<void> _restartAfterConfigInit() async {
    await _stopSoloPoolSidecar();
    _stopWalletHeartbeat();
    _stakePoolsTimer?.cancel();
    _stakePoolsTimer = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _heartbeatSlow?.cancel();
    _heartbeatSlow = null;
    _pendingTxRelay.clear();
    _openedWalletDisplayName = '';
    _walletPasswordHashHex = null;
    try {
      await _walletRpc?.shutdown();
    } catch (_) {}
    _walletRpc = null;
    try {
      _daemonProcess?.kill();
    } catch (_) {}
    _daemonProcess = null;
    _startupFuture = null;
    _runtimeConfig = null;
    _startupFuture = _runCoreStartup();
    await _startupFuture;
  }

  Future<void> _maybePushMainnetRemote(
      ArqmaPaths paths, Map<String, dynamic> params) async {
    final Object? daemons = params['daemons'];
    if (daemons is! Map) {
      return;
    }
    final Object? mainnetObj = daemons['mainnet'];
    if (mainnetObj is! Map) {
      return;
    }
    final Map<String, dynamic> mainnet = Map<String, dynamic>.from(mainnetObj);
    final String? host = mainnet['remote_host'] as String?;
    if (host == null || host.isEmpty) {
      return;
    }
    final int port = (mainnet['remote_port'] as num?)?.toInt() ?? 19994;
    final File f = File(paths.remotesPath);
    List<dynamic> arr = <dynamic>[];
    if (f.existsSync()) {
      try {
        final Object? v = jsonDecode(f.readAsStringSync());
        if (v is List<dynamic>) {
          arr = v;
        }
      } catch (_) {}
    }
    final bool exists = arr.any((Object? n) {
      if (n is! Map) {
        return false;
      }
      final Map<String, dynamic> m = Map<String, dynamic>.from(n);
      return '${m['host']}' == host && (m['port'] as num?)?.toInt() == port;
    });
    if (exists) {
      return;
    }
    arr.add(<String, dynamic>{'host': host, 'port': port});
    await f.parent.create(recursive: true);
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(arr));
    _emit(<String, dynamic>{
      'event': 'set_app_data',
      'data': <String, dynamic>{'remotes': arr}
    });
  }

  Map<String, dynamic> _normalizePoolVarDiff(Map<String, dynamic> pool) {
    final Map<String, dynamic> vd = Map<String, dynamic>.from(
        pool['varDiff'] as Map? ?? <String, dynamic>{});
    int clampU(Object? v, int def, int lo, int hi) {
      final int x = (v is num) ? v.toInt() : int.tryParse('$v') ?? def;
      return x.clamp(lo, hi);
    }

    int start = clampU(vd['startDiff'], 150000, 1000, 100000000);
    int minD = clampU(vd['minDiff'], 150000, 1, 100000000);
    int maxD = clampU(vd['maxDiff'], 10000000, 1, 100000000);
    if (minD > maxD) {
      final int t = minD;
      minD = maxD;
      maxD = t;
    }
    start = start.clamp(minD, maxD);
    final int target = clampU(vd['targetTime'], 20, 5, 600);
    final int retarget = clampU(vd['retargetTime'], 30, 1, 3600);
    final int variance = clampU(vd['variancePercent'], 25, 1, 95);
    final int jump = clampU(vd['maxJump'], 200, 1, 10000);
    final Map<String, dynamic> merged = Map<String, dynamic>.from(pool);
    merged['varDiff'] = <String, dynamic>{
      'enabled': true,
      'startDiff': start,
      'minDiff': minD,
      'maxDiff': maxD,
      'targetTime': target,
      'retargetTime': retarget,
      'variancePercent': variance,
      'maxJump': jump,
    };
    return merged;
  }

  Future<void> _coreOpenExplorer(Map<String, dynamic> params) async {
    if (params['type'] == 'swap_tx_id') {
      final String ex = '${params['explorer'] ?? ''}';
      final String id = '${params['id'] ?? ''}';
      final String url = '$ex$id';
      if (url.isNotEmpty) {
        await backendSend('core', 'open_url', <String, dynamic>{'url': url});
      }
      return;
    }
    final String? typ = params['type'] as String?;
    final String end = typ == 'service_node' ? 'service_node' : 'tx';
    if (typ != 'tx' && typ != 'service_node') {
      return;
    }
    final String? id = params['id'] as String?;
    if (id == null || id.isEmpty) {
      return;
    }
    final String url = 'https://explorer.arqma.com/$end/$id';
    await backendSend('core', 'open_url', <String, dynamic>{'url': url});
  }

  Future<void> _coreSaveImage(
      String method, Map<String, dynamic> params) async {
    final ArqmaPaths paths = ArqmaPaths.defaultForPlatform();
    final String? wdir = walletFilesDir(_runtimeConfig ?? <String, dynamic>{});
    final String initial = wdir ?? paths.walletDir;
    if (method == 'save_svg') {
      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ${params['type'] ?? 'file'}',
        fileName: 'arqma-qr.svg',
        type: FileType.custom,
        allowedExtensions: <String>['svg'],
        initialDirectory: initial,
      );
      final String? svg = params['svg'] as String?;
      if (path != null && svg != null && svg.isNotEmpty) {
        await File(path).writeAsString(svg);
        _showNotification(
            'positive', '${params['type'] ?? 'File'} saved to $path', 3000);
      }
      return;
    }
    final String? img = params['img'] as String?;
    if (img == null || img.isEmpty) {
      return;
    }
    final String b64 =
        img.replaceFirst(RegExp(r'^data:image/png;base64,?,?'), '').trim();
    final List<int> bytes = base64Decode(b64);
    final String? path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save ${params['type'] ?? 'Identicon'}',
      fileName: 'arqma-identicon.png',
      type: FileType.custom,
      allowedExtensions: <String>['png'],
      initialDirectory: initial,
    );
    if (path != null) {
      await File(path).writeAsBytes(bytes);
      _showNotification(
          'positive', '${params['type'] ?? 'File'} saved to $path', 3000);
    }
  }

  Future<void> _daemonBanPeer(Map<String, dynamic> params) async {
    final String host = '${params['host'] ?? ''}';
    if (host.isEmpty) {
      return;
    }
    int seconds = (params['seconds'] as num?)?.toInt() ?? 3600;
    if (seconds <= 0) {
      seconds = 3600;
    }
    final Map<String, dynamic>? cfg = _runtimeConfig;
    final ({String host, int port})? ep =
        cfg == null ? null : daemonRpcHostPort(cfg);
    if (ep == null) {
      _showNotification('negative', 'Error banning peer', 3000);
      return;
    }
    final Map<String, dynamic>? r = await DaemonJsonRpc.post(
      ep.host,
      ep.port,
      'set_bans',
      params: <String, dynamic>{
        'bans': <Map<String, dynamic>>[
          <String, dynamic>{'host': host, 'seconds': seconds, 'ban': true},
        ],
      },
    );
    if (r == null || r['error'] != null || r['result'] == null) {
      _showNotification('negative', 'Error banning peer', 3000);
      return;
    }
    _showNotification('positive', 'Banned $host for $seconds s', 3000);
  }

  Future<bool> _handleCoreRest(String method, Object? data) async {
    final Map<String, dynamic>? cfg0 = _runtimeConfig;
    if (cfg0 == null) {
      return false;
    }
    final ArqmaPaths paths = ArqmaPaths.defaultForPlatform();
    final Map<String, dynamic> params = _coerceMap(data);

    switch (method) {
      case 'change_remotes':
        final File f = File(paths.remotesPath);
        await f.parent.create(recursive: true);
        await f.writeAsString(jsonEncode(data is List ? data : <dynamic>[]));
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{'remotes': data}
        });
        return true;
      case 'change_ethereum':
        final Map<String, dynamic> eth =
            deepMergeMaps(cfg0['ethereum'] ?? <String, dynamic>{}, params)
                as Map<String, dynamic>;
        final Map<String, dynamic> mergedEthCfg =
            deepMergeMaps(cfg0, <String, dynamic>{'ethereum': eth})
                as Map<String, dynamic>;
        await _persistConfigSnapshot(paths, mergedEthCfg,
            stripPoolLegacy: false);
        final Object? ethOut = _runtimeConfig?['ethereum'];
        if (ethOut is Map) {
          _emit(<String, dynamic>{
            'event': 'set_ethereum_data',
            'data': Map<String, dynamic>.from(ethOut),
          });
        }
        return true;
      case 'change_scan':
        final Map<String, dynamic> mergedScan =
            deepMergeMaps(cfg0, <String, dynamic>{
          'app': <String, dynamic>{'scan': params},
        }) as Map<String, dynamic>;
        await _persistConfigSnapshot(
          paths,
          mergedScan,
          stripPoolLegacy: false,
          extraSetAppData: <String, dynamic>{'scan': params},
        );
        return true;
      case 'set_daysOfTransactions':
        final int days = (params['daysOfTransactions'] is num)
            ? (params['daysOfTransactions'] as num).toInt()
            : int.tryParse('${params['daysOfTransactions'] ?? 1}') ?? 1;
        final Map<String, dynamic> mergedDays = deepMergeMaps(
          cfg0,
          <String, dynamic>{
            'app': <String, dynamic>{'daysOfTransactions': days},
          },
        ) as Map<String, dynamic>;
        await _persistConfigSnapshot(
          paths,
          mergedDays,
          stripPoolLegacy: false,
          extraSetAppData: <String, dynamic>{'daysOfTransactions': days},
        );
        return true;
      case 'set_inactivityTimeout':
        final int inact = (params['inactivityTimeout'] is num)
            ? (params['inactivityTimeout'] as num).toInt()
            : int.tryParse('${params['inactivityTimeout'] ?? 5}') ?? 5;
        final Map<String, dynamic> mergedInact = deepMergeMaps(
          cfg0,
          <String, dynamic>{
            'app': <String, dynamic>{'inactivityTimeout': inact},
          },
        ) as Map<String, dynamic>;
        await _persistConfigSnapshot(
          paths,
          mergedInact,
          stripPoolLegacy: false,
          extraSetAppData: <String, dynamic>{'inactivityTimeout': inact},
        );
        return true;
      case 'quick_save_config':
        final Map<String, dynamic> ethIn = Map<String, dynamic>.from(
            cfg0['ethereum'] as Map? ?? <String, dynamic>{});
        final Map<String, dynamic> mergedEth =
            deepMergeMaps(ethIn, params) as Map<String, dynamic>;
        final Map<String, dynamic> mergedQuick =
            deepMergeMaps(cfg0, <String, dynamic>{'ethereum': mergedEth})
                as Map<String, dynamic>;
        final Map<String, dynamic> outQuick = _finalizeConfigForDiskWrite(
            paths, mergedQuick,
            stripPoolLegacy: false);
        _setRuntimeConfig(outQuick);
        await File(paths.configPath).writeAsString(
            const JsonEncoder.withIndent('  ').convert(_runtimeConfig));
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{
            'config': _runtimeConfig,
            'pending_config': _runtimeConfig
          },
        });
        return true;
      case 'save_config':
        await _maybePushMainnetRemote(paths, params);
        final String before = jsonEncode(cfg0);
        final Map<String, dynamic> mergedSave =
            deepMergeMaps(cfg0, params) as Map<String, dynamic>;
        final Map<String, dynamic> outSave = _finalizeConfigForDiskWrite(
            paths, mergedSave,
            stripPoolLegacy: false);
        _setRuntimeConfig(outSave);
        await File(paths.configPath).writeAsString(
            const JsonEncoder.withIndent('  ').convert(_runtimeConfig));
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{
            'config': _runtimeConfig,
            'pending_config': _runtimeConfig
          },
        });
        if (jsonEncode(_runtimeConfig) != before) {
          _emit(<String, dynamic>{
            'event': 'settings_changed_reboot',
            'data': <String, dynamic>{}
          });
        }
        return true;
      case 'save_config_init':
        await _maybePushMainnetRemote(paths, params);
        final Map<String, dynamic> mergedInit =
            deepMergeMaps(cfg0, params) as Map<String, dynamic>;
        final Map<String, dynamic> outInit = _finalizeConfigForDiskWrite(
            paths, mergedInit,
            stripPoolLegacy: true);
        _setRuntimeConfig(outInit);
        await File(paths.configPath).writeAsString(
            const JsonEncoder.withIndent('  ').convert(_runtimeConfig));
        await _restartAfterConfigInit();
        return true;
      case 'save_pool_config':
        final String net =
            (cfg0['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
        final String daemonType =
            '${((cfg0['daemons'] as Map?)?[net] as Map?)?['type'] ?? 'remote'}';
        final bool oldEnabled = ((((cfg0['pool'] as Map?)?['server']
                as Map?)?['enabled']) as bool?) ??
            false;
        Map<String, dynamic> mergedPool =
            deepMergeMaps(cfg0['pool'] ?? <String, dynamic>{}, params)
                as Map<String, dynamic>;
        String bindIp = '${((mergedPool['server'] as Map?)?['bindIP']) ?? ''}';
        if (bindIp.isEmpty || bindIp == '0.0.0.0' || bindIp == '127.0.0.1') {
          mergedPool = deepMergeMaps(mergedPool, <String, dynamic>{
            'server': <String, dynamic>{'bindIP': '127.0.0.1'},
          }) as Map<String, dynamic>;
        }
        mergedPool = _normalizePoolVarDiff(mergedPool);
        _setRuntimeConfig(
            deepMergeMaps(cfg0, <String, dynamic>{'pool': mergedPool})
                as Map<String, dynamic>);
        if (daemonType == 'remote') {
          _setRuntimeConfig(
            deepMergeMaps(
              _runtimeConfig!,
              <String, dynamic>{
                'pool': <String, dynamic>{
                  'server': <String, dynamic>{'enabled': false}
                }
              },
            ) as Map<String, dynamic>,
          );
          _showNotification(
              'warning', 'Solo pool requires local daemon mode', 3500);
        }
        final Map<String, dynamic> outPool = _finalizeConfigForDiskWrite(
            paths, _runtimeConfig!,
            stripPoolLegacy: true);
        _setRuntimeConfig(outPool);
        await File(paths.configPath).writeAsString(
            const JsonEncoder.withIndent('  ').convert(_runtimeConfig));
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{
            'config': _runtimeConfig,
            'pending_config': _runtimeConfig
          },
        });
        final bool enabled = (((_runtimeConfig!['pool'] as Map?)?['server']
                as Map?)?['enabled'] as bool?) ??
            false;
        int status = 0;
        if (enabled) {
          status = oldEnabled ? 2 : 1;
        }
        _emit(<String, dynamic>{
          'event': 'set_pool_data',
          'data': <String, dynamic>{'status': status},
        });
        await _syncSoloPoolSidecar(_runtimeConfig!);
        return true;
      default:
        return false;
    }
  }

  Future<void> _runCoreStartup() async {
    final ArqmaPaths paths = ArqmaPaths.defaultForPlatform();
    Directory(paths.guiDir).createSync(recursive: true);

    final dynamic remotes = _loadRemotes(paths);
    final Map<String, dynamic> defaults = buildDefaultsOnly(paths);
    final Map<String, dynamic> ethDefault = Map<String, dynamic>.from(
        buildInitialConfigData(paths)['ethereum'] as Map? ??
            <String, dynamic>{});

    _emit(<String, dynamic>{
      'event': 'set_app_data',
      'data': <String, dynamic>{'remotes': remotes, 'defaults': defaults},
    });
    _emit(<String, dynamic>{'event': 'set_ethereum_data', 'data': ethDefault});

    final File configFile = File(paths.configPath);
    if (!configFile.existsSync()) {
      final Map<String, dynamic> initial = buildInitialConfigData(paths);
      stripLegacyUniformPoolOption(initial);
      await mergePoolBindIpIfNeeded(initial);
      mergeWalletRpcBindPort19999(initial);
      final bool poolOn = poolServerEnabled(initial);
      _emit(<String, dynamic>{
        'event': 'set_pool_data',
        'data': <String, dynamic>{
          'status': poolOn ? 1 : 0,
          'desynced': false,
          'system_clock_error': false,
        },
      });
      _emit(<String, dynamic>{
        'event': 'set_app_data',
        'data': <String, dynamic>{
          // Treat as ready for wallet UI: list comes from default paths in [initial] until user saves `config.json`.
          'status': <String, dynamic>{'code': 0},
          'config': initial,
          'pending_config': initial,
        },
      });
      _setRuntimeConfig(initial);
      return;
    }

    Map<String, dynamic> configData;
    try {
      final Map<String, dynamic> disk = Map<String, dynamic>.from(
          jsonDecode(await configFile.readAsString()) as Map);
      // Same as Rust `fold_disk_into_config(build_initial_config_data, disk)`: disk overrides,
      // but missing `daemons[net_type]` / RPC fields are filled from defaults (Tauri startup parity).
      configData = Map<String, dynamic>.from(
          deepMergeMaps(buildInitialConfigData(paths), disk) as Map);
    } catch (e) {
      debugPrint('[DesktopNative] config.json parse error: $e');
      _showNotification('negative', 'Invalid config.json in ${paths.guiDir}');
      _emit(<String, dynamic>{
        'event': 'set_app_data',
        'data': <String, dynamic>{
          'status': <String, dynamic>{'code': -1}
        },
      });
      return;
    }

    stripLegacyUniformPoolOption(configData);
    await mergePoolBindIpIfNeeded(configData);
    mergeWalletRpcBindPort19999(configData);
    await applyScanAndFastestRemote(configData, remotes);
    try {
      await writeGuiConfigFile(paths, configData);
    } catch (e) {
      debugPrint('[DesktopNative] write config.json after startup merge: $e');
      _showNotification('negative', 'Could not write ${paths.configPath}');
      _emit(<String, dynamic>{
        'event': 'set_app_data',
        'data': <String, dynamic>{
          'status': <String, dynamic>{'code': -1}
        },
      });
      _setRuntimeConfig(configData);
      await _bestEffortWalletRpcAfterFailure(configData);
      return;
    }

    _setRuntimeConfig(configData);

    final Object? ethObj = configData['ethereum'];
    if (ethObj is Map) {
      _emit(<String, dynamic>{
        'event': 'set_ethereum_data',
        'data': Map<String, dynamic>.from(ethObj),
      });
    }

    final String selected = _selectedNodeString(configData);
    _emit(<String, dynamic>{
      'event': 'set_app_data',
      'data': <String, dynamic>{
        'config': configData,
        'pending_config': configData,
        'selected_node': selected,
      },
    });

    final bool poolOn = poolServerEnabled(configData);
    _emit(<String, dynamic>{
      'event': 'set_pool_data',
      'data': <String, dynamic>{
        'status': poolOn ? 1 : 0,
        'desynced': false,
        'system_clock_error': false,
      },
    });

    // Match practical UX (and fix deadlock vs Rust order): create dirs first, then verify.
    // Otherwise first-time users with valid paths in config never get directories created and
    // local `arqmad` never starts ("paths not found").
    try {
      _ensureDatadirLayout(configData);
    } catch (e) {
      debugPrint('[DesktopNative] ensure_datadir_layout failed: $e');
      _showNotification(
        'negative',
        'Could not create data or wallet directories. Check paths and permissions '
            '(on sandboxed macOS use folders you can write to, or set paths via Select Location).',
      );
      _emit(<String, dynamic>{
        'event': 'set_app_data',
        'data': <String, dynamic>{
          'status': <String, dynamic>{'code': -1}
        },
      });
      await _bestEffortWalletRpcAfterFailure(configData);
      return;
    }
    if (!_requiredDirsExist(configData)) {
      _showNotification(
        'negative',
        'Data Storage path or Wallet Storage path is missing or not accessible after create attempt.',
      );
      _emit(<String, dynamic>{
        'event': 'set_app_data',
        'data': <String, dynamic>{
          'status': <String, dynamic>{'code': -1}
        },
      });
      await _bestEffortWalletRpcAfterFailure(configData);
      return;
    }

    final String net =
        (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    Map<String, dynamic> daemonEntry = Map<String, dynamic>.from(
        (configData['daemons'] as Map? ?? <String, dynamic>{})[net] as Map? ??
            <String, dynamic>{});
    String daemonType = '${daemonEntry['type'] ?? 'remote'}';

    _emit(<String, dynamic>{
      'event': 'set_app_data',
      'data': <String, dynamic>{
        'status': <String, dynamic>{'code': 3}
      },
    });
    // Unblock `/` → `/wallet-select` while local `arqmad` may still be binding JSON-RPC (spawn wait
    // can take up to 120s). `code: 3` alone keeps the splash screen until the final `code: 0`.
    _emit(<String, dynamic>{
      'event': 'set_app_data',
      'data': <String, dynamic>{
        'status': <String, dynamic>{'code': 0},
      },
    });

    final DaemonReachableResult reach = await checkDaemonReachable(configData);
    if (reach == DaemonReachableResult.netMismatch) {
      _showNotification(
          'negative', 'Error: Remote node is using a different nettype');
      _emit(<String, dynamic>{
        'event': 'set_app_data',
        'data': <String, dynamic>{
          'status': <String, dynamic>{'code': -1}
        },
      });
      await _bestEffortWalletRpcAfterFailure(configData);
      return;
    }
    if (reach == DaemonReachableResult.inaccessible) {
      if (daemonType == 'local_remote') {
        await flipLocalRemoteToLocalAndPersist(paths, configData, net);
        _setRuntimeConfig(configData);
        _emit(<String, dynamic>{
          'event': 'show_notification',
          'data': <String, dynamic>{
            'type': 'warning',
            'message':
                'Warning: Could not access remote node, switching to local only',
            'timeout': 3000,
          },
        });
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{
            'config': configData,
            'pending_config': configData,
            'selected_node': _selectedNodeString(configData),
          },
        });
        daemonEntry = Map<String, dynamic>.from(
          (configData['daemons'] as Map? ?? <String, dynamic>{})[net] as Map? ??
              <String, dynamic>{},
        );
        daemonType = '${daemonEntry['type'] ?? 'remote'}';
      } else {
        _showNotification('negative',
            'Error: Could not access remote node, please try another remote node');
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{
            'status': <String, dynamic>{'code': -1}
          },
        });
        await _bestEffortWalletRpcAfterFailure(configData);
        return;
      }
    }

    final String ver = await arqmadVersionProbeStr();
    if (ver != 'unknown') {
      _emit(<String, dynamic>{
        'event': 'set_app_data',
        'data': <String, dynamic>{
          'status': <String, dynamic>{'code': 4, 'message': ver},
        },
      });
    } else {
      // Tauri also falls back to remote when `arqmad --version` fails, but on sandboxed macOS
      // `Process.run(..., --version)` often fails even when `arqmad` can be spawned — and flipping
      // `local` / `local_remote` → `remote` produces a misleading "Remote daemon can not be reached".
      if (daemonType == 'remote') {
        await setCurrentNetDaemonTypeRemoteAndPersist(paths, configData);
        _setRuntimeConfig(configData);
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{
            'status': <String, dynamic>{'code': 5},
            'config': configData,
            'pending_config': configData,
          },
        });
      } else {
        debugPrint(
          '[DesktopNative] arqmad --version returned unknown; keeping daemon type "$daemonType" '
          '(skip remote fallback — try local spawn)',
        );
      }
    }

    final Map<String, dynamic> daemonEntryNow = Map<String, dynamic>.from(
      (configData['daemons'] as Map? ?? <String, dynamic>{})[net] as Map? ??
          <String, dynamic>{},
    );
    final String daemonTypeNow = '${daemonEntryNow['type'] ?? 'remote'}';

    if (daemonTypeNow == 'remote') {
      final String? rh = daemonEntryNow['remote_host'] as String?;
      final int? rp = (daemonEntryNow['remote_port'] as num?)?.toInt();
      if (rh == null || rp == null) {
        _showNotification(
            'negative', 'Remote daemon: missing host/port in configuration');
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{
            'status': <String, dynamic>{'code': -1}
          },
        });
        await _bestEffortWalletRpcAfterFailure(configData);
        return;
      }
      final Map<String, dynamic>? r = await DaemonJsonRpc.getInfo(rh, rp);
      if (DaemonJsonRpc.getInfoPayload(r) == null) {
        _showNotification('negative', 'Remote daemon can not be reached');
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{
            'status': <String, dynamic>{'code': -1}
          },
        });
        await _bestEffortWalletRpcAfterFailure(configData);
        return;
      }
    } else {
      final ({Process? process, String? error}) spawned =
          await spawnLocalArqmadAndWait(
        configData: configData,
        net: net,
        onDaemonProcessLaunched: (Process p) {
          _daemonProcess = p;
          _startHeartbeat(configData);
        },
      );
      if (spawned.error != null) {
        _showNotification('negative', spawned.error!);
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{
            'status': <String, dynamic>{'code': -1}
          },
        });
        _daemonProcess = spawned.process;
        // Still poll `get_info`: user may start `arqmad` manually or RPC may already be up.
        _startHeartbeat(configData);
        await _bestEffortWalletRpcAfterFailure(configData);
        return;
      }
      _daemonProcess = spawned.process;
    }

    final ({String host, int port})? ep = daemonRpcHostPort(configData);
    if (ep != null) {
      final Map<String, dynamic>? r =
          await DaemonJsonRpc.getInfo(ep.host, ep.port);
      final Map<String, dynamic>? info = DaemonJsonRpc.getInfoPayload(r);
      if (info != null) {
        _applyDaemonInfo(configData, info);
      }
    }

    _emit(<String, dynamic>{
      'event': 'set_app_data',
      'data': <String, dynamic>{
        'status': <String, dynamic>{'code': 6}
      },
    });
    _emit(<String, dynamic>{
      'event': 'set_app_data',
      'data': <String, dynamic>{
        'status': <String, dynamic>{'code': 7}
      },
    });

    _emit(<String, dynamic>{
      'event': 'set_app_data',
      'data': <String, dynamic>{
        'status': <String, dynamic>{'code': 0}
      },
    });

    await _syncSoloPoolSidecar(configData);
    _startHeartbeat(configData);

    if (Platform.environment['ARQMA_FLUTTER_NO_WALLET_RPC'] != '1') {
      _walletRpc = await ArqmaWalletRpcSession.tryStart(configData);
      if (_walletRpc == null) {
        _showNotification(
          'warning',
          'Native wallet FFI did not start (${ArqmaWalletRpcSession.lastNativeStartupDiagnosis.trim().isNotEmpty ? ArqmaWalletRpcSession.lastNativeStartupDiagnosis : _walletFfiMissedStartHint()})',
          16000,
        );
      }
      _emitWalletBackendState();
    } else {
      _emit(<String, dynamic>{
        'event': 'set_app_data',
        'data': <String, dynamic>{'wallet_backend': 'off'},
      });
    }
  }

  void _emitWalletBackendState() {
    if (Platform.environment['ARQMA_FLUTTER_NO_WALLET_RPC'] == '1') {
      return;
    }
    final ArqmaWalletRpcSession? s = _walletRpc;
    final String wb =
        s == null ? 'none' : (s.usesNativeFfi ? 'ffi' : 'subprocess');
    _emit(<String, dynamic>{
      'event': 'set_app_data',
      'data': <String, dynamic>{'wallet_backend': wb},
    });
  }

  /// When daemon startup fails with `status -1`, still attempt wallet JSON-RPC (native FFI or
  /// subprocess if opted in) so account list / open wallet can work when the node comes back, and
  /// the footer shows `wallet_backend` instead of staying `pending`.
  Future<void> _bestEffortWalletRpcAfterFailure(
      Map<String, dynamic> configData) async {
    if (Platform.environment['ARQMA_FLUTTER_NO_WALLET_RPC'] == '1') {
      _emit(<String, dynamic>{
        'event': 'set_app_data',
        'data': <String, dynamic>{'wallet_backend': 'off'},
      });
      return;
    }
    try {
      if (_walletRpc != null) {
        await _walletRpc!.shutdown();
      }
    } catch (_) {}
    _walletRpc = null;
    try {
      _walletRpc = await ArqmaWalletRpcSession.tryStart(configData);
    } catch (e, st) {
      debugPrint('[DesktopNative] best-effort tryStart threw: $e\n$st');
      _walletRpc = null;
    }
    if (_walletRpc == null) {
      debugPrint(
          '[DesktopNative] best-effort wallet RPC did not start (check daemon address, paths, native FFI .dll/.so/.dylib)');
    }
    _emitWalletBackendState();
  }

  void _startHeartbeat(Map<String, dynamic> configData) {
    _heartbeat?.cancel();
    _heartbeatSlow?.cancel();
    _heartbeatSlow = null;
    final String net =
        (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final Map<String, dynamic>? dm = ((configData['daemons'] as Map?) ??
        <dynamic, dynamic>{})[net] as Map<String, dynamic>?;
    final String typ = '${dm?['type'] ?? 'remote'}';
    final bool isLocal = typ != 'remote';
    final Duration interval = Duration(seconds: isLocal ? 5 : 30);
    _heartbeat = Timer.periodic(interval, (_) {
      unawaited(_heartbeatTick(configData));
    });
    unawaited(_heartbeatTick(configData));
    // Tauri `daemon_heartbeat::run_heartbeat_loop`: `tick_slow` only when local daemon.
    if (isLocal) {
      _heartbeatSlow = Timer.periodic(const Duration(seconds: 60), (_) {
        unawaited(_heartbeatSlowTick(configData));
      });
    }
  }

  /// `daemon_heartbeat::tick_slow` — explorer clock skew (pool) + connections/bans/backlog.
  Future<void> _heartbeatSlowTick(Map<String, dynamic> configData) async {
    final Map<String, dynamic> cfg = _runtimeConfig != null
        ? Map<String, dynamic>.from(_runtimeConfig!)
        : configData;
    final String net =
        (cfg['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final String daemonTyp =
        '${((cfg['daemons'] as Map?)?[net] as Map?)?['type'] ?? 'remote'}';
    if (daemonTyp == 'remote') {
      return;
    }
    final ({String host, int port})? ep = daemonRpcHostPort(cfg);
    if (ep == null) {
      return;
    }
    final bool poolOn = poolServerEnabled(cfg);
    final bool testnet = (cfg['app'] as Map?)?['testnet'] == true;
    if (poolOn) {
      final bool? sce = await explorerClockSkewArqma(testnet: testnet);
      if (sce != null) {
        _emit(<String, dynamic>{
          'event': 'set_pool_data',
          'data': <String, dynamic>{'system_clock_error': sce},
        });
      }
    }
    final Map<String, dynamic> extra =
        await collectSlowDaemonHeartbeat(ep.host, ep.port);
    if (extra.isEmpty) {
      return;
    }
    _emit(<String, dynamic>{
      'event': 'set_daemon_data',
      'data': extra,
    });
  }

  Future<void> _heartbeatTick(Map<String, dynamic> configData) async {
    final Map<String, dynamic> cfg = _runtimeConfig != null
        ? Map<String, dynamic>.from(_runtimeConfig!)
        : configData;
    final String net =
        (cfg['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final String daemonTyp =
        '${((cfg['daemons'] as Map?)?[net] as Map?)?['type'] ?? 'remote'}';
    final ({String host, int port})? ep = daemonRpcHostPort(cfg);
    if (ep == null) {
      return;
    }
    final Map<String, dynamic>? r =
        await DaemonJsonRpc.getInfo(ep.host, ep.port);
    // Tauri `daemon_heartbeat`: only auto-restart local child on **transport** failure, not JSON-RPC errors.
    if (r == null) {
      if (daemonTyp != 'remote') {
        await _restartLocalDaemonIfExited(cfg, net);
      }
      return;
    }
    final Map<String, dynamic>? info = DaemonJsonRpc.getInfoPayload(r);
    if (info != null) {
      _applyDaemonInfo(cfg, info);
    }
  }

  void _stopWalletHeartbeat() {
    _walletHeartbeat?.cancel();
    _walletHeartbeat = null;
    _walletXferScanThrottleUntil = null;
  }

  /// Electron `wallet-rpc.js` / Tauri `wallet_heartbeat::start`: 5 s when not `remote`, else 60 s.
  void _startWalletHeartbeat() {
    _stopWalletHeartbeat();
    final Map<String, dynamic>? cfg = _runtimeConfig;
    if (cfg == null || _walletRpc == null || _openedWalletDisplayName.isEmpty) {
      return;
    }
    final String net =
        (cfg['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final String typ =
        '${((cfg['daemons'] as Map?)?[net] as Map?)?['type'] ?? 'remote'}';
    final bool isLocal = typ != 'remote';
    final Duration interval = Duration(seconds: isLocal ? 5 : 60);
    _walletHeartbeat = Timer.periodic(interval, (_) {
      unawaited(_walletHeartbeatTick());
    });
    unawaited(_walletHeartbeatTick());
  }

  /// Same bucket merge + sort as `wallet_heartbeat::merge_transfers_list`.
  List<dynamic> _mergeWalletRpcTransfersList(Map<String, dynamic> result) {
    const List<String> keys = <String>[
      'in',
      'out',
      'pending',
      'failed',
      'pool',
      'miner',
      'snode',
      'gov',
      'stake',
      'net',
    ];
    // Wallet RPC `get_transfers` only emits five top-level buckets (`in`, `out`,
    // `pending`, `failed`, `pool`); the per-row `type` carries the real
    // `pay_type` (`in`/`out`/`snode`/`miner`/`gov`/`stake`/`net`/`dev`) — see
    // `arqma-rpc-upstream::wallet2.h::pay_type_string`. Preserve the row's
    // `type` for the categorising buckets so the Service Node / Stake / Miner
    // filters match (parity with Tauri `wallet_heartbeat::merge_transfers_list`).
    // For `pending`/`failed`/`pool` the bucket key is authoritative because
    // native FFI rows still carry a direction-derived `in`/`out` placeholder.
    const Set<String> bucketKeyAuthoritative = <String>{
      'pending',
      'failed',
      'pool',
    };
    const Set<String> validRpcTypes = <String>{
      'in',
      'out',
      'snode',
      'stake',
      'miner',
      'gov',
      'dev',
      'net',
      'pending',
      'failed',
      'pool',
    };
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final String k in keys) {
      final Object? arr = result[k];
      if (arr is List) {
        for (final Object? x in arr) {
          if (x is Map) {
            final Map<String, dynamic> row = Map<String, dynamic>.from(x);
            final String existing = '${row['type'] ?? ''}';
            if (bucketKeyAuthoritative.contains(k) ||
                !validRpcTypes.contains(existing)) {
              row['type'] = k;
            }
            out.add(row);
          }
        }
      }
    }
    out.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final int ta = int.tryParse('${a['timestamp'] ?? 0}') ?? 0;
      final int tb = int.tryParse('${b['timestamp'] ?? 0}') ?? 0;
      return tb.compareTo(ta);
    });
    return out;
  }

  Future<void> _walletXferHeavy(
      String walletNameAtStart, int curH, int daysWindowBlocks) async {
    if (_walletXferBusy) {
      return;
    }
    _walletXferBusy = true;
    bool emittedOk = false;
    try {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w == null || _openedWalletDisplayName != walletNameAtStart) {
        return;
      }
      final int minHeight =
          curH > daysWindowBlocks ? curH - daysWindowBlocks : 0;
      // Include all buckets merged in [_mergeWalletRpcTransfersList]; otherwise
      // UI filters (e.g. service node / stake) see an empty list even when txs exist.
      final Map<String, dynamic> p = <String, dynamic>{
        'in': true,
        'out': true,
        'pending': true,
        'failed': true,
        'pool': false,
        'miner': true,
        'snode': true,
        'gov': true,
        'stake': true,
        'net': true,
        'filter_by_height': true,
        'min_height': minHeight,
      };
      final Map<String, dynamic>? txf = await w
          .call('get_transfers', p)
          .timeout(const Duration(seconds: 300), onTimeout: () => null);
      if (_openedWalletDisplayName != walletNameAtStart ||
          txf == null ||
          !walletJsonRpcNoError(txf)) {
        return;
      }
      final Object? res = txf['result'];
      if (res is! Map) {
        return;
      }
      final List<dynamic> list =
          _mergeWalletRpcTransfersList(Map<String, dynamic>.from(res));
      _emit(<String, dynamic>{
        'event': 'set_wallet_transactions',
        'data': <String, dynamic>{'tx_list': list},
      });
      emittedOk = true;
      _whFetchTxPending = false;
      // A slow `get_transfers` can finish after the wallet height has advanced several
      // ticks (footer updates from `getheight` while this call was in flight). The RPC
      // snapshot may omit rows for blocks scanned only after [curH]. Without a follow-up
      // xfer, `xferTrigger` stays false at a flat tip (`newH == h0`) and the tx list
      // stays stuck with an old newest height — see wallet_heartbeat parity / issue reports.
      if (walletNameAtStart == _openedWalletDisplayName &&
          _whStoredHeight > curH) {
        _whFetchTxPending = true;
      }
    } catch (e, st) {
      debugPrint('[DesktopNative] wallet get_transfers: $e\n$st');
    } finally {
      _walletXferBusy = false;
      if (!emittedOk && walletNameAtStart == _openedWalletDisplayName) {
        _whFetchTxPending = true;
      }
    }
  }

  /// Parity with Tauri `wallet_heartbeat`: never drop ticks — a slow `getheight` must not
  /// suppress later polls (that froze footer sync %). Heavy `get_transfers` runs via
  /// [unawaited] + [_walletXferBusy]; native FFI serializes concurrent calls.
  Future<void> _walletHeartbeatTick() async {
    await _walletHeartbeatTickBody();
  }

  Future<void> _walletHeartbeatTickBody() async {
    final ArqmaWalletRpcSession? w = _walletRpc;
    final String name = _openedWalletDisplayName;
    final Map<String, dynamic>? cfg = _runtimeConfig;
    if (w == null || name.isEmpty || cfg == null) {
      return;
    }
    final int h0 = _whStoredHeight;
    final int b0 = _whStoredBalance;
    final int u0 = _whStoredUnlocked;
    final int dh = _daemonChainTipHeight;
    final bool inScanRhythm = dh == 0 || h0 < dh;
    final Duration ghCap = inScanRhythm
        ? const Duration(seconds: 120)
        : const Duration(seconds: 45);
    final Duration abCap = inScanRhythm
        ? const Duration(seconds: 30)
        : const Duration(seconds: 12);

    Map<String, dynamic>? gh;
    try {
      gh = await w.call('getheight', <String, dynamic>{}).timeout(ghCap);
    } catch (e, st) {
      debugPrint('[DesktopNative] wallet hb getheight: $e\n$st');
      gh = null;
    }
    final bool ghOk = gh != null && walletJsonRpcNoError(gh);

    Map<String, dynamic>? ga;
    if (ghOk) {
      try {
        ga = await w.call('get_address',
            <String, dynamic>{'account_index': 0}).timeout(abCap);
      } catch (e, st) {
        debugPrint('[DesktopNative] wallet hb get_address: $e\n$st');
        ga = null;
      }
    }

    Map<String, dynamic>? gb;
    try {
      gb = await w.call(
          'getbalance', <String, dynamic>{'account_index': 0}).timeout(abCap);
    } catch (e, st) {
      debugPrint('[DesktopNative] wallet hb getbalance: $e\n$st');
      gb = null;
    }

    int newH = h0;
    int newB = b0;
    int newU = u0;
    bool hasBalanceChange = false;
    if (ghOk) {
      final int? parsed = walletHeightFromGetheight(gh);
      if (parsed != null) {
        newH = parsed;
      }
    }
    if (_walletFullRescanUi && _walletCaughtDaemonTip(newH, dh)) {
      _walletFullRescanUi = false;
    }
    final Map<String, dynamic> info = <String, dynamic>{
      'name': name,
      'height': newH,
      'scan_poll_ts': DateTime.now().millisecondsSinceEpoch,
      'full_rescan_ui': _walletFullRescanUi,
    };
    if (ga != null && walletJsonRpcNoError(ga)) {
      final Object? res = ga['result'];
      if (res is Map) {
        final String addr = '${res['address'] ?? ''}'.trim();
        if (addr.isNotEmpty) {
          info['address'] = addr;
        }
      }
    }
    if (gb != null && walletJsonRpcNoError(gb)) {
      final Object? res = gb['result'];
      if (res is Map) {
        final Map<String, dynamic> rm = Map<String, dynamic>.from(res);
        final int bal = (rm['balance'] as num?)?.toInt() ?? 0;
        final int unl = (rm['unlocked_balance'] as num?)?.toInt() ??
            (rm['unlocked'] as num?)?.toInt() ??
            0;
        hasBalanceChange = !(b0 == bal && u0 == unl);
        newB = bal;
        newU = unl;
        info['balance'] = bal;
        info['unlocked_balance'] = unl;
      }
    }
    _whStoredHeight = newH;
    _whStoredBalance = newB;
    _whStoredUnlocked = newU;
    // One more `get_transfers` after the wallet height crosses the daemon tip in this tick.
    // Otherwise the last poll can leave an empty list / zero balance until the next height
    // nudge (which never comes at a flat tip).
    if (dh > 0 && h0 < dh && newH >= dh) {
      _whFetchTxPending = true;
    }
    _emit(<String, dynamic>{
      'event': 'set_wallet_info',
      'data': info,
    });
    _emit(<String, dynamic>{
      'event': 'reset_wallet_status',
      'data': <String, dynamic>{'code': 0, 'message': 'OK'},
    });

    final int daysWt =
        (((cfg['app'] as Map?)?['daysOfTransactions'] as num?)?.toInt() ?? 1)
            .clamp(1, 365);
    final int daysWindowBlocks = daysWt * 720;
    // Match Tauri `wallet_heartbeat`: xfer on pending open, balance change, or (once caught up)
    // each height tick — see `wallet_heartbeat.rs`. Additionally refresh txs periodically **during**
    // chain scan (Electron only refreshed on balance_change; that misses rows until balance moves).
    final DateTime now = DateTime.now();
    bool xferDuringScan = false;
    if (inScanRhythm && newH != h0) {
      if (_walletXferScanThrottleUntil == null ||
          !now.isBefore(_walletXferScanThrottleUntil!)) {
        xferDuringScan = true;
      }
    }
    final bool xferTrigger = _whFetchTxPending ||
        hasBalanceChange ||
        (!inScanRhythm && newH != h0) ||
        xferDuringScan;
    // Start xfer when `getbalance` succeeded (Tauri parity), **or** when `getbalance` is flaky
    // during scan but `getheight` works — otherwise open-wallet pending xfer never runs.
    final bool gbOk = gb != null && walletJsonRpcNoError(gb);
    final bool canXfer = xferTrigger &&
        !_walletXferBusy &&
        (gbOk ||
            (_whFetchTxPending && ghOk) ||
            (xferDuringScan && ghOk));
    if (canXfer) {
      if (xferDuringScan) {
        _walletXferScanThrottleUntil =
            now.add(const Duration(seconds: 45));
      }
      unawaited(_walletXferHeavy(name, newH, daysWindowBlocks));
    }
  }

  /// Before `rescan_blockchain`: force footer/list into “scanning from scratch” so the UI paints before the RPC returns.
  void _emitRescanStartingUi({required bool clearTransactions}) {
    final String name = _openedWalletDisplayName;
    if (name.isEmpty) {
      return;
    }
    _whStoredHeight = 0;
    _whFetchTxPending = true;
    _walletFullRescanUi = true;
    _emit(<String, dynamic>{
      'event': 'set_wallet_info',
      'data': <String, dynamic>{
        'name': name,
        'height': 0,
        'balance': _whStoredBalance,
        'unlocked_balance': _whStoredUnlocked,
        'scan_poll_ts': DateTime.now().millisecondsSinceEpoch,
        'allow_lower_height': true,
        'full_rescan_ui': true,
      },
    });
    if (clearTransactions) {
      _emit(<String, dynamic>{
        'event': 'set_wallet_transactions',
        'data': <String, dynamic>{'tx_list': <dynamic>[]},
      });
    }
    _emit(<String, dynamic>{
      'event': 'reset_wallet_status',
      'data': <String, dynamic>{'code': 0, 'message': 'OK'},
    });
  }

  /// Poll wallet RPC once after `rescan_*` so the footer shows scan height immediately (from genesis)
  /// instead of waiting for the next heartbeat; [GatewayStore.setWalletInfo] normally blocks height
  /// decreases — we pass `allow_lower_height` for this snapshot.
  Future<void> _refreshWalletUiAfterRescan({required bool clearTransactions}) async {
    final ArqmaWalletRpcSession? w = _walletRpc;
    final String name = _openedWalletDisplayName;
    if (w == null || name.isEmpty) {
      return;
    }
    Map<String, dynamic>? gh;
    Map<String, dynamic>? gb;
    try {
      gh = await w
          .call('getheight', <String, dynamic>{})
          .timeout(const Duration(seconds: 30), onTimeout: () => null);
    } catch (_) {}
    try {
      gb = await w
          .call('getbalance', <String, dynamic>{'account_index': 0})
          .timeout(const Duration(seconds: 30), onTimeout: () => null);
    } catch (_) {}

    int newH = _whStoredHeight;
    if (gh != null && walletJsonRpcNoError(gh)) {
      final int? parsed = walletHeightFromGetheight(gh);
      if (parsed != null) {
        newH = parsed;
      }
    }
    _whStoredHeight = newH;

    if (gb != null && walletJsonRpcNoError(gb)) {
      final Object? res = gb['result'];
      if (res is Map) {
        final Map<String, dynamic> rm = Map<String, dynamic>.from(res);
        _whStoredBalance =
            (rm['balance'] as num?)?.toInt() ?? _whStoredBalance;
        _whStoredUnlocked = (rm['unlocked_balance'] as num?)?.toInt() ??
            (rm['unlocked'] as num?)?.toInt() ??
            _whStoredUnlocked;
      }
    }

    _whFetchTxPending = true;
    _emit(<String, dynamic>{
      'event': 'set_wallet_info',
      'data': <String, dynamic>{
        'name': name,
        'height': newH,
        'balance': _whStoredBalance,
        'unlocked_balance': _whStoredUnlocked,
        'scan_poll_ts': DateTime.now().millisecondsSinceEpoch,
        'allow_lower_height': true,
      },
    });
    if (clearTransactions) {
      _emit(<String, dynamic>{
        'event': 'set_wallet_transactions',
        'data': <String, dynamic>{'tx_list': <dynamic>[]},
      });
    }
    _emit(<String, dynamic>{
      'event': 'reset_wallet_status',
      'data': <String, dynamic>{'code': 0, 'message': 'OK'},
    });
  }

  /// `daemon_process::restart_local_daemon_if_exited` — best-effort for desktop `dart:io` [Process].
  Future<void> _restartLocalDaemonIfExited(
      Map<String, dynamic> cfg, String net) async {
    final bool exitedOrMissing = await _localDaemonExitedOrMissing();
    if (!exitedOrMissing) {
      return;
    }
    final Process? old = _daemonProcess;
    _daemonProcess = null;
    try {
      old?.kill(ProcessSignal.sigterm);
    } catch (_) {}
    try {
      await old?.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {}
    final ({Process? process, String? error}) spawned =
        await spawnLocalArqmadAndWait(
      configData: cfg,
      net: net,
      onDaemonProcessLaunched: (Process p) {
        _daemonProcess = p;
      },
    );
    if (spawned.error != null) {
      debugPrint(
          '[DesktopNative] heartbeat: local arqmad restart failed: ${spawned.error}');
      _daemonProcess = spawned.process;
      return;
    }
    _daemonProcess = spawned.process;
    debugPrint('[DesktopNative] heartbeat: local arqmad auto-restarted');
  }

  Future<bool> _localDaemonExitedOrMissing() async {
    final Process? p = _daemonProcess;
    if (p == null) {
      return true;
    }
    final Object? raced = await Future.any<Object?>(<Future<Object?>>[
      p.exitCode.then<Object?>((int code) => true),
      Future<Object?>.delayed(Duration.zero).then((_) => false),
    ]);
    return raced == true;
  }

  /// `daemon_heartbeat::tick_fast` — `set_daemon_data` + pool network stats (`set_pool_data`) like Tauri.
  void _applyDaemonInfo(Map<String, dynamic> cfg, Map<String, dynamic> result) {
    final int h = jsonRpcLooseInt(result['height']) ?? 0;
    final int targetH = jsonRpcLooseInt(result['target_height']) ?? h;
    final int hw = jsonRpcLooseInt(result['height_without_bootstrap']) ?? h;
    final bool isReadyRpc = result['is_ready'] == true;
    final int footerTarget = h > targetH ? h : targetH;
    final bool caughtUp = hw >= footerTarget;
    final bool isReadyUi = caughtUp || isReadyRpc;
    final Map<String, dynamic> m = Map<String, dynamic>.from(result);
    m['is_ready_daemon_rpc'] = isReadyRpc;
    m['is_ready'] = isReadyUi;
    final int prevDaemonTip = _daemonChainTipHeight;
    _emit(<String, dynamic>{
      'event': 'set_daemon_data',
      'data': <String, dynamic>{'info': m},
    });
    _daemonChainTipHeight = footerTarget;
    if (_openedWalletDisplayName.isNotEmpty &&
        prevDaemonTip > 0 &&
        footerTarget > prevDaemonTip) {
      _whFetchTxPending = true;
    }
    _emitPoolDataWithHeartbeat(cfg, m);
  }

  void _emitPoolDataWithHeartbeat(
      Map<String, dynamic> cfg, Map<String, dynamic> result) {
    final bool poolEnabled = poolServerEnabled(cfg);
    final int h = jsonRpcLooseInt(result['height']) ?? 0;
    final int targetH = jsonRpcLooseInt(result['target_height']) ?? h;
    final int hw = jsonRpcLooseInt(result['height_without_bootstrap']) ?? h;
    final bool isReadyRpc = result['is_ready_daemon_rpc'] == true;
    final int footerTarget = h > targetH ? h : targetH;
    final bool daemonChainCaughtUp = hw >= footerTarget;
    final bool isReadyForUi = daemonChainCaughtUp || isReadyRpc;
    final bool daemonAvailable = h > 0;
    final bool synced = (h >= targetH - 1 && isReadyForUi) || daemonAvailable;
    final int difficulty = (result['difficulty'] as num?)?.toInt() ?? 0;
    final int target = (result['target'] as num?)?.toInt() ?? 120;
    final int networkHashrate = target == 0 ? 0 : difficulty ~/ target;
    final int poolStatus = !poolEnabled ? 0 : (synced ? 2 : 1);

    if (poolEnabled) {
      _emit(<String, dynamic>{
        'event': 'set_pool_data',
        'data': <String, dynamic>{
          'desynced': !daemonChainCaughtUp,
          'stats': <String, dynamic>{
            'networkHashrate': networkHashrate,
            'diff': difficulty,
            'height': h,
          },
        },
      });
    } else {
      _emit(<String, dynamic>{
        'event': 'set_pool_data',
        'data': <String, dynamic>{
          'status': poolStatus,
          'desynced': false,
          'system_clock_error': false,
          'stats': <String, dynamic>{
            'networkHashrate': networkHashrate,
            'diff': difficulty,
            'height': h,
            'activeWorkers': 0,
          },
        },
      });
    }
  }

  dynamic _loadRemotes(ArqmaPaths paths) {
    final File f = File(paths.remotesPath);
    if (f.existsSync()) {
      try {
        final Object? v = jsonDecode(f.readAsStringSync());
        if (v is List<dynamic>) {
          return v;
        }
      } catch (e) {
        debugPrint('[DesktopNative] remotes.json: $e');
      }
    }
    return List<dynamic>.generate(
      5,
      (int i) =>
          <String, dynamic>{'host': 'node${i + 1}.arqma.com', 'port': 19994},
    );
  }

  String _selectedNodeString(Map<String, dynamic> configData) {
    final String a =
        (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final Map<String, dynamic>? d =
        (configData['daemons'] as Map?)?[a] as Map<String, dynamic>?;
    if (d == null) {
      return '';
    }
    final String? h = d['remote_host'] as String?;
    final int? p = (d['remote_port'] as num?)?.toInt();
    if (h == null || p == null) {
      return '';
    }
    return '$h:$p';
  }

  bool _requiredDirsExist(Map<String, dynamic> configData) {
    final Map<String, dynamic>? app =
        configData['app'] as Map<String, dynamic>?;
    if (app == null) {
      return false;
    }
    final String? dd = app['data_dir'] as String?;
    final String? wd = app['wallet_data_dir'] as String?;
    if (dd == null || wd == null || dd.isEmpty || wd.isEmpty) {
      return false;
    }
    return Directory(dd).existsSync() && Directory(wd).existsSync();
  }

  void _ensureDatadirLayout(Map<String, dynamic> configData) {
    final Map<String, dynamic> app = Map<String, dynamic>.from(
        configData['app'] as Map? ?? <String, dynamic>{});
    final String? wdir = app['wallet_data_dir'] as String?;
    final String? dataDir = app['data_dir'] as String?;
    final String net = app['net_type'] as String? ?? 'mainnet';
    if (wdir != null && wdir.isNotEmpty) {
      Directory(wdir).createSync(recursive: true);
    }
    if (dataDir != null && dataDir.isNotEmpty) {
      final Directory mainData = Directory(dataDir);
      final Directory netDir = switch (net) {
        'stagenet' => Directory(
            <String>[mainData.path, 'stagenet'].join(Platform.pathSeparator)),
        'testnet' => Directory(
            <String>[mainData.path, 'testnet'].join(Platform.pathSeparator)),
        _ => mainData,
      };
      netDir.createSync(recursive: true);
      Directory(<String>[netDir.path, 'logs'].join(Platform.pathSeparator))
          .createSync(recursive: true);
    }
  }

  Future<dynamic> _openWalletDesktop(Object? data) async {
    final Stopwatch sw = Stopwatch()..start();
    _traceWalletOpen('begin open_wallet flow', sw: sw);
    final ArqmaWalletRpcSession? w = _walletRpc;
    if (w == null) {
      _traceWalletOpen('abort: wallet RPC null', sw: sw);
      _showNotification(
        'negative',
        _walletFfiBackendOfflineHint(),
        12000,
      );
      _emit(<String, dynamic>{
        'event': 'reset_wallet_status',
        'data': <String, dynamic>{
          'code': -1,
          'message': 'Wallet RPC unavailable'
        },
      });
      return <String, dynamic>{};
    }
    final Map<String, dynamic> p = _coerceMap(data);
    final String name = '${p['name'] ?? p['filename'] ?? ''}'.trim();
    final String password = '${p['password'] ?? ''}';
    _traceWalletOpen('wallet name="${name.isEmpty ? '<empty>' : name}" ffi=${w.usesNativeFfi}',
        sw: sw);
    if (name.isEmpty) {
      _emit(<String, dynamic>{
        'event': 'reset_wallet_status',
        'data': <String, dynamic>{'code': -1, 'message': 'Missing wallet name'},
      });
      return <String, dynamic>{};
    }
    _emit(<String, dynamic>{
      'event': 'reset_wallet_error',
      'data': <String, dynamic>{}
    });
    // Let the UI paint [AppLoading] before the synchronous FFI `open_wallet` blocks the isolate.
    await Future<void>.delayed(Duration.zero);
    _traceWalletOpen('calling RPC open_wallet (may block isolate / UI)', sw: sw);
    final Map<String, dynamic>? opened = await w.call(
      'open_wallet',
      <String, dynamic>{'filename': name, 'password': password},
    );
    _traceWalletOpen('RPC open_wallet returned ok=${walletJsonRpcNoError(opened)}', sw: sw);
    if (!walletJsonRpcNoError(opened)) {
      final String msg = '${opened?['error'] ?? 'open_wallet failed'}';
      _traceWalletOpen('open_wallet error: $msg', sw: sw);
      _emit(<String, dynamic>{
        'event': 'reset_wallet_status',
        'data': <String, dynamic>{'code': -1, 'message': msg},
      });
      return <String, dynamic>{};
    }
    _walletFullRescanUi = false;
    _refreshSessionPasswordDigest(password);
    _traceWalletOpen('starting _emitWalletOpenedUi', sw: sw);
    await _emitWalletOpenedUi(name);
    _traceWalletOpen('done open_wallet flow', sw: sw);
    return <String, dynamic>{};
  }

  /// Same as Tauri `refresh_wallet_password_hash_from_password` after a successful wallet session password is known.
  void _refreshSessionPasswordDigest(String password) {
    final ArqmaWalletRpcSession? w = _walletRpc;
    if (w == null) {
      _walletPasswordHashHex = null;
      return;
    }
    final String saltHex = w.rpcPbkdf2SaltHex;
    if (saltHex.length != 64) {
      _walletPasswordHashHex = null;
      return;
    }
    _walletPasswordHashHex =
        tryPbkdf2PasswordHex(password: password, saltHex: saltHex);
  }

  bool _promptPasswordEnabled() =>
      (_runtimeConfig?['app'] as Map?)?['promptForPassword'] == true;

  /// `wallet_handler::wallet_password_matches` — always enforced when salt + hash exist (e.g. `unlock_stake`).
  bool _walletPasswordMatches(String password) {
    final String salt = _walletRpc?.rpcPbkdf2SaltHex ?? '';
    if (salt.isEmpty || salt.length != 64) {
      return true;
    }
    final String? want = _walletPasswordHashHex;
    if (want == null) {
      return false;
    }
    final String? got = tryPbkdf2PasswordHex(password: password, saltHex: salt);
    return got != null && got == want;
  }

  /// `wallet_handler::wallet_password_ok_for_tx` — skips check when `promptForPassword` is false.
  bool _walletPasswordOkForTx(String password) {
    if (!_promptPasswordEnabled()) {
      return true;
    }
    return _walletPasswordMatches(password);
  }

  Future<void> _emitWalletOpenedUi(String name) async {
    final Stopwatch sw = Stopwatch()..start();
    _traceWalletOpen('_emitWalletOpenedUi begin name=$name', sw: sw);
    final ArqmaWalletRpcSession? w = _walletRpc;
    if (w == null) {
      _traceWalletOpen('_emitWalletOpenedUi abort: no session', sw: sw);
      return;
    }
    _openedWalletDisplayName = name;
    final int ts = DateTime.now().millisecondsSinceEpoch;
    _emit(<String, dynamic>{
      'event': 'set_wallet_info',
      'data': <String, dynamic>{
        'name': name,
        'height': 0,
        'balance': 0,
        'unlocked_balance': 0,
        'scan_poll_ts': ts,
      },
    });
    _emit(<String, dynamic>{
      'event': 'reset_wallet_status',
      'data': <String, dynamic>{'code': 0, 'message': 'OK'},
    });

    final Map<String, dynamic>? gh = await w
        .call('getheight', <String, dynamic>{}).timeout(
            const Duration(seconds: 30),
            onTimeout: () => null);
    _traceWalletOpen(
        'post-open getheight ok=${walletJsonRpcNoError(gh)} height=${walletHeightFromGetheight(gh)}',
        sw: sw);
    final Map<String, dynamic>? gb = await w
        .call('getbalance', <String, dynamic>{'account_index': 0}).timeout(
            const Duration(seconds: 30),
            onTimeout: () => null);
    _traceWalletOpen('post-open getbalance ok=${walletJsonRpcNoError(gb)}', sw: sw);

    final int openedHeight = walletHeightFromGetheight(gh) ?? 0;
    int bal = 0;
    int unl = 0;
    if (walletJsonRpcNoError(gb) && gb != null) {
      final Object? res = gb['result'];
      if (res is Map) {
        final Map<String, dynamic> rm = Map<String, dynamic>.from(res);
        bal = (rm['balance'] as num?)?.toInt() ?? 0;
        unl = (rm['unlocked_balance'] as num?)?.toInt() ??
            (rm['unlocked'] as num?)?.toInt() ??
            0;
      }
    }

    String? address;
    final Map<String, dynamic>? ga = await w
        .call('get_address', <String, dynamic>{'account_index': 0}).timeout(
            const Duration(seconds: 25),
            onTimeout: () => null);
    _traceWalletOpen('post-open get_address ok=${walletJsonRpcNoError(ga)}', sw: sw);
    if (walletJsonRpcNoError(ga) && ga != null) {
      final Object? res = ga['result'];
      if (res is Map) {
        final String a = '${res['address'] ?? ''}'.trim();
        if (a.isNotEmpty) {
          address = a;
        }
      }
    }

    bool viewOnly = false;
    final Map<String, dynamic>? qk = await w
        .call('query_key', <String, dynamic>{'key_type': 'spend_key'}).timeout(
            const Duration(seconds: 20),
            onTimeout: () => null);
    _traceWalletOpen('post-open query_key(spend) ok=${walletJsonRpcNoError(qk)}', sw: sw);
    if (walletJsonRpcNoError(qk) && qk != null) {
      final Object? res = qk['result'];
      if (res is Map) {
        final String key = '${res['key'] ?? ''}';
        if (key.isNotEmpty && key.split('').every((String c) => c == '0')) {
          viewOnly = true;
        }
      }
    }

    _emit(<String, dynamic>{
      'event': 'set_wallet_info',
      'data': <String, dynamic>{
        'name': name,
        'address': ?address,
        'height': openedHeight,
        'balance': bal,
        'unlocked_balance': unl,
        'view_only': viewOnly,
        'scan_poll_ts': DateTime.now().millisecondsSinceEpoch,
      },
    });
    _emit(<String, dynamic>{
      'event': 'set_wallet_transactions',
      'data': <String, dynamic>{'tx_list': <dynamic>[]},
    });
    _whStoredHeight = openedHeight;
    _whStoredBalance = bal;
    _whStoredUnlocked = unl;
    _whFetchTxPending = true;
    _traceWalletOpen('_emitWalletOpenedUi starting wallet heartbeat', sw: sw);
    _startWalletHeartbeat();
    _traceWalletOpen('_emitWalletOpenedUi complete', sw: sw);
  }

  static const double _arqCoinUnits = 1e9;
  /// Warn / suggest sweep when any relay slice sends less than this many ARQ (atomic units).
  static const int _maxSingleSplitPartArqAtoms = 1000 * 1000000000;

  Map<String, dynamic> _transferSplitFeeDialogExtras(
      Map<String, dynamic> res) {
    final List<dynamic>? metaList =
        res['tx_metadata_list'] as List<dynamic>?;
    final List<dynamic>? partAmounts = res['amount_list'] as List<dynamic>?;
    final int nParts = metaList?.length ??
        partAmounts?.length ??
        1;
    int minAtoms = -1;
    bool anyUnder1000 = false;
    final List<String> partArqStrs = <String>[];
    if (partAmounts != null) {
      for (final Object? v in partAmounts) {
        final int a = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
        partArqStrs.add((a / _arqCoinUnits).toStringAsFixed(9));
        if (a <= 0) {
          continue;
        }
        if (minAtoms < 0 || a < minAtoms) {
          minAtoms = a;
        }
        if (a < _maxSingleSplitPartArqAtoms) {
          anyUnder1000 = true;
        }
      }
    }
    if (minAtoms < 0) {
      minAtoms = 0;
    }
    return <String, dynamic>{
      'transfer_split_parts': nParts,
      'transfer_split_is_split': nParts > 1,
      'transfer_split_min_part_atoms': minAtoms,
      'transfer_split_any_part_under_1000_arq': anyUnder1000,
      'transfer_suggest_sweep_all': anyUnder1000,
      if (partArqStrs.isNotEmpty) 'transfer_split_part_amounts_arq': partArqStrs,
    };
  }

  String _walletRpcErrCapitalized(Object? err) {
    if (err is! Map) {
      return 'Unknown error';
    }
    final String? m = err['message'] as String?;
    if (m == null || m.isEmpty) {
      return 'Unknown error';
    }
    return m[0].toUpperCase() + m.substring(1);
  }

  Map<String, dynamic> _mapTransferSplitParams(Map<String, dynamic> p) {
    final Object? rawA = p['amount'];
    double amountUi;
    if (rawA is num) {
      amountUi = rawA.toDouble();
    } else if (rawA is String) {
      amountUi = double.tryParse(rawA) ?? double.nan;
    } else {
      amountUi = double.nan;
    }
    if (!amountUi.isFinite) {
      throw StateError('transfer: amount');
    }
    final String address = '${p['address'] ?? ''}'.trim();
    if (address.isEmpty) {
      throw StateError('transfer: address');
    }
    final double amountFixed = double.parse(amountUi.toStringAsFixed(9));
    final int atoms = (amountFixed * _arqCoinUnits).round();
    final int priority = (p['priority'] as num?)?.toInt() ?? 0;
    return <String, dynamic>{
      'destinations': <Map<String, dynamic>>[
        <String, dynamic>{'amount': atoms, 'address': address},
      ],
      'priority': priority,
      'ring_size': 16,
      'do_not_relay': true,
      'get_tx_metadata': true,
    };
  }

  void _pushTransferMetadataFromResult(
      Map<String, dynamic> r, Map<String, dynamic> p) {
    _pendingTxRelay
        .removeWhere((Map<String, dynamic> m) => m['kind'] == 'transfer_split');
    final Object? res = r['result'];
    if (res is! Map) {
      return;
    }
    final List<dynamic>? list = res['tx_metadata_list'] as List<dynamic>?;
    if (list == null) {
      return;
    }
    final String note = '${p['note'] ?? ''}';
    for (final Object? item in list) {
      String hex;
      if (item is String) {
        hex = item;
      } else if (item is Map && item['as_hex'] is String) {
        hex = item['as_hex'] as String;
      } else {
        hex = '$item';
      }
      if (hex.isEmpty) {
        continue;
      }
      _pendingTxRelay.add(<String, dynamic>{
        'tx_metadata': hex,
        'kind': 'transfer_split',
        'note': note,
        'service_node_key': null,
        'amount': null,
      });
    }
  }

  void _pushSweepMetadataFromResult(
      Map<String, dynamic> r, Map<String, dynamic> p) {
    if (p['do_not_relay'] != true) {
      return;
    }
    final Object? res = r['result'];
    if (res is! Map) {
      return;
    }
    final List<dynamic>? list = res['tx_metadata_list'] as List<dynamic>?;
    if (list == null) {
      return;
    }
    final List<dynamic>? txHashes = res['tx_hash_list'] as List<dynamic>?;
    final String? txh0 =
        txHashes != null && txHashes.isNotEmpty ? '${txHashes[0]}' : null;
    for (final Object? item in list) {
      String h = item is String ? item : '$item';
      if (h.isEmpty) {
        continue;
      }
      _pendingTxRelay.add(<String, dynamic>{
        'tx_metadata': h,
        'kind': 'sweepAll',
        'note': '',
        'tx_hash': txh0,
        'amount': null,
        'service_node_key': null,
      });
    }
  }

  void _pushStakeMetadataFromResult(
      Map<String, dynamic> r, Map<String, dynamic> p) {
    _pendingTxRelay
        .removeWhere((Map<String, dynamic> m) => m['kind'] == 'stake');
    final Object? res = r['result'];
    if (res is! Map) {
      return;
    }
    final Object? h = res['tx_metadata'];
    String hex = h is String ? h : '$h';
    if (hex.isEmpty) {
      return;
    }
    final double amountF = (p['amount'] as num?)?.toDouble() ?? 0;
    final int atoms = (amountF * _arqCoinUnits).round();
    final String? sk = (p['key'] ?? p['service_node_key']) as String?;
    _pendingTxRelay.add(<String, dynamic>{
      'tx_metadata': hex,
      'kind': 'stake',
      'note': '',
      'amount': atoms,
      'service_node_key': sk,
    });
  }

  Map<String, dynamic> _mapStakeRpcParams(Map<String, dynamic> p) {
    final Object? rawA = p['amount'];
    double amountUi;
    if (rawA is num) {
      amountUi = rawA.toDouble();
    } else if (rawA is String) {
      amountUi = double.tryParse(rawA) ?? double.nan;
    } else {
      amountUi = double.nan;
    }
    if (!amountUi.isFinite) {
      throw StateError('stake: amount');
    }
    final double amountFixed = double.parse(amountUi.toStringAsFixed(9));
    final int atoms = (amountFixed * _arqCoinUnits).round();
    final String serviceNodeKey =
        '${p['key'] ?? p['service_node_key'] ?? ''}'.trim();
    if (serviceNodeKey.isEmpty) {
      throw StateError('stake: key');
    }
    final String destination = '${p['destination'] ?? ''}'.trim();
    if (destination.isEmpty) {
      throw StateError('stake: destination');
    }
    return <String, dynamic>{
      'amount': atoms,
      'destination': destination,
      'service_node_key': serviceNodeKey,
      'do_not_relay': true,
      'get_tx_metadata': true,
    };
  }

  Future<void> _relayTransferSplit() async {
    final ArqmaWalletRpcSession? w = _walletRpc;
    if (w == null) {
      return;
    }
    String err = '';
    final List<Map<String, dynamic>> items = _pendingTxRelay
        .where((Map<String, dynamic> m) => m['kind'] == 'transfer_split')
        .toList();
    for (final Map<String, dynamic> t in items) {
      final String hex = '${t['tx_metadata'] ?? ''}';
      final Map<String, dynamic>? rr =
          await w.call('relay_tx', <String, dynamic>{'hex': hex});
      if (!walletJsonRpcNoError(rr)) {
        err = _walletRpcErrCapitalized(rr?['error']);
        break;
      }
      final Object? res = rr?['result'];
      if (res is Map) {
        final String? txh = res['tx_hash'] as String?;
        final String note = '${t['note'] ?? ''}';
        if (txh != null && txh.isNotEmpty && note.isNotEmpty) {
          await w.call(
            'set_tx_notes',
            <String, dynamic>{
              'txids': <String>[txh],
              'notes': <String>[note],
            },
          );
        }
      }
    }
    if (err.isNotEmpty) {
      _emit(<String, dynamic>{
        'event': 'set_tx_status',
        'data': <String, dynamic>{
          'code': -200,
          'message': err,
          'sending': false
        },
      });
    } else {
      _whFetchTxPending = true;
      _emit(<String, dynamic>{
        'event': 'set_tx_status',
        'data': <String, dynamic>{
          'code': 201,
          'message': 'Transaction successfully sent',
          'sending': false,
        },
      });
    }
    _pendingTxRelay
        .removeWhere((Map<String, dynamic> m) => m['kind'] == 'transfer_split');
  }

  Future<void> _relayStakeSplit(Map<String, dynamic> origin) async {
    final ArqmaWalletRpcSession? w = _walletRpc;
    if (w == null) {
      return;
    }
    final List<Map<String, dynamic>> items = _pendingTxRelay
        .where((Map<String, dynamic> m) => m['kind'] == 'stake')
        .toList();
    for (final Map<String, dynamic> t in items) {
      final String hex = '${t['tx_metadata'] ?? ''}';
      final Map<String, dynamic>? rr =
          await w.call('relay_tx', <String, dynamic>{'hex': hex});
      if (!walletJsonRpcNoError(rr)) {
        final String err = _walletRpcErrCapitalized(rr?['error']);
        _emit(<String, dynamic>{
          'event': 'set_tx_status',
          'data': <String, dynamic>{
            'code': -300,
            'message': err,
            'sending': false,
            'origin': origin
          },
        });
        _pendingTxRelay
            .removeWhere((Map<String, dynamic> m) => m['kind'] == 'stake');
        return;
      }
      final int? amt = t['amount'] as int?;
      final String? snk = t['service_node_key'] as String?;
      if (amt != null && snk != null && snk.isNotEmpty) {
        final double a = amt / _arqCoinUnits;
        _showNotification(
          'positive',
          'Staked ${a.toStringAsFixed(5)} ARQ to: $snk',
          3000,
        );
      }
      final Object? res = rr?['result'];
      if (res is Map && res['tx_hash'] is String) {
        final String txh = res['tx_hash'] as String;
        if (snk != null && snk.isNotEmpty) {
          await w.call(
            'set_tx_notes',
            <String, dynamic>{
              'txids': <String>[txh],
              'notes': <String>['Service Node: $snk'],
            },
          );
        }
      }
    }
    if (items.isNotEmpty) {
      _whFetchTxPending = true;
    }
    _pendingTxRelay
        .removeWhere((Map<String, dynamic> m) => m['kind'] == 'stake');
  }

  Future<void> _relaySweepAllSplit(Map<String, dynamic> origin) async {
    final ArqmaWalletRpcSession? w = _walletRpc;
    if (w == null) {
      return;
    }
    String err = '';
    final List<Map<String, dynamic>> items = _pendingTxRelay
        .where((Map<String, dynamic> m) => m['kind'] == 'sweepAll')
        .toList();
    for (final Map<String, dynamic> t in items) {
      final String hex = '${t['tx_metadata'] ?? ''}';
      final Map<String, dynamic>? rr =
          await w.call('relay_tx', <String, dynamic>{'hex': hex});
      if (!walletJsonRpcNoError(rr)) {
        err = _walletRpcErrCapitalized(rr?['error']);
        break;
      }
    }
    if (err.isNotEmpty) {
      _emit(<String, dynamic>{
        'event': 'set_tx_status',
        'data': <String, dynamic>{
          'code': -100,
          'message': err,
          'sending': false,
          'origin': origin,
        },
      });
    } else {
      _whFetchTxPending = true;
      _emit(<String, dynamic>{
        'event': 'set_tx_status',
        'data': <String, dynamic>{
          'code': 200,
          'message': 'SweepAll transaction successfully sent',
          'sending': false,
          'origin': origin,
        },
      });
    }
    _pendingTxRelay
        .removeWhere((Map<String, dynamic> m) => m['kind'] == 'sweepAll');
  }

  String _normalizeRestoreSeed(String seed) {
    return seed
        .split(RegExp(r'\s+'))
        .where((String s) => s.isNotEmpty)
        .join(' ');
  }

  String _configuredNetType() =>
      (_runtimeConfig?['app'] as Map?)?['net_type'] as String? ?? 'mainnet';

  /// `wallet_handler::emit_validate_address_from_rpc_result` — `nettype` vs app `net_type`.
  void _emitSetValidAddress({
    required String address,
    required bool rpcFieldValid,
    required String rpcNettype,
  }) {
    final String appNet = _configuredNetType();
    final bool netMatches = rpcNettype.isNotEmpty && appNet == rpcNettype;
    final bool isValid = rpcFieldValid && netMatches;
    _emit(<String, dynamic>{
      'event': 'set_valid_address',
      'data': <String, dynamic>{
        'address': address,
        'valid': isValid,
        'nettype': rpcNettype,
      },
    });
  }

  /// Wallet RPC parity for UI flows not yet wired to a native wallet process (same as [StubNativeBridge] subset).
  Future<dynamic> _walletStubBackendSend(String module, String method,
      [Object? data]) async {
    if (module != 'wallet') {
      return <String, dynamic>{};
    }
    if (method == 'has_password') {
      // `wallet_handler.rs` `has_password`
      if (_walletPasswordHashHex == null) {
        _emit(<String, dynamic>{'event': 'set_has_password', 'data': false});
        return <String, dynamic>{};
      }
      final bool prompt =
          (_runtimeConfig?['app'] as Map?)?['promptForPassword'] == true;
      if (!prompt) {
        _emit(<String, dynamic>{'event': 'set_has_password', 'data': true});
        return <String, dynamic>{};
      }
      final String salt = _walletRpc?.rpcPbkdf2SaltHex ?? '';
      if (salt.length != 64) {
        _emit(<String, dynamic>{'event': 'set_has_password', 'data': false});
        return <String, dynamic>{};
      }
      final String? emptyH = tryPbkdf2PasswordHex(password: '', saltHex: salt);
      if (emptyH == null) {
        _emit(<String, dynamic>{'event': 'set_has_password', 'data': false});
        return <String, dynamic>{};
      }
      final bool sameAsEmpty = _walletPasswordHashHex == emptyH;
      _emit(
          <String, dynamic>{'event': 'set_has_password', 'data': sameAsEmpty});
      return <String, dynamic>{};
    }
    if (method == 'validate_address') {
      final String addr = '${_coerceMap(data)['address'] ?? ''}';
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w != null && addr.isNotEmpty) {
        final Map<String, dynamic>? r = await w
            .call('validate_address', <String, dynamic>{'address': addr});
        if (!walletJsonRpcNoError(r) || r == null) {
          _emitSetValidAddress(
              address: addr, rpcFieldValid: false, rpcNettype: '');
          return <String, dynamic>{};
        }
        final Object? res = r['result'];
        if (res is! Map) {
          _emitSetValidAddress(
              address: addr, rpcFieldValid: false, rpcNettype: '');
          return <String, dynamic>{};
        }
        final Map<String, dynamic> rm = Map<String, dynamic>.from(res);
        final bool fieldValid = rm['valid'] == true || rm['integrated'] == true;
        final String rpcNet = '${rm['nettype'] ?? rm['net_type'] ?? ''}';
        _emitSetValidAddress(
            address: addr, rpcFieldValid: fieldValid, rpcNettype: rpcNet);
        return <String, dynamic>{};
      }
      _emitSetValidAddress(
        address: addr,
        rpcFieldValid: addr.isNotEmpty,
        rpcNettype: _configuredNetType(),
      );
      return <String, dynamic>{};
    }
    if (method == 'subscribe_for_signature_data' ||
        method == 'unsubscribe_for_signature_data') {
      return <String, dynamic>{};
    }
    if (method == 'remove_signature_data' || method == 'cancel_stake') {
      // Tauri `wallet_handler`: no-op (ZMQ not wired / empty match arm).
      return <String, dynamic>{};
    }
    if (method == 'get_coin_price') {
      unawaited(fetchCoinPriceAndConversion(_emit));
      return <String, dynamic>{};
    }
    if (method == 'begin_Stake_Acquisition') {
      _stakePoolsTimer?.cancel();
      Future<void> tick() async {
        await runDesktopStakePoolsTick(
          emit: _emit,
          configData: _runtimeConfig ?? <String, dynamic>{},
          walletCall: (String m, Map<String, dynamic> p) =>
              _walletRpc?.call(m, p) ??
              Future<Map<String, dynamic>?>.value(null),
        );
      }

      unawaited(tick());
      _stakePoolsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(tick());
      });
      return <String, dynamic>{};
    }
    if (method == 'end_Stake_Acquisition') {
      _stakePoolsTimer?.cancel();
      _stakePoolsTimer = null;
      return <String, dynamic>{};
    }
    if (method == 'close_wallet') {
      _pendingTxRelay.clear();
      _stopWalletHeartbeat();
      _openedWalletDisplayName = '';
      _walletPasswordHashHex = null;
      _walletFullRescanUi = false;
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w != null) {
        await w.closeWalletSession();
      }
      _emit(<String, dynamic>{
        'event': 'reset_wallet_error',
        'data': <String, dynamic>{}
      });
      _emit(<String, dynamic>{
        'event': 'set_wallet_info',
        'data': <String, dynamic>{
          'name': '',
          'address': '',
          'height': 0,
          'balance': 0,
          'unlocked_balance': 0,
          'scan_poll_ts': DateTime.now().millisecondsSinceEpoch,
        },
      });
      _emit(<String, dynamic>{
        'event': 'reset_wallet_status',
        'data': <String, dynamic>{'code': 1, 'message': null},
      });
      return <String, dynamic>{};
    }
    if (method == 'open_wallet') {
      return _openWalletDesktop(data);
    }
    if (method == 'save_wallet') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w != null) {
        await w.call('store', <String, dynamic>{});
      }
      return <String, dynamic>{};
    }
    if (method == 'transfer') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w == null) {
        _emit(<String, dynamic>{
          'event': 'set_tx_status',
          'data': <String, dynamic>{
            'code': -200,
            'message': 'Wallet RPC unavailable',
            'sending': false
          },
        });
        return <String, dynamic>{};
      }
      final Map<String, dynamic> p = _coerceMap(data);
      try {
        final Map<String, dynamic> params = _mapTransferSplitParams(p);
        final Map<String, dynamic>? r = await w.call('transfer_split', params);
        if (!walletJsonRpcNoError(r)) {
          _emit(<String, dynamic>{
            'event': 'set_tx_status',
            'data': <String, dynamic>{
              'code': -200,
              'message': _walletRpcErrCapitalized(r?['error']),
              'sending': false,
            },
          });
          return <String, dynamic>{};
        }
        if (r != null) {
          _pushTransferMetadataFromResult(r, p);
          final Object? res = r['result'];
          if (res is Map) {
            final List<dynamic>? feeList = res['fee_list'] as List<dynamic>?;
            int feeAtoms = 0;
            if (feeList != null && feeList.isNotEmpty) {
              final Object? v0 = feeList.first;
              if (v0 is num) {
                feeAtoms = v0.toInt();
              }
            }
            final String feeMsg = feeAtoms > 0
                ? 'Fee ${(feeAtoms / _arqCoinUnits).toStringAsFixed(9)}'
                : 'Fee';
            _emit(<String, dynamic>{
              'event': 'set_tx_status',
              'data': <String, dynamic>{
                'code': 200,
                'message': feeMsg,
                'sending': false,
                ..._transferSplitFeeDialogExtras(
                    Map<String, dynamic>.from(res)),
              },
            });
            if (p['address_book'] is Map &&
                (p['address_book'] as Map)['save'] == true) {
              final String addr = '${p['address'] ?? ''}'.trim();
              if (addr.isNotEmpty) {
                final Map<String, dynamic> ab = Map<String, dynamic>.from(
                    p['address_book'] as Map? ?? <String, dynamic>{});
                await backendSend(
                  'wallet',
                  'add_address_book',
                  <String, dynamic>{
                    'address': addr,
                    'payment_id': '${p['payment_id'] ?? ''}',
                    'name': '${ab['name'] ?? ''}',
                    'description': '${ab['description'] ?? ''}',
                    'starred': false,
                    'index': false,
                  },
                );
              }
            }
          } else {
            _emit(<String, dynamic>{
              'event': 'set_tx_status',
              'data': <String, dynamic>{
                'code': -200,
                'message': 'No result from transfer_split',
                'sending': false
              },
            });
          }
        }
      } catch (e) {
        _emit(<String, dynamic>{
          'event': 'set_tx_status',
          'data': <String, dynamic>{
            'code': -200,
            'message': '$e',
            'sending': false
          },
        });
      }
      return <String, dynamic>{};
    }
    if (method == 'relay_transfer') {
      await _relayTransferSplit();
      return <String, dynamic>{};
    }
    if (method == 'relay_stake') {
      await _relayStakeSplit(_coerceMap(data));
      return <String, dynamic>{};
    }
    if (method == 'relay_sweepAll') {
      await _relaySweepAllSplit(_coerceMap(data));
      return <String, dynamic>{};
    }
    if (method == 'cancelTransaction') {
      final String t = '${_coerceMap(data)['type'] ?? ''}';
      _pendingTxRelay.removeWhere((Map<String, dynamic> m) => m['kind'] == t);
      return <String, dynamic>{};
    }
    if (method == 'rescan_blockchain') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w != null) {
        final bool hard = _coerceMap(data)['hard'] == true;
        _emitRescanStartingUi(clearTransactions: hard);
        await Future<void>.delayed(const Duration(milliseconds: 48));
        await WidgetsBinding.instance.endOfFrame;
        try {
          await w.call(
            'rescan_blockchain',
            <String, dynamic>{if (hard) 'hard': true},
          );
        } catch (e, st) {
          debugPrint('[DesktopNative] rescan_blockchain: $e\n$st');
          _walletFullRescanUi = false;
          _emit(<String, dynamic>{
            'event': 'set_wallet_info',
            'data': <String, dynamic>{
              'full_rescan_ui': false,
              'scan_poll_ts': DateTime.now().millisecondsSinceEpoch,
            },
          });
        }
        // Native rescan runs on a background thread; still push one RPC snapshot so the
        // footer height can drop immediately (allow_lower_height); xfer keeps txs flowing.
        unawaited(_refreshWalletUiAfterRescan(clearTransactions: hard));
      }
      return <String, dynamic>{};
    }
    if (method == 'rescan_spent') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w != null) {
        try {
          await w.call('rescan_spent', <String, dynamic>{});
        } catch (e, st) {
          debugPrint('[DesktopNative] rescan_spent: $e\n$st');
        }
        unawaited(_refreshWalletUiAfterRescan(clearTransactions: false));
      }
      return <String, dynamic>{};
    }
    if (method == 'sweepAll') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w == null) {
        return <String, dynamic>{};
      }
      final Map<String, dynamic> p = _coerceMap(data);
      final Map<String, dynamic>? addrR =
          await w.call('get_address', <String, dynamic>{'account_index': 0});
      if (!walletJsonRpcNoError(addrR)) {
        _emit(<String, dynamic>{
          'event': 'set_tx_status',
          'data': <String, dynamic>{
            'code': -100,
            'message': _walletRpcErrCapitalized(addrR?['error']),
            'sending': false,
            'origin': p['origin'],
          },
        });
        return <String, dynamic>{};
      }
      final String myAddress =
          '${(addrR!['result'] as Map?)?['address'] ?? ''}';
      final bool doNot = p['do_not_relay'] == true;
      final Map<String, dynamic>? r = await w.call(
        'sweep_all',
        <String, dynamic>{
          'address': myAddress,
          'account_index': 0,
          'priority': 0,
          'ring_size': 16,
          'do_not_relay': doNot,
          'get_tx_metadata': true,
          'get_tx_hex': true,
        },
      );
      if (!walletJsonRpcNoError(r)) {
        _emit(<String, dynamic>{
          'event': 'set_tx_status',
          'data': <String, dynamic>{
            'code': -100,
            'message': _walletRpcErrCapitalized(r?['error']),
            'sending': false,
            'origin': p['origin'],
          },
        });
        return <String, dynamic>{};
      }
      if (r != null) {
        _pushSweepMetadataFromResult(r, p);
        final Object? res = r['result'];
        if (res is Map) {
          final List<dynamic>? feeList = res['fee_list'] as List<dynamic>?;
          int sumFees = 0;
          if (feeList != null) {
            for (final Object? v in feeList) {
              if (v is num) {
                sumFees += v.toInt();
              }
            }
          }
          final double feeUi = sumFees / _arqCoinUnits;
          final Map<String, dynamic> status = <String, dynamic>{
            'sending': false,
            'origin': p['origin'],
            'code': doNot ? 99 : 100,
            'message': doNot
                ? feeUi.toStringAsFixed(9)
                : 'sweep_all_rpc_success_message',
          };
          _emit(<String, dynamic>{'event': 'set_tx_status', 'data': status});
        }
      }
      return <String, dynamic>{};
    }
    if (method == 'add_address_book') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w == null) {
        return <String, dynamic>{};
      }
      final Map<String, dynamic> p = _coerceMap(data);
      final Object? idx = p['index'];
      if (idx is num) {
        await w.call(
            'delete_address_book', <String, dynamic>{'index': idx.toInt()});
      }
      final bool starred = p['starred'] == true;
      final String name = '${p['name'] ?? ''}';
      final String description = '${p['description'] ?? ''}';
      final List<String> parts = <String>[];
      if (starred) {
        parts.add('starred');
      }
      parts.add(name);
      parts.add(description);
      final String desc = parts.join('::');
      final Map<String, dynamic> rpc = <String, dynamic>{
        'address': '${p['address'] ?? ''}',
        'description': desc,
      };
      final String pid = '${p['payment_id'] ?? ''}';
      if (pid.isNotEmpty) {
        rpc['payment_id'] = pid;
      }
      final Map<String, dynamic>? r = await w.call('add_address_book', rpc);
      if (!walletJsonRpcNoError(r)) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{'status': r?['error']}
        });
        _showNotification(
            'negative', 'Wallet RPC Error, Address Rejected', 3000);
        return <String, dynamic>{};
      }
      await w.call('store', <String, dynamic>{});
      _showNotification(
          'positive', 'Address Book updated with ${p['address'] ?? ''}', 3000);
      return <String, dynamic>{};
    }
    if (method == 'delete_address_book') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w == null) {
        return <String, dynamic>{};
      }
      final Object? idx = _coerceMap(data)['index'];
      if (idx is! num) {
        return <String, dynamic>{};
      }
      final Map<String, dynamic>? r = await w
          .call('delete_address_book', <String, dynamic>{'index': idx.toInt()});
      if (walletJsonRpcNoError(r)) {
        await w.call('store', <String, dynamic>{});
      }
      return <String, dynamic>{};
    }
    if (method == 'stake') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w == null) {
        return <String, dynamic>{};
      }
      final Map<String, dynamic> p = _coerceMap(data);
      final String pw = '${p['password'] ?? ''}';
      if (!_walletPasswordOkForTx(pw)) {
        _showNotification('negative', 'Password Error', 3000);
        return <String, dynamic>{};
      }
      try {
        final Map<String, dynamic> params = _mapStakeRpcParams(p);
        final Map<String, dynamic>? r = await w.call('stake', params);
        if (!walletJsonRpcNoError(r)) {
          _emit(<String, dynamic>{
            'event': 'set_tx_status',
            'data': <String, dynamic>{
              'code': -300,
              'message': _walletRpcErrCapitalized(r?['error']),
              'sending': false,
            },
          });
          return <String, dynamic>{};
        }
        if (r != null && r['result'] != null) {
          final Object? res = r['result'];
          int feeAtoms = 0;
          if (res is Map && res['fee'] != null) {
            feeAtoms = (res['fee'] as num?)?.toInt() ?? 0;
          }
          final String feeMsg = feeAtoms > 0
              ? 'Fee ${(feeAtoms / _arqCoinUnits).toStringAsFixed(9)}'
              : 'Fee';
          _emit(<String, dynamic>{
            'event': 'set_tx_status',
            'data': <String, dynamic>{
              'code': 300,
              'message': feeMsg,
              'sending': false
            },
          });
          _pushStakeMetadataFromResult(r, p);
        }
      } catch (e) {
        _emit(<String, dynamic>{
          'event': 'set_tx_status',
          'data': <String, dynamic>{
            'code': -300,
            'message': '$e',
            'sending': false
          },
        });
      }
      return <String, dynamic>{};
    }
    if (method == 'unlock_stake') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w == null) {
        return <String, dynamic>{};
      }
      final Map<String, dynamic> p = _coerceMap(data);
      _emit(<String, dynamic>{
        'event': 'set_snode_status_unlock',
        'data': <String, dynamic>{'code': 0, 'message': '', 'sending': false},
      });
      final String snk = '${p['service_node_key'] ?? ''}'.trim();
      if (snk.isEmpty) {
        return <String, dynamic>{};
      }
      final String pw = '${p['password'] ?? ''}';
      if (!_walletPasswordMatches(pw)) {
        _emit(<String, dynamic>{
          'event': 'set_snode_status_unlock',
          'data': <String, dynamic>{
            'code': -400,
            'message': 'invalidPassword',
            'sending': false
          },
        });
        return <String, dynamic>{};
      }
      final bool confirmed = p['confirmed'] == true;
      final Map<String, dynamic>? r = await w.call(
        confirmed ? 'request_stake_unlock' : 'can_request_stake_unlock',
        <String, dynamic>{'service_node_key': snk},
      );
      if (!walletJsonRpcNoError(r)) {
        final String msg = _walletRpcErrCapitalized(r?['error']);
        _emit(<String, dynamic>{
          'event': 'set_snode_status_unlock',
          'data': <String, dynamic>{
            'code': -400,
            'message': msg,
            'sending': false
          },
        });
        return <String, dynamic>{};
      }
      if (confirmed && r?['result'] is Map) {
        final Map<String, dynamic> res =
            Map<String, dynamic>.from(r!['result'] as Map);
        final String msg = '${res['msg'] ?? res['message'] ?? ''}';
        final bool unlocked = res['unlocked'] == true;
        _emit(<String, dynamic>{
          'event': 'set_snode_status_unlock',
          'data': <String, dynamic>{
            'code': unlocked ? 400 : -400,
            'message': msg,
            'sending': false
          },
        });
      }
      return <String, dynamic>{};
    }
    if (method == 'save_tx_notes') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w != null) {
        final Map<String, dynamic> p = _coerceMap(data);
        await w.call(
          'set_tx_notes',
          <String, dynamic>{
            'txids': <String>['${p['txid'] ?? ''}'],
            'notes': <String>['${p['note'] ?? ''}'],
          },
        );
      }
      return <String, dynamic>{};
    }
    if (method == 'get_private_keys') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w == null) {
        return <String, dynamic>{};
      }
      final Map<String, dynamic> p = _coerceMap(data);
      final String pw = '${p['password'] ?? ''}';
      if (!_walletPasswordOkForTx(pw)) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_secret',
          'data': <String, dynamic>{
            'mnemonic': 'Invalid password',
            'spend_key': -1,
            'view_key': -1,
          },
        });
        return <String, dynamic>{};
      }
      final Map<String, dynamic> secret = <String, dynamic>{
        'mnemonic': '',
        'spend_key': '',
        'view_key': ''
      };
      for (final String kt in <String>['mnemonic', 'spend_key', 'view_key']) {
        final Map<String, dynamic>? q =
            await w.call('query_key', <String, dynamic>{'key_type': kt});
        if (walletJsonRpcNoError(q) && q?['result'] is Map) {
          secret[kt] = (q!['result'] as Map)['key'];
        }
      }
      _emit(<String, dynamic>{'event': 'set_wallet_secret', 'data': secret});
      return <String, dynamic>{};
    }
    if (method == 'change_wallet_password') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w != null) {
        final Map<String, dynamic> p = _coerceMap(data);
        final String oldPw = '${p['old_password'] ?? ''}';
        if (!_walletPasswordOkForTx(oldPw)) {
          _showNotification('negative', 'Invalid old password', 3000);
          return <String, dynamic>{};
        }
        final Map<String, dynamic>? r = await w.call(
          'change_wallet_password',
          <String, dynamic>{
            'old_password': oldPw,
            'new_password': '${p['new_password'] ?? ''}',
          },
        );
        if (walletJsonRpcNoError(r)) {
          _refreshSessionPasswordDigest('${p['new_password'] ?? ''}');
          _showNotification('positive', 'Password updated', 3000);
        } else {
          _showNotification(
              'negative', _walletRpcErrCapitalized(r?['error']), 4000);
        }
      }
      return <String, dynamic>{};
    }
    if (method == 'register_service_node') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w == null) {
        return <String, dynamic>{};
      }
      final Map<String, dynamic> p = _coerceMap(data);
      final String pw = '${p['password'] ?? ''}';
      if (!_walletPasswordOkForTx(pw)) {
        _emit(<String, dynamic>{
          'event': 'set_snode_status',
          'data': <String, dynamic>{
            'registration': <String, dynamic>{
              'code': -1,
              'message': '',
              'sending': false
            },
          },
        });
        return <String, dynamic>{};
      }
      final String s = '${p['string'] ?? p['register_service_node_str'] ?? ''}';
      final Map<String, dynamic>? r = await w.call('register_service_node',
          <String, dynamic>{'register_service_node_str': s});
      if (!walletJsonRpcNoError(r)) {
        _emit(<String, dynamic>{
          'event': 'set_snode_status',
          'data': <String, dynamic>{
            'registration': <String, dynamic>{
              'code': -1,
              'message': _walletRpcErrCapitalized(r?['error']),
              'sending': false
            },
          },
        });
        return <String, dynamic>{};
      }
      _emit(<String, dynamic>{
        'event': 'set_snode_status',
        'data': <String, dynamic>{
          'registration': <String, dynamic>{'code': 0, 'sending': false}
        },
      });
      return <String, dynamic>{};
    }
    if (method == 'export_key_images') {
      await _walletExportKeyImages(_coerceMap(data));
      return <String, dynamic>{};
    }
    if (method == 'import_key_images') {
      await _walletImportKeyImages(_coerceMap(data));
      return <String, dynamic>{};
    }
    if (method == 'delete_wallet') {
      await _walletDeleteOpen(_coerceMap(data));
      return <String, dynamic>{};
    }
    if (method == 'export_transactions') {
      final Map<String, dynamic> p = _coerceMap(data);
      final String password = '${p['password'] ?? ''}';
      final String path = '${p['path'] ?? ''}'.trim();
      if (!_walletPasswordOkForTx(password)) {
        _emit(<String, dynamic>{
          'event': 'set_tx_status',
          'data': <String, dynamic>{
            'code': -99,
            'message': 'backend.Invalid_password',
            'origin': 'wallet_settings',
          },
        });
        return <String, dynamic>{};
      }
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w == null || path.isEmpty) {
        _emit(<String, dynamic>{
          'event': 'set_tx_status',
          'data': <String, dynamic>{
            'code': -99,
            'message': 'backend.transaction_export_failed',
            'origin': 'wallet_settings',
          },
        });
        return <String, dynamic>{};
      }
      try {
        await exportWalletTransactionsToCsv(
          walletCall: w.call,
          exportDir: path,
        );
        _emit(<String, dynamic>{
          'event': 'set_tx_status',
          'data': <String, dynamic>{
            'code': 100,
            'message': 'backend.transaction_export_complete',
            'origin': 'wallet_settings',
          },
        });
      } catch (e) {
        debugPrint('[DesktopNative] export_transactions: $e');
        _emit(<String, dynamic>{
          'event': 'set_tx_status',
          'data': <String, dynamic>{
            'code': -99,
            'message': 'backend.transaction_export_failed',
            'origin': 'wallet_settings',
          },
        });
      }
      return <String, dynamic>{};
    }
    if (method == 'copy_old_gui_wallets') {
      final Map<String, dynamic>? cfg = _runtimeConfig;
      if (cfg == null) {
        return <String, dynamic>{};
      }
      final List<dynamic> list = (_coerceMap(data)['wallets'] is List)
          ? List<dynamic>.from(_coerceMap(data)['wallets'] as List)
          : <dynamic>[];
      final List<String> failed = runCopyOldGuiWallets(cfg, list);
      _emit(<String, dynamic>{
        'event': 'set_old_gui_import_status',
        'data': <String, dynamic>{'code': 0, 'failed_wallets': failed},
      });
      final String? wdir = walletFilesDir(cfg);
      if (wdir != null) {
        _emit(<String, dynamic>{
          'event': 'wallet_list',
          'data': listWalletFiles(wdir)
        });
      }
      return <String, dynamic>{};
    }
    if (method == 'create_wallet' ||
        method == 'restore_wallet' ||
        method == 'import_wallet' ||
        method == 'restore_view_wallet') {
      return _walletCreateRestoreImport(method, data);
    }
    debugPrint('[DesktopNative] unhandled wallet::$method');
    return <String, dynamic>{};
  }

  Future<void> _walletExportKeyImages(Map<String, dynamic> p) async {
    final ArqmaWalletRpcSession? w = _walletRpc;
    final Map<String, dynamic>? cfg = _runtimeConfig;
    if (w == null || cfg == null) {
      return;
    }
    final String pw = '${p['password'] ?? ''}';
    if (!_walletPasswordOkForTx(pw)) {
      _showNotification('negative', 'Invalid password', 3000);
      return;
    }
    final bool all = p['all'] == true;
    final Map<String, dynamic>? data =
        await w.call('export_key_images', <String, dynamic>{'all': all});
    if (!walletJsonRpcNoError(data) || data?['result'] == null) {
      _showNotification('negative', 'Error exporting key images', 3000);
      return;
    }
    final Object? ski = (data!['result'] as Map)['signed_key_images'];
    if (ski == null) {
      _showNotification('warning', 'No key images found to export', 3000);
      return;
    }
    final String body = jsonEncode(ski);
    final String? wdata = (cfg['app'] as Map?)?['wallet_data_dir'] as String?;
    final String name = _openedWalletDisplayName;
    final String basePath = p['path'] as String? ?? '';
    final File out = basePath.isNotEmpty
        ? File('$basePath${Platform.pathSeparator}key_image_export')
        : File(
            '${wdata ?? ''}${Platform.pathSeparator}images${Platform.pathSeparator}$name${Platform.pathSeparator}key_image_export',
          );
    await out.parent.create(recursive: true);
    await out.writeAsString(body);
    _showNotification('positive', 'Key images exported to ${out.path}', 3000);
  }

  Future<void> _walletImportKeyImages(Map<String, dynamic> p) async {
    final ArqmaWalletRpcSession? w = _walletRpc;
    final Map<String, dynamic>? cfg = _runtimeConfig;
    if (w == null || cfg == null) {
      return;
    }
    final String pw = '${p['password'] ?? ''}';
    if (!_walletPasswordOkForTx(pw)) {
      _showNotification('negative', 'Invalid password', 3000);
      return;
    }
    final String? wdata = (cfg['app'] as Map?)?['wallet_data_dir'] as String?;
    final String name = _openedWalletDisplayName;
    final String basePath = p['path'] as String? ?? '';
    final File file = basePath.isNotEmpty
        ? File('$basePath${Platform.pathSeparator}key_image_export')
        : File(
            '${wdata ?? ''}${Platform.pathSeparator}images${Platform.pathSeparator}$name${Platform.pathSeparator}key_image_export',
          );
    if (!file.existsSync()) {
      _showNotification('negative', 'Error parsing key images as JSON', 3000);
      return;
    }
    final Object? signed = jsonDecode(await file.readAsString());
    final Map<String, dynamic>? data = await w.call(
        'import_key_images', <String, dynamic>{'signed_key_images': signed});
    if (!walletJsonRpcNoError(data) || data?['result'] == null) {
      _showNotification('negative',
          'Error importing key images. change to local daemon', 3000);
      return;
    }
    _showNotification('positive', 'Key images imported', 3000);
  }

  Future<void> _walletDeleteOpen(Map<String, dynamic> p) async {
    final ArqmaWalletRpcSession? w = _walletRpc;
    final Map<String, dynamic>? cfg = _runtimeConfig;
    if (w == null || cfg == null) {
      return;
    }
    final String pw = '${p['password'] ?? ''}';
    if (!_walletPasswordOkForTx(pw)) {
      _showNotification('negative', 'Invalid password', 3000);
      return;
    }
    final String walletName = _openedWalletDisplayName;
    if (walletName.isEmpty) {
      return;
    }
    _emit(<String, dynamic>{
      'event': 'show_loading',
      'data': <String, dynamic>{'message': 'Deleting wallet'}
    });
    _stopWalletHeartbeat();
    await w.call('store', <String, dynamic>{});
    _openedWalletDisplayName = '';
    _walletPasswordHashHex = null;
    _pendingTxRelay.clear();
    await _walletRpc?.shutdown();
    _walletRpc = null;
    final String? wdir = walletFilesDir(cfg);
    if (wdir != null) {
      try {
        File('$wdir${Platform.pathSeparator}$walletName').deleteSync();
      } catch (_) {}
      try {
        File('$wdir${Platform.pathSeparator}$walletName.keys').deleteSync();
      } catch (_) {}
      try {
        File('$wdir${Platform.pathSeparator}$walletName.address.txt')
            .deleteSync();
      } catch (_) {}
      _emit(<String, dynamic>{
        'event': 'wallet_list',
        'data': listWalletFiles(wdir)
      });
    }
    _emit(<String, dynamic>{
      'event': 'hide_loading',
      'data': <String, dynamic>{}
    });
    _emit(<String, dynamic>{
      'event': 'return_to_wallet_select',
      'data': <String, dynamic>{}
    });
    if (Platform.environment['ARQMA_FLUTTER_NO_WALLET_RPC'] != '1') {
      _walletRpc = await ArqmaWalletRpcSession.tryStart(cfg);
      _emitWalletBackendState();
    }
  }

  Future<dynamic> _walletCreateRestoreImport(
      String method, Object? data) async {
    final ArqmaWalletRpcSession? w = _walletRpc;
    final Map<String, dynamic>? cfg = _runtimeConfig;
    if (w == null || cfg == null) {
      _showNotification(
        'negative',
        _walletFfiCreateRestoreHint(),
        8000,
      );
      return <String, dynamic>{};
    }
    final Map<String, dynamic> p = _coerceMap(data);
    if (method == 'create_wallet') {
      final String name = '${p['name'] ?? ''}';
      final String password = '${p['password'] ?? ''}';
      final String language = '${p['language'] ?? 'English'}';
      final Map<String, dynamic>? r = await w.call(
        'create_wallet',
        <String, dynamic>{
          'filename': name,
          'password': password,
          'language': language
        },
      );
      if (!walletJsonRpcNoError(r)) {
        _emit(<String, dynamic>{
          'event': 'reset_wallet_status',
          'data': <String, dynamic>{
            'code': -1,
            'message': '${r?['error'] ?? 'create_wallet failed'}'
          },
        });
        return <String, dynamic>{};
      }
      _refreshSessionPasswordDigest(password);
      await _emitWalletOpenedUi(name);
      return <String, dynamic>{};
    }
    if (method == 'restore_wallet') {
      _emit(<String, dynamic>{
        'event': 'reset_wallet_error',
        'data': <String, dynamic>{}
      });
      final ({String host, int port})? ep = daemonRpcHostPort(cfg);
      if (ep == null) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{
            'status': <String, dynamic>{
              'code': -1,
              'message': 'restore: daemon RPC missing'
            }
          },
        });
        return <String, dynamic>{};
      }
      final int? rh =
          await resolveRestoreRefreshHeight(host: ep.host, port: ep.port, p: p);
      if (rh == null) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{
            'status': <String, dynamic>{
              'code': -1,
              'message': 'restore: refresh_start_height'
            }
          },
        });
        return <String, dynamic>{};
      }
      _stopWalletHeartbeat();
      await w.closeWalletSession();
      final String seed = _normalizeRestoreSeed('${p['seed'] ?? ''}');
      final String name = '${p['name'] ?? ''}';
      final String password = '${p['password'] ?? ''}';
      final Map<String, dynamic>? r = await w.call(
        'restore_deterministic_wallet',
        <String, dynamic>{
          'filename': name,
          'password': password,
          'seed': seed,
          'restore_height': rh,
        },
      );
      if (!walletJsonRpcNoError(r)) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{'status': r?['error']}
        });
        return <String, dynamic>{};
      }
      _refreshSessionPasswordDigest(password);
      await _emitWalletOpenedUi(name);
      return <String, dynamic>{};
    }
    if (method == 'restore_view_wallet') {
      _emit(<String, dynamic>{
        'event': 'reset_wallet_error',
        'data': <String, dynamic>{}
      });
      final ({String host, int port})? ep = daemonRpcHostPort(cfg);
      if (ep == null) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{
            'status': <String, dynamic>{
              'code': -1,
              'message': 'restore: daemon RPC missing'
            }
          },
        });
        return <String, dynamic>{};
      }
      int? refreshH =
          await resolveRestoreRefreshHeight(host: ep.host, port: ep.port, p: p);
      if (refreshH == null) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{
            'status': <String, dynamic>{
              'code': -1,
              'message': 'restore: refresh_start_height'
            }
          },
        });
        return <String, dynamic>{};
      }
      if (p['refresh_type'] == 'height') {
        final Object? raw = p['refresh_start_height'];
        final bool isInt = raw is int || raw is num;
        if (!isInt) {
          refreshH = 0;
        }
      }
      _stopWalletHeartbeat();
      await w.closeWalletSession();
      final String name = '${p['name'] ?? ''}';
      final String password = '${p['password'] ?? ''}';
      final Map<String, dynamic>? r = await w.call(
        'generate_from_keys',
        <String, dynamic>{
          'filename': name,
          'password': password,
          'address': '${p['address'] ?? ''}',
          'viewkey': '${p['viewkey'] ?? ''}',
          'refresh_start_height': refreshH,
        },
      );
      if (!walletJsonRpcNoError(r)) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{'status': r?['error']}
        });
        return <String, dynamic>{};
      }
      _refreshSessionPasswordDigest(password);
      await _emitWalletOpenedUi(name);
      return <String, dynamic>{};
    }
    if (method == 'import_wallet') {
      _emit(<String, dynamic>{
        'event': 'reset_wallet_error',
        'data': <String, dynamic>{}
      });
      final String filename = '${p['name'] ?? p['filename'] ?? ''}'.trim();
      final String? importPathRaw = p['path'] as String?;
      final String password = '${p['password'] ?? ''}';
      if (filename.isEmpty || importPathRaw == null || importPathRaw.isEmpty) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{
            'status': <String, dynamic>{
              'code': -1,
              'message': 'import_wallet: name/path'
            }
          },
        });
        return <String, dynamic>{};
      }
      String importBase = importPathRaw.trim();
      if (importBase.endsWith('.keys')) {
        importBase =
            importBase.substring(0, importBase.length - '.keys'.length);
      } else if (importBase.endsWith('.address.txt')) {
        importBase =
            importBase.substring(0, importBase.length - '.address.txt'.length);
      }
      final File importSrc = File(importBase);
      if (!importSrc.existsSync()) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{
            'status': <String, dynamic>{
              'code': -1,
              'message': 'Invalid wallet path'
            }
          },
        });
        return <String, dynamic>{};
      }
      final String? wdir = walletFilesDir(cfg);
      if (wdir == null) {
        return <String, dynamic>{};
      }
      final File destination = File('$wdir${Platform.pathSeparator}$filename');
      final File destKeys =
          File('$wdir${Platform.pathSeparator}$filename.keys');
      if (destination.existsSync() || destKeys.existsSync()) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{
            'status': <String, dynamic>{
              'code': -1,
              'message': 'Wallet with name already exists'
            }
          },
        });
        return <String, dynamic>{};
      }
      try {
        importSrc.copySync(destination.path);
        final File keysSrc = File('$importBase.keys');
        if (keysSrc.existsSync()) {
          keysSrc.copySync(destKeys.path);
        }
      } catch (_) {
        try {
          if (destination.existsSync()) {
            destination.deleteSync();
          }
        } catch (_) {}
        try {
          if (destKeys.existsSync()) {
            destKeys.deleteSync();
          }
        } catch (_) {}
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{
            'status': <String, dynamic>{
              'code': -1,
              'message': 'Failed to copy wallet'
            }
          },
        });
        return <String, dynamic>{};
      }
      final Map<String, dynamic>? openR = await w.call(
        'open_wallet',
        <String, dynamic>{'filename': filename, 'password': password},
      );
      if (!walletJsonRpcNoError(openR)) {
        try {
          destination.deleteSync();
        } catch (_) {}
        try {
          destKeys.deleteSync();
        } catch (_) {}
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{'status': openR?['error']}
        });
        return <String, dynamic>{};
      }
      _refreshSessionPasswordDigest(password);
      await _emitWalletOpenedUi(filename);
      return <String, dynamic>{};
    }
    return <String, dynamic>{};
  }
}
