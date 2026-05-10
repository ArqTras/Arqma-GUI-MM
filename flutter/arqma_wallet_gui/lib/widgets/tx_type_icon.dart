import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/locale_controller.dart';
import '../core/theme/arqma_colors.dart';

/// Parity with `components/tx_type_icon.vue` (incoming / outgoing / pending / failed).
class TxTypeIcon extends StatelessWidget {
  const TxTypeIcon({
    super.key,
    required this.type,
    this.tooltip = true,
    this.mainSize = 40,
  });

  final String type;
  final bool tooltip;
  final double mainSize;

  String _tooltipMessage(LocaleController loc) {
    switch (type) {
      case 'in':
        return loc.tr('components.tx_type_icon.incoming_transaction');
      case 'out':
        return loc.tr('components.tx_type_icon.outgoing_transaction');
      case 'pool':
        return loc.tr('components.tx_type_icon.pending_incoming_transaction');
      case 'pending':
        return loc.tr('components.tx_type_icon.pending_outgoing_transaction');
      case 'failed':
        return loc.tr('components.tx_type_icon.failed_transaction');
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final double sub = (mainSize * 0.35).clamp(12, 16);
    final Widget icon = switch (type) {
      'in' => Icon(Icons.call_received,
          size: mainSize, color: ArqmaColors.textSecondary),
      'out' =>
        Icon(Icons.call_made, size: mainSize, color: ArqmaColors.textSecondary),
      'pool' => _Stacked(
          main: Icon(Icons.call_received,
              size: mainSize, color: ArqmaColors.textSecondary),
          sub: Icon(Icons.access_time,
              size: sub, color: ArqmaColors.textSecondary),
        ),
      'pending' => _Stacked(
          main: Icon(Icons.call_made,
              size: mainSize, color: ArqmaColors.textSecondary),
          sub: Icon(Icons.access_time,
              size: sub, color: ArqmaColors.textSecondary),
        ),
      'failed' => Icon(Icons.close, size: mainSize, color: Colors.redAccent),
      _ => Icon(Icons.swap_horiz,
          size: mainSize * 0.75, color: ArqmaColors.textMuted),
    };

    final Widget sized = SizedBox(
      width: 36,
      height: 36,
      child: Center(child: icon),
    );

    if (!tooltip) {
      return sized;
    }
    return Tooltip(
      message: _tooltipMessage(loc),
      child: sized,
    );
  }
}

class _Stacked extends StatelessWidget {
  const _Stacked({required this.main, required this.sub});

  final Widget main;
  final Widget sub;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Transform.translate(offset: const Offset(-4, -4), child: main),
        Positioned(
          right: -2,
          bottom: -3,
          child: sub,
        ),
      ],
    );
  }
}
