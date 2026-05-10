import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'app_nav.dart';
import 'core/app_api.dart';
import 'core/services/app_receiver.dart';
import 'core/services/native_bridge.dart';
import 'core/services/native_bridge_resolver.dart';
import 'core/theme/arqma_theme.dart';
import 'i18n/locale_controller.dart';
import 'router/app_router.dart';
import 'store/gateway_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final LocaleController locale = LocaleController();
  await locale.loadSaved();
  _configureTimeago(locale.locale);

  final GatewayStore store = GatewayStore();
  // Native: MethodChannel embedder when it implements `native_ping`; else desktop I/O + `arqmad`.
  // `ARQMA_FLUTTER_USE_STUB=1` forces in-memory stub.
  final NativeBridge bridge = await resolveAppNativeBridge();

  late final GoRouter router;
  router = createAppRouter(store);

  final AppReceiver receiver = AppReceiver(
    bridge: bridge,
    store: store,
    router: router,
    locale: locale,
  );
  await receiver.start();

  runApp(
    ArqmaWalletApp(
      store: store,
      bridge: bridge,
      router: router,
      receiver: receiver,
      locale: locale,
    ),
  );
}

void _configureTimeago(String normalizedLocale) {
  timeago.setLocaleMessages('en', timeago.EnMessages());
  final String primary = normalizedLocale.split('-').first.toLowerCase();
  switch (primary) {
    case 'pl':
      timeago.setLocaleMessages('pl', timeago.PlMessages());
      break;
    case 'fr':
      timeago.setLocaleMessages('fr', timeago.FrMessages());
      break;
    case 'es':
      timeago.setLocaleMessages('es', timeago.EsMessages());
      break;
    case 'de':
      timeago.setLocaleMessages('de', timeago.DeMessages());
      break;
    case 'ru':
      timeago.setLocaleMessages('ru', timeago.RuMessages());
      break;
    case 'pt':
      timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
      break;
    case 'ja':
    case 'jp':
      timeago.setLocaleMessages('ja', timeago.JaMessages());
      break;
    case 'zh':
    case 'cn':
      timeago.setLocaleMessages('zh_CN', timeago.ZhCnMessages());
      break;
    default:
      break;
  }
}

Locale _flutterLocaleFromTag(String tag) {
  final List<String> p = tag.split('-');
  if (p.length >= 2) {
    return Locale(p[0].toLowerCase(), p[1].toUpperCase());
  }
  return Locale(p[0].toLowerCase());
}

const List<Locale> kAppSupportedLocales = <Locale>[
  Locale('en', 'US'),
  Locale('de', 'DE'),
  Locale('fr', 'FR'),
  Locale('ua', 'UA'),
  Locale('pl', 'PL'),
  Locale('es', 'ES'),
  Locale('cn', 'CN'),
  Locale('jp', 'JP'),
  Locale('ms', 'MY'),
  Locale('ar', 'SA'),
  Locale('pt', 'BR'),
  Locale('ru', 'RU'),
];

class ArqmaWalletApp extends StatefulWidget {
  const ArqmaWalletApp({
    super.key,
    required this.store,
    required this.bridge,
    required this.router,
    required this.receiver,
    required this.locale,
  });

  final GatewayStore store;
  final NativeBridge bridge;
  final GoRouter router;
  final AppReceiver receiver;
  final LocaleController locale;

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
        ChangeNotifierProvider<LocaleController>.value(value: widget.locale),
        Provider<NativeBridge>.value(value: widget.bridge),
        ProxyProvider2<NativeBridge, GatewayStore, AppApi>(
          update:
              (BuildContext _, NativeBridge b, GatewayStore s, AppApi? __) =>
                  AppApi(b, s),
        ),
      ],
      child: Consumer<LocaleController>(
        builder: (BuildContext context, LocaleController loc, _) {
          return MaterialApp.router(
            title: 'Arqma Wallet',
            debugShowCheckedModeBanner: false,
            theme: buildArqmaTheme(),
            routerConfig: widget.router,
            scaffoldMessengerKey: appScaffoldMessengerKey,
            locale: _flutterLocaleFromTag(loc.locale),
            supportedLocales: kAppSupportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          );
        },
      ),
    );
  }
}
