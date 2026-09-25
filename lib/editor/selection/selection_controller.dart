import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../document/model/document.dart';
import '../editor_controller.dart';
import 'pixel_selection.dart';

/// The canvas tools of the Select menu.
enum SelectToolKind {
  rectangle,
  ellipse,
  lasso,
  polygon,
  pen,
  magicWand,
  colorRange,
  luminance,
}

/// Luminance presets (Photoshop's Color Range → Highlights / Midtones /
/// Shadows).
enum LuminancePreset { shadows, midtones, highlights }

/// Photoshop-like pixel selection: which tool the canvas uses, how new
/// selections combine, the current selection with its own undo history,
/// and the overlay (dimmed outside + marching ants) the canvas draws.
///
/// The selection is editor state, not part of the document; actions
/// (mask, copy, cut, fill, crop…) turn it into document edits.
class SelectionController extends ChangeNotifier {
  SelectToolKind _tool = SelectToolKind.rectangle;
  SelectionMode _mode = SelectionMode.replace;
  String? _targetId;
  int _tolerance = 32;
  bool _contiguous = true;
  int _fuzziness = 60;
  double _lumFrom = 0.7, _lumTo = 1, _lumSoft = 0.12;
  bool _busy = false;

  PixelSelection? _current;
  final List<PixelSelection?> _undo = [];
  final List<PixelSelection?> _redo = [];

  /// Where Color Range sampled and what the selection was before it, so
  /// the fuzziness slider can redo it live.
  Offset? _rangePoint;
  Color? _rangeColor;
  PixelSelection? _rangeBase;

  /// Selection before the luminance tool started previewing.
  PixelSelection? _lumBase;
  bool _lumLive = false;

  // Overlay.
  ui.Image? _maskImage;
  ui.Path? _outline;
  int _overlayGen = 0;

  /// Bumps while the tool is active to animate the marching ants.
  final ValueNotifier<int> ants = ValueNotifier(0);
  Timer? _antsTimer;

  SelectToolKind get tool => _tool;
  SelectionMode get mode => _mode;

  /// Layer the selection samples and acts on; null = the whole canvas.
  String? get targetId => _targetId;
  int get tolerance => _tolerance;
  bool get contiguous => _contiguous;
  int get fuzziness => _fuzziness;
  double get lumFrom => _lumFrom;
  double get lumTo => _lumTo;
  double get lumSoftness => _lumSoft;
  Color? get rangeColor => _rangeColor;

  /// True while a pixel operation runs.
  bool get busy => _busy;

  PixelSelection? get current => _current;
  bool get hasSelection => _current != null;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// White image whose alpha is the selection (document-sized grid).
  ui.Image? get maskImage => _maskImage;

  /// Selection edge in document space.
  ui.Path? get outline => _outline;

  set tool(SelectToolKind v) {
    if (_tool == v) return;
    _endLuminance();
    _tool = v;
    notifyListeners();
  }

  set mode(SelectionMode v) => _set(() => _mode = v);
  set targetId(String? v) => _set(() {
    _targetId = v;
    _sample = null;
  });
  set tolerance(int v) => _set(() => _tolerance = v.clamp(0, 255));
  set contiguous(bool v) => _set(() => _contiguous = v);

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  /// Starts / stops the marching-ants animation.
  void setActive(bool active) {
    if (active) {
      _antsTimer ??= Timer.periodic(
        const Duration(milliseconds: 90),
        (_) => ants.value++,
      );
    } else {
      _antsTimer?.cancel();
      _antsTimer = null;
      _endLuminance();
    }
  }

