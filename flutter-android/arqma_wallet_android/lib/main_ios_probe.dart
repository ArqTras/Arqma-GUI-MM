// Temporary iOS render probe — build with:
// flutter build ios --release --target=lib/main_ios_probe.dart
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFFB00020),
        body: Center(
          child: Text(
            'FLUTTER OK',
            style: TextStyle(
              color: Color(0xFFFFEB3B),
              fontSize: 42,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    ),
  );
}
