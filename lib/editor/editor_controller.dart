import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Alignment;

import '../document/assets/asset_store.dart';
import '../document/effects/effect_registry.dart';
import '../document/model/document.dart';
import '../document/model/effect.dart';
import '../document/model/fill.dart';
import '../document/model/guides.dart';
import '../document/model/blend.dart';
import '../document/model/layer.dart';
import '../document/model/layer_geometry.dart';
import '../document/model/layer_transform.dart';
import '../document/model/mask.dart';
import '../document/render/document_renderer.dart';
import '../document/render/layer_cache.dart';
import '../document/render/brush_paint.dart';
import '../document/render/vector_paths.dart';
import 'history.dart';

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
    PixDocument op(PixDocument d) =>
        ids.fold(d, (d, id) => d.updateLayer(id, (l) => applySimilarity(l, s)));
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

  /// Mirrors layers around the centre of their combined bounds.
  void flipLayers(List<String> ids, {required bool horizontal}) {
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
    Similarity(pivot: boundsOf(ids).center, rotation: radians),
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
