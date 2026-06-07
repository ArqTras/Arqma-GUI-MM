import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../core/desktop/wallet_biometric_unlock.dart';
import '../core/services/native_bridge.dart';
import '../core/theme/arqma_colors.dart';
import '../i18n/locale_controller.dart';
import '../store/gateway_store.dart';
import '../widgets/arqma_logo_asset.dart';
import '../widgets/format_arqma.dart';
import '../widgets/status_footer.dart';
import '../widgets/wallet_main_menu.dart';
import '../widgets/wallet_main_tab_bar.dart';
import '../widgets/wallet_settings_button.dart';
import '../widgets/wallet_tab_body.dart';

/// Parity with `layouts/wallet/main.vue`.
class WalletMainLayout extends StatefulWidget {
  const WalletMainLayout({super.key});

  @override
  State<WalletMainLayout> createState() => _WalletMainLayoutState();
}

class _WalletMainLayoutState extends State<WalletMainLayout>
    with WidgetsBindingObserver {
  static const Duration _inactivityDebounce = Duration(milliseconds: 300);

  static const List<String> _walletTabRoutes = <String>[
    '/wallet',
    '/wallet/send',
    '/wallet/receive',
    '/wallet/staking-pools',
    '/wallet/addressbook',
    '/wallet/solo-pool',
  ];

  Timer? _debounce;
  Timer? _inactivity;
  bool _inactivityPausedForBackground = false;

  /// Updated immediately on tab tap (before [GoRouter] catches up).
  String? _displayedTabPath;

  bool _onHardwareKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      _debouncedArmInactivity();
    }
    return false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final String routerPath = GoRouterState.of(context).uri.path;
    if (_walletTabRoutes.contains(routerPath) || routerPath == '/wallet/swap') {
      if (_displayedTabPath != routerPath) {
        _displayedTabPath = routerPath;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<NativeBridge>().backendSend('wallet', 'get_coin_price', {});
      _debouncedArmInactivity();
      if (WalletBiometricUnlock.isNativeBiometricPlatform) {
        unawaited(WalletBiometricUnlock.flushPendingEnable());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _debounce?.cancel();
    _inactivity?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _pauseInactivityForBackground();
      case AppLifecycleState.resumed:
        _resumeInactivityAfterForeground();
      case AppLifecycleState.detached:
        break;
    }
  }

  void _pauseInactivityForBackground() {
    if (_inactivityPausedForBackground) {
      return;
    }
    _inactivityPausedForBackground = true;
    _debounce?.cancel();
    _debounce = null;
    _inactivity?.cancel();
    _inactivity = null;
  }

  void _resumeInactivityAfterForeground() {
    if (!_inactivityPausedForBackground) {
      return;
    }
    _inactivityPausedForBackground = false;
    if (!mounted) {
      return;
    }
    if (context.read<GatewayStore>().walletInfo['full_rescan_ui'] == true) {
      return;
    }
    _debouncedArmInactivity();
  }

  void _debouncedArmInactivity() {
    if (_inactivityPausedForBackground) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(_inactivityDebounce, _armInactivityTimer);
  }

  int _readInactivityMinutes(GatewayStore store) {
    final Map<String, dynamic>? cfg =
        store.app['config'] as Map<String, dynamic>?;
    final Map<String, dynamic>? appNested =
        cfg?['app'] as Map<String, dynamic>?;
    final dynamic v =
        appNested?['inactivityTimeout'] ?? store.app['inactivityTimeout'];
    final int m = int.tryParse('$v') ?? 5;
    if (m < 1 || m > 31) {
      return 5;
    }
    return m;
  }

  bool _soloPoolServerEnabled(GatewayStore store) {
    final Map<String, dynamic>? cfg =
        store.app['config'] as Map<String, dynamic>?;
    final Map<String, dynamic>? pool = cfg?['pool'] as Map<String, dynamic>?;
    final Map<String, dynamic>? server =
        pool?['server'] as Map<String, dynamic>?;
    return server?['enabled'] == true;
  }

  int _inactivityTimeoutMs(int minutes, bool soloServerEnabled) {
    if (minutes == 31) {
      return soloServerEnabled ? 0 : 30 * 60000;
    }
    return minutes * 60000;
  }

  void _armInactivityTimer() {
    if (!mounted) {
      return;
    }
    final GatewayStore store = context.read<GatewayStore>();
    if (store.walletInfo['full_rescan_ui'] == true) {
      return;
    }
    final int minutes = _readInactivityMinutes(store);
    final bool soloOn = _soloPoolServerEnabled(store);

    _inactivity?.cancel();
    _inactivity = null;

    if (minutes == 31 && soloOn) {
      return;
    }
    final int ms = _inactivityTimeoutMs(minutes, soloOn);
    if (ms <= 0) {
      return;
    }
    _inactivity = Timer(Duration(milliseconds: ms), _onInactivityFired);
  }

  Future<void> _onInactivityFired() async {
    if (!mounted) {
      return;
    }
    final AppLifecycleState? life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) {
      _debouncedArmInactivity();
      return;
    }
    final GatewayStore store = context.read<GatewayStore>();
    if (store.walletInfo['full_rescan_ui'] == true) {
      return;
    }
    if (!store.isAbleToSend) {
      _debouncedArmInactivity();
      return;
    }
    _inactivity?.cancel();
    _inactivity = null;

    final NativeBridge bridge = context.read<NativeBridge>();
    final LocaleController loc = context.read<LocaleController>();
    try {
      final String msg = loc.tr('layouts.wallet.main.wallet_inactivityMessage');
      await Future<void>.delayed(Duration.zero);
      try {
        await bridge
            .backendSend('wallet', 'save_wallet', <String, dynamic>{})
            .timeout(const Duration(seconds: 12));
      } catch (e, st) {
        debugPrint('wallet_main_layout inactivity save_wallet: $e\n$st');
      }
      try {
        await bridge
            .backendSend('wallet', 'close_wallet', <String, dynamic>{})
            .timeout(const Duration(seconds: 22));
      } catch (e, st) {
        debugPrint('wallet_main_layout inactivity close_wallet: $e\n$st');
      }
      if (!mounted) {
        return;
      }
      context.go('/wallet-select');
      appScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          store.resetWalletDataDispatch();
        }),
      );
    } catch (e) {
      appScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
              '${loc.tr('components.mainmenu.switch_account_failed')}: $e'),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  String _resolveActivePath(BuildContext context) {
    final String routerPath = GoRouterState.of(context).uri.path;
    if (_displayedTabPath != null &&
        (_walletTabRoutes.contains(_displayedTabPath) ||
            _displayedTabPath == '/wallet/swap')) {
      return _displayedTabPath!;
    }
    if (_walletTabRoutes.contains(routerPath) || routerPath == '/wallet/swap') {
      return routerPath;
    }
    return '/wallet';
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final String path = _resolveActivePath(context);

    Future<void> refreshPrice() async {
      await context
          .read<NativeBridge>()
          .backendSend('wallet', 'get_coin_price', {});
    }

    void goToWalletTab(String route) {
      final String prev = path;
      if (path != route) {
        setState(() => _displayedTabPath = route);
      }
      if (GoRouterState.of(context).uri.path != route) {
        context.go(route);
      }
      if (route == '/wallet' && prev != '/wallet') {
        unawaited(context
            .read<NativeBridge>()
            .backendSend('wallet', 'refresh_transactions', {}));
      }
    }

    final List<WalletMainTabItem> walletTabs = <WalletMainTabItem>[
      WalletMainTabItem(
        route: '/wallet',
        label: loc.tr('layouts.wallet.main.transactions'),
        icon: Icons.swap_horiz,
      ),
      WalletMainTabItem(
        route: '/wallet/send',
        label: loc.tr('layouts.wallet.main.send'),
        icon: Icons.arrow_right_alt,
      ),
      WalletMainTabItem(
        route: '/wallet/receive',
        label: loc.tr('layouts.wallet.main.receive'),
        icon: Icons.save_alt,
      ),
      WalletMainTabItem(
        route: '/wallet/staking-pools',
        label: loc.tr('layouts.wallet.main.staking_pools'),
        icon: Icons.arrow_right_alt,
      ),
      WalletMainTabItem(
        route: '/wallet/addressbook',
        label: loc.tr('layouts.wallet.main.address_book'),
        icon: Icons.person,
      ),
      WalletMainTabItem(
        route: '/wallet/solo-pool',
        label: loc.tr('components.mainmenu.solo_pool'),
        icon: Icons.engineering,
      ),
    ];

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _debouncedArmInactivity(),
      onPointerMove: (_) => _debouncedArmInactivity(),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 8, top: 5),
                child: ArqmaLogoAsset(height: 52),
              ),
              Expanded(
                child: Selector<GatewayStore, _WalletHeaderSnapshot>(
                  selector: (_, GatewayStore s) =>
                      _WalletHeaderSnapshot.fromStore(s),
                  builder: (BuildContext context, _WalletHeaderSnapshot snap,
                      Widget? _) {
                    return _WalletBalanceHeader(
                      loc: loc,
                      snapshot: snap,
                      onRefreshPrice: refreshPrice,
                    );
                  },
                ),
              ),
            ],
          ),
          actions: const <Widget>[
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: WalletMainMenu(),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(
              height: 1,
              color: ArqmaColors.outlineDefault.withValues(alpha: 0.85),
            ),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: WalletMainTabBar(
                activePath: path,
                tabs: walletTabs,
                onTabTap: goToWalletTab,
                trailing: const WalletSettingsButton(),
              ),
            ),
            const Divider(color: ArqmaColors.dividerLine, height: 24),
            Expanded(
              child: WalletMainTabSwipeNavigator(
                tabRoutes: _walletTabRoutes,
                activePath: path,
                onTabChange: goToWalletTab,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: WalletTabBody(
                    activePath: path,
                    tabRoutes: _walletTabRoutes,
                  ),
                ),
              ),
            ),
            const StatusFooter(),
          ],
        ),
      ),
    );
  }
}

