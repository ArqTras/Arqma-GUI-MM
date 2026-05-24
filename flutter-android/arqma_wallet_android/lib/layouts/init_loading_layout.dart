import 'package:flutter/material.dart';

/// Parity with `layouts/init/loading.vue` (minimal `q-layout` wrapper).
class InitLoadingLayout extends StatelessWidget {
  const InitLoadingLayout({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: child,
    );
  }
}
