import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../editor/editor_controller.dart';
import '../../../core/units/units.dart';
import '../../../editor/tools/editor_tool.dart';
import '../../../editor/tools/grid_tool.dart';
import '../../../ui/widgets/checkerboard.dart';

/// Lets the page drive the canvas viewport (fit, zoom presets) and read
/// the current zoom level.
class CanvasViewController extends ChangeNotifier {
  _CanvasViewState? _state;

  /// Current zoom (1 = 100 %, one canvas pixel per logical pixel).
  double get zoom => _state?._vp.scale ?? 1;

  void fit() => _state?._animateFit();

  /// Zooms to [scale] around the view centre (1 = 100 %).
  void zoomTo(double scale) => _state?._animateZoom(scale);

  void zoomBy(double factor) => zoomTo(zoom * factor);

  void _changed() => notifyListeners();
}

/// The interactive canvas: renders the document, owns the viewport
/// (pan/zoom) and forwards input to the active [EditorTool].
class CanvasView extends StatefulWidget {
  const CanvasView({
    super.key,
    required this.editor,
    required this.tool,
    required this.snap,
    this.showRulers = false,
    this.rulerUnit = MeasureUnit.px,
    this.guideColor = const Color(0xFF00C2FF),
    this.controller,
    this.onTap,
  });

  /// Called after every single tap on the canvas (after the tool).
  final VoidCallback? onTap;

  final EditorController editor;
  final EditorTool tool;
  final SnapOptions snap;
  final bool showRulers;
  final MeasureUnit rulerUnit;
  final Color guideColor;
  final CanvasViewController? controller;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView>
    with SingleTickerProviderStateMixin {
  final CanvasViewport _vp = CanvasViewport();
  Size _size = Size.zero;
  Size _docSize = Size.zero;
  bool _userNavigated = false;

  bool _navigating = false;
  double _navStartScale = 1;
  Offset _navStartFocal = Offset.zero;
  Offset _navStartOffset = Offset.zero;

  Offset? _lastTapPos;
  DateTime _lastTapTime = DateTime(0);
  MouseCursor _cursor = MouseCursor.defer;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: PixTokens.medium,
  )..addListener(_onAnim);
  double _animFromScale = 1, _animToScale = 1;
  Offset _animFromOffset = Offset.zero, _animToOffset = Offset.zero;

  final ValueNotifier<int> _overlayTick = ValueNotifier(0);

  /// Guide being dragged out of a ruler: (vertical?, doc position).
  final ValueNotifier<(bool, double)?> _pendingGuide = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(CanvasView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.controller?._changed();
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _pendingGuide.dispose();
    _anim.dispose();
    _overlayTick.dispose();
    super.dispose();
  }

  Offset? _pointerDown;

  ToolContext get _ctx {
    final pix = PixColors.of(context);
    return ToolContext(
      pointerDown: _pointerDown,
      editor: widget.editor,
      viewport: _vp,
      snap: widget.snap,
      style: ToolStyle(
        selection: pix.selection,
        guide: pix.guide,
        handleFill: Colors.white,
      ),
      requestRepaint: () => _overlayTick.value++,
    );
  }

  (double, Offset) _fitFor(Size view, Size doc) {
    final margin = math.min(view.width, view.height) * 0.06 + 12;
    final s = math.min(
      (view.width - margin * 2) / doc.width,
      (view.height - margin * 2) / doc.height,
    );
    final scale = s.isFinite && s > 0 ? s : 1.0;
    final offset = Offset(
      (view.width - doc.width * scale) / 2,
      (view.height - doc.height * scale) / 2,
    );
    return (scale, offset);
  }

  void _fitNow() {
    final (s, o) = _fitFor(_size, _docSize);
    _vp
      ..scale = s
      ..offset = o;
  }

  void _animateFit() {
    final (s, o) = _fitFor(_size, _docSize);
    _animFromScale = _vp.scale;
    _animFromOffset = _vp.offset;
    _animToScale = s;
    _animToOffset = o;
    _userNavigated = false;
    _anim.forward(from: 0);
  }

