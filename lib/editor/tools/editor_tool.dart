import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../editor_controller.dart';

/// Maps between screen space (logical pixels of the canvas widget) and
/// document space (canvas pixels).
class CanvasViewport {
  CanvasViewport({this.scale = 1, this.offset = Offset.zero});

  /// Screen pixels per document pixel.
  double scale;

  /// Screen position of the document's origin.
  Offset offset;

  Offset toDoc(Offset screen) => (screen - offset) / scale;
  Offset toScreen(Offset doc) => doc * scale + offset;

  /// Zooms by [factor] keeping the document point under [focal] fixed.
  void zoomAt(
    Offset focal,
    double factor, {
    double min = 0.02,
    double max = 64,
  }) {
    final next = (scale * factor).clamp(min, max);
    final docPt = toDoc(focal);
    scale = next;
    offset = focal - docPt * scale;
  }
}

/// Visual colors a tool needs for its overlay.
class ToolStyle {
  const ToolStyle({
    required this.selection,
    required this.guide,
    required this.handleFill,
  });
  final Color selection;
  final Color guide;
  final Color handleFill;
}

/// What moving layers snap to.
class SnapOptions {
  const SnapOptions({
    this.enabled = true,
    this.canvas = true,
    this.guides = true,
    this.layers = true,
    this.angles = true,
  });

  static const SnapOptions off = SnapOptions(enabled: false);

  final bool enabled;

  /// Canvas edges and centre.
  final bool canvas;

  /// Ruler guides and (unrotated) grid lines.
  final bool guides;

  /// Smart guides: edges and centres of other layers.
  final bool layers;

  /// 45° rotation steps.
  final bool angles;

  bool get positions => enabled && (canvas || guides || layers);
  bool get rotation => enabled && angles;
}

/// What a tool receives for every event.
class ToolContext {
  const ToolContext({
    required this.editor,
    required this.viewport,
    required this.snap,
    required this.style,
    required this.requestRepaint,
    this.pointerDown,
  });

  /// Where the current gesture's first finger went down (screen space).
  /// Gesture starts are reported after the touch slop; tools that draw
  /// from the exact start point use this.
  final Offset? pointerDown;

  final EditorController editor;
  final CanvasViewport viewport;
  final SnapOptions snap;
  final ToolStyle style;
  final void Function() requestRepaint;
}

/// A canvas interaction mode (transform, brush, eraser, crop, selection…).
///
/// The canvas widget owns the viewport and forwards input to the active
/// tool. A tool that doesn't consume a gesture (returns false from
/// [onScaleStart]) lets the canvas pan/zoom instead, so every tool gets
/// navigation for free. New tools only need to implement this class.
abstract class EditorTool {
  String get id;

  /// A single tap (or click) at [screen].
  void onTap(ToolContext ctx, Offset screen) {}

  /// A quick second tap at the same place.
  void onDoubleTap(ToolContext ctx, Offset screen) {}

  /// Return true to own this gesture; false to let the canvas navigate.
  bool onScaleStart(ToolContext ctx, ScaleStartDetails d) => false;
  void onScaleUpdate(ToolContext ctx, ScaleUpdateDetails d) {}
  void onScaleEnd(ToolContext ctx, ScaleEndDetails d) {}

  /// Mouse hover (desktop) — used for cursors and hover highlights.
  MouseCursor cursorAt(ToolContext ctx, Offset screen) => MouseCursor.defer;

  /// Extra state the overlay depends on (repaints when it changes).
  Listenable? get repaint => null;

  /// Draws handles, guides, brush previews… in screen space.
  void paintOverlay(Canvas canvas, Size size, ToolContext ctx) {}
}
