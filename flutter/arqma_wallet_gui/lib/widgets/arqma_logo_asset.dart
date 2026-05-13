import 'package:flutter/material.dart';

import '../core/theme/arqma_colors.dart';

/// Central logo [Image.asset] with [errorBuilder] so a missing/corrupt asset never
/// paints Flutter's default red [ErrorWidget] (visible on Windows at startup).
class ArqmaLogoAsset extends StatelessWidget {
  const ArqmaLogoAsset({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.medium,
  });

  static const String assetPath = 'assets/images/arq_logo_with_padding.png';

  final double? width;
  final double? height;
  final BoxFit fit;
  final FilterQuality filterQuality;

  double get _fallbackIconSize {
    final double? w = width;
    final double? h = height;
    if (w != null) {
      return (w * 0.2).clamp(28.0, 88.0);
    }
    if (h != null) {
      return (h * 0.45).clamp(24.0, 64.0);
    }
    return 48;
  }

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      filterQuality: filterQuality,
      errorBuilder: (BuildContext context, Object error, StackTrace? st) => Icon(
        Icons.image_not_supported_outlined,
        size: _fallbackIconSize,
        color: ArqmaColors.textMuted,
      ),
    );
  }
}
