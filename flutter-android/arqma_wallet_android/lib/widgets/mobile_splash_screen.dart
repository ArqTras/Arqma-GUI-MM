import 'package:flutter/material.dart';

import '../core/theme/arqma_colors.dart';
import 'arqma_logo_asset.dart';

/// Shown before async bootstrap completes — must paint without GatewayStore / router.
class MobileSplashScreen extends StatelessWidget {
  const MobileSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0E0C09),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 88,
                  color: ArqmaColors.arqmaGreenSolid,
                ),
                SizedBox(height: 20),
                ArqmaLogoAsset(width: 240),
                SizedBox(height: 28),
                Text(
                  'Arqma Wallet',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: ArqmaColors.textPrimary,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Starting…',
                  style: TextStyle(
                    fontSize: 15,
                    color: ArqmaColors.textSecondary,
                  ),
                ),
                SizedBox(height: 28),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ArqmaColors.arqmaGreenSolid,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
