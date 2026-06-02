import 'package:flutter/material.dart';

import 'arqma_field.dart';

/// Restore-from date / block-height field with mode toggle.
/// Stacks vertically on narrow screens (e.g. iPhone 15) instead of squeezing a [Row].
class WalletRestoreRefreshControls extends StatelessWidget {
  const WalletRestoreRefreshControls({
    super.key,
    required this.refreshType,
    required this.refreshStartDate,
    required this.refreshHeightController,
    required this.dateLabel,
    required this.heightLabel,
    required this.switchToHeightLabel,
    required this.switchToDateLabel,
    required this.onPickDate,
    required this.onSwitchToHeight,
    required this.onSwitchToDate,
    this.narrowBreakpoint = 420,
  });

  final String refreshType;
  final String refreshStartDate;
  final TextEditingController refreshHeightController;
  final String dateLabel;
  final String heightLabel;
  final String switchToHeightLabel;
  final String switchToDateLabel;
  final VoidCallback onPickDate;
  final VoidCallback onSwitchToHeight;
  final VoidCallback onSwitchToDate;
  final double narrowBreakpoint;

  Widget _refreshField() {
    if (refreshType == 'date') {
      return ArqmaField(
        label: dateLabel,
        child: InkWell(
          onTap: onPickDate,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  refreshStartDate,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.calendar_today, size: 20),
                onPressed: onPickDate,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ),
        ),
      );
    }
    return ArqmaField(
      label: heightLabel,
      child: TextField(
        controller: refreshHeightController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(border: InputBorder.none),
      ),
    );
  }

  Widget _modeToggle() {
    final bool isDate = refreshType == 'date';
    return TextButton(
      onPressed: isDate ? onSwitchToHeight : onSwitchToDate,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        isDate ? switchToHeightLabel : switchToDateLabel,
        textAlign: TextAlign.center,
        maxLines: 3,
        softWrap: true,
        style: const TextStyle(fontSize: 13, height: 1.25),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget field = _refreshField();
    final Widget toggle = _modeToggle();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stack = constraints.maxWidth < narrowBreakpoint;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: toggle),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: field),
            const SizedBox(width: 8),
            Flexible(child: toggle),
          ],
        );
      },
    );
  }
}
