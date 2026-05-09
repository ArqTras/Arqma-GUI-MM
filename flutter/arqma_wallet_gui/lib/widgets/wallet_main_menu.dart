import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_strings.dart';
import '../core/services/native_bridge.dart';
import '../store/gateway_store.dart';

/// Parity with `components/mainmenu.vue` (settings modal still TODO).
class WalletMainMenu extends StatefulWidget {
  const WalletMainMenu({super.key, this.disableSwitchWallet = false});

  final bool disableSwitchWallet;

  @override
  State<WalletMainMenu> createState() => _WalletMainMenuState();
}

class _WalletMainMenuState extends State<WalletMainMenu> {
  String _version = '';
  String _daemonVersion = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bridge = context.read<NativeBridge>();
      final v = await bridge.invoke('app_version_str');
      final d = await bridge.invoke('daemon_version_probe');
      if (mounted) {
        setState(() {
          _version = v?.toString() ?? '';
          _daemonVersion = d?.toString() ?? '';
        });
      }
    });
  }

  Future<void> _exitWallet(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Exit'),
        content: const Text(AppStrings.confirmClose),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.go('/quit');
      await context.read<NativeBridge>().invoke('confirm_close', {'restart': false});
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu, size: 32, color: Colors.white),
      color: const Color(0xFF1d1d1d),
      onSelected: (String value) async {
        switch (value) {
          case 'switch':
            final go = await showDialog<bool>(
              context: context,
              builder: (BuildContext c) => AlertDialog(
                title: const Text(AppStrings.menuSwitchAccount),
                content: const Text(AppStrings.confirmClose),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Switch')),
                ],
              ),
            );
            if (go == true && context.mounted) {
              final GatewayStore store = context.read<GatewayStore>();
              final NativeBridge bridgeSwitch = context.read<NativeBridge>();
              context.go('/wallet-select');
              unawaited(
                Future<void>.delayed(const Duration(milliseconds: 250), () {
                  store.resetWalletDataDispatch();
                }),
              );
              unawaited(bridgeSwitch.backendSend('wallet', 'close_wallet', {}));
            }
            break;
          case 'settings':
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Daemon settings — UI parity pending')),
            );
            break;
          case 'about':
            final NativeBridge bridgeForAbout = context.read<NativeBridge>();
            await showDialog<void>(
              context: context,
              builder: (BuildContext c) => AlertDialog(
                backgroundColor: const Color(0xFF1d1d1d),
                title: Image.asset('assets/images/arq_logo_with_padding.png', height: 64),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Version: $_version'),
                      Text(_daemonVersion),
                      const SizedBox(height: 8),
                      const Text('Copyright (c) 2018–2025, Arqma Project'),
                      const Text('Copyright (c) 2018–2019, Loki Project'),
                      const Text('Copyright (c) 2018, Ryo Currency Project'),
                      const Text('All rights reserved.'),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () async {
                          await bridgeForAbout.backendSend(
                            'core',
                            'open_url',
                            {'url': 'https://arqma.com/'},
                          );
                        },
                        child: const Text('https://arqma.com/'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text(AppStrings.aboutClose),
                  ),
                ],
              ),
            );
            break;
          case 'exit':
            await _exitWallet(context);
            break;
        }
      },
      itemBuilder: (BuildContext context) => [
        if (!widget.disableSwitchWallet)
          const PopupMenuItem<String>(
            value: 'switch',
            child: Text(AppStrings.menuSwitchAccount),
          ),
        const PopupMenuItem<String>(
          value: 'settings',
          child: Text(AppStrings.menuDaemonSettings),
        ),
        const PopupMenuItem<String>(
          value: 'about',
          child: Text(AppStrings.menuAbout),
        ),
        const PopupMenuItem<String>(
          value: 'exit',
          child: Text(AppStrings.menuExitWallet),
        ),
      ],
    );
  }
}
