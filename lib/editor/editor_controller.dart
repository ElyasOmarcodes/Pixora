import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Alignment;

import '../core/utils/ids.dart';
import '../document/assets/asset_store.dart';
import '../document/effects/effect_registry.dart';
import '../document/model/document.dart';
import '../document/model/effect.dart';
import '../document/model/fill.dart';
import '../document/model/guides.dart';
import '../document/model/blend.dart';
import '../document/model/layer.dart';
import '../document/model/layer_geometry.dart';
import '../document/model/layer_stroke.dart';
import '../document/model/layer_transform.dart';
import '../document/model/mask.dart';
import '../document/model/patterns.dart';
import '../document/render/mask_jobs.dart';
import '../document/render/text_layout.dart';
import '../document/render/document_renderer.dart';
import '../document/render/layer_cache.dart';
import '../document/render/brush_paint.dart';
import '../document/render/vector_paths.dart';
import 'history.dart';
import 'selection/pixel_selection.dart';

/// Signature of a document edit. Every change to a document is expressed as
/// one of these pure functions.
typedef DocOp = PixDocument Function(PixDocument doc);

enum LayerArrange { forward, backward, front, back }

enum LayerAlign { left, centerH, right, top, centerV, bottom }

/// The single source of truth for an open project.
///
/// UI widgets, keyboard shortcuts, automation scripts and (later) the AI
/// agent all edit the document through this controller, so every path gets
/// undo/redo, selection handling and autosave for free.
///
/// Two ways to edit:
/// * [apply] — a discrete edit, recorded in history immediately.
/// * [preview] + [commit] — continuous edits (dragging, sliders). Previews
///   update the canvas live; [commit] records the whole gesture as one undo
///   step.
class EditorController extends ChangeNotifier {
  EditorController({required PixDocument document, AssetStore? assets})
    // ignore: prefer_initializing_formals
    : _document = document,
      assets = assets ?? AssetStore() {
    this.assets.addListener(_onAssetsChanged);
    Patterns.addLookup(this.assets.imageOf);
    MaskJobCache.instance.addListener(_onBevelReady);
  }

  /// A bevel finished computing in the background: repaint.
  void _onBevelReady() {
    paintRevision++;
    notifyListeners();
  }

  final AssetStore assets;
  final History history = History();

  PixDocument _document;
  List<String> _selection = const [];
  HistoryEntry? _previewBase;

  /// Increments whenever the committed document changes (autosave hook).
  int revision = 0;

  /// Increments on any visual change including previews (repaint hook).
  int paintRevision = 0;

  PixDocument get document => _document;

  /// Selected layer ids; the primary selection (the one property panels
  /// edit) is last.
  List<String> get selectedIds => _selection;
  String? get selectedId => _selection.isEmpty ? null : _selection.last;
  Layer? get selectedLayer => _document.layerById(selectedId);
  List<Layer> get selectedLayers => [
    for (final id in _selection) ?_document.layerById(id),
  ];
  bool get hasMultiSelection => _selection.length > 1;
  bool isSelected(String id) => _selection.contains(id);

  bool get isPreviewing => _previewBase != null;
  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  DocumentRenderer get renderer => DocumentRenderer(assets);

  /// Bitmap cache for expensive layers on the on-screen canvas.
  final LayerRasterCache rasterCache = LayerRasterCache();

  /// Renderer for the canvas at [pixelScale] output pixels per document
  /// pixel, drawing expensive layers from [rasterCache].
  DocumentRenderer viewRenderer(double pixelScale) =>
      DocumentRenderer(assets, cache: rasterCache, pixelScale: pixelScale);

  void _onAssetsChanged() {
    // Text layouts bake their shader; rebuild them once an image pattern
    // they use has decoded.
    if (_document.allLayers.any(
      (l) => l is TextLayer && l.fillAssets.isNotEmpty,
    )) {
      TextLayoutCache.instance.clear();
    }
    paintRevision++;
    notifyListeners();
  }

  List<String> _valid(PixDocument d, Iterable<String> ids) => [
    for (final id in ids)
      if (d.contains(id)) id,
  ];

  // ------------------------------------------------------------ core API

  /// Applies a discrete, undoable edit. If previews are pending they are
  /// folded into the same undo step. [select] replaces the selection with
  /// one layer, [selectIds] with several; [deselect] clears it.
  void apply(
    String label,
    DocOp op, {
    String? select,
    List<String>? selectIds,
    bool deselect = false,
  }) {
    final base = _previewBase ?? HistoryEntry(_document, _selection, label);
    _previewBase = null;
    final next = op(_document);
    final wanted = deselect
        ? const <String>[]
        : selectIds ?? (select != null ? [select] : _selection);
    final nextSel = _valid(next, wanted);
    final unchanged =
        next == base.document && listEquals(nextSel, base.selection);
    _document = next;
    _selection = nextSel;
    if (unchanged) {
      _changed(committed: false);
      return;
    }
    history.push(HistoryEntry(base.document, base.selection, label));
    _changed(committed: true);
  }

  /// Live update without recording history (call [commit] when done).
  void preview(DocOp op) {
    _previewBase ??= HistoryEntry(_document, _selection, '');
    _document = op(_document);
    _changed(committed: false);
  }

  /// Like [preview], but [op] always starts from the document as it was
  /// before the preview began — for gestures that rebuild their whole
  /// result every frame (a growing brush stroke), so earlier frames don't
  /// pile up.
  void previewFromStart(DocOp op) {
    _previewBase ??= HistoryEntry(_document, _selection, '');
    _document = op(_previewBase!.document);
    _changed(committed: false);
  }

  /// Records everything since the first [preview] as one undo step.
  void commit(String label) {
    final base = _previewBase;
    if (base == null) return;
    _previewBase = null;
    if (base.document == _document) return;
    history.push(HistoryEntry(base.document, base.selection, label));
    _changed(committed: true);
  }

  /// Reverts all previews since the last commit.
  void cancelPreview() {
    final base = _previewBase;
    if (base == null) return;
    _previewBase = null;
    _document = base.document;
    _changed(committed: false);
  }

  /// Changes the document without an undo step (UI state stored in the
  /// document, such as whether a group is expanded in the layers panel).
  void _silent(DocOp op) {
    _document = op(_document);
    _changed(committed: true);
  }

  void undo() {
    if (_previewBase != null) cancelPreview();
    final prev = history.undo(HistoryEntry(_document, _selection, ''));
    if (prev == null) return;
    _restore(prev);
  }

  void redo() {
    if (_previewBase != null) cancelPreview();
    final next = history.redo(HistoryEntry(_document, _selection, ''));
    if (next == null) return;
    _restore(next);
  }

  void _restore(HistoryEntry e) {
    _document = e.document;
    _selection = _valid(_document, e.selection);
    _changed(committed: true);
  }

  // ----------------------------------------------------------- selection

  void _setSelection(List<String> ids) {
    final next = _valid(_document, ids);
    if (listEquals(next, _selection)) return;
    if (_previewBase != null) commit('edit');
    _selection = next;
    paintRevision++;
    notifyListeners();
  }

  /// Selects exactly one layer (or nothing).
  void select(String? id) => _setSelection(id == null ? const [] : [id]);

  void selectMany(List<String> ids) => _setSelection(ids);

