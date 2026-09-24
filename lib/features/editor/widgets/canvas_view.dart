import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../editor/editor_controller.dart';
import '../../../editor/tools/editor_tool.dart';
import '../../../ui/widgets/checkerboard.dart';

/// Lets the page ask the canvas to re-fit (e.g. from a toolbar button).
class CanvasViewController extends ChangeNotifier {
  void fit() => notifyListeners();
}

/// The interactive canvas: renders the document, owns the viewport
/// (pan/zoom) and forwards input to the active [EditorTool].
class CanvasView extends StatefulWidget {
  const CanvasView({
    super.key,
    required this.editor,
    required this.tool,
    required this.snapping,
    required this.showGrid,
    this.controller,
  });

  final EditorController editor;
  final EditorTool tool;
  final bool snapping;
  final bool showGrid;
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

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_animateFit);
  }

  @override
  void didUpdateWidget(CanvasView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_animateFit);
      widget.controller?.addListener(_animateFit);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_animateFit);
    _anim.dispose();
    _overlayTick.dispose();
    super.dispose();
  }

  ToolContext get _ctx {
    final pix = PixColors.of(context);
    return ToolContext(
      editor: widget.editor,
      viewport: _vp,
      snapping: widget.snapping,
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
        return ClipRect(
          child: ColoredBox(
            color: pix.canvasBackdrop,
            child: Listener(
              onPointerSignal: _onPointerSignal,
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
                      ),
                      foregroundPainter: _OverlayPainter(
                        editor: widget.editor,
                        tool: widget.tool,
                        ctx: _ctx,
                        showGrid: widget.showGrid,
                        tick: _overlayTick,
                        scale: _vp.scale,
                        offset: _vp.offset,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DocumentPainter extends CustomPainter {
  _DocumentPainter({
    required this.editor,
    required this.scale,
    required this.offset,
    required this.checkerA,
    required this.checkerB,
    required this.shadow,
  }) : super(repaint: editor);

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
    editor.renderer.paint(canvas, doc);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DocumentPainter old) =>
      old.scale != scale ||
      old.offset != offset ||
      old.editor != editor ||
      old.checkerA != checkerA;
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.editor,
    required this.tool,
    required this.ctx,
    required this.showGrid,
    required ValueNotifier<int> tick,
    required this.scale,
    required this.offset,
  }) : super(repaint: Listenable.merge([editor, tick]));

  final EditorController editor;
  final EditorTool tool;
  final ToolContext ctx;
  final bool showGrid;
  final double scale;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    final doc = editor.document;
    if (showGrid) {
      final r = Rect.fromLTWH(
        offset.dx,
        offset.dy,
        doc.width * scale,
        doc.height * scale,
      );
      final p = Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 1;
      final shadow = Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..strokeWidth = 2.5;
      for (var i = 1; i < 3; i++) {
        final x = r.left + r.width * i / 3, y = r.top + r.height * i / 3;
        for (final paint in [shadow, p]) {
          canvas
            ..drawLine(Offset(x, r.top), Offset(x, r.bottom), paint)
            ..drawLine(Offset(r.left, y), Offset(r.right, y), paint);
        }
      }
    }
    tool.paintOverlay(canvas, size, ctx);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.scale != scale ||
      old.offset != offset ||
      old.showGrid != showGrid ||
      old.tool != tool;
}
