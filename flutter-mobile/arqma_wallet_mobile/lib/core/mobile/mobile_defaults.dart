import 'dart:io';

import 'mobile_remote_nodes.dart';
import '../desktop/arqma_paths.dart';

/// Mobile wallet config: **remote daemon only**, default [kMobileDefaultRemoteHost].
Map<String, dynamic> buildMobileInitialConfigData(ArqmaPaths paths) {
  final Map<String, dynamic> daemonBase = <String, dynamic>{
    'type': 'remote',
    'p2p_bind_ip': '0.0.0.0',
    'p2p_bind_port': 19993,
    'rpc_bind_ip': '127.0.0.1',
    'rpc_bind_port': 19994,
    'zmq_rpc_bind_ip': '127.0.0.1',
    'zmq_rpc_bind_port': 19995,
    'out_peers': -1,
    'in_peers': -1,
    'limit_rate_up': -1,
    'limit_rate_down': -1,
    'log_level': 0,
  };
  Map<String, dynamic> remoteMainnet() => <String, dynamic>{
        ...daemonBase,
        'type': 'remote',
        'remote_host': kMobileDefaultRemoteHost,
        'remote_port': kArqmaMainnetRemotePort,
      };
  return <String, dynamic>{
    'daemons': <String, dynamic>{
      'mainnet': remoteMainnet(),
      'stagenet': remoteMainnet(),
      'testnet': remoteMainnet(),
    },
    'app': <String, dynamic>{
      'data_dir': paths.configDir,
      'wallet_data_dir': paths.walletDir,
      'net_type': 'mainnet',
      'scan': false,
      'promptForPassword': true,
      'daysOfTransactions': 1,
      'loggingLevel': 'error',
      'inactivityTimeout': 5,
      'appearance': <String, dynamic>{'theme': 'dark'},
    },
    'wallet': <String, dynamic>{'rpc_bind_port': 19999, 'log_level': 1},
    'pool': <String, dynamic>{
      'server': <String, dynamic>{
        'enabled': false,
        'bindIP': '127.0.0.1',
        'bindPort': 3333,
      },
      'mining': <String, dynamic>{
        'address': '',
        'enableBlockRefreshInterval': true,
        'blockRefreshInterval': 5,
        'minerTimeout': 900,
      },
      'varDiff': <String, dynamic>{
        'enabled': true,
        'startDiff': 60000,
        'minDiff': 25000,
        'maxDiff': 5000000,
        'targetTime': 45,
        'retargetTime': 30,
        'variancePercent': 25,
        'maxJump': 50,
        'fixedDiffSeparator': '.',
      },
    },
    'ethereum': _defaultEthereum(),
  };
}

Map<String, dynamic> _defaultEthereum() => <String, dynamic>{
      'ethereum_network_index': '0',
      'networks': <dynamic>[
        <dynamic>[
          <String, dynamic>{
            'token_name': 'ETH',
            'network': 'ethereum',
            'id': 1,
            'token_address': '0x0d40aD54EDc0A3632A1996e5f8fd10b91f298A27',
            'bridge_address': '0x631a2C078aE1dF2d04062DEca539197Ef5AC546e',
            'explorer': 'https://etherscan.io/tx/',
            'governance':
                'Tw1WW1jYkS3144DkXTDQgg6j2fDk28KuDeYdQZb91UvnZ462yRExJz2h7k116wXbRp4JhcYyfb3PabpTuaRX9DiG2U5kGJ6wS',
          },
          <String, dynamic>{
            'token_name': 'BNB',
            'network': 'bnb',
            'id': 56,
            'token_address': '0x0d40aD54EDc0A3632A1996e5f8fd10b91f298A27',
            'bridge_address': '0x631a2C078aE1dF2d04062DEca539197Ef5AC546e',
            'explorer': 'https://bscscan.com/tx/',
            'governance':
                'Tw1WW1jYkS3144DkXTDQgg6j2fDk28KuDeYdQZb91UvnZ462yRExJz2h7k116wXbRp4JhcYyfb3PabpTuaRX9DiG2U5kGJ6wS',
          },
        ],
      ],
    };

