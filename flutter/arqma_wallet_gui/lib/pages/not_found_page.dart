import 'package:flutter/material.dart';

import '../app_strings.dart';

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text(AppStrings.notFound)),
    );
  }
}
