import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Parity with `pages/init/welcome.vue` (first-run wizard — incremental port).
class InitWelcomePage extends StatelessWidget {
  const InitWelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/arq_logo_with_padding.png', width: 280),
            const SizedBox(height: 32),
            const Text(
              'Welcome to Arqma',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/wallet-select'),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