  /// Adds/removes a layer from the selection (Ctrl/Shift-click, checkbox).
  void toggleSelect(String id) => _setSelection(
    _selection.contains(id)
        ? [
            for (final s in _selection)
              if (s != id) s,
          ]
        : [..._selection, id],
  );

  void selectAll() => _setSelection([for (final l in _document.layers) l.id]);

  void deselect() => _setSelection(const []);

  /// The selection without layers whose group is also selected — the set
  /// that should move/duplicate/delete as units.
  List<String> get topLevelSelection {
    final sel = _selection.toSet();
    return [
      for (final l in _document.allLayers)
        if (sel.contains(l.id) &&
            !_document.ancestorsOf(l.id).any((g) => sel.contains(g.id)))
          l.id,
    ];
  }

  void _changed({required bool committed}) {
    if (committed) revision++;
    paintRevision++;
    notifyListeners();
  }

  @override
  void dispose() {
    assets.removeListener(_onAssetsChanged);
    Patterns.removeLookup(assets.imageOf);
    MaskJobCache.instance.removeListener(_onBevelReady);
    rasterCache.clear();
    super.dispose();
  }

  // ------------------------------------------------------ layer creation

  double get _unit => math.min(_document.width, _document.height);

  String _nextName(String base) {
    final used = {for (final l in _document.allLayers) l.props.name};
    for (var i = 1; ; i++) {
      final name = '$base $i';
      if (!used.contains(name)) return name;
    }
  }

  /// New layers go directly above the primary selection, inside the same
  /// group (like Photoshop); with nothing selected, on top of the stack.
  PixDocument _insertAtCursor(PixDocument d, Layer layer) {
    final anchor = selectedId;
    if (anchor == null || !d.contains(anchor)) return d.insertLayer(layer);
    return d.insertLayer(
      layer,
      parentId: d.parentOf(anchor)?.id,
      index: d.indexOf(anchor) + 1,
    );
  }

  TextLayer addText(
    String text, {
    String name = 'Text',
    Color? color,
    String? fontFamily,
  }) {
    final layer = TextLayer(
      LayerProps(
        name: _nextName(name),
        transform: LayerTransform(
          x: _document.center.dx,
          y: _document.center.dy,
        ),
      ),
      text: text,
      fontFamily: fontFamily ?? 'Vazirmatn',
      fontSize: (_unit * 0.09).roundToDouble(),
      fill: color == null ? null : PixFill.color(color),
    );
    apply('add_text', (d) => _insertAtCursor(d, layer), select: layer.id);
    return layer;
  }

  ShapeLayer addShape(ShapeKind kind, {String name = 'Shape', Color? color}) {
    final size = (_unit * 0.36).roundToDouble();
    final layer = ShapeLayer(
      LayerProps(
        name: _nextName(name),
        transform: LayerTransform(
          x: _document.center.dx,
          y: _document.center.dy,
        ),
      ),
      shape: kind,
      width: size,
      height: kind == ShapeKind.line ? math.max(4, size * 0.04) : size,
      fill: PixFill.color(color ?? const Color(0xFFFFFFFF)),
      cornerRadius: kind == ShapeKind.rectangle ? size * 0.12 : 0,
      sides: kind == ShapeKind.polygon ? 6 : 5,
    );
    apply('add_shape', (d) => _insertAtCursor(d, layer), select: layer.id);
    return layer;
  }

  /// Adds an encoded image as a new raster layer, fitted inside the canvas.
  Future<RasterLayer> addImage(Uint8List bytes, {String name = 'Image'}) async {
    final size = await measureImage(bytes);
    final assetId = assets.add(bytes);
    unawaited(assets.decode(assetId));
    final fit = math.min(
      1.0,
      math.min(
        _document.width * 0.9 / size.width,
        _document.height * 0.9 / size.height,
      ),
    );
    final layer = RasterLayer(
      LayerProps(
        name: _nextName(name),
        transform: LayerTransform(
          x: _document.center.dx,
          y: _document.center.dy,
          scaleX: fit,
          scaleY: fit,
        ),
      ),
      assetId: assetId,
      width: size.width,
      height: size.height,
    );
    apply('add_image', (d) => _insertAtCursor(d, layer), select: layer.id);
    return layer;
  }

  /// Swaps the pixels of a raster layer, keeping its on-canvas width.
  Future<void> replaceImage(String id, Uint8List bytes) async {
    final current = _document.layerById(id);
    if (current is! RasterLayer) return;
    final size = await measureImage(bytes);
    final assetId = assets.add(bytes);
    unawaited(assets.decode(assetId));
    updateLayer(id, (l) {
      final r = l as RasterLayer;
      final t = r.props.transform;
      final k = r.width * t.scaleX.abs() / size.width;
      return r
          .copyWith(assetId: assetId, width: size.width, height: size.height)
          .update(
            (p) => p.copyWith(
              transform: t.copyWith(
                scaleX: k * t.scaleX.sign,
                scaleY: k * t.scaleY.sign,
              ),
            ),
          );
    }, label: 'replace_image');
  }

  /// Replaces an image's pixels with a cropped version, keeping the
  /// original for later re-crops and the on-canvas pixel scale.
  void applyCrop(
    String id,
    Uint8List bytes,
    double width,
    double height,
    CropState state,
  ) {
    final current = _document.layerById(id);
    if (current is! RasterLayer) return;
    final assetId = assets.add(bytes);
    unawaited(assets.decode(assetId));
    final source = current.sourceAssetId ?? current.assetId;
    // One original pixel keeps its on-canvas size: it was `prevRes` image
    // pixels before and is `state.resolution` pixels now.
    final k = (current.crop?.resolution ?? 1) / state.resolution;
    updateLayer(id, (l) {
      final r = l as RasterLayer;
      final t = r.props.transform;
      return r
          .copyWith(
            assetId: assetId,
            width: width,
            height: height,
            sourceAssetId: source,
            crop: state,
          )
          .update(
            (p) => p.copyWith(
              transform: t.copyWith(scaleX: t.scaleX * k, scaleY: t.scaleY * k),
            ),
          );
    }, label: 'crop');
  }

  // ------------------------------------------------------- layer editing

  void updateLayer(
    String id,
    Layer Function(Layer l) f, {
    String label = 'edit',
  }) => apply(label, (d) => d.updateLayer(id, f));

  void previewLayer(String id, Layer Function(Layer l) f) =>
      preview((d) => d.updateLayer(id, f));

  void updateProps(
    String id,
    LayerProps Function(LayerProps p) f, {
    String label = 'edit',
    bool live = false,
  }) => live
      ? previewLayer(id, (l) => l.update(f))
      : updateLayer(id, (l) => l.update(f), label: label);

  void deleteLayer(String id) => deleteLayers([id]);

  void deleteLayers(List<String> ids) {
    if (ids.isEmpty) return;
    final set = ids.toSet();
    apply(
      'delete_layer',
      (d) => d.removeLayers(set),
      selectIds: [
        for (final s in _selection)
          if (!set.contains(s)) s,
      ],
    );
  }

  void deleteSelected() => deleteLayers(topLevelSelection);

  Layer? duplicateLayer(String id) => duplicateLayers([id]).firstOrNull;

