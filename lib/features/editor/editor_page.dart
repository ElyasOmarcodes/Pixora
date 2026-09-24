import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_theme.dart';
import '../../document/model/layer.dart';
import '../../editor/editor_controller.dart';
import '../../editor/tools/editor_tool.dart';
import '../../editor/tools/transform_tool.dart';
import '../../l10n/app_localizations.dart';
import '../../projects/project_store.dart';
import '../home/widgets/new_canvas_dialog.dart';
import '../home/widgets/text_prompt.dart';
import 'editor_scope.dart';
import 'panels/tool_panel_host.dart';
import 'widgets/canvas_view.dart';
import 'widgets/context_dock.dart';
import 'widgets/export_sheet.dart';
import 'widgets/layers_panel.dart';
import 'widgets/text_input_sheet.dart';

/// Wide layouts (tablets in landscape, desktops) get a side panel.
const double kWideLayoutBreakpoint = 840;

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
  late final EditorTool _tool = TransformTool(
    onEditRequest: (l) {
      if (l is TextLayer) _editText(l);
    },
  );

  Timer? _saveTimer;
  int _savedRevision = -1;
  bool _saving = false;
  bool _pendingSave = false;
  String? _lastSelection;

  @override
  void initState() {
    super.initState();
    _editor = EditorController(document: widget.project.document)
      ..assets.addAll(widget.project.assets)
      ..addListener(_onEditorChanged);
    for (final id in widget.project.document.referencedAssets) {
      unawaited(_editor.assets.decode(id));
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _editor.removeListener(_onEditorChanged);
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
      final keep =
          _ui.panel == ToolPanel.background && _editor.selectedId == null;
      if (!keep) _ui.panel = null;
    }
    if (_services.settings.autosave && _dirty && !_editor.isPreviewing) {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 1400), _save);
    }
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

  Future<void> _addText() async {
    final l = AppLocalizations.of(context);
    final text = await showTextInputSheet(context);
    if (text == null || text.trim().isEmpty) return;
    _editor.addText(text, name: l.text, color: _contrastingTextColor());
  }

  Future<void> _editText(TextLayer layer) async {
    final text = await showTextInputSheet(context, initial: layer.text);
    if (text == null || text.trim().isEmpty) return;
    _editor.updateLayer(
      layer.id,
      (l) => (l as TextLayer).copyWith(text: text),
      label: 'text',
    );
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
      resizing: true,
    );
    if (r != null) {
      _editor.resizeCanvas(r.width, r.height, scaleContent: r.scaleContent);
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

  void _nudge(double dx, double dy) {
    final l = _editor.selectedLayer;
    if (l == null || l.props.locked) return;
    _editor.updateProps(
      l.id,
      (p) => p.copyWith(
        transform: p.transform.copyWith(
          x: p.transform.x + dx,
          y: p.transform.y + dy,
        ),
      ),
      label: 'nudge',
    );
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final apple = _services.platform.info.isApple;
    SingleActivator mod(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k, control: !apple, meta: apple, shift: shift);
    void withSel(void Function(String id) f) {
      final id = _editor.selectedId;
      if (id != null) f(id);
    }

    return {
      mod(LogicalKeyboardKey.keyZ): _editor.undo,
      mod(LogicalKeyboardKey.keyZ, shift: true): _editor.redo,
      mod(LogicalKeyboardKey.keyY): _editor.redo,
      mod(LogicalKeyboardKey.keyS): () => unawaited(_save()),
      mod(LogicalKeyboardKey.keyD): () => withSel(_editor.duplicateLayer),
      mod(LogicalKeyboardKey.keyE): () =>
          unawaited(showExportSheet(context, _editor)),
      mod(LogicalKeyboardKey.digit0): _canvas.fit,
      const SingleActivator(LogicalKeyboardKey.delete): () =>
          withSel(_editor.deleteLayer),
      const SingleActivator(LogicalKeyboardKey.backspace): () =>
          withSel(_editor.deleteLayer),
      const SingleActivator(LogicalKeyboardKey.escape): () {
        _ui.panel = null;
        _editor.select(null);
      },
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _nudge(-1, 0),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => _nudge(1, 0),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _nudge(0, -1),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _nudge(0, 1),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () =>
          _nudge(-10, 0),
      const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () =>
          _nudge(10, 0),
      const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () =>
          _nudge(0, -10),
      const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): () =>
          _nudge(0, 10),
    };
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_saveAndExit());
      },
      child: EditorScope(
        controller: _editor,
        ui: _ui,
        child: CallbackShortcuts(
          bindings: _shortcuts,
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: SafeArea(
                child: ListenableBuilder(
                  listenable: _ui,
                  builder: (context, _) => Column(
                    children: [
                      _TopBar(
                        editor: _editor,
                        ui: _ui,
                        wide: wide,
                        saved: !_dirty,
                        onBack: _saveAndExit,
                        onRename: _renameDocument,
                        onFit: _canvas.fit,
                        onExport: () => showExportSheet(context, _editor),
                        onResize: _resizeCanvas,
                        onSave: _save,
                      ),
                      Expanded(
                        child: wide
                            ? _buildWide(context)
                            : _buildCompact(context),
                      ),
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

  Widget _canvasView() => CanvasView(
    editor: _editor,
    tool: _tool,
    snapping: _services.settings.snapping,
    showGrid: _ui.showGrid,
    controller: _canvas,
  );

  ContextDock _dock({bool vertical = false}) => ContextDock(
    editor: _editor,
    ui: _ui,
    vertical: vertical,
    onAddText: _addText,
    onAddImage: _addImage,
    onEditText: _editText,
    onResizeCanvas: _resizeCanvas,
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
              if (_editor.document.layers.isEmpty)
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
              // Floating layers drawer over the canvas.
              AnimatedPositionedDirectional(
                duration: PixTokens.medium,
                curve: PixTokens.emphasized,
                top: 10,
                bottom: 10,
                end: _ui.showLayers ? 10 : -340,
                width: size.width * 0.82 > 330 ? 330 : size.width * 0.82,
                child: AnimatedOpacity(
                  duration: PixTokens.fast,
                  opacity: _ui.showLayers ? 1 : 0,
                  child: Material(
                    elevation: 0,
                    color: theme.bottomSheetTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(PixTokens.radiusL),
                    clipBehavior: Clip.antiAlias,
                    shadowColor: pix.softShadow,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(PixTokens.radiusL),
                        boxShadow: [
                          BoxShadow(color: pix.softShadow, blurRadius: 30),
                        ],
                      ),
                      child: LayersPanel(
                        editor: _editor,
                        onClose: () => _ui.showLayers = false,
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
              ),
              _dock(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWide(BuildContext context) {
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
          width: 340,
          child: ColoredBox(
            color: side ?? theme.colorScheme.surface,
            child: Column(
              children: [
                Expanded(child: LayersPanel(editor: _editor)),
                const Divider(height: 1),
                ToolPanelHost(editor: _editor, ui: _ui, maxHeight: 440),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _MoreAction { grid, fit, resize, save }

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.editor,
    required this.ui,
    required this.wide,
    required this.saved,
    required this.onBack,
    required this.onRename,
    required this.onFit,
    required this.onExport,
    required this.onResize,
    required this.onSave,
  });

  final EditorController editor;
  final EditorUiState ui;
  final bool wide;
  final bool saved;
  final VoidCallback onBack;
  final VoidCallback onRename;
  final VoidCallback onFit;
  final VoidCallback onExport;
  final VoidCallback onResize;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: onBack,
            icon: const BackButtonIcon(),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(PixTokens.radiusS),
              onTap: onRename,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      editor.document.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Row(
                      children: [
                        AnimatedSwitcher(
                          duration: PixTokens.fast,
                          child: Icon(
                            saved
                                ? Icons.cloud_done_rounded
                                : Icons.cloud_upload_outlined,
                            key: ValueKey(saved),
                            size: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${editor.document.width.round()} × ${editor.document.height.round()}',
                            textDirection: TextDirection.ltr,
                            maxLines: 1,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l.undo,
            onPressed: editor.canUndo ? editor.undo : null,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: l.redo,
            onPressed: editor.canRedo ? editor.redo : null,
            icon: const Icon(Icons.redo_rounded),
          ),
          if (!wide)
            IconButton(
              tooltip: l.layers,
              isSelected: ui.showLayers,
              onPressed: () => ui.showLayers = !ui.showLayers,
              icon: const Icon(Icons.layers_outlined),
              selectedIcon: const Icon(Icons.layers_rounded),
            ),
          if (wide) ...[
            IconButton(
              tooltip: l.grid,
              isSelected: ui.showGrid,
              onPressed: ui.toggleGrid,
              icon: const Icon(Icons.grid_4x4_rounded),
            ),
            IconButton(
              tooltip: l.fitToScreen,
              onPressed: onFit,
              icon: const Icon(Icons.fit_screen_rounded),
            ),
          ],
          PopupMenuButton<_MoreAction>(
            tooltip: l.more,
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PixTokens.radiusM),
            ),
            onSelected: (a) => switch (a) {
              _MoreAction.grid => ui.toggleGrid(),
              _MoreAction.fit => onFit(),
              _MoreAction.resize => onResize(),
              _MoreAction.save => onSave(),
            },
            itemBuilder: (context) => [
              if (!wide)
                CheckedPopupMenuItem(
                  value: _MoreAction.grid,
                  checked: ui.showGrid,
                  child: Text(l.grid),
                ),
              if (!wide)
                PopupMenuItem(
                  value: _MoreAction.fit,
                  child: ListTile(
                    leading: const Icon(Icons.fit_screen_rounded),
                    title: Text(l.fitToScreen),
                  ),
                ),
              PopupMenuItem(
                value: _MoreAction.resize,
                child: ListTile(
                  leading: const Icon(Icons.aspect_ratio_rounded),
                  title: Text(l.canvasSize),
                ),
              ),
              PopupMenuItem(
                value: _MoreAction.save,
                child: ListTile(
                  leading: const Icon(Icons.save_rounded),
                  title: Text(l.save),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: onExport,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: Text(l.export),
          ),
        ],
      ),
    );
  }
}
