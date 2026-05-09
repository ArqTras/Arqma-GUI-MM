import 'package:flutter/material.dart';

/// Parity with `pages/init/quit.vue`.
class InitQuitPage extends StatelessWidget {
  const InitQuitPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Shutting down…', style: TextStyle(color: Colors.white70)),
      ),
    );
  }
}
