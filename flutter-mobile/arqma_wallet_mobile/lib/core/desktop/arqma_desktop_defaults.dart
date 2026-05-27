import 'arqma_paths.dart';

/// Baseline `config_data` when `gui/config.json` is missing — aligned with
/// `defaults::build_initial_config_data` + `build_defaults` (`rust/core/src/defaults.rs`).
Map<String, dynamic> buildInitialConfigData(ArqmaPaths paths) {
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
  Map<String, dynamic> d(Map<String, dynamic> extra) =>
      <String, dynamic>{...daemonBase, ...extra};
  return <String, dynamic>{
    'daemons': <String, dynamic>{
      'mainnet': d(<String, dynamic>{
        'remote_host': 'node1.arqma.com',
        'remote_port': 19994,
      }),
      'stagenet': d(<String, dynamic>{
        'type': 'local',
        'p2p_bind_port': 39993,
        'rpc_bind_port': 39994,
        'zmq_rpc_bind_port': 39995,
      }),
      'testnet': d(<String, dynamic>{
        'type': 'local',
        'p2p_bind_port': 29993,
        'rpc_bind_port': 29994,
        'zmq_rpc_bind_port': 29995,
      }),
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

/// `build_defaults` only (for `set_app_data.defaults`).
Map<String, dynamic> buildDefaultsOnly(ArqmaPaths paths) {
  final Map<String, dynamic> full = buildInitialConfigData(paths);
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
