import 'package:flutter/material.dart';

import '../../app_strings.dart';

class WalletPageStub extends StatelessWidget {
  const WalletPageStub({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w300)),
        const SizedBox(height: 12),
        const Text(AppStrings.walletPagePlaceholder),
      ],
    );
  }
}
