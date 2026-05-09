import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/services/native_bridge.dart';
import '../core/theme/arqma_colors.dart';
import '../i18n/locale_controller.dart';
import '../store/gateway_store.dart';

/// Parity with `components/footer.vue` (status + language picker).
class StatusFooter extends StatefulWidget {
  const StatusFooter({super.key});

  @override
  State<StatusFooter> createState() => _StatusFooterState();
}

class _StatusFooterState extends State<StatusFooter> {
  String _version = '';

  static const List<Map<String, String>> _localeOptions = <Map<String, String>>[
    <String, String>{'value': 'en-US', 'label': 'English'},
    <String, String>{'value': 'de-DE', 'label': 'Deutsch'},
    <String, String>{'value': 'fr-FR', 'label': 'Français'},
    <String, String>{'value': 'ua-UA', 'label': 'українська'},
    <String, String>{'value': 'pl-PL', 'label': 'Polski'},
    <String, String>{'value': 'es-ES', 'label': 'Spanish'},
    <String, String>{'value': 'cn-CN', 'label': '中國人'},
    <String, String>{'value': 'jp-JP', 'label': '日本語'},
    <String, String>{'value': 'ms-MY', 'label': 'Bahasa Melayu'},
    <String, String>{'value': 'ar-SA', 'label': 'العربية'},
    <String, String>{'value': 'pt-BR', 'label': 'Português (Brasil)'},
    <String, String>{'value': 'ru-RU', 'label': 'Русский'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final Object? v = await context.read<NativeBridge>().invoke('app_version_str');
      if (mounted) {
        setState(() => _version = v?.toString() ?? '');
      }
    });
  }

  int _daemonChainTip(Map<String, dynamic> info) {
    final h = num.tryParse('${info['height']}') ?? 0;
    final th = num.tryParse('${info['target_height']}') ?? 0;
    return (h > th ? h : th).toInt();
  }

  String _statusText(LocaleController loc, GatewayStore store) {
    final Map<String, dynamic> cfg = store.app['config'] as Map<String, dynamic>? ?? {};
    final String? net = (cfg['app'] as Map?)?['net_type'] as String?;
    final Map<String, dynamic> daemons = cfg['daemons'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> configDaemon = daemons[net] as Map<String, dynamic>? ?? {'type': 'local'};
    final String dtype = configDaemon['type'] as String? ?? 'local';
    final Map<String, dynamic> info = store.daemon['info'] as Map<String, dynamic>? ?? {};
    final int targetHeight = _daemonChainTip(info);
    final num walletHeight = num.tryParse('${store.walletInfo['height']}') ?? 0;
    if (targetHeight == 0) {
      return '';
    }
    final bool walletBehind = walletHeight < targetHeight;
    final num dwo = num.tryParse('${info['height_without_bootstrap']}') ?? 0;
    if (dtype == 'local') {
      if (dwo < targetHeight) {
        return loc.tr('components.footer.syncing');
      }
      if (walletBehind) {
        return loc.tr('components.footer.scanning');
      }
      return loc.tr('components.footer.ready');
    }
    if (walletBehind) {
      return loc.tr('components.footer.scanning');
    }
    if (dtype == 'local_remote' && dwo < targetHeight) {
      return loc.tr('components.footer.syncing');
    }
    return loc.tr('components.footer.ready');
  }

  Color _statusColor(String s, LocaleController loc) {
    final String ready = loc.tr('components.footer.ready');
    if (s == ready) {
      return ArqmaColors.arqmaGreenSolid;
    }
    final String scan = loc.tr('components.footer.scanning');
    final String sync = loc.tr('components.footer.syncing');
    if (s == scan || s == sync) {
      return Colors.amber.shade600;
    }
    return Colors.white70;
  }

  @override
  Widget build(BuildContext context) {
    final GatewayStore store = context.watch<GatewayStore>();
    final LocaleController loc = context.watch<LocaleController>();

    final Map<String, dynamic> cfg = store.app['config'] as Map<String, dynamic>? ?? {};
    final String? net = (cfg['app'] as Map?)?['net_type'] as String?;
    final Map<String, dynamic> daemons = cfg['daemons'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> configDaemon = daemons[net] as Map<String, dynamic>? ?? {'type': 'local'};
    final String dtype = configDaemon['type'] as String? ?? 'local';

    final Map<String, dynamic> info = store.daemon['info'] as Map<String, dynamic>? ?? {};
    final int targetHeight = _daemonChainTip(info);
    final num walletHeight = num.tryParse('${store.walletInfo['height']}') ?? 0;

    double daemonLocalPct() {
      if (dtype == 'remote') {
        return 0;
      }
      if (targetHeight == 0) {
        return 0;
      }
      final num dwo = num.tryParse('${info['height_without_bootstrap']}') ?? 0;
      var pct = (100 * dwo) / targetHeight;
      if (dwo < targetHeight && (pct * 10).round() / 10 >= 100) {
        pct = 99.9;
      }
      final int decimals = pct >= 100 ? 1 : 2;
      return double.parse(pct.clamp(0, 100).toStringAsFixed(decimals));
    }

    double walletPct() {
      if (targetHeight == 0) {
        return 0;
      }
      final num pct = (100 * walletHeight) / targetHeight;
      if (pct >= 100) {
        return double.parse(pct.toStringAsFixed(1)).clamp(0, 100);
      }
      if (walletHeight < targetHeight && pct >= 99) {
        return double.parse(pct.toStringAsFixed(3)).clamp(0, 100);
      }
      return double.parse(pct.toStringAsFixed(2)).clamp(0, 100);
    }

    double barFloor(double pct) {
      if (pct <= 0) {
        return 0;
      }
      if (pct >= 100) {
        return 100;
      }
      return pct < 1 ? 1 : pct;
    }

    final double daemonPct = (dtype == 'local' || dtype == 'local_remote') ? daemonLocalPct() : 0.0;
    final double wPct = walletPct();

    final int walletBlocksLeft = targetHeight == 0 ? 0 : (targetHeight - walletHeight).clamp(0, 1 << 62).toInt();

    bool showBars() {
      if (targetHeight == 0) {
        return false;
      }
      final bool walletNeeds = walletHeight < targetHeight;
      if (dtype == 'remote') {
        return walletNeeds;
      }
      final num dwo = num.tryParse('${info['height_without_bootstrap']}') ?? 0;
      return dwo < targetHeight || walletNeeds;
    }

    final String st = _statusText(loc, store);
    final num dh = targetHeight == 0
        ? (num.tryParse('${info['height_without_bootstrap']}') ?? 0)
        : (num.tryParse('${info['height_without_bootstrap']}') ?? 0).clamp(0, targetHeight);
    final num whDisp = targetHeight == 0 ? walletHeight : walletHeight.clamp(0, targetHeight);

    String selectedLocaleLabel = loc.locale;
    for (final Map<String, String> o in _localeOptions) {
      if (o['value'] == loc.locale) {
        selectedLocaleLabel = o['label']!;
        break;
      }
    }

    return Material(
      color: ArqmaColors.black90,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${loc.tr('components.footer.status')}: '),
                      Text(st, style: TextStyle(color: _statusColor(st, loc))),
                    ],
                  ),
                  Text('${loc.tr('components.footer.version')} $_version'),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${loc.tr('components.footer.language')}: '),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        onSelected: (String v) => context.read<LocaleController>().setLocale(v),
                        itemBuilder: (BuildContext c) => _localeOptions
                            .map(
                              (Map<String, String> o) => PopupMenuItem<String>(
                                value: o['value'],
                                child: Text(o['label']!),
                              ),
                            )
                            .toList(),
                        child: Text(selectedLocaleLabel),
                      ),
                    ],
                  ),
                  if (dtype != 'remote')
                    Text('${loc.tr('components.footer.daemon')}: $dh / $targetHeight (${daemonPct.toStringAsFixed(1)}%)'),
                  if (dtype != 'local')
                    Text('${loc.tr('components.footer.remote')}: ${info['height']}'),
                  Text(
                    '${loc.tr('components.footer.wallet')}: $whDisp / $targetHeight (${wPct.toStringAsFixed(2)}%)'
                    '${walletBlocksLeft > 0 ? ' · ${loc.tr('components.footer.blocks_left', named: {'n': walletBlocksLeft.toString()})}' : ''}',
                  ),
                ],
              ),
            ),
          ),
          if (showBars())
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: [
                  if (dtype != 'remote')
                    _BarTrack(widthPct: barFloor(daemonPct)),
                  _BarTrack(widthPct: barFloor(wPct)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BarTrack extends StatelessWidget {
  const _BarTrack({required this.widthPct});

  final double widthPct;

  @override
  Widget build(BuildContext context) {
    final double f = (widthPct / 100).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      height: 4,
      width: double.infinity,
      decoration: BoxDecoration(
        color: ArqmaColors.barTrack,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: f,
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(colors: [Color(0xFFa89050), Color(0xFFc9a85a), Color(0xFFd4c48a)]),
              boxShadow: [BoxShadow(color: Color(0xFFb49646), blurRadius: 8, spreadRadius: 0)],
            ),
          ),
        ),
      ),
    );
  }
}
