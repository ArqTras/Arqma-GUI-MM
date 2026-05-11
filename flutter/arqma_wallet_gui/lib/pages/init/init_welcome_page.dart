import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_api.dart';
import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
import '../../widgets/settings_general_panel.dart';

/// Parity with `pages/init/welcome.vue` (stepper + `SettingsGeneral`).
class InitWelcomePage extends StatefulWidget {
  const InitWelcomePage({super.key});

  @override
  State<InitWelcomePage> createState() => _InitWelcomePageState();
}

class _InitWelcomePageState extends State<InitWelcomePage> {
  int _step = 1;
  final GlobalKey<SettingsGeneralPanelState> _settingsKey =
      GlobalKey<SettingsGeneralPanelState>();
  String _version = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final AppApi api = context.read<AppApi>();
      final GatewayStore store = context.read<GatewayStore>();
      final Object? v = await api.invoke('app_version_str');
      if (mounted) {
        setState(() => _version = v?.toString() ?? '');
        store.setAppData(<String, dynamic>{
          'status': <String, dynamic>{'code': 2},
        });
      }
    });
  }

  Future<void> _next() async {
    if (_step == 2) {
      await _settingsKey.currentState?.applySaveInit();
      if (!mounted) {
        return;
      }
      // Do not reset `app.status` to code 1 here: that shows "Connecting to backend…" and
      // `AppReceiver` will not run `core::init` again (`_initRequested` is already true).
      // `save_config_init` + backend restart already emitted the correct status/config.
      context.go('/');
    } else {
      setState(() => _step = 2);
    }
  }

  void _back() {
    if (_step > 1) {
      setState(() => _step = 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final String daemonVersion =
        '${context.watch<GatewayStore>().raw['daemon_version'] ?? ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_step == 1
                  ? loc.tr('pages.welcome.step_one')
                  : loc.tr('pages.welcome.step_two')),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _step - 1,
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/images/arq_logo_with_padding.png',
                          height: 100),
                      const SizedBox(height: 12),
                      Text(
                        '${loc.tr('pages.welcome.version')}: $_version',
                        textAlign: TextAlign.center,
                      ),
                      if (daemonVersion.isNotEmpty)
                        Text(daemonVersion, textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _next,
                        child: Text(loc.tr('pages.welcome.load_wallet')),
                      ),
                    ],
                  ),
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SettingsGeneralPanel(key: _settingsKey),
              ),
            ],
          ),
        ),
        if (_step > 1)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: _back,
                    child: Text(loc.tr('pages.welcome.button_back'))),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: _next,
                    child: Text(loc.tr('pages.welcome.button_next'))),
              ],
            ),
          ),
      ],
    );
  }
}