  void _animateZoom(double scale) {
    final target = scale.clamp(0.02, 64.0);
    final center = Offset(_size.width / 2, _size.height / 2);
    final docPt = _vp.toDoc(center);
    _animFromScale = _vp.scale;
    _animFromOffset = _vp.offset;
    _animToScale = target;
    _animToOffset = center - docPt * target;
    _userNavigated = true;
    _anim.forward(from: 0);
  }

  void _onAnim() {
    final t = PixTokens.emphasized.transform(_anim.value);
    setState(() {
      _vp.scale = _animFromScale + (_animToScale - _animFromScale) * t;
      _vp.offset = Offset.lerp(_animFromOffset, _animToOffset, t)!;
    });
  }

  // ----------------------------------------------------------- input

  void _onTapUp(TapUpDetails d) {
    final now = DateTime.now();
    final isDouble =
        _lastTapPos != null &&
        now.difference(_lastTapTime).inMilliseconds < 320 &&
        (d.localPosition - _lastTapPos!).distance < 24;
    _lastTapTime = now;
    _lastTapPos = d.localPosition;
    if (isDouble) {
      _lastTapPos = null;
      final hit = widget.editor.layerAt(
        _vp.toDoc(d.localPosition),
        tolerance: 6 / _vp.scale,
      );
      if (hit == null) {
        _animateFit();
      } else {
        widget.tool.onDoubleTap(_ctx, d.localPosition);
      }
      return;
    }
    widget.tool.onTap(_ctx, d.localPosition);
    widget.onTap?.call();
  }

