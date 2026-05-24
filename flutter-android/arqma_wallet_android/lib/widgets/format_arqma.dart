import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Same units as `components/format_arqma.vue` (1 ARQ = 1e9 atomic units).
class FormatArqma extends StatelessWidget {
  const FormatArqma({
    super.key,
    required this.amount,
    this.round = false,
    this.digits = 9,
    this.asWei = false,
    this.textColor,
  });

  final num amount;
  final bool round;
  final int digits;
  final bool asWei;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      color: textColor ?? Theme.of(context).colorScheme.onSurface,
    );
    if (asWei) {
      return Text(NumberFormat.decimalPattern().format(amount), style: style);
    }
    const coinUnits = 1000000000;
    double val = amount / coinUnits;
    if (round) {
      val = double.parse(val.toStringAsFixed(digits));
    }
    final fmt = NumberFormat.decimalPattern()
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = digits;
    return Text(fmt.format(val), style: style);
  }
}
