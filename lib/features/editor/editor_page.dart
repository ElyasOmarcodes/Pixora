import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_theme.dart';
import '../../document/model/document.dart';
import '../../document/model/layer.dart';
import '../../editor/editor_controller.dart';
import '../../editor/tools/editor_tool.dart';
import '../../editor/tools/transform_tool.dart';
import '../../l10n/app_localizations.dart';
import '../../projects/pixora_format.dart';
import '../../projects/project_share.dart';
import '../../projects/project_store.dart';
import '../../ui/layer_style.dart';
import '../home/widgets/new_canvas_dialog.dart';
import '../home/widgets/text_prompt.dart';
import 'editor_scope.dart';
import 'panels/tool_panel_host.dart';
import 'widgets/canvas_view.dart';
import 'widgets/context_dock.dart';
import 'widgets/export_sheet.dart';
import 'widgets/layer_actions.dart';
import 'widgets/layers_panel.dart';
import 'widgets/text_input_sheet.dart';

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
    replaceImage: _replaceImage,
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
      mod(LogicalKeyboardKey.keyS): () => unawaited(_save()),
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
      const SingleActivator(LogicalKeyboardKey.delete): e.deleteSelected,
      const SingleActivator(LogicalKeyboardKey.backspace): e.deleteSelected,
      const SingleActivator(LogicalKeyboardKey.escape): () {
        _ui.panel = null;
        e.deselect();
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

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final screen = ScreenClass.of(context);
    final wide = screen.isWide;
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
              body: ListenableBuilder(
                listenable: _ui,
                builder: (context, _) => Stack(
                  children: [
                    SafeArea(
                      child: Column(
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
                            onExportProject: _exportProject,
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
                ToolPanelHost(editor: _editor, ui: _ui, maxHeight: 440),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _MoreAction { grid, fit, resize, save, exportProject }

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
    required this.onExportProject,
  });

  final VoidCallback onExportProject;
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
              _MoreAction.exportProject => onExportProject(),
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
              PopupMenuItem(
                value: _MoreAction.exportProject,
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_rounded),
                  title: Text(l.exportProject),
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

Uint8List _encodeProject((PixDocument, Map<String, Uint8List>, Uint8List?) a) =>
    PixoraFormat.encode(a.$1, a.$2, thumbnail: a.$3);