  /// Duplicates each layer directly above its original and selects the
  /// copies.
  List<Layer> duplicateLayers(List<String> ids) {
    final offset = _unit * 0.03;
    final copies = <Layer>[];
    var d = _document;
    for (final id in ids) {
      final l = d.layerById(id);
      if (l == null) continue;
      final copy = applySimilarity(
        l.cloneWithNewId(name: '${l.props.name} copy'),
        Similarity(translate: Offset(offset, offset)),
      );
      d = d.insertLayer(
        copy,
        parentId: d.parentOf(id)?.id,
        index: d.indexOf(id) + 1,
      );
      copies.add(copy);
    }
    if (copies.isEmpty) return copies;
    final result = d;
    apply(
      'duplicate_layer',
      (_) => result,
      selectIds: [for (final c in copies) c.id],
    );
    return copies;
  }

  void duplicateSelected() => duplicateLayers(topLevelSelection);

  void arrange(String id, LayerArrange a) {
    final i = _document.indexOf(id);
    if (i < 0) return;
    final top = _document.siblingsOf(id).length - 1;
    final target = switch (a) {
      LayerArrange.forward => math.min(top, i + 1),
      LayerArrange.backward => math.max(0, i - 1),
      LayerArrange.front => top,
      LayerArrange.back => 0,
    };
    if (target == i) return;
    apply('arrange', (d) => d.moveLayerTo(id, target));
  }

  void moveLayerTo(String id, int index) =>
      apply('reorder', (d) => d.moveLayerTo(id, index));

  /// Moves a layer into another group (or to the top level) at [index].
  void moveLayer(String id, {String? parentId, required int index}) => apply(
    'reorder',
    (d) => d.moveLayer(id, parentId: parentId, index: index),
  );

  void toggleVisible(String id) => updateProps(
    id,
    (p) => p.copyWith(visible: !p.visible),
    label: 'visibility',
  );

  void toggleLocked(String id) =>
      updateProps(id, (p) => p.copyWith(locked: !p.locked), label: 'lock');

  /// Sets visibility / lock for several layers in one undo step.
  void setVisible(List<String> ids, bool visible) => apply(
    'visibility',
    (d) => ids.fold(
      d,
      (d, id) => d.updateLayer(
        id,
        (l) => l.update((p) => p.copyWith(visible: visible)),
      ),
    ),
  );

  void setLocked(List<String> ids, bool locked) => apply(
    'lock',
    (d) => ids.fold(
      d,
      (d, id) =>
          d.updateLayer(id, (l) => l.update((p) => p.copyWith(locked: locked))),
    ),
  );

  /// Shows only [id] (Alt-click on the eye in Photoshop); calling it again
  /// on the same layer shows everything.
  void soloVisible(String id) {
    final others = [
      for (final l in _document.allLayers)
        if (l.id != id && !_document.ancestorsOf(id).any((g) => g.id == l.id))
          l,
    ];
    final alreadySolo = others.every((l) => !l.props.visible);
    apply(
      'visibility',
      (d) => d.mapLayers(
        (l) => l.id == id
            ? l.update((p) => p.copyWith(visible: true))
            : others.any((o) => o.id == l.id)
            ? l.update((p) => p.copyWith(visible: alreadySolo))
            : l,
      ),
    );
  }

  void rename(String id, String name) =>
      updateProps(id, (p) => p.copyWith(name: name), label: 'rename');

  void toggleClip(String id) =>
      updateProps(id, (p) => p.copyWith(clip: !p.clip), label: 'clipping_mask');

  void setExpanded(String groupId, bool expanded) {
    final g = _document.layerById(groupId);
    if (g is! GroupLayer || g.expanded == expanded) return;
    _silent((d) => d.replaceLayer(g.copyWith(expanded: expanded)));
  }

  /// Transforms layers as one rigid unit (used for groups and
  /// multi-selections, by the transform tool and the arrange panel).
  void transformLayers(
    List<String> ids,
    Similarity s, {
    String label = 'transform',
    bool live = false,
  }) {
    // Linked layers go along (Photoshop).
    final targets = withLinked(ids);
    PixDocument op(PixDocument d) => targets.fold(
      d,
      (d, id) => d.updateLayer(id, (l) => applySimilarity(l, s)),
    );
    live ? preview(op) : apply(label, op);
  }

  /// Moves the top-level selection by a document-space offset.
  void nudgeSelection(double dx, double dy) {
    final ids = [
      for (final id in topLevelSelection)
        if (!_document.isEffectivelyLocked(id)) id,
    ];
    if (ids.isEmpty) return;
    transformLayers(ids, Similarity(translate: Offset(dx, dy)), label: 'nudge');
  }

  List<String> get _movableSelection => [
    for (final id in topLevelSelection)
      if (!_document.isEffectivelyLocked(id)) id,
  ];

  /// Live (previewed) move of the selection by [total] from where it was
  /// when the gesture started; call [commit] at the end.
  void nudgeSelectionLive(Offset total) {
    final ids = _movableSelection;
    if (ids.isEmpty) return;
    transformLayers(ids, Similarity(translate: total), live: true);
  }

  /// Places the selection on the canvas at [a] (e.g. topLeft, center,
  /// bottomRight), flush with the edges.
  void placeOnCanvas(List<String> ids, Alignment a) {
    if (ids.isEmpty) return;
    final b = boundsOf(ids);
    final f = _document.bounds;
    final target = Offset(
      f.left + (a.x + 1) / 2 * (f.width - b.width),
      f.top + (a.y + 1) / 2 * (f.height - b.height),
    );
    transformLayers(
      ids,
      Similarity(translate: target - b.topLeft),
      label: 'place',
    );
  }

  /// Scales the selection to fit inside ([cover] = false) or fill the
  /// canvas, centred.
  void fitToCanvas(List<String> ids, {bool cover = false}) {
    if (ids.isEmpty) return;
    final b = boundsOf(ids);
    if (b.isEmpty) return;
    final f = _document.bounds;
    final sx = f.width / b.width, sy = f.height / b.height;
    final k = cover ? math.max(sx, sy) : math.min(sx, sy);
    transformLayers(
      ids,
      Similarity(pivot: b.center, scale: k, translate: f.center - b.center),
      label: cover ? 'fill_canvas' : 'fit_canvas',
    );
  }

  // ------------------------------------------------------- icons & paths

  /// Adds an icon (path data kept in the project) at the canvas centre.
  IconLayer addIcon(
    String iconName,
    String pathData, {
    IconStyle style = IconStyle.outlined,
    bool filled = false,
    int weight = 400,
    String name = 'Icon',
    Color? color,
  }) {
    final size = (_unit * 0.3).roundToDouble();
    final layer = IconLayer(
      LayerProps(
        name: _nextName(name),
        transform: LayerTransform(
          x: _document.center.dx,
          y: _document.center.dy,
        ),
      ),
      iconName: iconName,
      pathData: pathData,
      style: style,
      filled: filled,
      weight: weight,
      width: size,
      height: size,
      fill: color == null ? null : PixFill.color(color),
    );
    apply('add_icon', (d) => _insertAtCursor(d, layer), select: layer.id);
    return layer;
  }

  /// Swaps the icon of an icon layer, keeping size, colours and effects.
  void replaceIcon(
    String id,
    String iconName,
    String pathData, {
    IconStyle style = IconStyle.outlined,
    bool filled = false,
    int weight = 400,
  }) => updateLayer(
    id,
    (l) => l is IconLayer
        ? l.copyWith(
            iconName: iconName,
            pathData: pathData,
            style: style,
            filled: filled,
            weight: weight,
          )
        : l,
    label: 'replace_icon',
  );

