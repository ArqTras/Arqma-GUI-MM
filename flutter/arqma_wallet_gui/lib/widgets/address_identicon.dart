import 'package:flutter/material.dart';

import '../core/utils/identicon_generator.dart';

/// Visual hash for an address — parity with `components/identicon.vue` (grid + HSL colors).
class AddressIdenticon extends StatelessWidget {
  const AddressIdenticon({
    super.key,
    required this.address,
    this.size = 40,
    this.gridSize = 8,
  });

  final String address;
  final double size;
  final int gridSize;

  @override
  Widget build(BuildContext context) {
    if (!identiconSeedLooksValid(address)) {
      return SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.account_balance_wallet,
            size: size * 0.85, color: const Color(0xFF434343)),
      );
    }
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(size, size),
        painter: _IdenticonPainter(address: address, gridSize: gridSize),
      ),
    );
  }
}

class _IdenticonPainter extends CustomPainter {
  _IdenticonPainter({required this.address, required this.gridSize});

  final String address;
  final int gridSize;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = size.shortestSide;
    paintIdenticon(canvas, address, side, gridSize: gridSize);
  }

  @override
  bool shouldRepaint(covariant _IdenticonPainter oldDelegate) {
    return oldDelegate.address != address || oldDelegate.gridSize != gridSize;
  }
}
