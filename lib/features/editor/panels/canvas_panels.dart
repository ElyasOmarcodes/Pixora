import 'package:flutter/material.dart';

import '../../../editor/editor_controller.dart';
import '../../../ui/widgets/fill_picker.dart';

/// Solid / gradient / transparent background of the canvas.
class BackgroundPanel extends StatelessWidget {
  const BackgroundPanel({super.key, required this.editor});
  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final bg = editor.document.background;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FillPicker(
          value: bg,
          allowTransparent: true,
          aspect: editor.document.width / editor.document.height,
          onChanged: (f, {required live}) =>
              editor.setBackground(f, live: live),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