  /// Adds a vector path layer at the canvas centre ([contours] in local
  /// coordinates around the origin) and selects it.
  PathLayer addPath(PathLayer template, {String name = 'Vector'}) {
    final layer = template.withProps(
      template.props.copyWith(
        name: _nextName(name),
        transform: LayerTransform(
          x: _document.center.dx,
          y: _document.center.dy,
        ),
      ),
    );
    apply('add_path', (d) => _insertAtCursor(d, layer), select: layer.id);
    return layer;
  }

  /// Adds an empty drawing layer at the canvas centre and selects it.
  DrawingLayer addDrawing({String name = 'Drawing'}) {
    final layer = DrawingLayer(
      LayerProps(
        name: _nextName(name),
        transform: LayerTransform(
          x: _document.center.dx,
          y: _document.center.dy,
        ),
      ),
    );
    apply('add_drawing', (d) => _insertAtCursor(d, layer), select: layer.id);
    return layer;
  }

  /// Adds a brush stroke to a drawing layer ([live] = while drawing).
  void addBrushStroke(String id, BrushStroke stroke, {bool live = false}) {
    DrawingLayer op(Layer l) {
      final d = l as DrawingLayer;
      return d.copyWith(strokes: [...d.strokes, stroke]);
    }

    live
        ? previewFromStart((d) => d.updateLayer(id, op))
        : updateLayer(id, op, label: 'draw');
  }

  /// Re-centres a drawing on its origin without moving it on the canvas.
  void normalizeDrawing(String id) {
    final l = _document.layerById(id);
    if (l is! DrawingLayer || l.strokes.isEmpty) return;
    final c = drawingRect(l).center;
    if (c.distance < 0.01) return;
    final t = l.props.transform;
    final shift = t.toDocument(c) - t.toDocument(Offset.zero);
    _silent(
      (d) => d.updateLayer(
        id,
        (x) => (x as DrawingLayer).copyWith(
          props: x.props.copyWith(
            transform: t.copyWith(x: t.x + shift.dx, y: t.y + shift.dy),
          ),
          strokes: [for (final s in x.strokes) s.mapped((p) => p - c, 1)],
        ),
      ),
    );
  }

