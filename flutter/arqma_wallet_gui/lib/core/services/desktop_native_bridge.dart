import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../desktop/arqma_daemon_launcher.dart';
import '../desktop/arqma_desktop_defaults.dart';
import '../desktop/arqma_paths.dart';
import '../desktop/daemon_heartbeat_extras.dart';
import '../desktop/desktop_export_transactions.dart';
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

/// Desktop (macOS/Linux/Windows): load `~/.arqma/gui/config.json`, scan wallet dir like Tauri,
/// start local `arqmad` when daemon type is not `remote`, poll `get_info` for footer sync state.
final class DesktopNativeBridge implements NativeBridge {
  DesktopNativeBridge();

  final StreamController<Map<String, dynamic>> _controller = StreamController<Map<String, dynamic>>.broadcast();
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

  void _emit(Map<String, dynamic> msg) {
    if (!_controller.isClosed) {
      _controller.add(msg);
    }
  }

  void _showNotification(String kind, String message, [int timeoutMs = 3000]) {
    _emit(<String, dynamic>{
      'event': 'show_notification',
      'data': <String, dynamic>{'type': kind, 'message': message, 'timeout': timeoutMs},
    });
  }

  Future<void> _ensureStartupDone() async {
    _startupFuture ??= _runCoreStartup();
    await _startupFuture;
  }

  /// Keep `app.data_dir` / `app.wallet_data_dir` absolute (expand `~`) like a shell/Tauri runtime.
  void _setRuntimeConfig(Map<String, dynamic> raw) {
    _runtimeConfig = normalizeConfigStoragePaths(Map<String, dynamic>.from(raw));
  }

  @override
  Stream<Map<String, dynamic>> get backendReceive => _controller.stream;

