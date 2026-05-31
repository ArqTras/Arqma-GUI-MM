import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/desktop/desktop_app_exit.dart';
import '../core/services/native_bridge.dart';
import '../core/theme/arqma_colors.dart';
import '../i18n/locale_controller.dart';
import '../store/gateway_store.dart';
import 'arqma_logo_asset.dart';
import 'daemon_settings_dialog.dart';

/// Parity with `components/mainmenu.vue` (settings via [showDaemonSettingsDialog]).
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
    final LocaleController loc = context.read<LocaleController>();
    final NativeBridge bridge = context.read<NativeBridge>();
    pauseBridgeTimersForExit(bridge);
    await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (BuildContext c) => AlertDialog(
        title: Text(loc.tr('components.mainmenu.exit_wallet')),
        content: Text(loc.tr('components.mainmenu.confirm_close')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(loc.tr('composables.cancel'))),
          TextButton(
            onPressed: () => confirmDesktopExitFromDialog(c, bridge),
            child: Text(loc.tr('components.mainmenu.exit_wallet')),
          ),
        ],
      ),
    );
    // Exit confirmed via [confirmDesktopExitFromDialog] in the dialog button handler.
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    return PopupMenuButton<String>(
      useRootNavigator: true,
      icon: const Icon(Icons.menu, size: 28, color: ArqmaColors.arqmaGreenSolid),
      padding: EdgeInsets.zero,
      color: ArqmaColors.darkPanel,
      onSelected: (String value) async {
        switch (value) {
          case 'switch':
            final go = await showDialog<bool>(
              context: context,
              useRootNavigator: true,
              builder: (BuildContext c) => AlertDialog(
                title: Text(loc.tr('components.mainmenu.switch_account')),
                content: Text(loc.tr('components.mainmenu.confirm_close')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text(loc.tr(
                          'components.mainmenu.switch_account_cancel_label'))),
                  TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(loc
                          .tr('components.mainmenu.switch_account_ok_label'))),
                ],
              ),
            );
            if (go == true && context.mounted) {
              final GatewayStore store = context.read<GatewayStore>();
              final NativeBridge bridgeSwitch = context.read<NativeBridge>();
              await Future<void>.delayed(Duration.zero);
              try {
                await bridgeSwitch
                    .backendSend('wallet', 'save_wallet', <String, dynamic>{})
                    .timeout(const Duration(seconds: 12));
              } catch (e, st) {
                debugPrint('[WalletMainMenu] switch save_wallet: $e\n$st');
              }
              try {
                await bridgeSwitch
                    .backendSend('wallet', 'close_wallet', <String, dynamic>{})
                    .timeout(const Duration(seconds: 3));
              } catch (e, st) {
                debugPrint('[WalletMainMenu] switch close_wallet: $e\n$st');
              }
              if (!context.mounted) {
                break;
              }
              context.go('/wallet-select');
              unawaited(
                Future<void>.delayed(const Duration(milliseconds: 250), () {
                  store.resetWalletDataDispatch();
                }),
              );
            }
            break;
          case 'settings':
            await showDaemonSettingsDialog(context);
            break;
          case 'about':
            final NativeBridge bridgeForAbout = context.read<NativeBridge>();
            await showDialog<void>(
              context: context,
              useRootNavigator: true,
              builder: (BuildContext c) => AlertDialog(
                backgroundColor: ArqmaColors.darkPanel,
                title: const ArqmaLogoAsset(height: 64),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Version: $_version'),
                      Text(_daemonVersion),
                      const SizedBox(height: 8),
                      const Text('Copyright (c) 2018–2026, Arqma Project'),
                      const Text('All rights reserved.'),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () async {
                          await bridgeForAbout.backendSend(
                            'core',
                            'open_url',
                            <String, dynamic>{'url': 'https://arqma.com/'},
                          );
                        },
                        child: const Text('https://arqma.com/'),
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () async {
                              await bridgeForAbout.backendSend(
                                'core',
                                'open_url',
                                <String, dynamic>{
                                  'url': 'https://chat.arqma.com'
                                },
                              );
                            },
                            child: const Text('Discord'),
                          ),
                          const Text('—',
                              style: TextStyle(color: ArqmaColors.textMuted)),
                          TextButton(
                            onPressed: () async {
                              await bridgeForAbout.backendSend(
                                'core',
                                'open_url',
                                <String, dynamic>{
                                  'url': 'https://telegram.arqma.com'
                                },
                              );
                            },
                            child: const Text('Telegram'),
                          ),
                          const Text('—',
                              style: TextStyle(color: ArqmaColors.textMuted)),
                          TextButton(
                            onPressed: () async {
                              await bridgeForAbout.backendSend(
                                'core',
                                'open_url',
                                <String, dynamic>{
                                  'url': 'https://github.com/Arqma/Arqma'
                                },
                              );
                            },
                            child: const Text('GitHub'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: Text(loc.tr('components.wallet_settings.close')),
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
          PopupMenuItem<String>(
            value: 'switch',
            child: Text(loc.tr('components.mainmenu.switch_account')),
          ),
        PopupMenuItem<String>(
          value: 'settings',
          child: Text(loc.tr('components.mainmenu.daemon_settings')),
        ),
        PopupMenuItem<String>(
          value: 'about',
          child: Text(loc.tr('components.mainmenu.about')),
        ),
        PopupMenuItem<String>(
          value: 'exit',
          child: Text(loc.tr('components.mainmenu.exit_wallet')),
        ),
      ],
    );
  }
}
