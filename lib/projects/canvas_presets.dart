import 'package:flutter/material.dart';

/// Ready-made canvas sizes offered when creating a project.
class CanvasPreset {
  const CanvasPreset(this.id, this.width, this.height, this.icon)
    : dpi = 72,
      mm = null;

  /// A paper size at its real physical size ([mm], width × height) and
  /// print resolution [dpi]; the pixel size follows from both.
  CanvasPreset.paper(this.id, (double, double) this.mm, this.icon)
    : dpi = 300,
      width = (mm.$1 / 25.4 * 300).roundToDouble(),
      height = (mm.$2 / 25.4 * 300).roundToDouble();

  final String id;
  final double width;
  final double height;
  final IconData icon;

  /// Pixels per inch the project is created with (print units follow).
  final double dpi;

  /// Physical size in millimetres for paper presets.
  final (double, double)? mm;

  double get aspect => width / height;

  /// "21 × 29.7 cm" for paper, "1080 × 1080" otherwise.
  String get sizeLabel {
    final m = mm;
    if (m == null) return '${width.round()} × ${height.round()}';
    String cm(double v) {
      final c = v / 10;
      return c == c.roundToDouble() ? c.toStringAsFixed(0) : '$c';
    }

    return '${cm(m.$1)} × ${cm(m.$2)} cm';
  }
}

final List<CanvasPreset> kCanvasPresets = [
  const CanvasPreset('square', 1080, 1080, Icons.crop_square_rounded),
  const CanvasPreset('portrait', 1080, 1350, Icons.crop_portrait_rounded),
  const CanvasPreset('story', 1080, 1920, Icons.smartphone_rounded),
  const CanvasPreset('landscape', 1920, 1080, Icons.crop_landscape_rounded),
  const CanvasPreset('youtube', 1280, 720, Icons.smart_display_rounded),
  CanvasPreset.paper('a4', (210, 297), Icons.description_rounded),
  CanvasPreset.paper('a4land', (297, 210), Icons.note_rounded),
  CanvasPreset.paper('a5', (148, 210), Icons.sticky_note_2_rounded),
  CanvasPreset.paper('a3', (297, 420), Icons.article_rounded),
  CanvasPreset.paper('letter', (215.9, 279.4), Icons.mail_rounded),
  const CanvasPreset('cover', 1640, 624, Icons.panorama_rounded),
  const CanvasPreset('logo', 1000, 1000, Icons.token_rounded),
];

/// Pleasant gradient backgrounds for new projects.
const List<List<Color>> kBackgroundGradients = [
  [Color(0xFF0A84FF), Color(0xFF021B4D)],
  [Color(0xFF7F5AF0), Color(0xFF2CB67D)],
  [Color(0xFFFF7E5F), Color(0xFFFEB47B)],
  [Color(0xFFFFE259), Color(0xFFFFA751)],
  [Color(0xFFE0EAFC), Color(0xFFCFDEF3)],
  [Color(0xFF232526), Color(0xFF414345)],
  [Color(0xFFFC466B), Color(0xFF3F5EFB)],
  [Color(0xFF11998E), Color(0xFF38EF7D)],
  [Color(0xFFA8E6CF), Color(0xFFFFD3B6)],
  [Color(0xFF141E30), Color(0xFF243B55)],
];

const List<Color> kSwatches = [
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFF9E9E9E),
  Color(0xFF455A64),
  Color(0xFFE53935),
  Color(0xFFFF7043),
  Color(0xFFFFB300),
  Color(0xFFFDD835),
  Color(0xFF7CB342),
  Color(0xFF43A047),
  Color(0xFF00897B),
  Color(0xFF00ACC1),
  Color(0xFF1E88E5),
  Color(0xFF3949AB),
  Color(0xFF5E35B1),
  Color(0xFF8E24AA),
  Color(0xFFD81B60),
  Color(0xFF6D4C41),
  Color(0xFFF8BBD0),
  Color(0xFFB3E5FC),
];
