import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/services/app_receiver.dart';
import 'core/services/native_bridge.dart';
import 'core/theme/arqma_theme.dart';
import 'router/app_router.dart';
import 'store/gateway_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final GatewayStore store = GatewayStore();
  final NativeBridge bridge = kDebugMode ? StubNativeBridge() : MethodChannelNativeBridge();

  late final GoRouter router;
  router = createAppRouter(store);

  final AppReceiver receiver = AppReceiver(bridge: bridge, store: store, router: router);
  await receiver.start();

  runApp(ArqmaWalletApp(store: store, bridge: bridge, router: router, receiver: receiver));
}

class ArqmaWalletApp extends StatefulWidget {
  const ArqmaWalletApp({
    super.key,
    required this.store,
    required this.bridge,
    required this.router,
    required this.receiver,
  });

  final GatewayStore store;
  final NativeBridge bridge;
  final GoRouter router;
  final AppReceiver receiver;

  @override
  State<ArqmaWalletApp> createState() => _ArqmaWalletAppState();
}

class _ArqmaWalletAppState extends State<ArqmaWalletApp> {
  @override
  void dispose() {
    widget.receiver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<GatewayStore>.value(value: widget.store),
        Provider<NativeBridge>.value(value: widget.bridge),
      ],
      child: MaterialApp.router(
        title: 'Arqma Wallet',
        debugShowCheckedModeBanner: false,
        theme: buildArqmaTheme(),
        routerConfig: widget.router,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'US')],
      ),
    );
  }
}
