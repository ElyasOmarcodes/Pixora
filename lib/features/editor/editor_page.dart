import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_theme.dart';
import '../../document/model/document.dart';
import '../../document/model/layer.dart';
import '../../document/model/text_span_style.dart';
import '../../editor/editor_controller.dart';
import '../../editor/tools/draw_tool.dart';
import '../../editor/tools/editor_tool.dart';
import '../../editor/tools/grid_tool.dart';
import '../../editor/tools/mask_tool.dart';
import '../../core/fonts/font_catalog.dart';
import 'dialogs/font_picker.dart';
import 'dialogs/icon_picker.dart';
import 'pen_targets.dart';
import '../../core/icons/icon_catalog.dart';
import '../../editor/tools/pen_tool.dart';
import '../../editor/tools/select_tool.dart';
import '../../editor/selection/selection_controller.dart';
import 'dialogs/text_dialog.dart';
import 'dialogs/close_dialog.dart';
import '../../ui/widgets/confirm_dialog.dart';
import '../../editor/tools/transform_tool.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/widgets/color_picker.dart';
import '../../projects/pixora_format.dart';
import '../../projects/project_share.dart';
import '../../projects/project_store.dart';
import '../../ui/layer_style.dart';
import '../home/widgets/new_canvas_dialog.dart';
import 'dialogs/crop_page.dart';
import '../home/widgets/text_prompt.dart';
import 'editor_scope.dart';
import 'panels/tool_panel_host.dart';
import 'widgets/canvas_view.dart';
import 'widgets/context_dock.dart';
import '../../ui/widgets/pattern_source.dart';
import 'widgets/editor_top_bar.dart';
import 'widgets/export_sheet.dart';
import 'widgets/layer_actions.dart';
import 'widgets/layers_panel.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.project});

  final StoredProject project;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final AppServices _services = AppScope.of(context);
  late final EditorController _editor;
  final EditorUiState _ui = EditorUiState();
  final CanvasViewController _canvas = CanvasViewController();
  late final TransformTool _moveTool = TransformTool(
    onEditRequest: (l) {
      if (l is TextLayer) _editText(l);
    },
  );
  final HandTool _handTool = HandTool();
  final GridTool _gridTool = GridTool();
  late final MaskTool _maskTool = MaskTool(_ui.maskBrush);
  late final PenTool _penTool = PenTool(_ui.penState);
  late final MaskPenTarget _maskPen = MaskPenTarget(_editor);
  late final PanelHooks _hooks = PanelHooks(
    addIcon: () => unawaited(_addIcon()),
    startPen: _startPen,
    startBrush: _startBrush,
    maskPen: _maskPen,
    selectTool: _selectTool,
    selectionPen: _selectionPen,
  );
  late final SelectTool _selectTool = SelectTool(_ui.selection);
  final SelectionPenTarget _selectionPen = SelectionPenTarget();
  late final DrawTool _drawTool = DrawTool(_ui.brushSettings);

  /// The drawing layer the brush panel is painting into.
  String? _drawingId;

  EditorTool get _tool => switch (_ui.mode) {
    ToolMode.move => _moveTool,
    ToolMode.hand => _handTool,
    ToolMode.grid => _gridTool,
    ToolMode.mask =>
      _ui.maskBrush.kind == MaskToolKind.pen ? _penTool : _maskTool,
    ToolMode.pen => _penTool,
    ToolMode.draw => _drawTool,
    ToolMode.select =>
      _ui.selection.tool == SelectToolKind.pen ? _penTool : _selectTool,
  };

  /// Points the pen at what it should edit: the selected vector layer in
  /// pen mode, the mask outline in mask-pen mode. Leaving the pen tidies
  /// the path (re-centred) or removes an empty one.
  void _syncPen() {
    final pen = _ui.penState;
    final p = _ui.panel;
    // Leaving the brush tidies the drawing (re-centred) or removes an
    // empty one.
    final sel = _editor.selectedLayer;
    if (p == ToolPanel.brush && sel is DrawingLayer) {
      if (_drawingId != sel.id) _finishDrawing();
      _drawingId = sel.id;
    } else if (_drawingId != null) {
      _finishDrawing();
    }
    if (p == ToolPanel.pen) {
      final l = _editor.selectedLayer;
      if (l is PathLayer) {
        final t = pen.target;
        if (t is! PathLayerPenTarget || t.id != l.id) {
          _finishPen();
          pen.reset();
          pen.target = PathLayerPenTarget(_editor, l.id);
          pen.active = l.contours.isEmpty ? 0 : l.contours.length - 1;
        }
      }
    } else if (p == ToolPanel.mask && _ui.maskBrush.kind == MaskToolKind.pen) {
      if (pen.target != _maskPen) {
        _finishPen();
        pen.reset();
        pen.target = _maskPen;
      }
    } else if (p == ToolPanel.selection &&
        _ui.selection.tool == SelectToolKind.pen) {
      if (pen.target != _selectionPen) {
        _finishPen();
        pen.reset();
        pen.target = _selectionPen;
      }
    } else if (pen.target != null) {
      _finishPen();
      pen.reset();
      _maskPen.clear();
      _selectionPen.clear();
    }
    // Rebuild only when what the page shows changed (the canvas tool, the
    // panel, the layers sheet) — not on every brush-size or pen tweak.
    final key = (
      _ui.mode,
      p,
      _ui.showLayers,
      _ui.maskBrush.kind,
      _ui.selection.tool,
    );
    if (key != _uiKey && mounted) {
      _uiKey = key;
      setState(() {});
    }
  }

  (ToolMode, ToolPanel?, bool, MaskToolKind, SelectToolKind)? _uiKey;

  void _finishDrawing() {
    final id = _drawingId;
    _drawingId = null;
    if (id == null) return;
    final l = _editor.document.layerById(id);
    if (l is! DrawingLayer) return;
    if (l.strokes.isEmpty) {
      _editor.deleteLayers([l.id]);
    } else {
      _editor.normalizeDrawing(l.id);
    }
  }

  void _startBrush() {
    final l = AppLocalizations.of(context);
    _editor.addDrawing(name: l.drawing);
    _ui.panel = ToolPanel.brush;
  }

  void _finishPen() {
    final t = _ui.penState.target;
    if (t is! PathLayerPenTarget) return;
    final l = _editor.document.layerById(t.id);
    if (l is! PathLayer) return;
    if (l.contours.every((c) => c.nodes.length < 2)) {
      _editor.deleteLayers([l.id]);
    } else {
      _editor.normalizePath(l.id);
    }
  }

  Future<void> _addIcon() async {
    final l = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme.primary;
    final pick = await showIconPicker(context);
    if (pick == null) return;
    _editor.addIcon(
      pick.name,
      pick.pathData,
      style: pick.style,
      filled: pick.filled,
      weight: pick.weight,
      name: l.icon,
      color: color,
    );
    _ui.panel = ToolPanel.fill;
  }

  Future<void> _changeIcon(IconLayer layer) async {
    final pick = await showIconPicker(
      context,
      current: IconPick(
        name: layer.iconName,
        pathData: layer.pathData,
        style: layer.style,
        filled: layer.filled,
        weight: layer.weight,
      ),
    );
    if (pick == null) return;
    _editor.replaceIcon(
      layer.id,
      pick.name,
      pick.pathData,
      style: pick.style,
      filled: pick.filled,
      weight: pick.weight,
    );
  }

  void _startPen() {
    final l = AppLocalizations.of(context);
    final unit = math.min(_editor.document.width, _editor.document.height);
    _editor.addPath(
      PathLayer(
        LayerProps(name: l.vector),
        strokeColor: Theme.of(context).colorScheme.primary,
        strokeWidth: math.max(2, unit * 0.01),
      ),
      name: l.vector,
    );
    _ui.panel = ToolPanel.pen;
  }

  Timer? _saveTimer;
  int _savedRevision = -1;
  bool _saving = false;
  bool _pendingSave = false;
  String? _lastSelection;

  /// Whether the project was already in the library when it was opened
  /// (decides what "don't save" means when closing).
  bool? _existedBefore;

  @override
  void initState() {
    super.initState();
    _editor = EditorController(document: widget.project.document)
      ..assets.addAll(widget.project.assets)
      ..addListener(_onEditorChanged);
    _ui.addListener(_syncPen);
    // The colour pickers' eyedropper samples the current design.
    Eyedropper.capture = () =>
        _editor.renderer.renderImage(_editor.document, maxSide: 1600);
    _ui.maskBrush.addListener(_syncPen);
    _ui.selection.addListener(_syncPen);
    for (final id in widget.project.document.referencedAssets) {
      unawaited(_editor.assets.decode(id));
    }
    unawaited(
      _services.projects
          .exists(widget.project.document.id)
          .then((v) => _existedBefore = v),
    );
  }

  @override
  void dispose() {
    Eyedropper.capture = null;
    _saveTimer?.cancel();
    _editor.removeListener(_onEditorChanged);
    _ui.removeListener(_syncPen);
    _ui.maskBrush.removeListener(_syncPen);
    _ui.selection.removeListener(_syncPen);
    _maskPen.dispose();
    _editor.dispose();
    _ui.dispose();
    _canvas.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- saving

  bool get _dirty => _editor.revision != _savedRevision;

  void _onEditorChanged() {
    if (_editor.selectedId != _lastSelection) {
      _lastSelection = _editor.selectedId;
      final p = _ui.panel;
      final keep =
          p == ToolPanel.grid ||
          p == ToolPanel.snap ||
          p == ToolPanel.rulers ||
          p == ToolPanel.pen ||
          (p == ToolPanel.background && _editor.selectedId == null);
      if (!keep) _ui.panel = null;
    }
    if (_services.settings.autosave && _dirty && !_editor.isPreviewing) {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 1400), _save);
    }
    // Live previews (dragging, pen, sliders) repaint the canvas and the
    // widgets that listen to the editor themselves; rebuilding the whole
    // page every frame made long gestures heavy.
    if (_editor.isPreviewing) return;
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) {
      _pendingSave = true;
      return;
    }
    _saving = true;
    try {
      final doc = _editor.document;
      final rev = _editor.revision;
      final thumb = await _editor.renderer.renderPng(doc, maxSide: 420);
      await _services.projects.save(
        doc,
        _editor.assets.allBytes,
        thumbnail: thumb,
      );
      _savedRevision = rev;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Pixora: save failed: $e');
    } finally {
      _saving = false;
      if (_pendingSave) {
        _pendingSave = false;
        unawaited(_save());
      }
    }
  }

  /// Asks what to do with changes made since the project was opened:
  /// save them, throw them away (restoring the project as it was), or keep
  /// editing.
  Future<void> _requestClose() async {
    if (_editor.isPreviewing) _editor.commit('edit');
    if (_editor.revision == 0) {
      await _saveAndExit();
      return;
    }
    final choice = await showCloseProjectDialog(context);
    if (!mounted || choice == null) return;
    switch (choice) {
      case CloseChoice.save:
        await _saveAndExit();
      case CloseChoice.discard:
        await _discardAndExit();
    }
  }

  Future<void> _discardAndExit() async {
    _saveTimer?.cancel();
    final nav = Navigator.of(context);
    // Wait for an autosave that is still writing.
    while (_saving) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final original = widget.project.document;
    try {
      if (_existedBefore ?? true) {
        if (_savedRevision >= 0) {
          final thumb = await _editor.renderer.renderPng(
            original,
            maxSide: 420,
          );
          await _services.projects.save(
            original,
            widget.project.assets,
            thumbnail: thumb,
          );
        }
      } else if (_savedRevision >= 0) {
        await _services.projects.delete(original.id);
      }
    } catch (e) {
      debugPrint('Pixora: discard failed: $e');
    }
    if (mounted) nav.pop();
  }

  Future<void> _saveAndExit() async {
    _saveTimer?.cancel();
    final nav = Navigator.of(context);
    if (_editor.isPreviewing) _editor.commit('edit');
    if (_dirty || _savedRevision < 0) await _save();
    if (mounted) nav.pop();
  }

  // ------------------------------------------------------------ actions

  Color _contrastingTextColor() {
    final bg = _editor.document.background;
    if (bg == null) return Colors.white;
    return bg.primary.computeLuminance() > 0.6
        ? const Color(0xFF1B1B1F)
        : Colors.white;
  }

  /// Font for new text: the last one used, else the default.
  String get _lastFont {
    final fonts = _services.fonts;
    return fonts.recent.where(fonts.isAvailable).firstOrNull ??
        FontCatalog.defaultFamily;
  }

  Future<void> _addText() async {
    final l = AppLocalizations.of(context);
    final r = await showTextDialog(context, fontFamily: _lastFont);
    if (r == null || r.text.trim().isEmpty) return;
    final layer = _editor.addText(
      r.text,
      name: l.text,
      color: _contrastingTextColor(),
      fontFamily: r.fontFamily,
    );
    if (r.spans.isNotEmpty) {
      _editor.updateLayer(
        layer.id,
        (x) => (x as TextLayer).copyWith(spans: r.spans),
        label: 'text',
      );
    }
  }

  Future<void> _editText(TextLayer layer) async {
    final r = await showTextDialog(
      context,
      initial: layer.text,
      fontFamily: layer.fontFamily,
      spans: layer.spans,
    );
    if (r == null || r.text.trim().isEmpty) return;
    _editor.updateLayer(
      layer.id,
      (l) => (l as TextLayer).copyWith(
        text: r.text,
        fontFamily: r.fontFamily,
        spans: r.spans,
      ),
      label: 'text',
    );
  }

  Future<void> _pickFont(TextLayer layer) async {
    final f = await showFontPicker(
      context,
      current: layer.fontFamily,
      sample: layer.text,
      partSpans: layer.spans,
    );
    if (f == null) return;
    final r = f.range;
    _editor.updateLayer(layer.id, (l) {
      final t = l as TextLayer;
      return r == null
          // Whole text: the new font replaces per-part fonts.
          ? t.copyWith(
              fontFamily: f.family,
              spans: TextSpans.clear(t.spans, 0, t.text.length, color: false),
            )
          : t.copyWith(
              spans: TextSpans.apply(
                t.spans,
                r.start,
                r.end,
                fontFamily: f.family,
              ),
            );
    }, label: 'font');
  }

  Future<void> _addImage() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await _services.platform.pickImage();
    if (picked == null) return;
    try {
      await _editor.addImage(picked.bytes, name: l.image);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.imageOpenFailed)));
    }
  }

  Future<void> _resizeCanvas() async {
    final d = _editor.document;
    final r = await showNewCanvasDialog(
      context,
      width: d.width,
      height: d.height,
      dpi: d.dpi,
      resizing: true,
    );
    if (r != null) {
      _editor.resizeCanvas(
        r.width,
        r.height,
        scaleContent: r.scaleContent,
        dpi: r.dpi,
      );
    }
  }

  Future<void> _renameDocument() async {
    final l = AppLocalizations.of(context);
    final name = await showTextPrompt(
      context,
      title: l.rename,
      label: l.projectName,
      initial: _editor.document.name,
    );
    if (name != null && name.trim().isNotEmpty) {
      _editor.renameDocument(name.trim());
    }
  }

  Future<void> _replaceImage(RasterLayer layer) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await _services.platform.pickImage();
    if (picked == null) return;
    try {
      await _editor.replaceImage(layer.id, picked.bytes);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.imageOpenFailed)));
    }
  }

  /// Crop & resize page, always starting from the original pixels.
  Future<void> _cropImage(RasterLayer layer) async {
    final source = layer.sourceAssetId ?? layer.assetId;
    final image = await _editor.assets.decode(source);
    if (image == null || !mounted) return;
    final r = await showCropPage(context, image: image, initial: layer.crop);
    if (r == null) return;
    _editor.applyCrop(layer.id, r.bytes, r.width, r.height, r.state);
  }

  void _openSaveSheet() => unawaited(
    showSaveSheet(
      context,
      saved: !_dirty && _savedRevision >= 0,
      onSaveChanges: () => unawaited(_saveNow()),
      onSaveAsCopy: () => unawaited(_saveAsCopy()),
      onExportProject: () => unawaited(_exportProject()),
      onSaveImage: () => unawaited(showExportSheet(context, _editor)),
    ),
  );

  Future<void> _saveNow() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    _saveTimer?.cancel();
    if (_editor.isPreviewing) _editor.commit('edit');
    await _save();
    messenger.showSnackBar(SnackBar(content: Text(l.allSaved)));
  }

  Future<void> _saveAsCopy() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = await showTextPrompt(
      context,
      title: l.saveAsCopy,
      label: l.projectName,
      initial: '${_editor.document.name} 2',
    );
    if (name == null || name.trim().isEmpty) return;
    final doc = _editor.document;
    final thumb = await _editor.renderer.renderPng(doc, maxSide: 420);
    await _services.projects.saveAsCopy(
      doc,
      _editor.assets.allBytes,
      name: name.trim(),
      thumbnail: thumb,
    );
    messenger.showSnackBar(
      SnackBar(content: Text(l.projectSavedAs(name.trim()))),
    );
  }

  Future<void> _confirmDeleteLayers(List<String> ids) async {
    if (ids.isEmpty) return;
    final l = AppLocalizations.of(context);
    final single = ids.length == 1
        ? _editor.document.layerById(ids.first)
        : null;
    final ok = await showConfirmDialog(
      context,
      title: single != null
          ? l.deleteLayerTitle(single.props.name)
          : l.deleteLayersTitle(ids.length),
      message: l.undoHint,
    );
    if (ok) _editor.deleteLayers(ids);
  }

  void _deleteSelectedGuide() {
    final ref = _gridTool.selected;
    if (ref == null) return;
    _gridTool.selected = null;
    _editor.updateGuides((_) => GuideGeometry.remove(_editor.document, ref));
  }

  void _toggleRulers() =>
      _services.settings.showRulers = !_services.settings.showRulers;

  void _toggleGridVisible() => _editor.updateGuides(
    (g) => g.copyWith(grid: g.grid.copyWith(visible: !g.grid.visible)),
  );

  Future<void> _exportProject() async {
    final platform = _services.platform;
    final doc = _editor.document;
    Uint8List? bytes;
    await runWithProgress(context, () async {
      final thumb = await _editor.renderer.renderPng(doc, maxSide: 420);
      final assets = _editor.assets.allBytes;
      bytes = await compute(_encodeProject, (doc, assets, thumb));
    });
    if (!mounted || bytes == null) return;
    await deliverProjectFile(context, platform, bytes!, doc.name);
  }

  late final LayerCommands _commands = LayerCommands(
    openPanel: (p) {
      if (!ScreenClass.of(context).isWide) _ui.showLayers = false;
      _ui.panel = p;
    },
    editText: _editText,
    pickFont: _pickFont,
    replaceImage: _replaceImage,
    cropImage: (r) => unawaited(_cropImage(r)),
    deleteLayers: (ids) => unawaited(_confirmDeleteLayers(ids)),
    changeIcon: (l) => unawaited(_changeIcon(l)),
    runAsync: (job) => runWithProgress(context, job),
  );

  /// Photoshop-compatible shortcuts (⌘ on Apple platforms, Ctrl elsewhere).
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final apple = _services.platform.info.isApple;
    final e = _editor;
    SingleActivator mod(
      LogicalKeyboardKey k, {
      bool shift = false,
      bool alt = false,
    }) => SingleActivator(
      k,
      control: !apple,
      meta: apple,
      shift: shift,
      alt: alt,
    );
    void withSel(void Function(String id) f) {
      final id = e.selectedId;
      if (id != null) f(id);
    }

    void run(Future<void> Function() job) => unawaited(_commands.runAsync(job));
    final l = AppLocalizations.of(context);

    return {
      mod(LogicalKeyboardKey.keyZ): e.undo,
      mod(LogicalKeyboardKey.keyZ, shift: true): e.redo,
      mod(LogicalKeyboardKey.keyY): e.redo,
      mod(LogicalKeyboardKey.keyS): () => unawaited(_saveNow()),
      mod(LogicalKeyboardKey.keyS, shift: true): () =>
          unawaited(showExportSheet(context, e)),
      mod(LogicalKeyboardKey.keyJ): e.duplicateSelected,
      mod(LogicalKeyboardKey.keyA): e.selectAll,
      mod(LogicalKeyboardKey.keyD): e.deselect,
      mod(LogicalKeyboardKey.keyG): () => e.groupSelected(name: l.group),
      mod(LogicalKeyboardKey.keyG, shift: true): () => withSel(e.ungroup),
      mod(LogicalKeyboardKey.keyG, alt: true): () => withSel(e.toggleClip),
      mod(LogicalKeyboardKey.keyE): () => run(() async {
        if (e.topLevelSelection.length > 1) {
          await e.mergeSelected();
        } else if (e.selectedId != null) {
          await e.mergeDown(e.selectedId!);
        }
      }),
      mod(LogicalKeyboardKey.keyE, shift: true): () =>
          run(() => e.mergeVisible(name: l.merge)),
      mod(LogicalKeyboardKey.bracketRight): () =>
          withSel((id) => e.arrange(id, LayerArrange.forward)),
      mod(LogicalKeyboardKey.bracketLeft): () =>
          withSel((id) => e.arrange(id, LayerArrange.backward)),
      mod(LogicalKeyboardKey.bracketRight, shift: true): () =>
          withSel((id) => e.arrange(id, LayerArrange.front)),
      mod(LogicalKeyboardKey.bracketLeft, shift: true): () =>
          withSel((id) => e.arrange(id, LayerArrange.back)),
      mod(LogicalKeyboardKey.digit0): _canvas.fit,
      mod(LogicalKeyboardKey.digit1): () => _canvas.zoomTo(1),
      mod(LogicalKeyboardKey.equal): () => _canvas.zoomBy(1.25),
      mod(LogicalKeyboardKey.add): () => _canvas.zoomBy(1.25),
      mod(LogicalKeyboardKey.minus): () => _canvas.zoomBy(0.8),
      mod(LogicalKeyboardKey.quote): _toggleGridVisible,
      mod(LogicalKeyboardKey.keyR): _toggleRulers,
      mod(LogicalKeyboardKey.semicolon, shift: true): () =>
          _services.settings.snapping = !_services.settings.snapping,
      const SingleActivator(LogicalKeyboardKey.keyV): () =>
          _ui.mode = ToolMode.move,
      const SingleActivator(LogicalKeyboardKey.keyH): () =>
          _ui.mode = ToolMode.hand,
      const SingleActivator(LogicalKeyboardKey.delete): _deleteKey,
      const SingleActivator(LogicalKeyboardKey.backspace): _deleteKey,
      const SingleActivator(LogicalKeyboardKey.escape): () {
        _ui.panel = null;
        if (_ui.mode != ToolMode.move) {
          _ui.mode = ToolMode.move;
        } else {
          e.deselect();
        }
      },
      for (final (k, dx, dy) in [
        (LogicalKeyboardKey.arrowLeft, -1.0, 0.0),
        (LogicalKeyboardKey.arrowRight, 1.0, 0.0),
        (LogicalKeyboardKey.arrowUp, 0.0, -1.0),
        (LogicalKeyboardKey.arrowDown, 0.0, 1.0),
      ]) ...{
        SingleActivator(k): () => e.nudgeSelection(dx, dy),
        SingleActivator(k, shift: true): () =>
            e.nudgeSelection(dx * 10, dy * 10),
      },
    };
  }

  /// Tapping the canvas closes the settings-like panels (grid, snap),
  /// except while grid lines are being edited.
  void _onCanvasTap() {
    final p = _ui.panel;
    if (_ui.mode == ToolMode.grid) return;
    if (p == ToolPanel.grid || p == ToolPanel.snap || p == ToolPanel.rulers) {
      _ui.panel = null;
    }
  }

  void _deleteKey() {
    if (_ui.mode == ToolMode.grid) {
      _deleteSelectedGuide();
    } else if (_ui.mode == ToolMode.move) {
      unawaited(_confirmDeleteLayers(_editor.topLevelSelection));
    }
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final screen = ScreenClass.of(context);
    final wide = screen.isWide;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: EditorScope(
        controller: _editor,
        ui: _ui,
        child: PatternSource(
          assets: _editor.assets,
          pickImage: _pickPatternImage,
          fromLayer: _patternFromLayer,
          fromSelection: _patternFromSelection,
          hasLayer: () => _editor.selectedId != null,
          hasSelection: () => _ui.selection.hasSelection,
          child: CallbackShortcuts(
            bindings: _shortcuts,
            child: Focus(
              autofocus: true,
              child: Scaffold(
                body: ListenableBuilder(
                  listenable: _ui,
                  builder: (context, _) => Stack(
                    children: [
                      SafeArea(
                        // The phone bar paints behind the status bar itself.
                        top: wide,
                        child: Column(
                          children: [
                            EditorTopBar(
                              editor: _editor,
                              ui: _ui,
                              settings: _services.settings,
                              canvas: _canvas,
                              wide: wide,
                              saved: !_dirty,
                              actions: _topBarActions,
                            ),
                            Expanded(
                              child: wide
                                  ? _buildWide(context, screen)
                                  : _buildCompact(context),
                            ),
                          ],
                        ),
                      ),
                      if (!wide) _layersDrawer(context, screen),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------ pattern sources

  /// Photo → crop page (free ratio) → pattern tile.
  Future<Uint8List?> _pickPatternImage() async {
    final picked = await _services.platform.pickImage();
    if (picked == null || !mounted) return null;
    final codec = await ui.instantiateImageCodec(picked.bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return null;
    }
    // Not disposed here: the crop page still paints it while it closes.
    final r = await showCropPage(context, image: frame.image);
    return r?.bytes;
  }

  Future<Uint8List?> _patternFromLayer() async {
    final id = _editor.selectedId;
    return id == null ? null : _editor.renderLayerPng(id);
  }

  Future<Uint8List?> _patternFromSelection() async {
    final sel = _ui.selection.current;
    if (sel == null) return null;
    return _editor.renderSelection(sel, sourceId: _ui.selection.targetId);
  }

  late final TopBarActions _topBarActions = TopBarActions(
    back: () => unawaited(_requestClose()),
    rename: () => unawaited(_renameDocument()),
    save: _openSaveSheet,
    exportImage: () => unawaited(showExportSheet(context, _editor)),
    resizeCanvas: () => unawaited(_resizeCanvas()),
    exportProject: () => unawaited(_exportProject()),
    editLayer: _editSelected,
    deleteSelection: () =>
        unawaited(_confirmDeleteLayers(_editor.topLevelSelection)),
  );

  void _editSelected() {
    switch (_editor.selectedLayer) {
      case final TextLayer t:
        unawaited(_editText(t));
      case final RasterLayer r:
        unawaited(_replaceImage(r));
      case ShapeLayer():
        _ui.panel = ToolPanel.shapeStyle;
      case final IconLayer i:
        unawaited(_changeIcon(i));
      case PathLayer():
        _ui.panel = ToolPanel.pen;
      case DrawingLayer():
        _ui.panel = ToolPanel.brush;
      case GroupLayer() || null:
        _ui.showLayers = true;
    }
  }

  Widget _canvasView() {
    final s = _services.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => CanvasView(
        editor: _editor,
        tool: _tool,
        snap: SnapOptions(
          enabled: s.snapping,
          canvas: s.snapCanvas,
          guides: s.snapGuides,
          layers: s.snapLayers,
          angles: s.snapAngles,
        ),
        showRulers: s.showRulers,
        rulerUnit: s.rulerUnit,
        guideColor: s.guideColor,
        controller: _canvas,
        onTap: _onCanvasTap,
      ),
    );
  }

  ContextDock _dock({bool vertical = false}) => ContextDock(
    editor: _editor,
    ui: _ui,
    vertical: vertical,
    onAddText: _addText,
    onAddImage: _addImage,
    onEditText: _editText,
    onPickFont: _pickFont,
    onResizeCanvas: _resizeCanvas,
    commands: _commands,
  );

  Widget _buildCompact(BuildContext context) {
    final theme = Theme.of(context);
    final pix = PixColors.of(context);
    final size = MediaQuery.sizeOf(context);
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _canvasView()),
              if (_editor.document.layers.isEmpty && _ui.panel == null)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 16,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.inverseSurface.withValues(
                            alpha: 0.85,
                          ),
                          borderRadius: BorderRadius.circular(
                            PixTokens.radiusL,
                          ),
                        ),
                        child: Text(
                          l.noLayers,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.onInverseSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.bottomSheetTheme.backgroundColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(PixTokens.radiusL),
            ),
            boxShadow: [
              BoxShadow(
                color: pix.softShadow,
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ToolPanelHost(
                editor: _editor,
                ui: _ui,
                maxHeight: size.height * 0.36,
                hooks: _hooks,
              ),
              _dock(),
            ],
          ),
        ),
      ],
    );
  }

  /// Phones and small tablets: the layers panel is a full-height sheet
  /// that runs edge to edge from the top of the screen, so the list gets as
  /// much room as possible. Swipe it towards the edge or tap the handle to
  /// close it.
  Widget _layersDrawer(BuildContext context, ScreenClass screen) {
    final theme = Theme.of(context);
    final pix = PixColors.of(context);
    final width = screen.panelWidth(MediaQuery.sizeOf(context).width);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final open = _ui.showLayers;
    return AnimatedPositionedDirectional(
      duration: PixTokens.medium,
      curve: PixTokens.emphasized,
      top: 0,
      bottom: 0,
      end: open ? 0 : -width - 24,
      width: width,
      child: IgnorePointer(
        ignoring: !open,
        child: GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            // Towards the screen edge: right in LTR, left in RTL.
            if ((rtl ? -v : v) > 250) _ui.showLayers = false;
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.bottomSheetTheme.backgroundColor,
              borderRadius: const BorderRadiusDirectional.horizontal(
                start: Radius.circular(PixTokens.radiusXL),
              ).resolve(Directionality.of(context)),
              boxShadow: [BoxShadow(color: pix.softShadow, blurRadius: 32)],
            ),
            child: SafeArea(
              left: rtl,
              right: !rtl,
              child: Row(
                children: [
                  // Grab edge.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _ui.showLayers = false,
                    child: SizedBox(
                      width: 14,
                      child: Center(
                        child: Container(
                          width: 4,
                          height: 44,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayersPanel(
                      editor: _editor,
                      commands: _commands,
                      onClose: () => _ui.showLayers = false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWide(BuildContext context, ScreenClass screen) {
    final theme = Theme.of(context);
    final side = theme.bottomSheetTheme.backgroundColor;
    return Row(
      children: [
        ColoredBox(
          color: side ?? theme.colorScheme.surface,
          child: _dock(vertical: true),
        ),
        Expanded(child: _canvasView()),
        SizedBox(
          width: screen.panelWidth(MediaQuery.sizeOf(context).width),
          child: ColoredBox(
            color: side ?? theme.colorScheme.surface,
            child: Column(
              children: [
                Expanded(
                  child: LayersPanel(editor: _editor, commands: _commands),
                ),
                const Divider(height: 1),
                ToolPanelHost(
                  editor: _editor,
                  ui: _ui,
                  maxHeight: 440,
                  hooks: _hooks,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Uint8List _encodeProject((PixDocument, Map<String, Uint8List>, Uint8List?) a) =>
    PixoraFormat.encode(a.$1, a.$2, thumbnail: a.$3);