Map<String, dynamic> buildMobileDefaultsOnly(ArqmaPaths paths) {
  final Map<String, dynamic> full = buildMobileInitialConfigData(paths);
  return <String, dynamic>{
    'daemons': full['daemons'],
    'app': <String, dynamic>{
      'data_dir': paths.configDir,
      'wallet_data_dir': paths.walletDir,
      'net_type': 'mainnet',
      'scan': false,
      'promptForPassword': true,
      'daysOfTransactions': 1,
      'loggingLevel': 'error',
      'inactivityTimeout': 5,
    },
    'wallet': full['wallet'],
    'pool': full['pool'],
  };
}

/// On iOS/Android, keep storage under the app sandbox (Documents). Desktop paths or `~`
/// from imported `config.json` cannot be created on device.
bool enforceMobileStoragePaths(
  Map<String, dynamic> config,
  ArqmaPaths paths,
) {
  if (!Platform.isIOS && !Platform.isAndroid) {
    return false;
  }
  final String docsRoot = File(paths.configDir).parent.path;
  final Map<String, dynamic> app =
      Map<String, dynamic>.from(config['app'] as Map? ?? <String, dynamic>{});
  String dataDir = expandArqUserPath('${app['data_dir'] ?? ''}'.trim());
  String walletDir = expandArqUserPath('${app['wallet_data_dir'] ?? ''}'.trim());

  bool underSandbox(String p) {
    if (p.isEmpty) {
      return false;
    }
    final String norm = p.replaceAll(r'\', '/');
    final String root = docsRoot.replaceAll(r'\', '/');
    return norm == root || norm.startsWith('$root/');
  }

  bool writable(String p) {
    try {
      Directory(p).createSync(recursive: true);
      final File probe = File('$p${Platform.pathSeparator}.arqma_write_probe');
      probe.writeAsStringSync('ok');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool changed = false;
  if (!underSandbox(dataDir) || !writable(dataDir)) {
    dataDir = paths.configDir;
    changed = true;
  }
  if (!underSandbox(walletDir) || !writable(walletDir)) {
    walletDir = paths.walletDir;
    changed = true;
  }
  app['data_dir'] = dataDir;
  app['wallet_data_dir'] = walletDir;
  config['app'] = app;
  return changed;
}

/// Force mainnet remote node and strip local / local_remote daemon modes.
void enforceMobileRemoteOnlyConfig(Map<String, dynamic> config) {
  final String net =
      (config['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  final Map<String, dynamic> daemons =
      Map<String, dynamic>.from(config['daemons'] as Map? ?? <String, dynamic>{});
  final Map<String, dynamic> entry =
      Map<String, dynamic>.from(daemons[net] as Map? ?? <String, dynamic>{});
  final String host =
      '${entry['remote_host'] ?? kMobileDefaultRemoteHost}'.trim();
  entry['type'] = 'remote';
  if (host.isEmpty) {
    entry['remote_host'] = kMobileDefaultRemoteHost;
  } else {
    entry['remote_host'] = host;
  }
  entry['remote_port'] =
      int.tryParse('${entry['remote_port']}') ?? kArqmaMainnetRemotePort;
  entry.remove('trusted-daemon');
  entry.remove('trusted_daemon');
  daemons[net] = entry;
  config['daemons'] = daemons;
  final Map<String, dynamic> pool =
      Map<String, dynamic>.from(config['pool'] as Map? ?? <String, dynamic>{});
  final Map<String, dynamic> server = Map<String, dynamic>.from(
      pool['server'] as Map? ?? <String, dynamic>{});
  server['enabled'] = false;
  pool['server'] = server;
  config['pool'] = pool;
}