  void _onScaleStart(ScaleStartDetails d) {
    _anim.stop();
    if (widget.tool.onScaleStart(_ctx, d)) {
      _navigating = false;
      return;
    }
    _navigating = true;
    _userNavigated = true;
    _navStartScale = _vp.scale;
    _navStartFocal = d.localFocalPoint;
    _navStartOffset = _vp.offset;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (!_navigating) {
      widget.tool.onScaleUpdate(_ctx, d);
      return;
    }
    setState(() {
      final newScale = (_navStartScale * d.scale).clamp(0.02, 64.0);
      // Keep the document point under the initial focal point under the
      // current focal point (pan + zoom in one go).
      final docPt = (_navStartFocal - _navStartOffset) / _navStartScale;
      _vp.scale = newScale;
      _vp.offset = d.localFocalPoint - docPt * newScale;
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_navigating) {
      _navigating = false;
      return;
    }
    widget.tool.onScaleEnd(_ctx, d);
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (event) {
        final s = event as PointerScrollEvent;
        _anim.stop();
        _userNavigated = true;
        setState(
          () => _vp.zoomAt(
            s.localPosition,
            math.pow(0.999, s.scrollDelta.dy).toDouble(),
          ),
        );
      });
    }
  }

  void _onHover(PointerHoverEvent e) {
    final c = widget.tool.cursorAt(_ctx, e.localPosition);
    if (c != _cursor) setState(() => _cursor = c);
  }

  // ---------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final pix = PixColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final docSize = widget.editor.document.size;
        if (size != _size || docSize != _docSize) {
          final first = _size == Size.zero;
          final docChanged = docSize != _docSize;
          _size = size;
          _docSize = docSize;
          if (first || docChanged || !_userNavigated) _fitNow();
        }
        final canvasWidget = ClipRect(
          child: ColoredBox(
            color: pix.canvasBackdrop,
            child: Listener(
              onPointerSignal: _onPointerSignal,
              onPointerDown: (e) => _pointerDown = e.localPosition,
              child: MouseRegion(
                cursor: _cursor,
                onHover: _onHover,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: _onTapUp,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: size,
                      painter: _DocumentPainter(
                        editor: widget.editor,
                        scale: _vp.scale,
                        offset: _vp.offset,
                        checkerA: pix.checkerA,
                        checkerB: pix.checkerB,
                        shadow: pix.softShadow,
                        devicePixelRatio: MediaQuery.devicePixelRatioOf(
                          context,
                        ),
                      ),
                      foregroundPainter: _OverlayPainter(
                        editor: widget.editor,
                        tool: widget.tool,
                        ctx: _ctx,
                        pendingGuide: _pendingGuide,
                        tick: _overlayTick,
                        scale: _vp.scale,
                        offset: _vp.offset,
                        guideColor: widget.guideColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        if (!widget.showRulers) return canvasWidget;
        return Stack(
          children: [
            Positioned.fill(child: canvasWidget),
            Positioned(
              left: _Ruler.thickness,
              right: 0,
              top: 0,
              height: _Ruler.thickness,
              child: _ruler(horizontal: true),
            ),
            Positioned(
              left: 0,
              top: _Ruler.thickness,
              bottom: 0,
              width: _Ruler.thickness,
              child: _ruler(horizontal: false),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: _Ruler.thickness,
              height: _Ruler.thickness,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
            ),
          ],
        );
      },
    );
  }

  /// A ruler strip. Dragging out of the top ruler creates a horizontal
  /// guide, out of the left ruler a vertical one (like Photoshop); drop it
  /// outside the canvas to cancel.
  Widget _ruler({required bool horizontal}) {
    double docPos(Offset local) {
      // Convert from ruler-local to canvas coordinates.
      final canvasPt = horizontal
          ? local + const Offset(_Ruler.thickness, 0)
          : local + const Offset(0, _Ruler.thickness);
      final d = _vp.toDoc(canvasPt);
      return horizontal ? d.dy : d.dx;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) =>
          _pendingGuide.value = (!horizontal, docPos(d.localPosition)),
      onPanUpdate: (d) =>
          _pendingGuide.value = (!horizontal, docPos(d.localPosition)),
      onPanEnd: (_) {
        final g = _pendingGuide.value;
        _pendingGuide.value = null;
        if (g == null) return;
        final (vertical, pos) = g;
        final doc = widget.editor.document;
        final limit = vertical ? doc.width : doc.height;
        if (pos < 0 || pos > limit) return;
        widget.editor.updateGuides(
          (x) => vertical
              ? x.copyWith(vertical: [...x.vertical, pos.roundToDouble()])
              : x.copyWith(horizontal: [...x.horizontal, pos.roundToDouble()]),
        );
      },
      child: MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeUpDown
            : SystemMouseCursors.resizeLeftRight,
        child: CustomPaint(
          painter: _Ruler(
            horizontal: horizontal,
            unit: widget.rulerUnit,
            dpi: widget.editor.document.dpi,
            reference: horizontal
                ? widget.editor.document.width
                : widget.editor.document.height,
            scale: _vp.scale,
            origin: horizontal
                ? _vp.offset.dx - _Ruler.thickness
                : _vp.offset.dy - _Ruler.thickness,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            background: Theme.of(context).colorScheme.surfaceContainerHigh,
          ),
        ),
      ),
    );
  }
}

/// Ruler with tick marks in the chosen unit (px, cm, mm, in, pt, %).
class _Ruler extends CustomPainter {
  _Ruler({
    required this.horizontal,
    required this.unit,
    required this.dpi,
    required this.reference,
    required this.scale,
    required this.origin,
    required this.color,
    required this.background,
  });

  static const double thickness = 22;

  final bool horizontal;
  final MeasureUnit unit;
  final double dpi;

  /// Canvas size along this ruler (100 % for percent units).
  final double reference;
  final double scale;

