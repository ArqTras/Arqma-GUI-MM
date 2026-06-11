import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/desktop/daemon_rpc_transport.dart';
import '../core/services/native_bridge.dart';
import '../core/wallet_daemon_tip_tolerance.dart';
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

  static String _walletBackendSuffix(String? wb) {
    switch (wb) {
      case 'ffi':
        return '+wallet-ffi';
      case 'none':
        return '+wallet-off';
      case 'off':
        return '+wallet-disabled';
      default:
        return '';
    }
  }

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
      final Object? v =
          await context.read<NativeBridge>().invoke('app_version_str');
      if (mounted) {
        setState(() => _version = v?.toString() ?? '');
      }
    });
  }

  static String _configLocalDaemonBind(Map<String, dynamic> configDaemon) {
    final String h = configDaemon['rpc_bind_ip'] as String? ?? '127.0.0.1';
    final int p = (configDaemon['rpc_bind_port'] as num?)?.toInt() ?? 19994;
    return '$h:$p';
  }

  static String? _walletEffectiveDaemonLabel(
    Map<String, dynamic> app,
    Map<String, dynamic> configDaemon,
  ) {
    final String configured = _configLocalDaemonBind(configDaemon);
    final String? effective = app['wallet_daemon_address'] as String?;
    if (effective == null || effective.isEmpty || effective == configured) {
      return null;
    }
    return effective;
  }

  static int _daemonChainTip(Map<String, dynamic> info) {
    final h = num.tryParse('${info['height']}') ?? 0;
    final th = num.tryParse('${info['target_height']}') ?? 0;
    return (h > th ? h : th).toInt();
  }

  static String _statusText(LocaleController loc, _FooterSnapshot snap) {
    final Map<String, dynamic> cfg =
        snap.app['config'] as Map<String, dynamic>? ?? {};
    // `daemons[null]` yields no RPC entry when `net_type` is missing — match Rust default `mainnet`.
    final String net =
        (cfg['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final Map<String, dynamic> daemons =
        cfg['daemons'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> configDaemon =
        daemons[net] as Map<String, dynamic>? ?? {'type': 'local'};
    final String dtype = configDaemon['type'] as String? ?? 'local';
    final Map<String, dynamic> info = snap.daemonInfo;
    final int daemonTip = _daemonChainTip(info);
    final num walletHeight = snap.walletHeight;
    final bool fullRescanUi = snap.fullRescanUi;
    final int displayTip = daemonTip > 0
        ? daemonTip
        : (walletHeight > 0 ? walletHeight.toInt() : 0);
    if (displayTip == 0) {
      return '';
    }
    final bool walletSyncing = snap.walletSyncing;
    final bool walletBehind = walletHeightScanningBehind(
          walletHeight.toInt(),
          displayTip,
        ) ||
        fullRescanUi ||
        walletSyncing;
    final bool walletBehindOrRescan = walletBehind;
    final num dwo = num.tryParse('${info['height_without_bootstrap']}') ?? 0;
    if (dtype == 'local') {
      if (daemonTip > 0 && dwo < daemonTip) {
        return loc.tr('components.footer.syncing');
      }
      if (walletBehindOrRescan) {
        return loc.tr('components.footer.scanning');
      }
      if (daemonTip == 0 && walletHeight > 0) {
        return loc.tr('components.footer.syncing');
      }
      return loc.tr('components.footer.ready');
    }
    if (walletBehindOrRescan) {
      return loc.tr('components.footer.scanning');
    }
    if (dtype == 'local_remote' && daemonTip > 0 && dwo < daemonTip) {
      return loc.tr('components.footer.syncing');
    }
    return loc.tr('components.footer.ready');
  }

  static Color _statusColor(String s, LocaleController loc) {
    final String ready = loc.tr('components.footer.ready');
    if (s == ready) {
      return ArqmaColors.arqmaGreenSolid;
    }
    final String scan = loc.tr('components.footer.scanning');
    final String sync = loc.tr('components.footer.syncing');
    if (s == scan || s == sync) {
      return ArqmaColors.warning;
    }
    return ArqmaColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    return Selector<GatewayStore, _FooterSnapshot>(
      selector: (_, GatewayStore store) => _FooterSnapshot.fromStore(store),
      builder: (BuildContext context, _FooterSnapshot snap, Widget? _) {
        final Map<String, dynamic> app = snap.app;
        final String wb = snap.walletBackend;
        final Map<String, dynamic> cfg =
            app['config'] as Map<String, dynamic>? ?? {};
        final String net =
            (cfg['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
        final Map<String, dynamic> daemons =
            cfg['daemons'] as Map<String, dynamic>? ?? {};
        final Map<String, dynamic> configDaemon =
            daemons[net] as Map<String, dynamic>? ?? {'type': 'local'};
        final String dtype = configDaemon['type'] as String? ?? 'local';

        final Map<String, dynamic> info = snap.daemonInfo;
        final int daemonTip = _daemonChainTip(info);
        final num walletHeight = snap.walletHeight;
        final bool fullRescanUi = snap.fullRescanUi;
    final int displayTip = daemonTip > 0
        ? daemonTip
        : (walletHeight > 0 ? walletHeight.toInt() : 0);
    final int gapBlocks = displayTip > 0
        ? (displayTip - walletHeight.toInt()).clamp(0, 1 << 62)
        : 0;
    final bool walletSyncing = snap.walletSyncing;
    final bool walletSyncedForFooter = displayTip > 0 &&
        gapBlocks <= kWalletDaemonTipToleranceBlocks &&
        !fullRescanUi &&
        !walletSyncing;

    double daemonLocalPct() {
      if (dtype == 'remote') {
        return 0;
      }
      if (daemonTip == 0) {
        return 0;
      }
      final num dwo = num.tryParse('${info['height_without_bootstrap']}') ?? 0;
      var pct = (100 * dwo) / daemonTip;
      if (dwo < daemonTip && (pct * 10).round() / 10 >= 100) {
        pct = 99.9;
      }
      final int decimals = pct >= 100 ? 1 : 2;
      return double.parse(pct.clamp(0, 100).toStringAsFixed(decimals));
    }

    double walletPct() {
      if (displayTip == 0) {
        return 0;
      }
      if (walletSyncedForFooter) {
        return 100;
      }
      return walletScanProgressPercent(
        walletHeight.toInt(),
        displayTip,
      );
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

    final double daemonPct =
        (dtype == 'local' || dtype == 'local_remote') ? daemonLocalPct() : 0.0;
    final double wPct = walletPct();

    final int walletBlocksLeft = walletSyncedForFooter ? 0 : gapBlocks;

    bool showBars() {
      if (displayTip == 0) {
        return false;
      }
      final bool walletNeeds = fullRescanUi ||
          walletSyncing ||
          (!walletSyncedForFooter && walletHeight < displayTip);
      if (dtype == 'remote') {
        return walletNeeds;
      }
      final num dwo = num.tryParse('${info['height_without_bootstrap']}') ?? 0;
      return (daemonTip > 0 && dwo < daemonTip) || walletNeeds;
    }

    final String st = _statusText(loc, snap);
    final String? walletNode =
        _walletEffectiveDaemonLabel(snap.app, configDaemon);
    final num dh = daemonTip == 0
        ? (num.tryParse('${info['height_without_bootstrap']}') ?? 0)
        : (num.tryParse('${info['height_without_bootstrap']}') ?? 0)
            .clamp(0, daemonTip);
    final num whDisp = displayTip == 0
        ? walletHeight
        : (walletSyncedForFooter
            ? displayTip
            : walletHeight.clamp(0, displayTip));
    final String walletLine =
        '${loc.tr('components.footer.wallet')}: $whDisp / $displayTip (${wPct.toStringAsFixed(2)}%)'
            '${walletBlocksLeft > 0 ? ' · ${loc.tr('components.footer.blocks_left', named: {
                  'n': walletBlocksLeft.toString()
                })}' : ''}';
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
                fontWeight: FontWeight.w600,
                color: ArqmaColors.arqmaGreenSolid,
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
                  Text(
                    '${loc.tr('components.footer.version')} $_version${_walletBackendSuffix(wb == 'pending' ? null : wb)}',
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${loc.tr('components.footer.language')}: '),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        useRootNavigator: true,
                        color: ArqmaColors.darkPanel,
                        onSelected: (String v) =>
                            context.read<LocaleController>().setLocale(v),
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
                    Text(
                      daemonTip > 0
                          ? '${loc.tr('components.footer.daemon')}: $dh / $daemonTip (${daemonPct.toStringAsFixed(1)}%)'
                          : '${loc.tr('components.footer.daemon')}: $dh / —',
                    ),
                  if (walletNode != null)
                    Text(
                      '${loc.tr('components.footer.remote')}: $walletNode',
                    ),
                  if (configUsesRemoteCleartextRpc(configDaemon))
                    Text(
                      loc.tr('components.footer.cleartext_remote_warning'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: ArqmaColors.warning,
                      ),
                    ),
                  if (dtype != 'local')
                    Text(
                        '${loc.tr('components.footer.remote')}: ${info['height']}'),
                  Text(walletLine),
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
      },
    );
  }
}

final class _FooterSnapshot {
  const _FooterSnapshot({
    required this.app,
    required this.daemonInfo,
    required this.walletHeight,
    required this.fullRescanUi,
    required this.walletSyncing,
    required this.walletBackend,
  });

  final Map<String, dynamic> app;
  final Map<String, dynamic> daemonInfo;
  final num walletHeight;
  final bool fullRescanUi;
  final bool walletSyncing;
  final String walletBackend;

  static _FooterSnapshot fromStore(GatewayStore store) {
    return _FooterSnapshot(
      app: store.app,
      daemonInfo: store.daemon['info'] as Map<String, dynamic>? ??
          const <String, dynamic>{},
      walletHeight: num.tryParse('${store.walletInfo['height']}') ?? 0,
      fullRescanUi: store.walletInfo['full_rescan_ui'] == true,
      walletSyncing: store.walletInfo['wallet_syncing'] == true,
      walletBackend: '${store.app['wallet_backend'] ?? 'pending'}',
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _FooterSnapshot &&
        identical(other.app, app) &&
        identical(other.daemonInfo, daemonInfo) &&
        other.walletHeight == walletHeight &&
        other.fullRescanUi == fullRescanUi &&
        other.walletSyncing == walletSyncing &&
        other.walletBackend == walletBackend;
  }

  @override
  int get hashCode => Object.hash(
      app, daemonInfo, walletHeight, fullRescanUi, walletSyncing, walletBackend);
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
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFa89050),
                  Color(0xFFc9a85a),
                  Color(0xFFd4c48a)
                ],
              ),
              boxShadow: const [
                BoxShadow(
                    color: Color(0xFFb49646), blurRadius: 8, spreadRadius: 0)
              ],
            ),
          ),
        ),
      ),
    );
  }
}
