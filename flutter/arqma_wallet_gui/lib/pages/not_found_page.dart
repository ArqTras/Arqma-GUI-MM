import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../i18n/locale_controller.dart';
import '../core/theme/arqma_colors.dart';

/// Parity with `pages/404.vue` (unknown route) + localized copy.
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(loc.tr('pages.not_found.title'),
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                loc.tr('pages.not_found.hint'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: ArqmaColors.textSecondary),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/'),
                child: Text(loc.tr('pages.not_found.go_home')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
