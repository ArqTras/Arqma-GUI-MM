import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/mobile/mobile_app_config.dart';
import '../core/theme/arqma_colors.dart';
import '../store/gateway_store.dart';

/// Shows active remote node and whether JSON-RPC heartbeat is connected.
class MobileRemoteConnectionBanner extends StatelessWidget {
  const MobileRemoteConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final GatewayStore store = context.watch<GatewayStore>();
    final Map<String, dynamic> cfg = effectiveAppConfig(store.app);
    final String node = remoteNodeLabel(cfg);
    if (node.isEmpty) {
      return const SizedBox.shrink();
    }
    final bool ok = store.app['remote_daemon_ok'] == true;
    final Map<String, dynamic> info =
        store.daemon['info'] as Map<String, dynamic>? ?? {};
    final int h = (info['height'] as num?)?.toInt() ?? 0;
    final Color dot = ok && h > 0
        ? ArqmaColors.arqmaGreenSolid
        : ArqmaColors.warning;
    final String status = ok && h > 0
        ? 'Connected · height $h'
        : (ok ? 'Syncing…' : 'Connecting…');

    return Material(
      color: ArqmaColors.darkPanel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cloud_outlined, color: dot, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Remote node',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: ArqmaColors.textMuted,
                        ),
                  ),
                  Text(
                    node,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: ArqmaColors.textPrimary,
                    ),
                  ),
                  Text(
                    status,
                    style: TextStyle(fontSize: 12, color: dot),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