/// Balance / fiat header — isolated from tab body rebuilds.
final class _WalletHeaderSnapshot {
  const _WalletHeaderSnapshot({
    required this.balance,
    required this.unlocked,
    required this.coinPrice,
  });

  final num balance;
  final num unlocked;
  final num coinPrice;

  static _WalletHeaderSnapshot fromStore(GatewayStore store) {
    final Map<String, dynamic> info = store.walletInfo;
    return _WalletHeaderSnapshot(
      balance: num.tryParse('${info['balance'] ?? 0}') ?? 0,
      unlocked: num.tryParse('${info['unlocked_balance'] ?? 0}') ?? 0,
      coinPrice: store.coinPrice,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _WalletHeaderSnapshot &&
        other.balance == balance &&
        other.unlocked == unlocked &&
        other.coinPrice == coinPrice;
  }

  @override
  int get hashCode => Object.hash(balance, unlocked, coinPrice);
}

class _WalletBalanceHeader extends StatelessWidget {
  const _WalletBalanceHeader({
    required this.loc,
    required this.snapshot,
    required this.onRefreshPrice,
  });

  final LocaleController loc;
  final _WalletHeaderSnapshot snapshot;
  final VoidCallback onRefreshPrice;

  @override
  Widget build(BuildContext context) {
    final num balance = snapshot.balance;
    final num unlocked = snapshot.unlocked;
    final num price = snapshot.coinPrice;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (price != 0)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                r'$',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  color: ArqmaColors.arqmaGreenSolid,
                ),
              ),
              FormatArqma(amount: balance * price, digits: 2),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: onRefreshPrice,
                color: ArqmaColors.arqmaGreenSolid,
              ),
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FormatArqma(amount: balance),
              const Text(
                ' ARQ',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w300,
                  color: ArqmaColors.arqmaGreenSolid,
                ),
              ),
            ],
          ),
        if (price != 0)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FormatArqma(amount: balance),
              const Text(
                ' ARQ',
                style: TextStyle(
                    fontSize: 13, color: ArqmaColors.textSecondary),
              ),
            ],
          ),
        if (balance != unlocked)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  loc.tr('layouts.wallet.main.temporarily_locked'),
                  style: const TextStyle(
                      fontSize: 12, color: ArqmaColors.textSecondary),
                ),
                FormatArqma(amount: (balance - unlocked).abs(), digits: 4),
                const Text(
                  ' ARQ',
                  style: TextStyle(
                      fontSize: 12, color: ArqmaColors.textSecondary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
