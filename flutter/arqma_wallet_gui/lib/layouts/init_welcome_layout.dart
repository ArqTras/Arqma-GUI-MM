import 'package:flutter/material.dart';

/// Parity with `layouts/init/welcome.vue`.
class InitWelcomeLayout extends StatelessWidget {
  const InitWelcomeLayout({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: child,
    );
  }
}
