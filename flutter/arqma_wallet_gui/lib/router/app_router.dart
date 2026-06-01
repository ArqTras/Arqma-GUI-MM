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
import '../pages/wallet_select/wallet_select_created_page.dart';
import '../pages/wallet_select/wallet_select_create_page.dart';
import '../pages/wallet_select/wallet_select_import_legacy_page.dart';
import '../pages/wallet_select/wallet_select_import_old_gui_page.dart';
import '../pages/wallet_select/wallet_select_import_page.dart';
import '../pages/wallet_select/wallet_select_import_view_only_page.dart';
import '../pages/wallet_select/wallet_select_index_page.dart';
import '../pages/wallet_select/wallet_select_restore_page.dart';
import '../store/gateway_router_refresh.dart';
import '../store/gateway_store.dart';

GoRouter createAppRouter(
  GatewayStore store, {
  required GatewayRouterRefreshListenable routerRefresh,
}) {
  return GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: '/',
    refreshListenable: routerRefresh,
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
          return const InitLoadingLayout(child: InitIndexPage());
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
          return const InitWelcomeLayout(child: InitWelcomePage());
        },
      ),
      GoRoute(
        path: '/wallet-select',
        builder: (BuildContext context, GoRouterState state) {
          return const WalletSelectLayout(child: WalletSelectIndexPage());
        },
      ),
      GoRoute(
        path: '/wallet-select/create',
        builder: (BuildContext context, GoRouterState state) {
          return const WalletSelectLayout(child: WalletSelectCreatePage());
        },
      ),
      GoRoute(
        path: '/wallet-select/restore',
        builder: (BuildContext context, GoRouterState state) {
          return const WalletSelectLayout(child: WalletSelectRestorePage());
        },
      ),
      GoRoute(
        path: '/wallet-select/import-view-only',
        builder: (BuildContext context, GoRouterState state) {
          return const WalletSelectLayout(
              child: WalletSelectImportViewOnlyPage());
        },
      ),
      GoRoute(
        path: '/wallet-select/import',
        builder: (BuildContext context, GoRouterState state) {
          return const WalletSelectLayout(child: WalletSelectImportPage());
        },
      ),
      GoRoute(
        path: '/wallet-select/import-legacy',
        builder: (BuildContext context, GoRouterState state) {
          return const WalletSelectLayout(
              child: WalletSelectImportLegacyPage());
        },
      ),
      GoRoute(
        path: '/wallet-select/created',
        builder: (BuildContext context, GoRouterState state) {
          return const WalletSelectLayout(child: WalletSelectCreatedPage());
        },
      ),
      GoRoute(
        path: '/wallet-select/import-old-gui',
        builder: (BuildContext context, GoRouterState state) {
          return const WalletSelectLayout(
              child: WalletSelectImportOldGuiPage());
        },
      ),
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) {
          return const WalletMainLayout();
        },
        routes: <RouteBase>[
          GoRoute(
            path: '/wallet',
            pageBuilder: (BuildContext context, GoRouterState state) {
              return const NoTransitionPage<void>(child: SizedBox.shrink());
            },
            routes: <RouteBase>[
              GoRoute(
                path: 'receive',
                pageBuilder: (BuildContext context, GoRouterState state) {
                  return const NoTransitionPage<void>(child: SizedBox.shrink());
                },
              ),
              GoRoute(
                path: 'send',
                pageBuilder: (BuildContext context, GoRouterState state) {
                  return const NoTransitionPage<void>(child: SizedBox.shrink());
                },
              ),
              GoRoute(
                path: 'swap',
                pageBuilder: (BuildContext context, GoRouterState state) {
                  return const NoTransitionPage<void>(child: SizedBox.shrink());
                },
              ),
              GoRoute(
                path: 'staking-pools',
                pageBuilder: (BuildContext context, GoRouterState state) {
                  return const NoTransitionPage<void>(child: SizedBox.shrink());
                },
              ),
              GoRoute(
                path: 'addressbook',
                pageBuilder: (BuildContext context, GoRouterState state) {
                  return const NoTransitionPage<void>(child: SizedBox.shrink());
                },
              ),
              GoRoute(
                path: 'solo-pool',
                pageBuilder: (BuildContext context, GoRouterState state) {
                  return const NoTransitionPage<void>(child: SizedBox.shrink());
                },
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) =>
        const NotFoundPage(),
  );
}
