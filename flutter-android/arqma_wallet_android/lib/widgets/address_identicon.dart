import 'package:flutter/material.dart';

import '../core/theme/arqma_colors.dart';

/// Small Arqma logo beside wallet / receive / address-book rows.
/// Keeps the same constructor as the old per-address identicon for drop-in replacement.
class AddressIdenticon extends StatelessWidget {
  const AddressIdenticon({
    super.key,
    required this.address,
    this.size = 40,
    this.gridSize = 8,
  });

  final String address;
  final double size;

  /// Retained for API compatibility with the previous identicon widget.
  final int gridSize;

  static const String _logoAsset = 'assets/images/arq_logo_with_padding.png';

  @override
  Widget build(BuildContext context) {
    final double r = (size * 0.12).clamp(4.0, 10.0);
    return SizedBox(
      key: ValueKey<String>('arq-leading-$address-$size-$gridSize'),
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF12100C),
          borderRadius: BorderRadius.circular(r),
          border: Border.all(
            color: ArqmaColors.outlineDefault.withValues(alpha: 0.45),
            width: 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(size * 0.08),
          child: Image.asset(
            _logoAsset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (BuildContext context, Object error, StackTrace? st) =>
                Icon(
              Icons.account_balance_wallet,
              size: size * 0.65,
              color: ArqmaColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
