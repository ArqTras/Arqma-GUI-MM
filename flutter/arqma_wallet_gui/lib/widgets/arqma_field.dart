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
    /// When true, the input [child] area expands to fill vertical space (use with a bounded parent height).
    this.stretchContent = false,
    /// Warmer gold label + border (e.g. wallet tx filters).
    this.goldChrome = false,
  });

  final String label;
  final Widget child;
  final bool optional;
  final bool error;
  final String errorLabel;
  final bool disable;
  final bool disableHover;
  final bool disableMenu;
  final bool stretchContent;
  final bool goldChrome;

  @override
  State<ArqmaField> createState() => _ArqmaFieldState();
}

class _ArqmaFieldState extends State<ArqmaField> {
  final GlobalKey _contentKey = GlobalKey();

  Future<void> _pasteIntoFocused() async {
    final String text =
        (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) {
      return;
    }
    final BuildContext? ctx = _contentKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      return;
    }
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

  Color _borderColor() {
    if (widget.error) {
      return ArqmaColors.negative;
    }
    if (widget.goldChrome) {
      return ArqmaColors.outlineBright;
    }
    return ArqmaColors.outlineDefault.withValues(alpha: 0.65);
  }

  double _borderWidth() {
    if (widget.error) {
      return 1.4;
    }
    if (widget.goldChrome) {
      return 1.15;
    }
    return 1;
  }

  Widget _inputBox({required bool stretch}) {
    final Widget inner = GestureDetector(
      onSecondaryTapDown: widget.disableMenu ? null : (_) => _showMenu(),
      child: Container(
        key: _contentKey,
        alignment: stretch ? Alignment.centerLeft : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF14110E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _borderColor(),
            width: _borderWidth(),
          ),
        ),
        child: widget.child,
      ),
    );
    if (stretch) {
      return Expanded(child: inner);
    }
    return inner;
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.disable ? 0.55 : 1,
      child: Column(
        crossAxisAlignment: widget.stretchContent
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.start,
        children: [
          if (widget.label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.goldChrome
                          ? ArqmaColors.arqmaGreenSolid
                          : ArqmaColors.textPrimary.withValues(alpha: 0.92),
                      fontSize: 13,
                      fontWeight:
                          widget.goldChrome ? FontWeight.w600 : FontWeight.normal,
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
          _inputBox(stretch: widget.stretchContent),
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