  /// Re-centres a path layer's nodes on its origin without moving it on
  /// the canvas (keeps handles and rotation centred after editing).
  void normalizePath(String id) {
    final l = _document.layerById(id);
    if (l is! PathLayer || l.contours.every((c) => c.nodes.isEmpty)) return;
    final c = pathLayerPath(l).getBounds().center;
    if (c.distance < 0.01) return;
    final t = l.props.transform;
    final shift = t.toDocument(c) - t.toDocument(Offset.zero);
    _silent(
      (d) => d.updateLayer(
        id,
        (x) => (x as PathLayer).copyWith(
          props: x.props.copyWith(
            transform: t.copyWith(x: t.x + shift.dx, y: t.y + shift.dy),
          ),
          contours: [
            for (final k in x.contours)
              k.copyWith(nodes: [for (final n in k.nodes) n.shifted(-c)]),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- mask

  /// A full-strength fill hides everything painted before it, so those
  /// strokes are dropped (keeps masks small after "Hide all" etc.).
  static List<MaskStroke> _pack(List<MaskStroke> mask) {
    for (var i = mask.length - 1; i > 0; i--) {
      final s = mask[i];
      if (s.shape == MaskShape.fill && s.opacity >= 1) {
        return mask.sublist(i);
      }
    }
    return mask;
  }

  void addMaskStrokes(String id, List<MaskStroke> strokes) => updateProps(
    id,
    (p) => p.copyWith(mask: _pack([...p.mask, ...strokes]), maskEnabled: true),
    label: 'mask',
  );

  void addMaskStroke(String id, MaskStroke stroke, {bool live = false}) {
    Layer op(Layer l) => l.update(
      (p) => p.copyWith(
        mask: live ? [...p.mask, stroke] : _pack([...p.mask, stroke]),
        maskEnabled: true,
      ),
    );
    live
        ? previewFromStart((d) => d.updateLayer(id, op))
        : updateLayer(id, op, label: 'mask');
  }

  /// Photoshop's "Add layer mask": Reveal all (white) or Hide all (black).
  void addLayerMask(String id, {bool hideAll = false}) => updateProps(
    id,
    (p) => p.copyWith(
      mask: [
        MaskStroke(
          mode: hideAll ? MaskMode.hide : MaskMode.show,
          shape: MaskShape.fill,
          points: const [],
        ),
      ],
      maskEnabled: true,
      maskDensity: 1,
      maskFeather: 0,
    ),
    label: 'mask_add',
  );

  /// Fills the whole mask with a grey (0 = hide all, 1 = reveal all).
  void fillMask(String id, double level) => addMaskStroke(
    id,
    MaskStroke(
      mode: level < 0.5 ? MaskMode.hide : MaskMode.show,
      shape: MaskShape.fill,
      points: const [],
      level: level == 0 || level == 1 ? null : level,
    ),
  );

  /// Swaps hidden and visible areas.
  void invertMask(String id) {
    final l = _document.layerById(id);
    if (l == null) return;
    updateProps(
      id,
      (p) => p.copyWith(
        mask: [
          // The mask starts white; inverted it starts black.
          MaskStroke(
            mode: MaskMode.hide,
            shape: MaskShape.fill,
            points: const [],
          ),
          for (final s in p.mask) s.inverted(),
        ],
        maskEnabled: true,
      ),
      label: 'mask_invert',
    );
  }

  /// Deletes the layer mask.
  void clearMask(String id) => updateProps(
    id,
    (p) => p.copyWith(
      mask: const [],
      maskEnabled: true,
      maskDensity: 1,
      maskFeather: 0,
    ),
    label: 'mask_clear',
  );

  void setMaskEnabled(String id, bool on) =>
      updateProps(id, (p) => p.copyWith(maskEnabled: on), label: 'mask_toggle');

  void setMaskDensity(String id, double v, {bool live = false}) => updateProps(
    id,
    (p) => p.copyWith(maskDensity: v.clamp(0.0, 1.0)),
    live: live,
    label: 'mask_density',
  );

  void setMaskFeather(String id, double v, {bool live = false}) => updateProps(
    id,
    (p) => p.copyWith(maskFeather: math.max(0, v)),
    live: live,
    label: 'mask_feather',
  );

  Rect boundsOf(List<String> ids) =>
      unionBounds([for (final id in ids) ?_document.layerById(id)]);

  void flip(String id, {bool horizontal = true}) =>
      flipLayers([id], horizontal: horizontal);

  // --------------------------------------------------------- linked layers

  /// Layers linked to [id] (not including it).
  List<String> linkedTo(String id) {
    final link = _document.layerById(id)?.props.link;
    if (link == null) return const [];
    return [
      for (final l in _document.allLayers)
        if (l.id != id && l.props.link == link) l.id,
    ];
  }

  bool isLinked(String id) => linkedTo(id).isNotEmpty;

  /// [ids] plus every layer linked to them, as top-level units (a layer
  /// inside a group that is also included is dropped) and without locked
  /// partners — what a move or transform acts on, like Photoshop.
  List<String> withLinked(List<String> ids) {
    final all = {...ids};
    for (final id in ids) {
      for (final other in linkedTo(id)) {
        if (!_document.isEffectivelyLocked(other)) all.add(other);
      }
    }
    if (all.length == ids.length) return ids;
    return [
      for (final l in _document.allLayers)
        if (all.contains(l.id) &&
            !_document.ancestorsOf(l.id).any((g) => all.contains(g.id)))
          l.id,
    ];
  }

  /// Links [ids] (and whatever they are already linked to) into one set.
  void linkLayers(List<String> ids) {
    if (ids.length < 2) return;
    final existing = {
      for (final id in ids) ?_document.layerById(id)?.props.link,
    };
    final link = existing.isNotEmpty ? existing.first : newId('lk');
    final members = {
      ...ids,
      for (final l in _document.allLayers)
        if (l.props.link != null && existing.contains(l.props.link)) l.id,
    };
    apply('link', (d) {
      var doc = d;
      for (final id in members) {
        doc = doc.updateLayer(
          id,
          (l) => l.update((p) => p.copyWith(link: link)),
        );
      }
      return doc;
    });
  }

  /// Unlinks [ids]; a set left with a single layer dissolves.
  void unlinkLayers(List<String> ids) {
    final links = {for (final id in ids) ?_document.layerById(id)?.props.link};
    if (links.isEmpty) return;
    apply('unlink', (d) {
      var doc = d;
      for (final id in ids) {
        doc = doc.updateLayer(
          id,
          (l) => l.update((p) => p.copyWith(clearLink: true)),
        );
      }
      for (final link in links) {
        final left = [
          for (final l in doc.allLayers)
            if (l.props.link == link) l.id,
        ];
        if (left.length == 1) {
          doc = doc.updateLayer(
            left.single,
            (l) => l.update((p) => p.copyWith(clearLink: true)),
          );
        }
      }
      return doc;
    });
  }

  /// Selects a layer together with the layers linked to it.
  void selectLinked(String id) => selectMany([id, ...linkedTo(id)]);

  /// Link button: links the selection, or unlinks it when it already is
  /// one linked set (or a single linked layer).
  void toggleLinkSelection() {
    final ids = topLevelSelection;
    if (ids.isEmpty) return;
    if (selectionIsLinked) {
      unlinkLayers(ids);
    } else {
      linkLayers(ids);
    }
  }

  /// Whether the selection is all one linked set.
  bool get selectionIsLinked {
    final ids = topLevelSelection;
    if (ids.isEmpty) return false;
    final links = {for (final id in ids) _document.layerById(id)?.props.link};
    return links.length == 1 && links.first != null;
  }

  /// Mirrors layers around the centre of their combined bounds.
  void flipLayers(List<String> layerIds, {required bool horizontal}) {
    final ids = withLinked(layerIds);
    final axis = boundsOf(ids).center;
    apply(
      'flip',
      (d) => ids.fold(
        d,
        (d, id) => d.updateLayer(
          id,
          (l) => applyFlip(l, axis, horizontal: horizontal),
        ),
      ),
    );
  }

  void rotateLayers(List<String> ids, double radians) => transformLayers(
    ids,
    Similarity(pivot: boundsOf(withLinked(ids)).center, rotation: radians),
    label: 'rotate',
  );

  /// Aligns one layer to the canvas, or several layers to their combined
  /// bounds (Photoshop's behaviour).
  void align(String id, LayerAlign a) => alignLayers([id], a);

  void alignLayers(List<String> ids, LayerAlign a) {
    if (ids.isEmpty) return;
    final frame = ids.length == 1 ? _document.bounds : boundsOf(ids);
    apply('align', (d) {
      var next = d;
      for (final id in ids) {
        final l = next.layerById(id);
        if (l == null) continue;
        final b = layerDocumentBounds(l);
        final delta = switch (a) {
          LayerAlign.left => Offset(frame.left - b.left, 0),
          LayerAlign.centerH => Offset(frame.center.dx - b.center.dx, 0),
          LayerAlign.right => Offset(frame.right - b.right, 0),
          LayerAlign.top => Offset(0, frame.top - b.top),
          LayerAlign.centerV => Offset(0, frame.center.dy - b.center.dy),
          LayerAlign.bottom => Offset(0, frame.bottom - b.bottom),
        };
        next = next.updateLayer(
          id,
          (l) => applySimilarity(l, Similarity(translate: delta)),
        );
      }
      return next;
    });
  }

  void resetTransform(String id) {
    final l = _document.layerById(id);
    if (l == null) return;
    if (l is GroupLayer) {
      final c = unionBounds(l.children).center;
      transformLayers(
        [id],
        Similarity(translate: _document.center - c),
        label: 'reset_transform',
      );
      return;
    }
    updateProps(
      id,
      (p) => p.copyWith(
        transform: LayerTransform(
          x: _document.center.dx,
          y: _document.center.dy,
        ),
      ),
      label: 'reset_transform',
    );
  }

  // -------------------------------------------------------------- groups

  /// Wraps the (top-level) selection in a new group placed where the
  /// topmost selected layer was, and selects it.
  GroupLayer? groupSelected({String name = 'Group'}) {
    final ids = topLevelSelection;
    if (ids.isEmpty) return null;
    final d = _document;
    final members = [for (final id in ids) d.layerById(id)!];
    final anchor = ids.last; // topmost in paint order
    final group = GroupLayer(
      LayerProps(name: _nextName(name)),
      children: members,
    );
    apply('group', (d) {
      final parentId = d.parentOf(anchor)?.id;
      final stripped = d.removeLayers(ids.where((id) => id != anchor).toSet());
      final index = stripped.indexOf(anchor);
      return stripped
          .removeLayer(anchor)
          .insertLayer(group, parentId: parentId, index: index);
    }, select: group.id);
    return group;
  }

  /// Replaces a group with its children.
  void ungroup(String groupId) {
    final g = _document.layerById(groupId);
    if (g is! GroupLayer) return;
    apply('ungroup', (d) {
      final parentId = d.parentOf(groupId)?.id;
      var index = d.indexOf(groupId);
      var next = d.removeLayer(groupId);
      for (final c in g.children) {
        next = next.insertLayer(c, parentId: parentId, index: index++);
      }
      return next;
    }, selectIds: [for (final c in g.children) c.id]);
  }

  // --------------------------------------------------- merge & rasterize

  /// Builds a raster layer from a rasterize result.
  RasterLayer _rasterFrom(
    (Uint8List, Rect) r,
    Size pixelSize,
    LayerProps props,
  ) {
    final (png, bounds) = r;
    final assetId = assets.add(png);
    unawaited(assets.decode(assetId));
    return RasterLayer(
      props.copyWith(
        transform: LayerTransform(
          x: bounds.center.dx,
          y: bounds.center.dy,
          scaleX: bounds.width / pixelSize.width,
          scaleY: bounds.height / pixelSize.height,
        ),
        effects: const [],
      ),
      assetId: assetId,
      width: pixelSize.width,
      height: pixelSize.height,
    );
  }

  /// Rasterizes [layers] and replaces them with the result, placed where
  /// the topmost one was. Returns the new layer, or null if nothing visible.
  Future<RasterLayer?> _mergeInto(
    List<Layer> layers, {
    required String label,
    required LayerProps props,
    bool removeHidden = true,
  }) async {
    if (layers.isEmpty) return null;
    final r = await renderer.rasterize(layers);
    if (r == null) return null;
    final size = await measureImage(r.$1);
    final raster = _rasterFrom(r, size, props);
    final anchor = layers.last.id;
    final remove = {
      for (final l in layers)
        if (removeHidden || l.props.visible) l.id,
    }..remove(anchor);
    apply(label, (d) {
      if (!d.contains(anchor)) return d;
      final parentId = d.parentOf(anchor)?.id;
      final stripped = d.removeLayers(remove);
      final index = stripped.indexOf(anchor);
      return stripped
          .removeLayer(anchor)
          .insertLayer(raster, parentId: parentId, index: index);
    }, select: raster.id);
    return raster;
  }

  /// Converts a text, shape or group layer into pixels (effects baked in;
  /// opacity, blend mode and clipping are kept as layer properties).
  Future<RasterLayer?> rasterizeLayer(String id) async {
    final l = _document.layerById(id);
    if (l == null) return null;
    final plain = l.update(
      (p) => p.copyWith(
        opacity: 1,
        blendMode: PixBlendMode.normal,
        clip: false,
        visible: true,
      ),
    );
    return _mergeInto([plain], label: 'rasterize', props: l.props);
  }

  /// Merges a layer with the one directly beneath it.
  Future<RasterLayer?> mergeDown(String id) async {
    final siblings = _document.siblingsOf(id);
    final i = _document.indexOf(id);
    if (i <= 0) return null;
    final below = siblings[i - 1];
    return _mergeInto(
      [below, siblings[i]],
      label: 'merge_down',
      props: LayerProps(name: below.props.name),
    );
  }

  /// Merges the selected layers into one.
  Future<RasterLayer?> mergeSelected() async {
    final ids = topLevelSelection;
    if (ids.length < 2) return ids.length == 1 ? mergeDown(ids.single) : null;
    final layers = [for (final id in ids) _document.layerById(id)!];
    return _mergeInto(
      layers,
      label: 'merge',
      props: LayerProps(name: layers.last.props.name),
    );
  }

  /// Merges every visible top-level layer, keeping hidden ones.
  Future<RasterLayer?> mergeVisible({String name = 'Merged'}) => _mergeInto(
    [
      for (final l in _document.layers)
        if (l.props.visible) l,
    ],
    label: 'merge_visible',
    props: LayerProps(name: name),
    removeHidden: false,
  );

  /// Flattens the design to a single layer and discards hidden layers.
  Future<RasterLayer?> flatten({String name = 'Flattened'}) async {
    final r = await mergeVisible(name: name);
    if (r == null) return null;
    apply(
      'flatten',
      (d) => d.copyWith(layers: [?d.layerById(r.id)]),
      select: r.id,
    );
    return r;
  }

  // ------------------------------------------------------------ effects

  LayerEffect? effectOf(String layerId, String type) {
    for (final e
        in _document.layerById(layerId)?.props.effects ??
            const <LayerEffect>[]) {
      if (e.type == type) return e;
    }
    return null;
  }

  /// Sets one parameter of the (single) effect of [type] on a layer,
  /// creating the effect if needed. Adjustment sliders use this.
  void setEffectParam(
    String layerId,
    String type,
    String key,
    Object value, {
    bool live = false,
  }) {
    LayerProps op(LayerProps p) {
      final existing = p.effects.where((e) => e.type == type).firstOrNull;
      if (existing != null) {
        return p.copyWith(
          effects: [
            for (final e in p.effects)
              e.id == existing.id ? e.withParam(key, value) : e,
          ],
        );
      }
      final def = EffectRegistry.instance[type];
      if (def == null) return p;
      return p.copyWith(
        effects: [
          ...p.effects,
          def.create({key: value}),
        ],
      );
    }

    updateProps(layerId, op, label: 'effect', live: live);
  }

  void removeEffectType(String layerId, String type) => updateProps(
    layerId,
    (p) => p.copyWith(
      effects: [
        for (final e in p.effects)
          if (e.type != type) e,
      ],
    ),
    label: 'remove_effect',
  );

  void removeEffectsIn(String layerId, EffectCategory category) => updateProps(
    layerId,
    (p) => p.copyWith(
      effects: [
        for (final e in p.effects)
          if (EffectRegistry.instance[e.type]?.category != category) e,
      ],
    ),
    label: 'remove_effects',
  );

  /// Filters are exclusive: applying one replaces any previous filter.
  void applyFilter(String layerId, String? type) => updateProps(layerId, (p) {
    final kept = [
      for (final e in p.effects)
        if (EffectRegistry.instance[e.type]?.category != EffectCategory.filter)
          e,
    ];
    final def = type == null ? null : EffectRegistry.instance[type];
    return p.copyWith(effects: def == null ? kept : [...kept, def.create()]);
  }, label: 'filter');

  /// Adds a new effect of [type] (filters may be stacked, like Photoshop's
  /// smart filters) and returns its id.
  String? addEffect(String layerId, String type) {
    final def = EffectRegistry.instance[type];
    if (def == null) return null;
    final fx = def.create();
    updateProps(
      layerId,
      (p) => p.copyWith(effects: [...p.effects, fx]),
      label: 'effect',
    );
    return fx.id;
  }

  LayerEffect? effectById(String layerId, String effectId) {
    for (final e
        in _document.layerById(layerId)?.props.effects ??
            const <LayerEffect>[]) {
      if (e.id == effectId) return e;
    }
    return null;
  }

  /// Edits one effect instance.
  void updateEffect(
    String layerId,
    String effectId,
    LayerEffect Function(LayerEffect e) f, {
    bool live = false,
    String label = 'effect',
  }) => updateProps(
    layerId,
    (p) => p.copyWith(
      effects: [for (final e in p.effects) e.id == effectId ? f(e) : e],
    ),
    label: label,
    live: live,
  );

  void setEffectParamById(
    String layerId,
    String effectId,
    String key,
    Object value, {
    bool live = false,
  }) => updateEffect(
    layerId,
    effectId,
    (e) => e.withParam(key, value),
    live: live,
  );

  void toggleEffect(String layerId, String effectId) => updateEffect(
    layerId,
    effectId,
    (e) => e.copyWith(enabled: !e.enabled),
    label: 'toggle_effect',
  );

  void removeEffect(String layerId, String effectId) => updateProps(
    layerId,
    (p) => p.copyWith(
      effects: [
        for (final e in p.effects)
          if (e.id != effectId) e,
      ],
    ),
    label: 'remove_effect',
  );

  /// Shows or hides every effect (and the stroke) of a layer at once.
  void setAllEffectsEnabled(String layerId, bool on) => updateProps(
    layerId,
    (p) => p.copyWith(
      effects: [for (final e in p.effects) e.copyWith(enabled: on)],
      stroke: p.stroke?.copyWith(enabled: on),
    ),
    label: 'toggle_effect',
  );

  void toggleStroke(String layerId) => updateProps(layerId, (p) {
    final s = p.stroke;
    return s == null ? p : p.copyWith(stroke: s.copyWith(enabled: !s.enabled));
  }, label: 'toggle_effect');

  /// The copied layer style (Photoshop's Copy Layer Style). Shared by all
  /// open projects.
  static LayerStyleClip? styleClipboard;

  bool get hasCopiedStyle => styleClipboard != null;

  /// Copies a layer's effects, stroke and fill blending options.
  void copyStyle(String layerId) {
    final p = _document.layerById(layerId)?.props;
    if (p == null) return;
    styleClipboard = LayerStyleClip(
      effects: p.effects,
      stroke: p.stroke,
      fillOpacity: p.fillOpacity,
      blendInterior: p.blendInterior,
      maskHidesEffects: p.maskHidesEffects,
    );
    notifyListeners();
  }

  /// Replaces the style of [layerIds] with the copied one (fresh effect
  /// ids per layer).
  void pasteStyle(List<String> layerIds) {
    final clip = styleClipboard;
    if (clip == null || layerIds.isEmpty) return;
    apply('paste_style', (d) {
      var doc = d;
      for (final id in layerIds) {
        if (doc.isEffectivelyLocked(id)) continue;
        doc = doc.updateLayer(
          id,
          (l) => l.update(
            (p) => p.copyWith(
              effects: [
                for (final e in clip.effects)
                  LayerEffect(
                    type: e.type,
                    enabled: e.enabled,
                    params: e.params,
                  ),
              ],
              stroke: clip.stroke,
              clearStroke: clip.stroke == null,
              fillOpacity: clip.fillOpacity,
              blendInterior: clip.blendInterior,
              maskHidesEffects: clip.maskHidesEffects,
            ),
          ),
        );
      }
      return doc;
    });
  }

  /// Removes every effect and the stroke (Photoshop's Clear Layer Style).
  void clearStyle(String layerId) => updateProps(
    layerId,
    (p) => p.copyWith(effects: const [], clearStroke: true, fillOpacity: 1),
    label: 'clear_style',
  );

  // ------------------------------------------------------------ document

  void setBackground(PixFill? fill, {bool live = false}) {
    PixDocument op(PixDocument d) => fill == null
        ? d.copyWith(clearBackground: true)
        : d.copyWith(background: fill);
    live ? preview(op) : apply('background', op);
  }

  /// Changes the grid / ruler guides (undoable, like Photoshop guides).
  void updateGuides(
    CanvasGuides Function(CanvasGuides g) f, {
    String label = 'guides',
    bool live = false,
  }) {
    PixDocument op(PixDocument d) => d.copyWith(guides: f(d.guides));
    live ? preview(op) : apply(label, op);
  }

  void renameDocument(String name) =>
      apply('rename_document', (d) => d.copyWith(name: name));

  /// Changes the canvas size. When [scaleContent] is true layers are scaled
  /// and moved proportionally, otherwise they keep their size and stay
  /// centred.
  void resizeCanvas(
    double width,
    double height, {
    bool scaleContent = true,
    double? dpi,
  }) {
    apply('resize_canvas', (d) {
      final sx = width / d.width, sy = height / d.height;
      final s = math.min(sx, sy);
      final dx = (width - d.width) / 2, dy = (height - d.height) / 2;
      final g = d.guides;
      // Grid lines are fractions and follow the canvas by themselves;
      // ruler guides are pixels.
      final guides = g.copyWith(
        vertical: [for (final x in g.vertical) scaleContent ? x * sx : x + dx],
        horizontal: [
          for (final y in g.horizontal) scaleContent ? y * sy : y + dy,
        ],
      );
      return d
          .copyWith(width: width, height: height, guides: guides, dpi: dpi)
          .mapLayers(
            (l) => l is GroupLayer
                ? l
                : l.update((p) {
                    final t = p.transform;
                    return p.copyWith(
                      transform: scaleContent
                          ? t.copyWith(
                              x: t.x * sx,
                              y: t.y * sy,
                              scaleX: t.scaleX * s,
                              scaleY: t.scaleY * s,
                            )
                          : t.copyWith(
                              x: t.x + (width - d.width) / 2,
                              y: t.y + (height - d.height) / 2,
                            ),
                    );
                  }),
          );
    });
  }

  // ------------------------------------------------------------ selection
  //
  // Pixel selections live in the editor UI (see SelectionController); these
  // turn them into document edits. Each action is one undo step.

  static Future<Image> _selectionImage(PixelSelection sel) {
    final done = Completer<Image>();
    decodeImageFromPixels(
      sel.toRgba(),
      sel.width,
      sel.height,
      PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  static Future<Uint8List> _png(Picture picture, int w, int h) async {
    final img = await picture.toImage(w, h);
    picture.dispose();
    final data = await img.toByteData(format: ImageByteFormat.png);
    img.dispose();
    return data!.buffer.asUint8List();
  }

  /// Selection bounds snapped to whole pixels and clipped to the canvas.
  Rect? _selectionRect(PixelSelection sel) {
    final b = sel.bounds?.intersect(_document.bounds);
    if (b == null || b.isEmpty) return null;
    return Rect.fromLTRB(
      b.left.floorToDouble(),
      b.top.floorToDouble(),
      b.right.ceilToDouble(),
      b.bottom.ceilToDouble(),
    );
  }

  /// A bitmap mask stroke for layer [l] from [sel]: with [reveal] only the
  /// selection stays visible (Photoshop's "Reveal selection"), otherwise
  /// the selection is hidden (Delete / Cut).
  Future<MaskStroke?> _selectionMaskStroke(
    Layer l,
    PixelSelection sel, {
    required bool reveal,
  }) async {
    final lr = layerLocalRect(l);
    if (lr.isEmpty || !lr.isFinite) return null;
    final k = math.min(1.0, 2048 / math.max(lr.width, lr.height));
    final w = math.max(1, (lr.width * k).ceil());
    final h = math.max(1, (lr.height * k).ceil());
    final inv = _invert3(l.props.transform.homography);
    if (inv == null) return null;
    final img = await _selectionImage(sel);
    final recorder = PictureRecorder();
    final c = Canvas(recorder)
      ..scale(w / lr.width, h / lr.height)
      ..translate(-lr.left, -lr.top);
    if (reveal) c.drawRect(lr, Paint()..color = const Color(0xFFFFFFFF));
    c
      ..save()
      ..transform(
        Float64List.fromList([
          inv[0], inv[3], 0, inv[6], //
          inv[1], inv[4], 0, inv[7], //
          0, 0, 1, 0, //
          inv[2], inv[5], 0, inv[8], //
        ]),
      )
      ..drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        _document.bounds,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..blendMode = reveal ? BlendMode.dstOut : BlendMode.srcOver,
      )
      ..restore();
    img.dispose();
    final png = await _png(recorder.endRecording(), w, h);
    final assetId = assets.add(png);
    await assets.decode(assetId);
    return MaskStroke(
      mode: MaskMode.hide,
      shape: MaskShape.image,
      points: [lr.topLeft, lr.bottomRight],
      assetId: assetId,
    );
  }

  static List<double>? _invert3(List<double> m) {
    final a = m[0], b = m[1], c = m[2];
    final d = m[3], e = m[4], f = m[5];
    final g = m[6], h = m[7], i = m[8];
    final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    if (det.abs() < 1e-12) return null;
    final s = 1 / det;
    return [
      (e * i - f * h) * s,
      (c * h - b * i) * s,
      (b * f - c * e) * s,
      (f * g - d * i) * s,
      (a * i - c * g) * s,
      (c * d - a * f) * s,
      (d * h - e * g) * s,
      (b * g - a * h) * s,
      (a * e - b * d) * s,
    ];
  }

  /// Layer mask that shows only the selection (intersected with an
  /// existing mask).
  Future<bool> maskFromSelection(String id, PixelSelection sel) async {
    final l = _document.layerById(id);
    if (l == null) return false;
    final s = await _selectionMaskStroke(l, sel, reveal: true);
    if (s == null) return false;
    addMaskStrokes(id, [s]);
    return true;
  }

  /// Photoshop's Delete on a selection, non-destructively: the selected
  /// part of the layer is hidden with its mask.
  Future<bool> clearSelection(String id, PixelSelection sel) async {
    final l = _document.layerById(id);
    if (l == null) return false;
    final s = await _selectionMaskStroke(l, sel, reveal: false);
    if (s == null) return false;
    addMaskStrokes(id, [s]);
    return true;
  }

  /// Renders the selected pixels of [sourceId] (null = the whole visible
  /// canvas, background included) into a new image layer above the
  /// selection. With [cut] the source layer hides that part in the same
  /// undo step (Layer via Cut).
  Future<RasterLayer?> copySelectionToLayer(
    PixelSelection sel, {
    String? sourceId,
    bool cut = false,
    String name = 'Selection',
  }) async {
    final b = _selectionRect(sel);
    if (b == null) return null;
    var src = _document;
    final source = sourceId == null ? null : src.layerById(sourceId);
    if (sourceId != null) {
      if (source == null) return null;
      src = src.copyWith(clearBackground: true, layers: [source]);
    }
    await assets.decodeAll(src.referencedAssets);
    final img = await _selectionImage(sel);
    final k = math.min(1.0, 8192 / math.max(b.width, b.height));
    final w = math.max(1, (b.width * k).round());
    final h = math.max(1, (b.height * k).round());
    final recorder = PictureRecorder();
    final c = Canvas(recorder)
      ..scale(k)
      ..translate(-b.left, -b.top)
      ..saveLayer(b, Paint());
    renderer.paint(c, src);
    c
      ..drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        _document.bounds,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..blendMode = BlendMode.dstIn,
      )
      ..restore();
    img.dispose();
    final png = await _png(recorder.endRecording(), w, h);
    final raster = _rasterFrom(
      (png, b),
      Size(w.toDouble(), h.toDouble()),
      LayerProps(name: _nextName(name)),
    );
    MaskStroke? hide;
    if (cut && source != null) {
      hide = await _selectionMaskStroke(source, sel, reveal: false);
    }
    apply(cut ? 'cut_selection' : 'copy_selection', (d) {
      var next = d;
      if (hide != null && sourceId != null && d.contains(sourceId)) {
        next = next.updateLayer(
          sourceId,
          (l) => l.update(
            (p) =>
                p.copyWith(mask: _pack([...p.mask, hide!]), maskEnabled: true),
          ),
        );
        return next.insertLayer(
          raster,
          parentId: next.parentOf(sourceId)?.id,
          index: next.indexOf(sourceId) + 1,
        );
      }
      return _insertAtCursor(next, raster);
    }, select: raster.id);
    return raster;
  }

  /// The selected pixels of [sourceId] (null = the visible canvas),
  /// cropped to the selection, as PNG — e.g. to define a pattern.
  Future<Uint8List?> renderSelection(
    PixelSelection sel, {
    String? sourceId,
  }) async {
    final b = _selectionRect(sel);
    if (b == null) return null;
    var src = _document;
    if (sourceId != null) {
      final l = src.layerById(sourceId);
      if (l == null) return null;
      src = src.copyWith(clearBackground: true, layers: [l]);
    }
    await assets.decodeAll(src.referencedAssets);
    final img = await _selectionImage(sel);
    final k = math.min(1.0, 2048 / math.max(b.width, b.height));
    final w = math.max(1, (b.width * k).round());
    final h = math.max(1, (b.height * k).round());
    final recorder = PictureRecorder();
    final c = Canvas(recorder)
      ..scale(k)
      ..translate(-b.left, -b.top)
      ..saveLayer(b, Paint());
    renderer.paint(c, src);
    c
      ..drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        _document.bounds,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..blendMode = BlendMode.dstIn,
      )
      ..restore();
    img.dispose();
    return _png(recorder.endRecording(), w, h);
  }

  /// One layer rendered on its own (effects included) as PNG.
  Future<Uint8List?> renderLayerPng(String id) async {
    final l = _document.layerById(id);
    if (l == null) return null;
    final r = await renderer.rasterize([l], maxSide: 2048);
    return r?.$1;
  }

  /// Fills the selection with [color] on a new image layer.
  Future<RasterLayer?> fillSelection(
    PixelSelection sel,
    Color color, {
    String name = 'Fill',
  }) async {
    final b = _selectionRect(sel);
    if (b == null) return null;
    final img = await _selectionImage(sel);
    final k = math.min(1.0, 8192 / math.max(b.width, b.height));
    final w = math.max(1, (b.width * k).round());
    final h = math.max(1, (b.height * k).round());
    final recorder = PictureRecorder();
    Canvas(recorder)
      ..scale(k)
      ..translate(-b.left, -b.top)
      ..drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        _document.bounds,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
      );
    img.dispose();
    final png = await _png(recorder.endRecording(), w, h);
    final raster = _rasterFrom(
      (png, b),
      Size(w.toDouble(), h.toDouble()),
      LayerProps(name: _nextName(name)),
    );
    apply(
      'fill_selection',
      (d) => _insertAtCursor(d, raster),
      select: raster.id,
    );
    return raster;
  }

  /// Crops the canvas to the selection's bounds (layers keep their place
  /// on the design).
  bool cropToSelection(PixelSelection sel) {
    final b = _selectionRect(sel);
    if (b == null) return false;
    apply('crop_canvas', (d) {
      final g = d.guides;
      return d
          .copyWith(
            width: b.width,
            height: b.height,
            guides: g.copyWith(
              vertical: [for (final x in g.vertical) x - b.left],
              horizontal: [for (final y in g.horizontal) y - b.top],
            ),
          )
          .mapLayers(
            (l) => l is GroupLayer
                ? l
                : l.update((p) {
                    final t = p.transform;
                    return p.copyWith(
                      transform: t.copyWith(x: t.x - b.left, y: t.y - b.top),
                    );
                  }),
          );
    });
    return true;
  }

  /// Topmost visible, unlocked leaf layer under [docPoint] (layers inside
  /// groups are picked directly, like Photoshop's auto-select).
  Layer? layerAt(
    Offset docPoint, {
    double tolerance = 0,
    bool includeLocked = false,
  }) {
    Layer? search(List<Layer> list, bool lockedAbove) {
      for (final l in list.reversed) {
        if (!l.props.visible) continue;
        final locked = lockedAbove || l.props.locked;
        if (l is GroupLayer) {
          final hit = search(l.children, locked);
          if (hit != null) return hit;
          continue;
        }
        if (locked && !includeLocked) continue;
        if (hitTestLayer(l, docPoint, tolerance: tolerance)) return l;
      }
      return null;
    }

    return search(_document.layers, false);
  }
}

/// A copied layer style (see [EditorController.copyStyle]).
@immutable
class LayerStyleClip {
  const LayerStyleClip({
    required this.effects,
    required this.stroke,
    required this.fillOpacity,
    required this.blendInterior,
    required this.maskHidesEffects,
  });
  final List<LayerEffect> effects;
  final LayerStroke? stroke;
  final double fillOpacity;
  final bool blendInterior;
  final bool maskHidesEffects;
}