  @override
  Future<void> start() async {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (!_controller.isClosed) {
          _controller.add(<String, dynamic>{'event': 'initialize', 'data': <String, dynamic>{}});
        }
      }),
    );
  }

  @override
  Future<dynamic> invoke(String cmd, [Map<String, dynamic>? args]) async {
    if (cmd == 'app_log_info' || cmd == 'app_log_error') {
      debugPrint('[$cmd] ${args ?? {}}');
      return null;
    }
    if (cmd == 'app_version_str') {
      return '5.0.3+flutter-desktop';
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
      final Map<String, dynamic>? r = await DaemonJsonRpc.getInfo(ep.host, ep.port);
      final Map<String, dynamic>? info = DaemonJsonRpc.result(r);
      return '${info?['version'] ?? 'unknown'}';
    }
    if (cmd == 'app_is_dev') {
      return kDebugMode;
    }
    if (cmd == 'confirm_close') {
      _stakePoolsTimer?.cancel();
      _stakePoolsTimer = null;
      _heartbeat?.cancel();
      _heartbeat = null;
      _heartbeatSlow?.cancel();
      _heartbeatSlow = null;
      _walletPasswordHashHex = null;
      _openedWalletDisplayName = '';
      try {
        await _walletRpc?.shutdown();
      } catch (_) {}
      _walletRpc = null;
      try {
        _daemonProcess?.kill();
      } catch (_) {}
      _daemonProcess = null;
      return null;
    }
    return null;
  }

  @override
  Future<dynamic> backendSend(String module, String method, [Object? data]) async {
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
      final Map<String, dynamic>? c = _runtimeConfig;
      if (c != null) {
        final String? wdir = walletFilesDir(c);
        if (wdir != null) {
          _emit(<String, dynamic>{'event': 'wallet_list', 'data': listWalletFiles(wdir)});
        }
      }
      return <String, dynamic>{};
    }
    return _walletStubBackendSend(module, method, data);
  }

  Future<void> _restartAfterConfigInit() async {
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

  Future<void> _maybePushMainnetRemote(ArqmaPaths paths, Map<String, dynamic> params) async {
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
    _emit(<String, dynamic>{'event': 'set_app_data', 'data': <String, dynamic>{'remotes': arr}});
  }

  Map<String, dynamic> _normalizePoolVarDiff(Map<String, dynamic> pool) {
    final Map<String, dynamic> vd =
        Map<String, dynamic>.from(pool['varDiff'] as Map? ?? <String, dynamic>{});
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

  Future<void> _coreSaveImage(String method, Map<String, dynamic> params) async {
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
        _showNotification('positive', '${params['type'] ?? 'File'} saved to $path', 3000);
      }
      return;
    }
    final String? img = params['img'] as String?;
    if (img == null || img.isEmpty) {
      return;
    }
    final String b64 = img.replaceFirst(RegExp(r'^data:image/png;base64,?,?'), '').trim();
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
      _showNotification('positive', '${params['type'] ?? 'File'} saved to $path', 3000);
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
    final ({String host, int port})? ep = cfg == null ? null : daemonRpcHostPort(cfg);
    if (ep == null) {
      _showNotification('negative', 'Error banning peer', 3000);
      return;
    }
    final Map<String, dynamic>? r = await DaemonJsonRpc.post(
      ep.host,
      ep.port,
      'set_bans',
      <String, dynamic>{
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
        _emit(<String, dynamic>{'event': 'set_app_data', 'data': <String, dynamic>{'remotes': data}});
        return true;
      case 'change_ethereum':
        final Map<String, dynamic> eth =
            deepMergeMaps(cfg0['ethereum'] ?? <String, dynamic>{}, params) as Map<String, dynamic>;
        _setRuntimeConfig(deepMergeMaps(cfg0, <String, dynamic>{'ethereum': eth}) as Map<String, dynamic>);
        _emit(<String, dynamic>{'event': 'set_ethereum_data', 'data': eth});
        return true;
      case 'change_scan':
        _setRuntimeConfig(
          deepMergeMaps(cfg0, <String, dynamic>{'app': <String, dynamic>{'scan': params}}) as Map<String, dynamic>,
        );
        _emit(<String, dynamic>{'event': 'set_app_data', 'data': <String, dynamic>{'scan': params}});
        return true;
      case 'set_daysOfTransactions':
        _setRuntimeConfig(
          deepMergeMaps(
            cfg0,
            <String, dynamic>{'app': <String, dynamic>{'daysOfTransactions': params['daysOfTransactions'] ?? 1}},
          ) as Map<String, dynamic>,
        );
        return true;
      case 'set_inactivityTimeout':
        _setRuntimeConfig(
          deepMergeMaps(
            cfg0,
            <String, dynamic>{'app': <String, dynamic>{'inactivityTimeout': params['inactivityTimeout'] ?? 5}},
          ) as Map<String, dynamic>,
        );
        return true;
      case 'quick_save_config':
        final Map<String, dynamic> ethIn = Map<String, dynamic>.from(cfg0['ethereum'] as Map? ?? <String, dynamic>{});
        final Map<String, dynamic> mergedEth = deepMergeMaps(ethIn, params) as Map<String, dynamic>;
        _setRuntimeConfig(deepMergeMaps(cfg0, <String, dynamic>{'ethereum': mergedEth}) as Map<String, dynamic>);
        await File(paths.configPath).writeAsString(const JsonEncoder.withIndent('  ').convert(_runtimeConfig));
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{'config': _runtimeConfig, 'pending_config': _runtimeConfig},
        });
        return true;
      case 'save_config':
        await _maybePushMainnetRemote(paths, params);
        final String before = jsonEncode(cfg0);
        _setRuntimeConfig(deepMergeMaps(cfg0, params) as Map<String, dynamic>);
        await File(paths.configPath).writeAsString(const JsonEncoder.withIndent('  ').convert(_runtimeConfig));
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{'config': _runtimeConfig, 'pending_config': _runtimeConfig},
        });
        if (jsonEncode(_runtimeConfig) != before) {
          _emit(<String, dynamic>{'event': 'settings_changed_reboot', 'data': <String, dynamic>{}});
        }
        return true;
      case 'save_config_init':
        await _maybePushMainnetRemote(paths, params);
        _setRuntimeConfig(deepMergeMaps(cfg0, params) as Map<String, dynamic>);
        await File(paths.configPath).writeAsString(const JsonEncoder.withIndent('  ').convert(_runtimeConfig));
        await _restartAfterConfigInit();
        return true;
      case 'save_pool_config':
        final String net = (cfg0['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
        final String daemonType =
            '${((cfg0['daemons'] as Map?)?[net] as Map?)?['type'] ?? 'remote'}';
        final bool oldEnabled =
            ((((cfg0['pool'] as Map?)?['server'] as Map?)?['enabled']) as bool?) ?? false;
        Map<String, dynamic> mergedPool =
            deepMergeMaps(cfg0['pool'] ?? <String, dynamic>{}, params) as Map<String, dynamic>;
        String bindIp = '${((mergedPool['server'] as Map?)?['bindIP']) ?? ''}';
        if (bindIp.isEmpty || bindIp == '0.0.0.0' || bindIp == '127.0.0.1') {
          mergedPool = deepMergeMaps(mergedPool, <String, dynamic>{
            'server': <String, dynamic>{'bindIP': '127.0.0.1'},
          }) as Map<String, dynamic>;
        }
        mergedPool = _normalizePoolVarDiff(mergedPool);
        _setRuntimeConfig(deepMergeMaps(cfg0, <String, dynamic>{'pool': mergedPool}) as Map<String, dynamic>);
        if (daemonType == 'remote') {
          _setRuntimeConfig(
            deepMergeMaps(
              _runtimeConfig!,
              <String, dynamic>{'pool': <String, dynamic>{'server': <String, dynamic>{'enabled': false}}},
            ) as Map<String, dynamic>,
          );
          _showNotification('warning', 'Solo pool requires local daemon mode', 3500);
        }
        await File(paths.configPath).writeAsString(const JsonEncoder.withIndent('  ').convert(_runtimeConfig));
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{'config': _runtimeConfig, 'pending_config': _runtimeConfig},
        });
        final bool enabled =
            (((_runtimeConfig!['pool'] as Map?)?['server'] as Map?)?['enabled'] as bool?) ?? false;
        int status = 0;
        if (enabled) {
          status = oldEnabled ? 2 : 1;
        }
        _emit(<String, dynamic>{
          'event': 'set_pool_data',
          'data': <String, dynamic>{'status': status},
        });
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
    final Map<String, dynamic> ethDefault =
        Map<String, dynamic>.from(buildInitialConfigData(paths)['ethereum'] as Map? ?? <String, dynamic>{});

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
          'status': <String, dynamic>{'code': -1},
          'config': initial,
          'pending_config': initial,
        },
      });
      return;
    }

    Map<String, dynamic> configData;
    try {
      final Map<String, dynamic> disk =
          Map<String, dynamic>.from(jsonDecode(await configFile.readAsString()) as Map);
      // Same as Rust `fold_disk_into_config(build_initial_config_data, disk)`: disk overrides,
      // but missing `daemons[net_type]` / RPC fields are filled from defaults (Tauri startup parity).
      configData = Map<String, dynamic>.from(deepMergeMaps(buildInitialConfigData(paths), disk) as Map);
    } catch (e) {
      debugPrint('[DesktopNative] config.json parse error: $e');
      _showNotification('negative', 'Invalid config.json in ${paths.guiDir}');
      _emit(<String, dynamic>{
        'event': 'set_app_data',
        'data': <String, dynamic>{'status': <String, dynamic>{'code': -1}},
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
        'data': <String, dynamic>{'status': <String, dynamic>{'code': -1}},
      });
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

    if (!_requiredDirsExist(configData)) {
      _showNotification('negative', 'Data Storage path or Wallet Data Storage path not found');
      _emit(<String, dynamic>{
        'event': 'set_app_data',
        'data': <String, dynamic>{'status': <String, dynamic>{'code': -1}},
      });
      return;
    }
    _ensureDatadirLayout(configData);

    final String net = (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    Map<String, dynamic> daemonEntry =
        Map<String, dynamic>.from((configData['daemons'] as Map? ?? <String, dynamic>{})[net] as Map? ?? <String, dynamic>{});
    String daemonType = '${daemonEntry['type'] ?? 'remote'}';

    _emit(<String, dynamic>{
      'event': 'set_app_data',
      'data': <String, dynamic>{'status': <String, dynamic>{'code': 3}},
    });

    final DaemonReachableResult reach = await checkDaemonReachable(configData);
    if (reach == DaemonReachableResult.netMismatch) {
      _showNotification('negative', 'Error: Remote node is using a different nettype');
      _emit(<String, dynamic>{
        'event': 'set_app_data',
        'data': <String, dynamic>{'status': <String, dynamic>{'code': -1}},
      });
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
            'message': 'Warning: Could not access remote node, switching to local only',
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
          (configData['daemons'] as Map? ?? <String, dynamic>{})[net] as Map? ?? <String, dynamic>{},
        );
        daemonType = '${daemonEntry['type'] ?? 'remote'}';
      } else {
        _showNotification('negative', 'Error: Could not access remote node, please try another remote node');
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{'status': <String, dynamic>{'code': -1}},
        });
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
    }

    final Map<String, dynamic> daemonEntryNow = Map<String, dynamic>.from(
      (configData['daemons'] as Map? ?? <String, dynamic>{})[net] as Map? ?? <String, dynamic>{},
    );
    final String daemonTypeNow = '${daemonEntryNow['type'] ?? 'remote'}';

    if (daemonTypeNow == 'remote') {
      final String? rh = daemonEntryNow['remote_host'] as String?;
      final int? rp = (daemonEntryNow['remote_port'] as num?)?.toInt();
      if (rh == null || rp == null) {
        _showNotification('negative', 'Remote daemon: missing host/port in configuration');
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{'status': <String, dynamic>{'code': -1}},
        });
        return;
      }
      final Map<String, dynamic>? r = await DaemonJsonRpc.getInfo(rh, rp);
      if (DaemonJsonRpc.result(r) == null) {
        _showNotification('negative', 'Remote daemon can not be reached');
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{'status': <String, dynamic>{'code': -1}},
        });
        return;
      }
    } else {
      final ({Process? process, String? error}) spawned =
          await spawnLocalArqmadAndWait(configData: configData, net: net);
      if (spawned.error != null) {
        _showNotification('negative', spawned.error!);
        _emit(<String, dynamic>{
          'event': 'set_app_data',
          'data': <String, dynamic>{'status': <String, dynamic>{'code': -1}},
        });
        _daemonProcess = spawned.process;
        return;
      }
      _daemonProcess = spawned.process;
    }

    final ({String host, int port})? ep = daemonRpcHostPort(configData);
    if (ep != null) {
      final Map<String, dynamic>? r = await DaemonJsonRpc.getInfo(ep.host, ep.port);
      final Map<String, dynamic>? info = DaemonJsonRpc.result(r);
      if (info != null) {
        _applyDaemonInfo(configData, info);
      }
    }

    _emit(<String, dynamic>{
      'event': 'set_app_data',
      'data': <String, dynamic>{'status': <String, dynamic>{'code': 6}},
    });
    _emit(<String, dynamic>{
      'event': 'set_app_data',
      'data': <String, dynamic>{'status': <String, dynamic>{'code': 7}},
    });

    final String? wdir = walletFilesDir(configData);
    final Map<String, dynamic> wallets =
        wdir != null ? listWalletFiles(wdir) : <String, dynamic>{'list': <dynamic>[], 'directories': <dynamic>[], 'legacy': <dynamic>[]};
    _emit(<String, dynamic>{'event': 'wallet_list', 'data': wallets});

    _emit(<String, dynamic>{
      'event': 'set_app_data',
      'data': <String, dynamic>{'status': <String, dynamic>{'code': 0}},
    });

    // Solo Stratum server is `solo_pool` in Tauri (large Rust module). Flutter desktop does not run it yet;
    // `set_pool_data` still reflects `pool.server.enabled` from config for UI parity.
    _startHeartbeat(configData);

    if (Platform.environment['ARQMA_FLUTTER_NO_WALLET_RPC'] != '1') {
      _walletRpc = await ArqmaWalletRpcSession.tryStart(configData);
      if (_walletRpc == null) {
        _showNotification(
          'warning',
          'arqma-wallet-rpc was not started (missing binary, daemon, or wallet dir). '
              'Set ARQMA_WALLET_RPC or copy arqma-wallet-rpc into rust/tauri-app/src-tauri/bin/.',
          14000,
        );
      }
    }
  }

  void _startHeartbeat(Map<String, dynamic> configData) {
    _heartbeat?.cancel();
    _heartbeatSlow?.cancel();
    _heartbeatSlow = null;
    final String net = (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final Map<String, dynamic>? dm =
        ((configData['daemons'] as Map?) ?? <dynamic, dynamic>{})[net] as Map<String, dynamic>?;
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
    final Map<String, dynamic> cfg =
        _runtimeConfig != null ? Map<String, dynamic>.from(_runtimeConfig!) : configData;
    final String net = (cfg['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final String daemonTyp = '${((cfg['daemons'] as Map?)?[net] as Map?)?['type'] ?? 'remote'}';
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
    final Map<String, dynamic> cfg =
        _runtimeConfig != null ? Map<String, dynamic>.from(_runtimeConfig!) : configData;
    final String net = (cfg['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final String daemonTyp = '${((cfg['daemons'] as Map?)?[net] as Map?)?['type'] ?? 'remote'}';
    final ({String host, int port})? ep = daemonRpcHostPort(cfg);
    if (ep == null) {
      return;
    }
    final Map<String, dynamic>? r = await DaemonJsonRpc.getInfo(ep.host, ep.port);
    // Tauri `daemon_heartbeat`: only auto-restart local child on **transport** failure, not JSON-RPC errors.
    if (r == null) {
      if (daemonTyp != 'remote') {
        await _restartLocalDaemonIfExited(cfg, net);
      }
      return;
    }
    final Map<String, dynamic>? info = DaemonJsonRpc.result(r);
    if (info != null) {
      _applyDaemonInfo(cfg, info);
    }
  }

  /// `daemon_process::restart_local_daemon_if_exited` — best-effort for desktop `dart:io` [Process].
  Future<void> _restartLocalDaemonIfExited(Map<String, dynamic> cfg, String net) async {
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
        await spawnLocalArqmadAndWait(configData: cfg, net: net);
    if (spawned.error != null) {
      debugPrint('[DesktopNative] heartbeat: local arqmad restart failed: ${spawned.error}');
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
    final int h = (result['height'] as num?)?.toInt() ?? 0;
    final int targetH = (result['target_height'] as num?)?.toInt() ?? h;
    final int hw = (result['height_without_bootstrap'] as num?)?.toInt() ?? h;
    final bool isReadyRpc = result['is_ready'] == true;
    final int footerTarget = h > targetH ? h : targetH;
    final bool caughtUp = hw >= footerTarget;
    final bool isReadyUi = caughtUp || isReadyRpc;
    final Map<String, dynamic> m = Map<String, dynamic>.from(result);
    m['is_ready_daemon_rpc'] = isReadyRpc;
    m['is_ready'] = isReadyUi;
    _emit(<String, dynamic>{
      'event': 'set_daemon_data',
      'data': <String, dynamic>{'info': m},
    });
    _emitPoolDataWithHeartbeat(cfg, m);
  }

  void _emitPoolDataWithHeartbeat(Map<String, dynamic> cfg, Map<String, dynamic> result) {
    final bool poolEnabled = poolServerEnabled(cfg);
    final int h = (result['height'] as num?)?.toInt() ?? 0;
    final int targetH = (result['target_height'] as num?)?.toInt() ?? h;
    final int hw = (result['height_without_bootstrap'] as num?)?.toInt() ?? h;
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
      (int i) => <String, dynamic>{'host': 'node${i + 1}.arqma.com', 'port': 19994},
    );
  }

  String _selectedNodeString(Map<String, dynamic> configData) {
    final String a = (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final Map<String, dynamic>? d = (configData['daemons'] as Map?)?[a] as Map<String, dynamic>?;
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
    final Map<String, dynamic>? app = configData['app'] as Map<String, dynamic>?;
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
    try {
      final Map<String, dynamic> app = Map<String, dynamic>.from(configData['app'] as Map? ?? <String, dynamic>{});
      final String? wdir = app['wallet_data_dir'] as String?;
      final String? dataDir = app['data_dir'] as String?;
      final String net = app['net_type'] as String? ?? 'mainnet';
      if (wdir != null && wdir.isNotEmpty) {
        Directory(wdir).createSync(recursive: true);
      }
      if (dataDir != null && dataDir.isNotEmpty) {
        final Directory mainData = Directory(dataDir);
        final Directory netDir = switch (net) {
          'stagenet' => Directory(<String>[mainData.path, 'stagenet'].join(Platform.pathSeparator)),
          'testnet' => Directory(<String>[mainData.path, 'testnet'].join(Platform.pathSeparator)),
          _ => mainData,
        };
        netDir.createSync(recursive: true);
        Directory(<String>[netDir.path, 'logs'].join(Platform.pathSeparator)).createSync(recursive: true);
      }
    } catch (e) {
      debugPrint('[DesktopNative] ensure_datadir_layout: $e');
    }
  }

  Future<dynamic> _openWalletDesktop(Object? data) async {
    final ArqmaWalletRpcSession? w = _walletRpc;
    if (w == null) {
      _showNotification(
        'negative',
        'arqma-wallet-rpc is not running. Check startup logs and ARQMA_WALLET_RPC / src-tauri/bin.',
        12000,
      );
      _emit(<String, dynamic>{
        'event': 'reset_wallet_status',
        'data': <String, dynamic>{'code': -1, 'message': 'Wallet RPC unavailable'},
      });
      return <String, dynamic>{};
    }
    final Map<String, dynamic> p = _coerceMap(data);
    final String name = '${p['name'] ?? p['filename'] ?? ''}'.trim();
    final String password = '${p['password'] ?? ''}';
    if (name.isEmpty) {
      _emit(<String, dynamic>{
        'event': 'reset_wallet_status',
        'data': <String, dynamic>{'code': -1, 'message': 'Missing wallet name'},
      });
      return <String, dynamic>{};
    }
    _emit(<String, dynamic>{'event': 'reset_wallet_error', 'data': <String, dynamic>{}});
    final Map<String, dynamic>? opened = await w.call(
      'open_wallet',
      <String, dynamic>{'filename': name, 'password': password},
    );
    if (!walletJsonRpcNoError(opened)) {
      final String msg = '${opened?['error'] ?? 'open_wallet failed'}';
      _emit(<String, dynamic>{
        'event': 'reset_wallet_status',
        'data': <String, dynamic>{'code': -1, 'message': msg},
      });
      return <String, dynamic>{};
    }
    _refreshSessionPasswordDigest(password);
    await _emitWalletOpenedUi(name);
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
    _walletPasswordHashHex = tryPbkdf2PasswordHex(password: password, saltHex: saltHex);
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
    final ArqmaWalletRpcSession? w = _walletRpc;
    if (w == null) {
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
        .call('getheight', <String, dynamic>{})
        .timeout(const Duration(seconds: 30), onTimeout: () => null);
    final Map<String, dynamic>? gb = await w
        .call('getbalance', <String, dynamic>{'account_index': 0})
        .timeout(const Duration(seconds: 30), onTimeout: () => null);

    final int openedHeight = walletHeightFromGetheight(gh) ?? 0;
    int bal = 0;
    int unl = 0;
    if (walletJsonRpcNoError(gb) && gb != null) {
      final Object? res = gb['result'];
      if (res is Map) {
        final Map<String, dynamic> rm = Map<String, dynamic>.from(res);
        bal = (rm['balance'] as num?)?.toInt() ?? 0;
        unl = (rm['unlocked_balance'] as num?)?.toInt() ?? (rm['unlocked'] as num?)?.toInt() ?? 0;
      }
    }

    String? address;
    final Map<String, dynamic>? ga =
        await w.call('get_address', <String, dynamic>{'account_index': 0}).timeout(const Duration(seconds: 25), onTimeout: () => null);
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
    final Map<String, dynamic>? qk =
        await w.call('query_key', <String, dynamic>{'key_type': 'spend_key'}).timeout(const Duration(seconds: 20), onTimeout: () => null);
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
        if (address != null) 'address': address,
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
  }

  static const double _arqCoinUnits = 1e9;

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

  void _pushTransferMetadataFromResult(Map<String, dynamic> r, Map<String, dynamic> p) {
    _pendingTxRelay.removeWhere((Map<String, dynamic> m) => m['kind'] == 'transfer_split');
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

  void _pushSweepMetadataFromResult(Map<String, dynamic> r, Map<String, dynamic> p) {
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
    final String? txh0 = txHashes != null && txHashes.isNotEmpty ? '${txHashes[0]}' : null;
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

  void _pushStakeMetadataFromResult(Map<String, dynamic> r, Map<String, dynamic> p) {
    _pendingTxRelay.removeWhere((Map<String, dynamic> m) => m['kind'] == 'stake');
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
    final String serviceNodeKey = '${p['key'] ?? p['service_node_key'] ?? ''}'.trim();
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
    final List<Map<String, dynamic>> items =
        _pendingTxRelay.where((Map<String, dynamic> m) => m['kind'] == 'transfer_split').toList();
    for (final Map<String, dynamic> t in items) {
      final String hex = '${t['tx_metadata'] ?? ''}';
      final Map<String, dynamic>? rr = await w.call('relay_tx', <String, dynamic>{'hex': hex});
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
        'data': <String, dynamic>{'code': -200, 'message': err, 'sending': false},
      });
    } else {
      _emit(<String, dynamic>{
        'event': 'set_tx_status',
        'data': <String, dynamic>{
          'code': 201,
          'message': 'Transaction successfully sent',
          'sending': false,
        },
      });
    }
    _pendingTxRelay.removeWhere((Map<String, dynamic> m) => m['kind'] == 'transfer_split');
  }

  Future<void> _relayStakeSplit(Map<String, dynamic> origin) async {
    final ArqmaWalletRpcSession? w = _walletRpc;
    if (w == null) {
      return;
    }
    final List<Map<String, dynamic>> items =
        _pendingTxRelay.where((Map<String, dynamic> m) => m['kind'] == 'stake').toList();
    for (final Map<String, dynamic> t in items) {
      final String hex = '${t['tx_metadata'] ?? ''}';
      final Map<String, dynamic>? rr = await w.call('relay_tx', <String, dynamic>{'hex': hex});
      if (!walletJsonRpcNoError(rr)) {
        final String err = _walletRpcErrCapitalized(rr?['error']);
        _emit(<String, dynamic>{
          'event': 'set_tx_status',
          'data': <String, dynamic>{'code': -300, 'message': err, 'sending': false, 'origin': origin},
        });
        _pendingTxRelay.removeWhere((Map<String, dynamic> m) => m['kind'] == 'stake');
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
    _pendingTxRelay.removeWhere((Map<String, dynamic> m) => m['kind'] == 'stake');
  }

  Future<void> _relaySweepAllSplit(Map<String, dynamic> origin) async {
    final ArqmaWalletRpcSession? w = _walletRpc;
    if (w == null) {
      return;
    }
    String err = '';
    final List<Map<String, dynamic>> items =
        _pendingTxRelay.where((Map<String, dynamic> m) => m['kind'] == 'sweepAll').toList();
    for (final Map<String, dynamic> t in items) {
      final String hex = '${t['tx_metadata'] ?? ''}';
      final Map<String, dynamic>? rr = await w.call('relay_tx', <String, dynamic>{'hex': hex});
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
    _pendingTxRelay.removeWhere((Map<String, dynamic> m) => m['kind'] == 'sweepAll');
  }

  String _normalizeRestoreSeed(String seed) {
    return seed.split(RegExp(r'\s+')).where((String s) => s.isNotEmpty).join(' ');
  }

  String _configuredNetType() => (_runtimeConfig?['app'] as Map?)?['net_type'] as String? ?? 'mainnet';

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
  Future<dynamic> _walletStubBackendSend(String module, String method, [Object? data]) async {
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
      _emit(<String, dynamic>{'event': 'set_has_password', 'data': sameAsEmpty});
      return <String, dynamic>{};
    }
    if (method == 'validate_address') {
      final String addr = '${_coerceMap(data)['address'] ?? ''}';
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w != null && addr.isNotEmpty) {
        final Map<String, dynamic>? r = await w.call('validate_address', <String, dynamic>{'address': addr});
        if (!walletJsonRpcNoError(r) || r == null) {
          _emitSetValidAddress(address: addr, rpcFieldValid: false, rpcNettype: '');
          return <String, dynamic>{};
        }
        final Object? res = r['result'];
        if (res is! Map) {
          _emitSetValidAddress(address: addr, rpcFieldValid: false, rpcNettype: '');
          return <String, dynamic>{};
        }
        final Map<String, dynamic> rm = Map<String, dynamic>.from(res);
        final bool fieldValid = rm['valid'] == true || rm['integrated'] == true;
        final String rpcNet =
            '${rm['nettype'] ?? rm['net_type'] ?? ''}';
        _emitSetValidAddress(address: addr, rpcFieldValid: fieldValid, rpcNettype: rpcNet);
        return <String, dynamic>{};
      }
      _emitSetValidAddress(
        address: addr,
        rpcFieldValid: addr.isNotEmpty,
        rpcNettype: _configuredNetType(),
      );
      return <String, dynamic>{};
    }
    if (method == 'subscribe_for_signature_data' || method == 'unsubscribe_for_signature_data') {
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
              _walletRpc?.call(m, p) ?? Future<Map<String, dynamic>?>.value(null),
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
      _openedWalletDisplayName = '';
      _walletPasswordHashHex = null;
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w != null) {
        await w.call('close_wallet', <String, dynamic>{});
      }
      _emit(<String, dynamic>{'event': 'reset_wallet_error', 'data': <String, dynamic>{}});
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
          'data': <String, dynamic>{'code': -200, 'message': 'Wallet RPC unavailable', 'sending': false},
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
            final String feeMsg = feeAtoms > 0 ? 'Fee ${(feeAtoms / _arqCoinUnits).toStringAsFixed(9)}' : 'Fee';
            _emit(<String, dynamic>{
              'event': 'set_tx_status',
              'data': <String, dynamic>{'code': 200, 'message': feeMsg, 'sending': false},
            });
            if (p['address_book'] is Map && (p['address_book'] as Map)['save'] == true) {
              final String addr = '${p['address'] ?? ''}'.trim();
              if (addr.isNotEmpty) {
                final Map<String, dynamic> ab = Map<String, dynamic>.from(p['address_book'] as Map? ?? <String, dynamic>{});
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
              'data': <String, dynamic>{'code': -200, 'message': 'No result from transfer_split', 'sending': false},
            });
          }
        }
      } catch (e) {
        _emit(<String, dynamic>{
          'event': 'set_tx_status',
          'data': <String, dynamic>{'code': -200, 'message': '$e', 'sending': false},
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
        await w.call('rescan_blockchain', <String, dynamic>{if (hard) 'hard': true});
      }
      return <String, dynamic>{};
    }
    if (method == 'rescan_spent') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w != null) {
        await w.call('rescan_spent', <String, dynamic>{});
      }
      return <String, dynamic>{};
    }
    if (method == 'sweepAll') {
      final ArqmaWalletRpcSession? w = _walletRpc;
      if (w == null) {
        return <String, dynamic>{};
      }
      final Map<String, dynamic> p = _coerceMap(data);
      final Map<String, dynamic>? addrR = await w.call('get_address', <String, dynamic>{'account_index': 0});
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
      final String myAddress = '${(addrR!['result'] as Map?)?['address'] ?? ''}';
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
            'message': doNot ? feeUi.toStringAsFixed(9) : 'sweep_all_rpc_success_message',
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
        await w.call('delete_address_book', <String, dynamic>{'index': idx.toInt()});
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
        _emit(<String, dynamic>{'event': 'set_wallet_error', 'data': <String, dynamic>{'status': r?['error']}});
        _showNotification('negative', 'Wallet RPC Error, Address Rejected', 3000);
        return <String, dynamic>{};
      }
      await w.call('store', <String, dynamic>{});
      _showNotification('positive', 'Address Book updated with ${p['address'] ?? ''}', 3000);
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
      final Map<String, dynamic>? r = await w.call('delete_address_book', <String, dynamic>{'index': idx.toInt()});
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
          final String feeMsg = feeAtoms > 0 ? 'Fee ${(feeAtoms / _arqCoinUnits).toStringAsFixed(9)}' : 'Fee';
          _emit(<String, dynamic>{
            'event': 'set_tx_status',
            'data': <String, dynamic>{'code': 300, 'message': feeMsg, 'sending': false},
          });
          _pushStakeMetadataFromResult(r, p);
        }
      } catch (e) {
        _emit(<String, dynamic>{
          'event': 'set_tx_status',
          'data': <String, dynamic>{'code': -300, 'message': '$e', 'sending': false},
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
          'data': <String, dynamic>{'code': -400, 'message': 'invalidPassword', 'sending': false},
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
          'data': <String, dynamic>{'code': -400, 'message': msg, 'sending': false},
        });
        return <String, dynamic>{};
      }
      if (confirmed && r?['result'] is Map) {
        final Map<String, dynamic> res = Map<String, dynamic>.from(r!['result'] as Map);
        final String msg = '${res['msg'] ?? res['message'] ?? ''}';
        final bool unlocked = res['unlocked'] == true;
        _emit(<String, dynamic>{
          'event': 'set_snode_status_unlock',
          'data': <String, dynamic>{'code': unlocked ? 400 : -400, 'message': msg, 'sending': false},
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
      final Map<String, dynamic> secret = <String, dynamic>{'mnemonic': '', 'spend_key': '', 'view_key': ''};
      for (final String kt in <String>['mnemonic', 'spend_key', 'view_key']) {
        final Map<String, dynamic>? q = await w.call('query_key', <String, dynamic>{'key_type': kt});
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
          _showNotification('negative', _walletRpcErrCapitalized(r?['error']), 4000);
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
            'registration': <String, dynamic>{'code': -1, 'message': '', 'sending': false},
          },
        });
        return <String, dynamic>{};
      }
      final String s = '${p['string'] ?? p['register_service_node_str'] ?? ''}';
      final Map<String, dynamic>? r =
          await w.call('register_service_node', <String, dynamic>{'register_service_node_str': s});
      if (!walletJsonRpcNoError(r)) {
        _emit(<String, dynamic>{
          'event': 'set_snode_status',
          'data': <String, dynamic>{
            'registration': <String, dynamic>{'code': -1, 'message': _walletRpcErrCapitalized(r?['error']), 'sending': false},
          },
        });
        return <String, dynamic>{};
      }
      _emit(<String, dynamic>{
        'event': 'set_snode_status',
        'data': <String, dynamic>{'registration': <String, dynamic>{'code': 0, 'sending': false}},
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
      final List<dynamic> list =
          (_coerceMap(data)['wallets'] is List) ? List<dynamic>.from(_coerceMap(data)['wallets'] as List) : <dynamic>[];
      final List<String> failed = runCopyOldGuiWallets(cfg, list);
      _emit(<String, dynamic>{
        'event': 'set_old_gui_import_status',
        'data': <String, dynamic>{'code': 0, 'failed_wallets': failed},
      });
      final String? wdir = walletFilesDir(cfg);
      if (wdir != null) {
        _emit(<String, dynamic>{'event': 'wallet_list', 'data': listWalletFiles(wdir)});
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
    final Map<String, dynamic>? data = await w.call('export_key_images', <String, dynamic>{'all': all});
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
    final Map<String, dynamic>? data =
        await w.call('import_key_images', <String, dynamic>{'signed_key_images': signed});
    if (!walletJsonRpcNoError(data) || data?['result'] == null) {
      _showNotification('negative', 'Error importing key images. change to local daemon', 3000);
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
    _emit(<String, dynamic>{'event': 'show_loading', 'data': <String, dynamic>{'message': 'Deleting wallet'}});
    await w.call('store', <String, dynamic>{});
    await w.call('close_wallet', <String, dynamic>{});
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
        File('$wdir${Platform.pathSeparator}$walletName.address.txt').deleteSync();
      } catch (_) {}
      _emit(<String, dynamic>{'event': 'wallet_list', 'data': listWalletFiles(wdir)});
    }
    _emit(<String, dynamic>{'event': 'hide_loading', 'data': <String, dynamic>{}});
    _emit(<String, dynamic>{'event': 'return_to_wallet_select', 'data': <String, dynamic>{}});
    if (Platform.environment['ARQMA_FLUTTER_NO_WALLET_RPC'] != '1') {
      _walletRpc = await ArqmaWalletRpcSession.tryStart(cfg);
    }
  }

  Future<dynamic> _walletCreateRestoreImport(String method, Object? data) async {
    final ArqmaWalletRpcSession? w = _walletRpc;
    final Map<String, dynamic>? cfg = _runtimeConfig;
    if (w == null || cfg == null) {
      _showNotification('negative', 'arqma-wallet-rpc is not running.', 8000);
      return <String, dynamic>{};
    }
    final Map<String, dynamic> p = _coerceMap(data);
    if (method == 'create_wallet') {
      final String name = '${p['name'] ?? ''}';
      final String password = '${p['password'] ?? ''}';
      final String language = '${p['language'] ?? 'English'}';
      final Map<String, dynamic>? r = await w.call(
        'create_wallet',
        <String, dynamic>{'filename': name, 'password': password, 'language': language},
      );
      if (!walletJsonRpcNoError(r)) {
        _emit(<String, dynamic>{
          'event': 'reset_wallet_status',
          'data': <String, dynamic>{'code': -1, 'message': '${r?['error'] ?? 'create_wallet failed'}'},
        });
        return <String, dynamic>{};
      }
      _refreshSessionPasswordDigest(password);
      await _emitWalletOpenedUi(name);
      return <String, dynamic>{};
    }
    if (method == 'restore_wallet') {
      _emit(<String, dynamic>{'event': 'reset_wallet_error', 'data': <String, dynamic>{}});
      final ({String host, int port})? ep = daemonRpcHostPort(cfg);
      if (ep == null) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{'status': <String, dynamic>{'code': -1, 'message': 'restore: daemon RPC missing'}},
        });
        return <String, dynamic>{};
      }
      final int? rh = await resolveRestoreRefreshHeight(host: ep.host, port: ep.port, p: p);
      if (rh == null) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{'status': <String, dynamic>{'code': -1, 'message': 'restore: refresh_start_height'}},
        });
        return <String, dynamic>{};
      }
      await w.call('close_wallet', <String, dynamic>{});
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
        _emit(<String, dynamic>{'event': 'set_wallet_error', 'data': <String, dynamic>{'status': r?['error']}});
        return <String, dynamic>{};
      }
      _refreshSessionPasswordDigest(password);
      await _emitWalletOpenedUi(name);
      return <String, dynamic>{};
    }
    if (method == 'restore_view_wallet') {
      _emit(<String, dynamic>{'event': 'reset_wallet_error', 'data': <String, dynamic>{}});
      final ({String host, int port})? ep = daemonRpcHostPort(cfg);
      if (ep == null) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{'status': <String, dynamic>{'code': -1, 'message': 'restore: daemon RPC missing'}},
        });
        return <String, dynamic>{};
      }
      int? refreshH = await resolveRestoreRefreshHeight(host: ep.host, port: ep.port, p: p);
      if (refreshH == null) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{'status': <String, dynamic>{'code': -1, 'message': 'restore: refresh_start_height'}},
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
      await w.call('close_wallet', <String, dynamic>{});
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
        _emit(<String, dynamic>{'event': 'set_wallet_error', 'data': <String, dynamic>{'status': r?['error']}});
        return <String, dynamic>{};
      }
      _refreshSessionPasswordDigest(password);
      await _emitWalletOpenedUi(name);
      return <String, dynamic>{};
    }
    if (method == 'import_wallet') {
      _emit(<String, dynamic>{'event': 'reset_wallet_error', 'data': <String, dynamic>{}});
      final String filename = '${p['name'] ?? p['filename'] ?? ''}'.trim();
      final String? importPathRaw = p['path'] as String?;
      final String password = '${p['password'] ?? ''}';
      if (filename.isEmpty || importPathRaw == null || importPathRaw.isEmpty) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{'status': <String, dynamic>{'code': -1, 'message': 'import_wallet: name/path'}},
        });
        return <String, dynamic>{};
      }
      String importBase = importPathRaw.trim();
      if (importBase.endsWith('.keys')) {
        importBase = importBase.substring(0, importBase.length - '.keys'.length);
      } else if (importBase.endsWith('.address.txt')) {
        importBase = importBase.substring(0, importBase.length - '.address.txt'.length);
      }
      final File importSrc = File(importBase);
      if (!importSrc.existsSync()) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{'status': <String, dynamic>{'code': -1, 'message': 'Invalid wallet path'}},
        });
        return <String, dynamic>{};
      }
      final String? wdir = walletFilesDir(cfg);
      if (wdir == null) {
        return <String, dynamic>{};
      }
      final File destination = File('$wdir${Platform.pathSeparator}$filename');
      final File destKeys = File('$wdir${Platform.pathSeparator}$filename.keys');
      if (destination.existsSync() || destKeys.existsSync()) {
        _emit(<String, dynamic>{
          'event': 'set_wallet_error',
          'data': <String, dynamic>{'status': <String, dynamic>{'code': -1, 'message': 'Wallet with name already exists'}},
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
          'data': <String, dynamic>{'status': <String, dynamic>{'code': -1, 'message': 'Failed to copy wallet'}},
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
        _emit(<String, dynamic>{'event': 'set_wallet_error', 'data': <String, dynamic>{'status': openR?['error']}});
        return <String, dynamic>{};
      }
      _refreshSessionPasswordDigest(password);
      await _emitWalletOpenedUi(filename);
      return <String, dynamic>{};
    }
    return <String, dynamic>{};
  }
}