  @override
  void dispose() {
    _antsTimer?.cancel();
    _maskImage?.dispose();
    ants.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ state

  /// An empty grid for [doc] (drops a selection made for another size).
  PixelSelection grid(PixDocument doc) {
    final c = _current;
    final fresh = PixelSelection.empty(doc.width, doc.height);
    if (c != null && (c.width != fresh.width || c.height != fresh.height)) {
      _current = null;
      _undo.clear();
      _redo.clear();
      _rebuildOverlay();
    }
    return fresh;
  }

  /// Replaces the selection (an undo step). An empty result deselects.
  void set(PixelSelection? next, {bool record = true}) {
    if (record) {
      _undo.add(_current);
      if (_undo.length > 40) _undo.removeAt(0);
      _redo.clear();
    }
    _current = (next == null || next.isEmpty) ? null : next;
    _rangePoint = null;
    _rebuildOverlay();
    notifyListeners();
  }

  /// Combines [next] into the selection with the current [mode].
  void combine(PixelSelection next, {SelectionMode? mode}) {
    final m = mode ?? _mode;
    final c = _current;
    if (c == null || m == SelectionMode.replace) {
      // Subtracting from / intersecting with nothing leaves nothing.
      set(
        m == SelectionMode.subtract || m == SelectionMode.intersect
            ? null
            : next,
      );
      return;
    }
    set(c.combine(next, m));
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_current);
    _current = _undo.removeLast();
    _rangePoint = null;
    _rebuildOverlay();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_current);
    _current = _redo.removeLast();
    _rangePoint = null;
    _rebuildOverlay();
    notifyListeners();
  }

  void selectAll(PixDocument doc) => set(grid(doc).all());
  void deselect() {
    if (_current != null) set(null);
  }

  void invert(PixDocument doc) => set((_current ?? grid(doc)).inverted());

  /// Applies a modification (feather, expand, smooth…) to the selection.
  void modify(PixelSelection Function(PixelSelection s) f) {
    final c = _current;
    if (c == null) return;
    set(f(c));
  }

  // ------------------------------------------------------------ overlay

  void _rebuildOverlay() {
    final gen = ++_overlayGen;
    final c = _current;
    if (c == null) {
      _maskImage?.dispose();
      _maskImage = null;
      _outline = null;
      return;
    }
    _outline = c.outline();
    ui.decodeImageFromPixels(
      c.toRgba(),
      c.width,
      c.height,
      ui.PixelFormat.rgba8888,
      (img) {
        if (gen != _overlayGen) {
          img.dispose();
          return;
        }
        _maskImage?.dispose();
        _maskImage = img;
        notifyListeners();
      },
    );
  }

  // ------------------------------------------------------------ sampling

  (PixDocument, String?, int)? _sampleKey;
  Uint8List? _sample;

  /// Pixels the pick tools look at, on the selection grid: the whole
  /// canvas (with background) or only the target layer.
  Future<Uint8List?> sample(EditorController editor) async {
    final doc = editor.document;
    final g = grid(doc);
    final key = (doc, _targetId, g.width);
    if (_sample != null && _sampleKey == key) return _sample;
    PixDocument src = doc;
    final id = _targetId;
    if (id != null) {
      final l = doc.layerById(id);
      if (l == null) return null;
      src = doc.copyWith(clearBackground: true, layers: [l]);
    }
    final img = await editor.renderer.renderImage(
      src,
      width: g.width,
      height: g.height,
    );
    final data = await img.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    img.dispose();
    if (data == null) return null;
    _sampleKey = key;
    _sample = data.buffer.asUint8List();
    return _sample;
  }

  /// Colour of the sampled pixels at a document point.
  Future<Color?> colorAt(EditorController editor, Offset doc) async {
    final px = await sample(editor);
    if (px == null) return null;
    final g = grid(editor.document);
    final x = (doc.dx * g.scale).floor(), y = (doc.dy * g.scale).floor();
    if (x < 0 || y < 0 || x >= g.width || y >= g.height) return null;
    final i = (y * g.width + x) * 4;
    return Color.fromARGB(px[i + 3], px[i], px[i + 1], px[i + 2]);
  }

  Future<void> _run(Future<void> Function() f) async {
    _busy = true;
    notifyListeners();
    try {
      await f();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ tools

  /// Fills [docPath] (document space) into the selection.
  Future<void> addPath(EditorController editor, ui.Path docPath) =>
      _run(() async {
        final g = grid(editor.document);
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
          ..scale(g.scale)
          ..drawPath(
            docPath,
            ui.Paint()
              ..isAntiAlias = true
              ..color = const Color(0xFFFFFFFF),
          );
        final picture = recorder.endRecording();
        final img = await picture.toImage(g.width, g.height);
        picture.dispose();
        final data = await img.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        img.dispose();
        if (data == null) return;
        combine(g.fromAlpha(data.buffer.asUint8List()));
        return;
      });

  Future<void> magicWand(EditorController editor, Offset doc) => _run(() async {
    final px = await sample(editor);
    if (px == null) return;
    final g = grid(editor.document);
    combine(
      g.magicWand(px, doc, tolerance: _tolerance, contiguous: _contiguous),
    );
    return;
  });

  /// Color Range from the colour under [doc].
  Future<void> colorRangeAt(EditorController editor, Offset doc) =>
      _run(() async {
        final color = await colorAt(editor, doc);
        if (color == null) return;
        final base = _current;
        await _applyRange(editor, color, base, record: true);
        _rangePoint = doc;
        _rangeColor = color;
        _rangeBase = base;
        notifyListeners();
        return;
      });

  Future<void> _applyRange(
    EditorController editor,
    Color color,
    PixelSelection? base, {
    required bool record,
  }) async {
    final px = await sample(editor);
    if (px == null) return;
    final g = grid(editor.document);
    final range = g.colorRange(px, color, fuzziness: _fuzziness);
    final m = _mode;
    PixelSelection? next;
    if (base == null || m == SelectionMode.replace) {
      next = m == SelectionMode.subtract || m == SelectionMode.intersect
          ? null
          : range;
    } else {
      next = base.combine(range, m);
    }
    final keepPoint = _rangePoint;
    set(next, record: record);
    _rangePoint = keepPoint;
  }

  /// Fuzziness; re-applies the last Color Range pick live.
  Future<void> setFuzziness(EditorController editor, int v) async {
    _fuzziness = v.clamp(0, 255);
    notifyListeners();
    final c = _rangeColor;
    if (c == null || _rangePoint == null || _busy) return;
    await _applyRange(editor, c, _rangeBase, record: false);
  }

  void setLuminance({double? from, double? to, double? softness}) {
    _lumFrom = from ?? _lumFrom;
    _lumTo = to ?? _lumTo;
    _lumSoft = softness ?? _lumSoft;
    notifyListeners();
  }

  void lumPreset(LuminancePreset p) => setLuminance(
    from: switch (p) {
      LuminancePreset.shadows => 0,
      LuminancePreset.midtones => 0.35,
      LuminancePreset.highlights => 0.7,
    },
    to: switch (p) {
      LuminancePreset.shadows => 0.3,
      LuminancePreset.midtones => 0.65,
      LuminancePreset.highlights => 1,
    },
    softness: 0.12,
  );

  /// Selects by brightness. The first call is an undo step; later calls
  /// (slider moves) refine it in place until the tool changes.
  Future<void> luminance(EditorController editor) => _run(() async {
    final px = await sample(editor);
    if (px == null) return;
    final g = grid(editor.document);
    final lum = g.luminanceRange(
      px,
      from: _lumFrom,
      to: _lumTo,
      softness: _lumSoft,
    );
    if (!_lumLive) {
      _lumBase = _current;
      _lumLive = true;
      _combineOnto(_lumBase, lum, record: true);
    } else {
      _combineOnto(_lumBase, lum, record: false);
    }
    return;
  });

  void _combineOnto(
    PixelSelection? base,
    PixelSelection next, {
    required bool record,
  }) {
    final m = _mode;
    PixelSelection? out;
    if (base == null || m == SelectionMode.replace) {
      out = m == SelectionMode.subtract || m == SelectionMode.intersect
          ? null
          : next;
    } else {
      out = base.combine(next, m);
    }
    set(out, record: record);
  }

  void _endLuminance() {
    _lumLive = false;
    _lumBase = null;
  }

  /// Photoshop's Ctrl+click on a layer thumbnail: the layer's pixels
  /// (alpha) become the selection.
  Future<void> layerPixels(EditorController editor, String layerId) =>
      _run(() async {
        final doc = editor.document;
        final l = doc.layerById(layerId);
        if (l == null) return;
        final g = grid(doc);
        final img = await editor.renderer.renderImage(
          doc.copyWith(clearBackground: true, layers: [l]),
          width: g.width,
          height: g.height,
        );
        final data = await img.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        img.dispose();
        if (data == null) return;
        combine(g.fromAlpha(data.buffer.asUint8List()));
        return;
      });
}
