import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/mobile/mobile_app_config.dart' as mobile_config;
import '../core/mobile/mobile_version_label.dart';
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
      final String v = await mobileVersionLabel();
      if (mounted) {
        setState(() => _version = v);
      }
    });
  }

  static String _statusText(LocaleController loc, _FooterSnapshot snap) {
    if (!snap.hasOpenWallet) {
      if (snap.daemonType == 'remote') {
        if (!snap.remoteDaemonOk) {
          final String node = snap.remoteNodeLabel;
          if (node.isNotEmpty) {
            return 'Connecting to $node…';
          }
          return loc.tr('pages.init.connecting_to_backend');
        }
        return loc.tr('components.footer.ready');
      }
      return '';
    }

    final int daemonTip = snap.daemonChainTip;
    final num walletHeight = snap.walletHeight;
    final bool fullRescanUi = snap.fullRescanUi;
    final int displayTip = walletDisplayDaemonTip(
      daemonChainTip: daemonTip,
      walletDaemonHeight: snap.walletDaemonHeight,
      walletHeight: walletHeight.toInt(),
    );
    if (displayTip == 0) {
      return loc.tr('components.footer.scanning');
    }
    if (walletHeightScanningBehind(walletHeight.toInt(), displayTip) ||
        fullRescanUi ||
        snap.walletSyncing) {
      return loc.tr('components.footer.scanning');
    }
    final String dtype = snap.daemonType;
    final num dwo = snap.daemonHeightWithoutBootstrap;
    if (dtype == 'local' && daemonTip > 0 && dwo < daemonTip) {
      return loc.tr('components.footer.syncing');
    }
    if (dtype == 'local_remote' && daemonTip > 0 && dwo < daemonTip) {
      return loc.tr('components.footer.syncing');
    }
    if (daemonTip == 0 && walletHeight > 0) {
      return loc.tr('components.footer.syncing');
    }
    return loc.tr('components.footer.synced');
  }

  static Color _statusColor(String s, LocaleController loc) {
    final String ready = loc.tr('components.footer.ready');
    final String synced = loc.tr('components.footer.synced');
    if (s == ready || s == synced) {
      return ArqmaColors.arqmaGreenSolid;
    }
    final String scan = loc.tr('components.footer.scanning');
    final String sync = loc.tr('components.footer.syncing');
    if (s == scan || s == sync) {
      return ArqmaColors.arqmaGreenSolid;
    }
    final String connecting = loc.tr('pages.init.connecting_to_backend');
    if (s == connecting || s.startsWith('Connecting to')) {
      return ArqmaColors.textPrimary;
    }
    return ArqmaColors.textSecondary;
  }

  Future<void> _showLanguageSheet(LocaleController loc) async {
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: ArqmaColors.darkPanel,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final Map<String, String> o in _localeOptions)
                ListTile(
                  title: Text(o['label']!),
                  trailing: o['value'] == loc.locale
                      ? const Icon(Icons.check, color: ArqmaColors.arqmaGreenSolid)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, o['value']),
                ),
              if (loc.locale != 'en-US')
                ListTile(
                  leading: const Icon(Icons.refresh, color: ArqmaColors.warning),
                  title: Text(
                    loc.tr('components.footer.reset_language'),
                    style: const TextStyle(color: ArqmaColors.warning),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'en-US'),
                ),
            ],
          ),
        );
      },
    );
    if (!mounted || picked == null) {
      return;
    }
    await context.read<LocaleController>().setLocale(picked);
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    return Selector<GatewayStore, _FooterSnapshot>(
      selector: (_, GatewayStore store) => _FooterSnapshot.fromStore(store),
      builder: (BuildContext context, _FooterSnapshot snap, Widget? _) {
        final String dtype = snap.daemonType;
        final String nodeLabel = snap.remoteNodeLabel;

        final int daemonTip = snap.daemonChainTip;
        final num walletHeight = snap.walletHeight;
        final bool fullRescanUi = snap.fullRescanUi;
        final int displayTip = walletDisplayDaemonTip(
          daemonChainTip: daemonTip,
          walletDaemonHeight: snap.walletDaemonHeight,
          walletHeight: walletHeight.toInt(),
        );
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
          final num dwo = snap.daemonHeightWithoutBootstrap;
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

        final double daemonPct = (dtype == 'local' || dtype == 'local_remote')
            ? daemonLocalPct()
            : 0.0;
        final double wPct = walletPct();

        final int walletBlocksLeft = walletSyncedForFooter ? 0 : gapBlocks;

        bool showBars() {
          if (displayTip == 0) {
            return false;
          }
          final bool walletNeeds = snap.hasOpenWallet &&
              (fullRescanUi ||
                  walletSyncing ||
                  (!walletSyncedForFooter && walletHeight < displayTip));
          if (dtype == 'remote') {
            return walletNeeds;
          }
          final num dwo = snap.daemonHeightWithoutBootstrap;
          return (daemonTip > 0 && dwo < daemonTip) || walletNeeds;
        }

        final String st = _statusText(loc, snap);
        final num dh = daemonTip == 0
            ? snap.daemonHeightWithoutBootstrap
            : snap.daemonHeightWithoutBootstrap.clamp(0, daemonTip);
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                          Text(st,
                              style: TextStyle(color: _statusColor(st, loc))),
                        ],
                      ),
                      Text(
                        '${loc.tr('components.footer.version')} $_version',
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${loc.tr('components.footer.language')}: '),
                          InkWell(
                            onTap: () => unawaited(_showLanguageSheet(loc)),
                            child: Text(
                              selectedLocaleLabel,
                              style: const TextStyle(
                                decoration: TextDecoration.underline,
                                decorationColor: ArqmaColors.arqmaGreenSolid,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (dtype != 'remote')
                        Text(
                          daemonTip > 0
                              ? '${loc.tr('components.footer.daemon')}: $dh / $daemonTip (${daemonPct.toStringAsFixed(1)}%)'
                              : '${loc.tr('components.footer.daemon')}: $dh / —',
                        ),
                      if (dtype != 'local' && nodeLabel.isNotEmpty)
                        Text(
                          daemonTip > 0
                              ? '${loc.tr('components.footer.remote')}: $nodeLabel · h ${snap.daemonHeight > 0 ? snap.daemonHeight : '—'}'
                              : '${loc.tr('components.footer.remote')}: $nodeLabel',
                        ),
                      if (snap.hasOpenWallet)
                        Text(
                          walletLine,
                          style: const TextStyle(
                            color: ArqmaColors.textPrimary,
                          ),
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
      },
    );
  }
}

final class _FooterSnapshot {
  const _FooterSnapshot({
    required this.remoteDaemonOk,
    required this.daemonHeight,
    required this.daemonTargetHeight,
    required this.daemonHeightWithoutBootstrap,
    required this.walletHeight,
    required this.walletDaemonHeight,
    required this.fullRescanUi,
    required this.walletSyncing,
    required this.hasOpenWallet,
    required this.walletBackend,
    required this.netType,
    required this.daemonType,
    required this.remoteNodeLabel,
  });

  final bool remoteDaemonOk;
  final int daemonHeight;
  final int daemonTargetHeight;
  final int daemonHeightWithoutBootstrap;
  final num walletHeight;
  final int walletDaemonHeight;
  final bool fullRescanUi;
  final bool walletSyncing;
  final bool hasOpenWallet;
  final String walletBackend;
  final String netType;
  final String daemonType;
  final String remoteNodeLabel;

  static _FooterSnapshot fromStore(GatewayStore store) {
    final Map<String, dynamic> app = store.app;
    final Map<String, dynamic> cfg = mobile_config.effectiveAppConfig(app);
    final String net =
        (cfg['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final Map<String, dynamic> configDaemon =
        mobile_config.daemonEntryForNet(cfg, net);
    final Map<String, dynamic> info =
        store.daemon['info'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
    return _FooterSnapshot(
      remoteDaemonOk: app['remote_daemon_ok'] == true,
      daemonHeight: (num.tryParse('${info['height']}') ?? 0).toInt(),
      daemonTargetHeight:
          (num.tryParse('${info['target_height']}') ?? 0).toInt(),
      daemonHeightWithoutBootstrap:
          (num.tryParse('${info['height_without_bootstrap']}') ?? 0).toInt(),
      walletHeight: num.tryParse('${store.walletInfo['height']}') ?? 0,
      walletDaemonHeight:
          (num.tryParse('${store.walletInfo['daemon_height']}') ?? 0).toInt(),
      fullRescanUi: store.walletInfo['full_rescan_ui'] == true,
      walletSyncing: store.walletInfo['wallet_syncing'] == true,
      hasOpenWallet: store.hasOpenWallet,
      walletBackend: '${app['wallet_backend'] ?? 'pending'}',
      netType: net,
      daemonType: configDaemon['type'] as String? ?? 'remote',
      remoteNodeLabel: mobile_config.remoteNodeLabel(cfg),
    );
  }

  int get daemonChainTip {
    return daemonHeight > daemonTargetHeight
        ? daemonHeight
        : daemonTargetHeight;
  }

  @override
  bool operator ==(Object other) {
    return other is _FooterSnapshot &&
        other.remoteDaemonOk == remoteDaemonOk &&
        other.daemonHeight == daemonHeight &&
        other.daemonTargetHeight == daemonTargetHeight &&
        other.daemonHeightWithoutBootstrap == daemonHeightWithoutBootstrap &&
        other.walletHeight == walletHeight &&
        other.walletDaemonHeight == walletDaemonHeight &&
        other.fullRescanUi == fullRescanUi &&
        other.walletSyncing == walletSyncing &&
        other.hasOpenWallet == hasOpenWallet &&
        other.walletBackend == walletBackend &&
        other.netType == netType &&
        other.daemonType == daemonType &&
        other.remoteNodeLabel == remoteNodeLabel;
  }

  @override
  int get hashCode => Object.hash(
        remoteDaemonOk,
        daemonHeight,
        daemonTargetHeight,
        daemonHeightWithoutBootstrap,
        walletHeight,
        walletDaemonHeight,
        fullRescanUi,
        walletSyncing,
        hasOpenWallet,
        walletBackend,
        netType,
        daemonType,
        remoteNodeLabel,
      );
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
