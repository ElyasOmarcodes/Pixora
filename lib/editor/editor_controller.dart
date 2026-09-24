import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../document/assets/asset_store.dart';
import '../document/effects/effect_registry.dart';
import '../document/model/document.dart';
import '../document/model/effect.dart';
import '../document/model/fill.dart';
import '../document/model/layer.dart';
import '../document/model/layer_transform.dart';
import '../document/render/document_renderer.dart';
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
  String? _selectedId;
  HistoryEntry? _previewBase;

  /// Increments whenever the committed document changes (autosave hook).
  int revision = 0;

  /// Increments on any visual change including previews (repaint hook).
  int paintRevision = 0;

  PixDocument get document => _document;
  String? get selectedId => _selectedId;
  Layer? get selectedLayer => _document.layerById(_selectedId);
  bool get isPreviewing => _previewBase != null;
  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  DocumentRenderer get renderer => DocumentRenderer(assets);

  void _onAssetsChanged() {
    paintRevision++;
    notifyListeners();
  }

  // ------------------------------------------------------------ core API

  /// Applies a discrete, undoable edit. If previews are pending they are
  /// folded into the same undo step.
  void apply(String label, DocOp op, {String? select, bool deselect = false}) {
    final base = _previewBase ?? HistoryEntry(_document, _selectedId, label);
    _previewBase = null;
    final next = op(_document);
    final wanted = deselect ? null : (select ?? _selectedId);
    final nextSel = next.layerById(wanted) == null ? null : wanted;
    final unchanged = next == base.document && nextSel == base.selection;
    _document = next;
    _selectedId = nextSel;
    if (unchanged) {
      _changed(committed: false);
      return;
    }
    history.push(HistoryEntry(base.document, base.selection, label));
    _changed(committed: true);
  }

  /// Live update without recording history (call [commit] when done).
  void preview(DocOp op) {
    _previewBase ??= HistoryEntry(_document, _selectedId, '');
    _document = op(_document);
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

  void undo() {
    if (_previewBase != null) cancelPreview();
    final prev = history.undo(HistoryEntry(_document, _selectedId, ''));
    if (prev == null) return;
    _restore(prev);
  }

  void redo() {
    if (_previewBase != null) cancelPreview();
    final next = history.redo(HistoryEntry(_document, _selectedId, ''));
    if (next == null) return;
    _restore(next);
  }

  void _restore(HistoryEntry e) {
    _document = e.document;
    _selectedId = _document.layerById(e.selection) == null ? null : e.selection;
    _changed(committed: true);
  }

  void select(String? id) {
    final next = _document.layerById(id) == null ? null : id;
    if (next == _selectedId) return;
    if (_previewBase != null) commit('edit');
    _selectedId = next;
    paintRevision++;
    notifyListeners();
  }

  void _changed({required bool committed}) {
    if (committed) revision++;
    paintRevision++;
    notifyListeners();
  }

  @override
  void dispose() {
    assets.removeListener(_onAssetsChanged);
    super.dispose();
  }

  // ------------------------------------------------------ layer creation

  double get _unit => math.min(_document.width, _document.height);

  String _nextName(String base) {
    final used = {for (final l in _document.layers) l.props.name};
    for (var i = 1; ; i++) {
      final name = '$base $i';
      if (!used.contains(name)) return name;
    }
  }

  TextLayer addText(String text, {String name = 'Text', Color? color}) {
    final layer = TextLayer(
      LayerProps(
        name: _nextName(name),
        transform: LayerTransform(
          x: _document.center.dx,
          y: _document.center.dy,
        ),
      ),
      text: text,
      fontSize: (_unit * 0.09).roundToDouble(),
      fill: color == null ? null : PixFill.color(color),
    );
    apply('add_text', (d) => d.insertLayer(layer), select: layer.id);
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
    apply('add_shape', (d) => d.insertLayer(layer), select: layer.id);
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
    apply('add_image', (d) => d.insertLayer(layer), select: layer.id);
    return layer;
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

  void deleteLayer(String id) => apply(
    'delete_layer',
    (d) => d.removeLayer(id),
    deselect: _selectedId == id,
  );

  Layer? duplicateLayer(String id) {
    final l = _document.layerById(id);
    if (l == null) return null;
    final t = l.props.transform;
    final offset = _unit * 0.03;
    final copy = l
        .cloneWithNewId(name: '${l.props.name} copy')
        .update(
          (p) => p.copyWith(
            transform: t.copyWith(x: t.x + offset, y: t.y + offset),
          ),
        );
    apply(
      'duplicate_layer',
      (d) => d.insertLayer(copy, d.indexOf(id) + 1),
      select: copy.id,
    );
    return copy;
  }

  void arrange(String id, LayerArrange a) {
    final i = _document.indexOf(id);
    if (i < 0) return;
    final top = _document.layers.length - 1;
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

  void toggleVisible(String id) => updateProps(
    id,
    (p) => p.copyWith(visible: !p.visible),
    label: 'visibility',
  );

  void toggleLocked(String id) =>
      updateProps(id, (p) => p.copyWith(locked: !p.locked), label: 'lock');

  void rename(String id, String name) =>
      updateProps(id, (p) => p.copyWith(name: name), label: 'rename');

  void flip(String id, {bool horizontal = true}) => updateProps(
    id,
    (p) => p.copyWith(
      transform: horizontal
          ? p.transform.copyWith(scaleX: -p.transform.scaleX)
          : p.transform.copyWith(scaleY: -p.transform.scaleY),
    ),
    label: 'flip',
  );

  void align(String id, LayerAlign a) {
    final l = _document.layerById(id);
    if (l == null) return;
    final b = layerDocumentBounds(l);
    final t = l.props.transform;
    final w = _document.width, h = _document.height;
    final (dx, dy) = switch (a) {
      LayerAlign.left => (-b.left, 0.0),
      LayerAlign.centerH => (w / 2 - b.center.dx, 0.0),
      LayerAlign.right => (w - b.right, 0.0),
      LayerAlign.top => (0.0, -b.top),
      LayerAlign.centerV => (0.0, h / 2 - b.center.dy),
      LayerAlign.bottom => (0.0, h - b.bottom),
    };
    updateProps(
      id,
      (p) => p.copyWith(
        transform: t.copyWith(x: t.x + dx, y: t.y + dy),
      ),
      label: 'align',
    );
  }

  void resetTransform(String id) {
    final l = _document.layerById(id);
    if (l == null) return;
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

  void renameDocument(String name) =>
      apply('rename_document', (d) => d.copyWith(name: name));

  /// Changes the canvas size. When [scaleContent] is true layers are scaled
  /// and moved proportionally, otherwise they keep their size and stay
  /// centred.
  void resizeCanvas(double width, double height, {bool scaleContent = true}) {
    apply('resize_canvas', (d) {
      final sx = width / d.width, sy = height / d.height;
      final s = math.min(sx, sy);
      return d.copyWith(
        width: width,
        height: height,
        layers: [
          for (final l in d.layers)
            l.update((p) {
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
        ],
      );
    });
  }

  /// Topmost visible, unlocked layer under [docPoint].
  Layer? layerAt(
    Offset docPoint, {
    double tolerance = 0,
    bool includeLocked = false,
  }) {
    for (final l in _document.layers.reversed) {
      if (!l.props.visible) continue;
      if (l.props.locked && !includeLocked) continue;
      if (hitTestLayer(l, docPoint, tolerance: tolerance)) return l;
    }
    return null;
  }
}
