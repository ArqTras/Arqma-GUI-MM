import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/arqma_colors.dart';

/// Parity with `components/arqma_field.vue` (label, optional, error border, context menu).
class ArqmaField extends StatefulWidget {
  const ArqmaField({
    super.key,
    required this.label,
    required this.child,
    this.optional = false,
    this.error = false,
    this.errorLabel = '',
    this.disable = false,
    this.disableHover = false,
    this.disableMenu = true,
  });

  final String label;
  final Widget child;
  final bool optional;
  final bool error;
  final String errorLabel;
  final bool disable;
  final bool disableHover;
  final bool disableMenu;

  @override
  State<ArqmaField> createState() => _ArqmaFieldState();
}

class _ArqmaFieldState extends State<ArqmaField> {
  final GlobalKey _contentKey = GlobalKey();

  Future<void> _pasteIntoFocused() async {
    final BuildContext? ctx = _contentKey.currentContext;
    if (ctx == null) {
      return;
    }
    final String text =
        (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final EditableTextState? et =
        ctx.findAncestorStateOfType<EditableTextState>();
    if (et != null) {
      final TextEditingValue v = et.textEditingValue;
      final TextSelection sel = v.selection;
      final String next = v.text.replaceRange(sel.start, sel.end, text);
      et.userUpdateTextEditingValue(
        TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: sel.start + text.length),
        ),
        SelectionChangedCause.toolbar,
      );
    }
  }

  Future<void> _showMenu() async {
    if (widget.disableMenu) {
      return;
    }
    final RenderBox? rb =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    final Offset pos = rb?.localToGlobal(Offset.zero) ?? Offset.zero;
    final RelativeRect rect =
        RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1);
    final String? cmd = await showMenu<String>(
      context: context,
      position: rect,
      items: const [
        PopupMenuItem<String>(value: 'paste', child: Text('Paste')),
      ],
    );
    if (cmd == 'paste') {
      await _pasteIntoFocused();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.disable ? 0.55 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: ArqmaColors.textPrimary.withValues(alpha: 0.92),
                      fontSize: 13,
                    ),
                  ),
                  if (widget.optional)
                    Text(
                      ' (Optional)',
                      style: TextStyle(
                        color: ArqmaColors.textMuted.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          GestureDetector(
            onSecondaryTapDown: widget.disableMenu ? null : (_) => _showMenu(),
            child: Container(
              key: _contentKey,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF14110E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.error
                      ? ArqmaColors.negative
                      : ArqmaColors.outlineDefault.withValues(alpha: 0.65),
                  width: widget.error ? 1.4 : 1,
                ),
              ),
              child: widget.child,
            ),
          ),
          if (widget.error && widget.errorLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(widget.errorLabel,
                  style: const TextStyle(
                      color: ArqmaColors.negative, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
