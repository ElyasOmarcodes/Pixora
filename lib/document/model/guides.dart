import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/json.dart';

/// A layout grid laid over the canvas.
///
/// By default lines are spread evenly ([columns] × [rows]). As soon as the
/// user drags or deletes a single line, the positions are stored explicitly
/// in [xLines] / [yLines] (fractions of the canvas, 0..1). The grid can be
/// rotated around the canvas centre.
@immutable
class GridSpec {
  const GridSpec({
    this.visible = false,
    this.columns = 3,
    this.rows = 3,
    this.rotation = 0,
    this.color = const Color(0xFFFFFFFF),
    this.opacity = 0.6,
    this.xLines,
    this.yLines,
  });

  final bool visible;
  final int columns;
  final int rows;

  /// Degrees, clockwise.
  final double rotation;
  final Color color;
  final double opacity;

  /// Custom line positions (fractions); null = evenly spaced.
  final List<double>? xLines;
  final List<double>? yLines;

  bool get isCustom => xLines != null || yLines != null;

  List<double> get verticalLines =>
      xLines ?? [for (var i = 1; i < columns; i++) i / columns];

  List<double> get horizontalLines =>
      yLines ?? [for (var i = 1; i < rows; i++) i / rows];

  double get rotationRadians => rotation * math.pi / 180;

  GridSpec copyWith({
    bool? visible,
    int? columns,
    int? rows,
    double? rotation,
    Color? color,
    double? opacity,
    List<double>? xLines,
    List<double>? yLines,
    bool resetLines = false,
  }) => GridSpec(
    visible: visible ?? this.visible,
    columns: columns ?? this.columns,
    rows: rows ?? this.rows,
    rotation: rotation ?? this.rotation,
    color: color ?? this.color,
    opacity: opacity ?? this.opacity,
    xLines: resetLines ? null : (xLines ?? this.xLines),
    yLines: resetLines ? null : (yLines ?? this.yLines),
  );

  Json toJson() => {
    if (visible) 'visible': true,
    'columns': columns,
    'rows': rows,
    if (rotation != 0) 'rotation': rotation,
    'color': writeColor(color),
    'opacity': opacity,
    'xLines': ?xLines,
    'yLines': ?yLines,
  };

  static GridSpec fromJson(Object? json) {
    final m = readMap(json);
    List<double>? lines(Object? v) =>
        v is List ? [for (final x in v) readDouble(x).clamp(0.0, 1.0)] : null;
    return GridSpec(
      visible: readBool(m['visible']),
      columns: readInt(m['columns'], 3).clamp(1, 64),
      rows: readInt(m['rows'], 3).clamp(1, 64),
      rotation: readDouble(m['rotation']),
      color: readColor(m['color'], const Color(0xFFFFFFFF)),
      opacity: readDouble(m['opacity'], 0.6).clamp(0.05, 1.0),
      xLines: lines(m['xLines']),
      yLines: lines(m['yLines']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GridSpec &&
      other.visible == visible &&
      other.columns == columns &&
      other.rows == rows &&
      other.rotation == rotation &&
      other.color == color &&
      other.opacity == opacity &&
      listEquals(other.xLines, xLines) &&
      listEquals(other.yLines, yLines);

  @override
  int get hashCode => Object.hash(
    visible,
    columns,
    rows,
    rotation,
    color,
    opacity,
    Object.hashAll(xLines ?? const []),
    Object.hashAll(yLines ?? const []),
  );
}

/// The canvas' layout aids: the grid and ruler guides (Photoshop's
/// "guides" — straight lines dragged out of the rulers, in canvas pixels).
@immutable
class CanvasGuides {
  CanvasGuides({
    this.grid = const GridSpec(),
    List<double> vertical = const [],
    List<double> horizontal = const [],
  }) : vertical = List.unmodifiable(vertical),
       horizontal = List.unmodifiable(horizontal);

  static final CanvasGuides none = CanvasGuides();

  final GridSpec grid;

  /// x positions of vertical guides, in canvas pixels.
  final List<double> vertical;

  /// y positions of horizontal guides, in canvas pixels.
  final List<double> horizontal;

  bool get isEmpty =>
      grid == const GridSpec() && vertical.isEmpty && horizontal.isEmpty;

  CanvasGuides copyWith({
    GridSpec? grid,
    List<double>? vertical,
    List<double>? horizontal,
  }) => CanvasGuides(
    grid: grid ?? this.grid,
    vertical: vertical ?? this.vertical,
    horizontal: horizontal ?? this.horizontal,
  );

  /// Grid lines that are axis-aligned in canvas pixels (only when the grid
  /// isn't rotated), for snapping.
  (List<double> xs, List<double> ys) gridLinesPx(Size canvas) {
    if (!grid.visible || grid.rotation % 360 != 0) return (const [], const []);
    return (
      [for (final f in grid.verticalLines) f * canvas.width],
      [for (final f in grid.horizontalLines) f * canvas.height],
    );
  }

  Json toJson() => {
    'grid': grid.toJson(),
    if (vertical.isNotEmpty) 'vertical': vertical,
    if (horizontal.isNotEmpty) 'horizontal': horizontal,
  };

  static CanvasGuides fromJson(Object? json) {
    final m = readMap(json);
    return CanvasGuides(
      grid: GridSpec.fromJson(m['grid']),
      vertical: [for (final v in readList(m['vertical'])) readDouble(v)],
      horizontal: [for (final v in readList(m['horizontal'])) readDouble(v)],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasGuides &&
      other.grid == grid &&
      listEquals(other.vertical, vertical) &&
      listEquals(other.horizontal, horizontal);

  @override
  int get hashCode =>
      Object.hash(grid, Object.hashAll(vertical), Object.hashAll(horizontal));
}
