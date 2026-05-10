import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_nav.dart';
import '../layouts/init_loading_layout.dart';
import '../layouts/init_welcome_layout.dart';
import '../layouts/wallet_main_layout.dart';
import '../layouts/wallet_select_layout.dart';
import '../pages/init/init_index_page.dart';
import '../pages/init/init_quit_page.dart';
import '../pages/init/init_welcome_page.dart';
import '../pages/not_found_page.dart';
import '../pages/wallet/addressbook_page.dart';
import '../pages/wallet/receive_page.dart';
import '../pages/wallet/send_page.dart';
import '../pages/wallet/solo_pool_page.dart';
import '../pages/wallet/staking_pools_page.dart';
import '../pages/wallet/swap_page.dart';
import '../pages/wallet/txhistory_page.dart';
import '../pages/wallet_select/wallet_select_created_page.dart';
import '../pages/wallet_select/wallet_select_create_page.dart';
import '../pages/wallet_select/wallet_select_import_legacy_page.dart';
import '../pages/wallet_select/wallet_select_import_old_gui_page.dart';
import '../pages/wallet_select/wallet_select_import_page.dart';
import '../pages/wallet_select/wallet_select_import_view_only_page.dart';
import '../pages/wallet_select/wallet_select_index_page.dart';
import '../pages/wallet_select/wallet_select_restore_page.dart';
import '../store/gateway_store.dart';

GoRouter createAppRouter(GatewayStore store) {
  return GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: '/',
    refreshListenable: store,
    redirect: (BuildContext context, GoRouterState state) {
      final path = state.uri.path;
      if (path == '/' || path.isEmpty) {
        final int c = store.appStatusCode;
        // Ready for wallet list, or recoverable setup error — same landing as Tauri (wallets from config paths first).
        if (c == 0 || c == -1) {
          return '/wallet-select';
        }
      }
      // Wallet layout expects an open account (`wallet.status.code == 0` after `open_wallet`).
      final bool wantsWalletChrome =
          path == '/wallet' || path.startsWith('/wallet/');
      if (wantsWalletChrome) {
        final int walletCode =
            (store.wallet['status'] as Map?)?['code'] as int? ?? 1;
        if (walletCode != 0) {
          return '/wallet-select';
        }
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) {
          return InitLoadingLayout(child: const InitIndexPage());
        },
      ),
      GoRoute(
        path: '/quit',
        builder: (BuildContext context, GoRouterState state) =>
            const InitQuitPage(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (BuildContext context, GoRouterState state) {
          return InitWelcomeLayout(child: const InitWelcomePage());
        },
      ),
      GoRoute(
        path: '/wallet-select',
        builder: (BuildContext context, GoRouterState state) {
          return WalletSelectLayout(child: const WalletSelectIndexPage());
        },
      ),
      GoRoute(
        path: '/wallet-select/create',
        builder: (BuildContext context, GoRouterState state) {
          return WalletSelectLayout(child: const WalletSelectCreatePage());
        },
      ),
      GoRoute(
        path: '/wallet-select/restore',
        builder: (BuildContext context, GoRouterState state) {
          return WalletSelectLayout(child: const WalletSelectRestorePage());
        },
      ),
      GoRoute(
        path: '/wallet-select/import-view-only',
        builder: (BuildContext context, GoRouterState state) {
          return WalletSelectLayout(
              child: const WalletSelectImportViewOnlyPage());
        },
      ),
      GoRoute(
        path: '/wallet-select/import',
        builder: (BuildContext context, GoRouterState state) {
          return WalletSelectLayout(child: const WalletSelectImportPage());
        },
      ),
      GoRoute(
        path: '/wallet-select/import-legacy',
        builder: (BuildContext context, GoRouterState state) {
          return WalletSelectLayout(
              child: const WalletSelectImportLegacyPage());
        },
      ),
      GoRoute(
        path: '/wallet-select/created',
        builder: (BuildContext context, GoRouterState state) {
          return WalletSelectLayout(child: const WalletSelectCreatedPage());
        },
      ),
      GoRoute(
        path: '/wallet-select/import-old-gui',
        builder: (BuildContext context, GoRouterState state) {
          return WalletSelectLayout(
              child: const WalletSelectImportOldGuiPage());
        },
      ),
      GoRoute(
        path: '/wallet',
        builder: (BuildContext context, GoRouterState state) {
          return WalletMainLayout(child: const TxHistoryPage());
        },
      ),
      GoRoute(
        path: '/wallet/receive',
        builder: (BuildContext context, GoRouterState state) {
          return WalletMainLayout(child: const ReceivePage());
        },
      ),
      GoRoute(
        path: '/wallet/send',
        builder: (BuildContext context, GoRouterState state) {
          return WalletMainLayout(child: const SendPage());
        },
      ),
      GoRoute(
        path: '/wallet/swap',
        builder: (BuildContext context, GoRouterState state) {
          return WalletMainLayout(child: const SwapPage());
        },
      ),
      GoRoute(
        path: '/wallet/staking-pools',
        builder: (BuildContext context, GoRouterState state) {
          return WalletMainLayout(child: const StakingPoolsPage());
        },
      ),
      GoRoute(
        path: '/wallet/addressbook',
        builder: (BuildContext context, GoRouterState state) {
          return WalletMainLayout(child: const AddressBookPage());
        },
      ),
      GoRoute(
        path: '/wallet/solo-pool',
        builder: (BuildContext context, GoRouterState state) {
          return WalletMainLayout(child: const SoloPoolPage());
        },
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) =>
        const NotFoundPage(),
  );
}