  /// Screen position (along the ruler) of canvas coordinate 0.
  final double origin;
  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final length = horizontal ? size.width : size.height;
    // Pick a step giving labels at least ~64 px apart.
    // Work in the ruler's unit: `k` document px per unit.
    final k = unit.pixelsPerUnit(dpi, reference: reference);
    final s = scale * k; // screen px per unit
    const steps = [
      0.01,
      0.02,
      0.05,
      0.1,
      0.2,
      0.25,
      0.5,
      1,
      2,
      5,
      10,
      20,
      25,
      50,
      100,
      200,
      250,
      500,
      1000,
      2000,
      5000,
      10000,
    ];
    final step = steps.firstWhere((x) => x * s >= 64, orElse: () => 20000);
    final minor = step / 5;
    final start = ((-origin) / s / minor).floor() * minor;
    final tick = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var i = 0; ; i++) {
      final v = start + i * minor;
      final pos = v * s + origin;
      if (pos > length) break;
      if (pos < 0) continue;
      final major = ((v / step) - (v / step).roundToDouble()).abs() < 1e-6;
      final len = major ? thickness * 0.55 : thickness * 0.25;
      if (horizontal) {
        canvas.drawLine(
          Offset(pos, thickness),
          Offset(pos, thickness - len),
          tick,
        );
      } else {
        canvas.drawLine(
          Offset(thickness, pos),
          Offset(thickness - len, pos),
          tick,
        );
      }
      if (major) {
        final tp = TextPainter(
          text: TextSpan(
            text: unit.format(v.abs() < 1e-9 ? 0 : v),
            style: TextStyle(fontSize: 9, color: color),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        if (horizontal) {
          tp.paint(canvas, Offset(pos + 2, 1));
        } else {
          canvas
            ..save()
            ..translate(1, pos + 2 + tp.width)
            ..rotate(-math.pi / 2);
          tp.paint(canvas, Offset.zero);
          canvas.restore();
        }
        tp.dispose();
      }
    }
    canvas.drawLine(
      horizontal ? Offset(0, size.height - 0.5) : Offset(size.width - 0.5, 0),
      horizontal
          ? Offset(size.width, size.height - 0.5)
          : Offset(size.width - 0.5, size.height),
      Paint()..color = color.withValues(alpha: 0.3),
    );
  }

  @override
  bool shouldRepaint(_Ruler old) =>
      old.scale != scale ||
      old.unit != unit ||
      old.dpi != dpi ||
      old.reference != reference ||
      old.origin != origin ||
      old.color != color ||
      old.background != background;
}

class _DocumentPainter extends CustomPainter {
  _DocumentPainter({
    required this.editor,
    required this.scale,
    required this.offset,
    required this.checkerA,
    required this.checkerB,
    required this.shadow,
    required this.devicePixelRatio,
  }) : super(repaint: editor);

  final double devicePixelRatio;

  final EditorController editor;
  final double scale;
  final Offset offset;
  final Color checkerA, checkerB, shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final doc = editor.document;
    final screenRect = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      doc.width * scale,
      doc.height * scale,
    );

    canvas.drawRect(
      screenRect.shift(const Offset(0, 6)),
      Paint()
        ..color = shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    if (doc.background == null || doc.background!.primary.a < 1) {
      paintCheckerboard(canvas, screenRect, checkerA, checkerB, cell: 10);
    }

    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);
    editor.viewRenderer(scale * devicePixelRatio).paint(canvas, doc);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DocumentPainter old) =>
      old.scale != scale ||
      old.offset != offset ||
      old.editor != editor ||
      old.devicePixelRatio != devicePixelRatio ||
      old.checkerA != checkerA;
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.editor,
    required this.tool,
    required this.ctx,
    required this.pendingGuide,
    required ValueNotifier<int> tick,
    required this.scale,
    required this.offset,
    required this.guideColor,
  }) : super(
         repaint: Listenable.merge([editor, tick, pendingGuide, tool.repaint]),
       );

  final Color guideColor;

  final EditorController editor;
  final EditorTool tool;
  final ToolContext ctx;
  final ValueNotifier<(bool, double)?> pendingGuide;
  final double scale;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    final doc = editor.document;
    paintGuides(canvas, doc, ctx.viewport, guideColor: guideColor);
    final pending = pendingGuide.value;
    if (pending != null) {
      final (vertical, pos) = pending;
      final vp = ctx.viewport;
      final inside = vertical
          ? pos >= 0 && pos <= doc.width
          : pos >= 0 && pos <= doc.height;
      final p = Paint()
        ..color = inside ? guideColor : guideColor.withValues(alpha: 0.5)
        ..strokeWidth = 1.5;
      if (vertical) {
        final x = vp.toScreen(Offset(pos, 0)).dx;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      } else {
        final y = vp.toScreen(Offset(0, pos)).dy;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      }
    }
    tool.paintOverlay(canvas, size, ctx);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.scale != scale ||
      old.offset != offset ||
      old.tool != tool ||
      old.guideColor != guideColor;
}
