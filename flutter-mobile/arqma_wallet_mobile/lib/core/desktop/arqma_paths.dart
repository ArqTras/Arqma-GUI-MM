import 'dart:io';

import '../utils/deep_merge.dart';

/// Expands a leading `~` to the user home directory (same convention as shell / legacy GUI paths).
String expandArqUserPath(String input) {
  final String t = input.trim();
  if (t.isEmpty) {
    return t;
  }
  if (Platform.isWindows) {
    final String home = Platform.environment['USERPROFILE'] ?? '';
    if (home.isEmpty) {
      return input;
    }
    if (t == '~') {
      return home;
    }
    if (t.startsWith(r'~\') || t.startsWith('~/')) {
      final String rest = t.substring(2).replaceFirst(RegExp(r'^[\\/]+'), '');
      return '$home${Platform.pathSeparator}$rest';
    }
    return input;
  }
  final String home = Platform.environment['HOME'] ?? '';
  if (home.isEmpty) {
    return input;
  }
  if (t == '~') {
    return home;
  }
  if (t.startsWith('~/')) {
    return '$home/${t.substring(2)}';
  }
  return input;
}

/// Normalizes [config] `app.data_dir` and `app.wallet_data_dir` so daemon / wallet use the same
/// absolute paths as Tauri when the JSON contains `~`.
Map<String, dynamic> normalizeConfigStoragePaths(Map<String, dynamic> config) {
  final Map<String, dynamic> out = Map<String, dynamic>.from(config);
  final Object? appObj = out['app'];
  if (appObj is! Map) {
    return out;
  }
  final Map<String, dynamic> app = Map<String, dynamic>.from(appObj);
  final Object? dd = app['data_dir'];
  if (dd is String && dd.isNotEmpty) {
    app['data_dir'] = expandArqUserPath(dd);
  }
  final Object? wd = app['wallet_data_dir'];
  if (wd is String && wd.isNotEmpty) {
    app['wallet_data_dir'] = expandArqUserPath(wd);
  }
  out['app'] = app;
  return out;
}

/// Same layout as [arqma_wallet_core::default_paths] (`rust/core/src/config.rs`) and Electron
/// `Backend` (`src-electron/main-process/modules/backend.js`): GUI metadata under `config_dir/gui`,
/// daemon/wallet locations follow `app.data_dir` / `app.wallet_data_dir` in `config.json`.
///
/// Platform defaults (when creating a new `config.json`):
/// - Windows — `C:\\ProgramData\\arqma` and `%USERPROFILE%\\Documents\\arqma`
/// - Unix/macOS — `$HOME/.arqma` and `$HOME/arqma`
class ArqmaPaths {
  ArqmaPaths({required this.configDir, required this.walletDir});

  final String configDir;
  final String walletDir;

  static ArqmaPaths defaultForPlatform() {
    if (Platform.isWindows) {
      final String home = Platform.environment['USERPROFILE'] ?? '.';
      return ArqmaPaths(
        configDir: r'C:\ProgramData\arqma',
        walletDir:
            '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}arqma',
      );
    }
    final String home = Platform.environment['HOME'] ?? '.';
    return ArqmaPaths(
      configDir: '$home/.arqma',
      walletDir: '$home/arqma',
    );
  }

  String get guiDir => '$configDir${Platform.pathSeparator}gui';

  String get configPath => '$guiDir${Platform.pathSeparator}config.json';

  String get remotesPath => '$guiDir${Platform.pathSeparator}remotes.json';
}

/// Mirrors `arqma_paths_config::wallet_files_dir_for_net` / `wallet_files_dir`.
String? walletFilesDirForNet(Map<String, dynamic> config, String net) {
  final Map<String, dynamic>? app = config['app'] as Map<String, dynamic>?;
  final String? wdata = app?['wallet_data_dir'] as String?;
  if (wdata == null || wdata.isEmpty) {
    return null;
  }
  final String sep = Platform.pathSeparator;
  switch (net) {
    case 'stagenet':
      return <String>[wdata, 'stagenet', 'wallets'].join(sep);
    case 'testnet':
      return <String>[wdata, 'testnet', 'wallets'].join(sep);
    default:
      return <String>[wdata, 'wallets'].join(sep);
  }
}

String? walletFilesDir(Map<String, dynamic> config) {
  final String net =
      (config['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  return walletFilesDirForNet(config, net);
}

/// Full wallet JSON (`config.json` shape): merge gateway `config` + `pending_config` like the UI, then expand `~`.
/// Used to scan the same directory the user configured before/without a successful daemon startup.
Map<String, dynamic>? mergedFilesystemConfig(
    Map<String, dynamic> gatewayAppSection) {
  final Object? c0 = gatewayAppSection['config'];
  final Object? p0 = gatewayAppSection['pending_config'];
  if (c0 is! Map && p0 is! Map) {
    return null;
  }
  Map<String, dynamic> base = <String, dynamic>{};
  if (c0 is Map) {
    base = Map<String, dynamic>.from(c0);
  }
  if (p0 is Map) {
    base = deepMergeMaps(base, Map<String, dynamic>.from(p0))
        as Map<String, dynamic>;
  }
  return normalizeConfigStoragePaths(base);
}

/// RPC endpoint for current net (`daemon_rpc_host_port` in Rust).
({String host, int port})? daemonRpcHostPort(Map<String, dynamic> config) {
  final String net =
      (config['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  final Map<String, dynamic>? d =
      (config['daemons'] as Map?)?[net] as Map<String, dynamic>?;
  if (d == null) {
    return null;
  }
  final String typ = d['type'] as String? ?? 'remote';
  if (typ == 'remote') {
    final String? h = d['remote_host'] as String?;
    final int? p = (d['remote_port'] as num?)?.toInt();
    if (h == null || p == null) {
      return null;
    }
    return (host: h, port: p);
  }
  final String h = d['rpc_bind_ip'] as String? ?? '127.0.0.1';
  final int p = (d['rpc_bind_port'] as num?)?.toInt() ?? 19994;
  return (host: h, port: p);
}

/// Safe wallet account basename for filesystem paths (blocks `..`, separators, odd chars).
String? sanitizeWalletBaseName(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final String collapsed = trimmed.replaceAll(RegExp(r'\s+'), '_');
  final String normalized = collapsed.replaceAll('\\', '/');
  if (normalized.contains('..')) {
    return null;
  }
  String base = normalized;
  if (normalized.contains('/')) {
    final bool windowsAbsolute = RegExp(r'^[A-Za-z]:/').hasMatch(normalized) ||
        normalized.startsWith('//');
    final bool unixAbsolute = normalized.startsWith('/');
    if (!windowsAbsolute && !unixAbsolute) {
      return null;
    }
    base = normalized.substring(normalized.lastIndexOf('/') + 1);
  }
  if (base.isEmpty || base == '.' || base == '..') {
    return null;
  }
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(base)) {
    return null;
  }
  return base;
}

/// Returns a user-facing error key suffix when [raw] cannot be used as a wallet name.
String? walletBaseNameInputErrorKey(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return 'empty';
  }
  if (sanitizeWalletBaseName(trimmed) == null) {
    return 'invalid_chars';
  }
  return null;
}
