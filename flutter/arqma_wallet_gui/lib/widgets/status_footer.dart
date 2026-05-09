import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_strings.dart';
import '../core/services/native_bridge.dart';
import '../core/theme/arqma_colors.dart';
import '../store/gateway_store.dart';

/// Parity with `components/footer.vue` (locale picker simplified to EN).
class StatusFooter extends StatefulWidget {
  const StatusFooter({super.key});

  @override
  State<StatusFooter> createState() => _StatusFooterState();
}

class _StatusFooterState extends State<StatusFooter> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final v = await context.read<NativeBridge>().invoke('app_version_str');
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

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GatewayStore>();
        final cfg = store.app['config'] as Map<String, dynamic>? ?? {};
        final net = (cfg['app'] as Map?)?['net_type'] as String?;
        final daemons = cfg['daemons'] as Map<String, dynamic>? ?? {};
        final configDaemon = daemons[net] as Map<String, dynamic>? ?? {'type': 'local'};
        final dtype = configDaemon['type'] as String? ?? 'local';

        final info = store.daemon['info'] as Map<String, dynamic>? ?? {};
        final targetHeight = _daemonChainTip(info);
        final walletHeight = num.tryParse('${store.walletInfo['height']}') ?? 0;

        double daemonLocalPct() {
          if (dtype == 'remote') {
            return 0;
          }
          if (targetHeight == 0) {
            return 0;
          }
          final dwo = num.tryParse('${info['height_without_bootstrap']}') ?? 0;
          var pct = (100 * dwo) / targetHeight;
          if (dwo < targetHeight && (pct * 10).round() / 10 >= 100) {
            pct = 99.9;
          }
          final decimals = pct >= 100 ? 1 : 2;
          return double.parse(pct.clamp(0, 100).toStringAsFixed(decimals));
        }

        double walletPct() {
          if (targetHeight == 0) {
            return 0;
          }
          final pct = (100 * walletHeight) / targetHeight;
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

        final daemonPct = (dtype == 'local' || dtype == 'local_remote') ? daemonLocalPct() : 0.0;
        final wPct = walletPct();

        final walletBlocksLeft = targetHeight == 0 ? 0 : (targetHeight - walletHeight).clamp(0, 1 << 62).toInt();

        bool showBars() {
          if (targetHeight == 0) {
            return false;
          }
          final walletNeeds = walletHeight < targetHeight;
          if (dtype == 'remote') {
            return walletNeeds;
          }
          final dwo = num.tryParse('${info['height_without_bootstrap']}') ?? 0;
          return dwo < targetHeight || walletNeeds;
        }

        String statusText() {
          if (targetHeight == 0) {
            return '';
          }
          final walletBehind = walletHeight < targetHeight;
          final dwo = num.tryParse('${info['height_without_bootstrap']}') ?? 0;
          if (dtype == 'local') {
            if (dwo < targetHeight) {
              return 'SYNCING';
            }
            if (walletBehind) {
              return 'SCANNING';
            }
            return 'READY';
          }
          if (walletBehind) {
            return 'SCANNING';
          }
          if (dtype == 'local_remote' && dwo < targetHeight) {
            return 'SYNCING';
          }
          return 'READY';
        }

        Color statusColor(String s) {
          if (s == 'READY') {
            return ArqmaColors.arqmaGreenSolid;
          }
          if (s == 'SCANNING' || s == 'SYNCING') {
            return Colors.amber.shade600;
          }
          return Colors.white70;
        }

        final st = statusText();
        final dh = targetHeight == 0
            ? (num.tryParse('${info['height_without_bootstrap']}') ?? 0)
            : (num.tryParse('${info['height_without_bootstrap']}') ?? 0)
                .clamp(0, targetHeight);
        final whDisp = targetHeight == 0 ? walletHeight : walletHeight.clamp(0, targetHeight);

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
                      Text('${AppStrings.footerStatus}: '),
                      Text(st, style: TextStyle(color: statusColor(st))),
                    ],
                  ),
                  Text('${AppStrings.footerVersion} $_version'),
                  Text('${AppStrings.footerLanguage}: English'),
                  if (dtype != 'remote')
                    Text('${AppStrings.footerDaemon}: $dh / $targetHeight (${daemonPct.toStringAsFixed(1)}%)'),
                  if (dtype != 'local')
                    Text('${AppStrings.footerRemote}: ${info['height']}'),
                  Text(
                    '${AppStrings.footerWallet}: $whDisp / $targetHeight (${wPct.toStringAsFixed(2)}%)'
                    '${walletBlocksLeft > 0 ? ' · ${AppStrings.footerBlocksLeft.replaceAll('{n}', walletBlocksLeft.toString())}' : ''}',
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
