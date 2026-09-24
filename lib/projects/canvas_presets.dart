import 'package:flutter/material.dart';

/// Ready-made canvas sizes offered when creating a project.
class CanvasPreset {
  const CanvasPreset(this.id, this.width, this.height, this.icon);
  final String id;
  final double width;
  final double height;
  final IconData icon;

  double get aspect => width / height;
}

const List<CanvasPreset> kCanvasPresets = [
  CanvasPreset('square', 1080, 1080, Icons.crop_square_rounded),
  CanvasPreset('portrait', 1080, 1350, Icons.crop_portrait_rounded),
  CanvasPreset('story', 1080, 1920, Icons.smartphone_rounded),
  CanvasPreset('landscape', 1920, 1080, Icons.crop_landscape_rounded),
  CanvasPreset('youtube', 1280, 720, Icons.smart_display_rounded),
  CanvasPreset('a4', 2480, 3508, Icons.description_rounded),
  CanvasPreset('a3', 3508, 4961, Icons.article_rounded),
  CanvasPreset('cover', 1640, 624, Icons.panorama_rounded),
  CanvasPreset('logo', 1000, 1000, Icons.token_rounded),
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
