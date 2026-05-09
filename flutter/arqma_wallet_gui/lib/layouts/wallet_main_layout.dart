import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../core/services/native_bridge.dart';
import '../core/theme/arqma_colors.dart';
import '../i18n/locale_controller.dart';
import '../store/gateway_store.dart';
import '../widgets/format_arqma.dart';
import '../widgets/status_footer.dart';
import '../widgets/wallet_main_menu.dart';
import '../widgets/wallet_settings_button.dart';

/// Parity with `layouts/wallet/main.vue`.
class WalletMainLayout extends StatefulWidget {
  const WalletMainLayout({super.key, required this.child});

  final Widget child;

  @override
  State<WalletMainLayout> createState() => _WalletMainLayoutState();
}

class _WalletMainLayoutState extends State<WalletMainLayout> {
  static const Duration _inactivityDebounce = Duration(milliseconds: 300);

  Timer? _debounce;
  Timer? _inactivity;

  bool _onHardwareKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      _debouncedArmInactivity();
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<NativeBridge>().backendSend('wallet', 'get_coin_price', {});
      _debouncedArmInactivity();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _debounce?.cancel();
    _inactivity?.cancel();
    super.dispose();
  }

  void _debouncedArmInactivity() {
    _debounce?.cancel();
    _debounce = Timer(_inactivityDebounce, _armInactivityTimer);
  }

  int _readInactivityMinutes(GatewayStore store) {
    final Map<String, dynamic>? cfg = store.app['config'] as Map<String, dynamic>?;
    final Map<String, dynamic>? appNested = cfg?['app'] as Map<String, dynamic>?;
    final dynamic v = appNested?['inactivityTimeout'] ?? store.app['inactivityTimeout'];
    final int m = int.tryParse('$v') ?? 5;
    if (m < 1 || m > 31) {
      return 5;
    }
    return m;
  }

  bool _soloPoolServerEnabled(GatewayStore store) {
    final Map<String, dynamic>? cfg = store.app['config'] as Map<String, dynamic>?;
    final Map<String, dynamic>? pool = cfg?['pool'] as Map<String, dynamic>?;
    final Map<String, dynamic>? server = pool?['server'] as Map<String, dynamic>?;
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

  void _onInactivityFired() {
    if (!mounted) {
      return;
    }
    final GatewayStore store = context.read<GatewayStore>();
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
      context.go('/wallet-select');
      appScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          store.resetWalletDataDispatch();
        }),
      );
      unawaited(
        bridge.backendSend('wallet', 'close_wallet', {}).catchError((Object e, StackTrace st) {
          debugPrint('wallet_main_layout inactivity close_wallet: $e');
        }),
      );
    } catch (e) {
      appScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('${loc.tr('components.mainmenu.switch_account_failed')}: $e'),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GatewayStore>();
    final LocaleController loc = context.watch<LocaleController>();
    final path = GoRouterState.of(context).uri.path;
    final price = store.coinPrice;
    final info = store.walletInfo;
    final balance = num.tryParse('${info['balance'] ?? 0}') ?? 0;
    final unlocked = num.tryParse('${info['unlocked_balance'] ?? 0}') ?? 0;

    Future<void> refreshPrice() async {
      await context.read<NativeBridge>().backendSend('wallet', 'get_coin_price', {});
    }

    Widget navBtn(String route, String label, IconData icon) {
      final active = path == route;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: active ? ArqmaColors.arqmaGreenSolid : ArqmaColors.arqmaGreenDarkSolid,
            foregroundColor: Colors.black87,
            minimumSize: const Size(100, 44),
          ),
          onPressed: () => context.go(route),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const SizedBox(width: 6),
              Icon(icon, size: 18),
            ],
          ),
        ),
      );
    }

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
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 5),
              child: Image.asset('assets/images/arq_logo_with_padding.png', height: 52),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (price != 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(r'$', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300)),
                        FormatArqma(amount: balance * price, digits: 2),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: refreshPrice,
                          color: Colors.white70,
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FormatArqma(amount: balance),
                        const Text(' ARQ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300)),
                      ],
                    ),
                  if (price != 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FormatArqma(amount: balance),
                        const Text(' ARQ', style: TextStyle(fontSize: 13, color: Colors.white70)),
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
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                          FormatArqma(amount: (balance - unlocked).abs(), digits: 4),
                          const Text(' ARQ', style: TextStyle(fontSize: 12, color: Colors.white70)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: WalletMainMenu(),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.white),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  navBtn('/wallet', loc.tr('layouts.wallet.main.transactions'), Icons.swap_horiz),
                  navBtn('/wallet/send', loc.tr('layouts.wallet.main.send'), Icons.arrow_right_alt),
                  navBtn('/wallet/receive', loc.tr('layouts.wallet.main.receive'), Icons.save_alt),
                  // Swap route exists (`/wallet/swap`) but the main nav button is commented out in `layouts/wallet/main.vue`.
                  navBtn('/wallet/staking-pools', loc.tr('layouts.wallet.main.staking_pools'), Icons.arrow_right_alt),
                  navBtn('/wallet/addressbook', loc.tr('layouts.wallet.main.address_book'), Icons.person),
                  navBtn('/wallet/solo-pool', loc.tr('components.mainmenu.solo_pool'), Icons.engineering),
                  const WalletSettingsButton(),
                ],
              ),
            ),
          ),
          const Divider(color: Colors.white24, height: 24),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: widget.child,
            ),
          ),
          const StatusFooter(),
        ],
      ),
    ),
    );
  }
}
