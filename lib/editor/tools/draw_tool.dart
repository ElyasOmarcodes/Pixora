import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../document/model/layer.dart';
import 'editor_tool.dart';

/// Freehand brush settings shared by the brush panel and the canvas tool.
class BrushSettings extends ChangeNotifier {
  BrushType _type = BrushType.pen;
  double _size = 12;
  Color _color = const Color(0xFF111827);
  double _opacity = 1;
  double _softness = 0;
  double _smoothing = 0.5;
  bool _eraser = false;
  BrushTip? _tip;

  BrushType get type => _type;

  /// Brush diameter in document pixels.
  double get size => _size;
  Color get color => _color;
  double get opacity => _opacity;
  double get softness => _softness;

  /// Stabilizer 0..1: higher = smoother, slightly lagging lines.
  double get smoothing => _smoothing;
  bool get eraser => _eraser;

  set type(BrushType v) => _set(() {
    _type = v;
    _tip = null;
    _eraser = false;
  });

  /// The tip settings in use (the brush's preset until changed); null
  /// for line brushes.
  BrushTip? get tip => _tip ?? BrushTip.presetFor(_type);

  /// Whether the brush has tip settings changed from its preset.
  bool get tipChanged => _tip != null;

  /// Changes the tip settings; a line brush becomes the round tip brush
  /// with the same edge.
  set tip(BrushTip? v) => _set(() {
    if (v != null && BrushTip.presetFor(_type) == null) {
      _type = BrushType.round;
    }
    _tip = v;
  });
  set size(double v) => _set(() => _size = v.clamp(0.5, 500.0));
  set color(Color v) => _set(() {
    _color = v;
    _eraser = false;
  });
  set opacity(double v) => _set(() => _opacity = v.clamp(0.02, 1.0));
  set softness(double v) => _set(() => _softness = v.clamp(0.0, 1.0));
  set smoothing(double v) => _set(() => _smoothing = v.clamp(0.0, 1.0));
  set eraser(bool v) => _set(() => _eraser = v);

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  BrushStroke stroke(
    List<Offset> points,
    double scale,
    int seed, [
    List<double>? pressures,
  ]) {
    final t = tip;
    return BrushStroke(
      points: points,
      // The eraser keeps a tip brush's shape; line brushes erase round.
      type: _eraser && t == null ? BrushType.pen : _type,
      color: _color,
      width: _size * scale,
      opacity: _eraser ? 1 : _opacity,
      softness: _softness,
      eraser: _eraser,
      seed: seed,
      tip: t,
      pressures: t != null && (t.pressureSize || t.pressureOpacity)
          ? pressures
          : null,
    );
  }
}

/// Draws brush strokes into the selected drawing layer. One finger draws;
/// two fingers still pan and zoom the canvas.
class DrawTool extends EditorTool {
  DrawTool(this.settings);

  final BrushSettings settings;
  String? _layerId;
  List<Offset> _points = [];
  List<double> _pressures = [];
  Offset? _smoothed;

  // Pressure from speed when the pen reports none (like Procreate:
  // faster strokes come out thinner).
  DateTime _lastTime = DateTime(0);
  Offset _lastScreen = Offset.zero;
  double _speedPressure = 0.7;

  double _pressureNow(ToolContext ctx, Offset screen, {bool start = false}) {
    final now = DateTime.now();
    final stylus = ctx.pressure;
    if (start) {
      _lastTime = now;
      _lastScreen = screen;
      _speedPressure = 0.7;
      return stylus ?? _speedPressure;
    }
    final dt = math.max(1, now.difference(_lastTime).inMilliseconds);
    final v = (screen - _lastScreen).distance / dt; // px per ms
    _lastTime = now;
    _lastScreen = screen;
    final target = (1.15 - v / 2.2).clamp(0.2, 1.0);
    _speedPressure += (target - _speedPressure) * 0.35;
    return stylus ?? _speedPressure;
  }

  Offset? _cursor;
  double _scale = 1;

  @override
  String get id => 'draw';

  @override
  Listenable get repaint => settings;

  DrawingLayer? _target(ToolContext ctx) {
    final l = ctx.editor.selectedLayer;
    return l is DrawingLayer && !l.props.locked ? l : null;
  }

  /// Local units per document pixel (brush sizes are in document pixels).
  double _localScale(Layer l) {
    final t = l.props.transform;
    return 1 / math.max(0.0001, (t.scaleX.abs() + t.scaleY.abs()) / 2);
  }

  int get _seed => DateTime.now().microsecondsSinceEpoch & 0x7fffffff;

  @override
  void onTap(ToolContext ctx, Offset screen) {
    final l = _target(ctx);
    if (l == null) return;
    final p = l.props.transform.toLocal(ctx.viewport.toDoc(screen));
    ctx.editor.addBrushStroke(
      l.id,
      settings.stroke([p], _localScale(l), _seed),
    );
  }

  @override
  bool onScaleStart(ToolContext ctx, ScaleStartDetails d) {
    if (d.pointerCount > 1 || d.kind == PointerDeviceKind.trackpad) {
      return false;
    }
    final l = _target(ctx);
    if (l == null) return false;
    _layerId = l.id;
    _scale = _localScale(l);
    final p = l.props.transform.toLocal(ctx.viewport.toDoc(d.localFocalPoint));
    _points = [p];
    _pressures = [_pressureNow(ctx, d.localFocalPoint, start: true)];
    _smoothed = p;
    _cursor = d.localFocalPoint;
    _seedNow = _seed;
    _preview(ctx);
    return true;
  }

  int _seedNow = 0;

  void _preview(ToolContext ctx) {
    final id = _layerId;
    if (id == null) return;
    ctx.editor.addBrushStroke(
      id,
      settings.stroke(_points, _scale, _seedNow, _pressures),
      live: true,
    );
  }

  @override
  void onScaleUpdate(ToolContext ctx, ScaleUpdateDetails d) {
    final id = _layerId;
    if (id == null) return;
    final l = ctx.editor.document.layerById(id);
    if (l == null) return;
    _cursor = d.localFocalPoint;
    final raw = l.props.transform.toLocal(
      ctx.viewport.toDoc(d.localFocalPoint),
    );
    // Stabilizer: follow the finger with some lag for smooth curves.
    final k = 1 - settings.smoothing * 0.85;
    final prev = _smoothed ?? raw;
    final p = prev + (raw - prev) * k;
    _smoothed = p;
    final pressure = _pressureNow(ctx, d.localFocalPoint);
    final minStep = 1.2 / ctx.viewport.scale * _scale;
    if ((p - _points.last).distance < minStep) return;
    _points = [..._points, p];
    _pressures = [..._pressures, pressure];
    _preview(ctx);
  }

  @override
  void onScaleEnd(ToolContext ctx, ScaleEndDetails d) {
    if (_layerId == null) return;
    if (ctx.editor.isPreviewing) ctx.editor.commit('draw');
    _layerId = null;
    _points = [];
    _pressures = [];
    _smoothed = null;
    ctx.requestRepaint();
  }

  @override
  MouseCursor cursorAt(ToolContext ctx, Offset screen) {
    _cursor = screen;
    ctx.requestRepaint();
    return SystemMouseCursors.precise;
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ToolContext ctx) {
    final c = _cursor;
    final l = _target(ctx);
    if (c == null || l == null) return;
    final r = math.max(
      2.0,
      settings.size *
          (settings.type == BrushType.highlighter ? 1.4 : 1) *
          ctx.viewport.scale /
          2,
    );
    canvas
      ..drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.white,
      )
      ..drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = settings.eraser ? const Color(0xFFFF4D6D) : Colors.black,
      );
  }
}
