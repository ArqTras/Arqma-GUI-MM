import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_strings.dart';
import '../../core/theme/arqma_colors.dart';
import '../../store/gateway_store.dart';
import '../../widgets/arqma_logo_asset.dart';

/// Parity with `pages/init/index.vue` (icon strip simplified to status text).
class InitIndexPage extends StatelessWidget {
  const InitIndexPage({super.key});

  String _messageForCode(int code) {
    switch (code) {
      case 1:
        return AppStrings.initConnecting;
      case 2:
        return 'Loading configuration…';
      case 3:
        return 'Connecting to daemon…';
      case 4:
        return 'Version check…';
      case 5:
        return 'Daemon not found';
      case 6:
        return AppStrings.initStartingWallet;
      case 7:
        return AppStrings.initReadingWalletList;
      case 8:
        return AppStrings.initRecalculating;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GatewayStore>();
    final code = store.appStatusCode;
    final status = store.app['status'] as Map<String, dynamic>? ?? {};
    final msg = status['message']?.toString();
    final line = code == 4 && (msg != null && msg.isNotEmpty)
        ? msg
        : _messageForCode(code);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const ArqmaLogoAsset(width: 320),
            const SizedBox(height: 32),
            Text(
              line,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16, color: ArqmaColors.textSecondary),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: ArqmaColors.arqmaGreenSolid),
            ),
          ],
        ),
      ),
    );
  }
}
