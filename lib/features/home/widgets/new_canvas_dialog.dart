import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';

class CanvasSizeResult {
  const CanvasSizeResult(
    this.width,
    this.height, {
    this.transparent = false,
    this.scaleContent = true,
  });
  final double width;
  final double height;
  final bool transparent;
  final bool scaleContent;
}

/// Dialog for a custom canvas size. Used both for new projects and for
/// resizing an open canvas ([resizing] shows "scale content" instead of the
/// background choice).
Future<CanvasSizeResult?> showNewCanvasDialog(
  BuildContext context, {
  double width = 1080,
  double height = 1080,
  bool resizing = false,
}) => showDialog<CanvasSizeResult>(
  context: context,
  builder: (_) =>
      _NewCanvasDialog(width: width, height: height, resizing: resizing),
);

class _NewCanvasDialog extends StatefulWidget {
  const _NewCanvasDialog({
    required this.width,
    required this.height,
    required this.resizing,
  });
  final double width;
  final double height;
  final bool resizing;

  @override
  State<_NewCanvasDialog> createState() => _NewCanvasDialogState();
}

class _NewCanvasDialogState extends State<_NewCanvasDialog> {
  late final _w = TextEditingController(text: widget.width.round().toString());
  late final _h = TextEditingController(text: widget.height.round().toString());
  bool _transparent = false;
  bool _scale = true;

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController c) {
    final v = int.tryParse(c.text);
    if (v == null || v < 1 || v > 16384) return null;
    return v.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final w = _parse(_w), h = _parse(_h);
    Widget field(TextEditingController c, String label) => Expanded(
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() {}),
      ),
    );
    return AlertDialog(
      title: Text(widget.resizing ? l.canvasSize : l.customSize),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              field(_w, l.width),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('×'),
              ),
              field(_h, l.height),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.resizing)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _scale,
              title: Text(l.scaleContent),
              onChanged: (v) => setState(() => _scale = v),
            )
          else
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _transparent,
              title: Text(l.transparent),
              onChanged: (v) => setState(() => _transparent = v),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: w == null || h == null
              ? null
              : () => Navigator.pop(
                  context,
                  CanvasSizeResult(
                    w,
                    h,
                    transparent: _transparent,
                    scaleContent: _scale,
                  ),
                ),
          child: Text(widget.resizing ? l.apply : l.create),
        ),
      ],
    );
  }
}
