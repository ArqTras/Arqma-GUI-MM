import 'package:flutter/material.dart';

import '../../app_strings.dart';

/// Shared placeholder for wallet-select flows until each Vue page is ported 1:1.
class WalletSelectStubPage extends StatelessWidget {
  const WalletSelectStubPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w300)),
        const SizedBox(height: 12),
        const Text(AppStrings.walletPagePlaceholder),
      ],
    );
  }
}
