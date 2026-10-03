import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../app/app_scope.dart';
import '../../core/platform/platform_services.dart';
import '../../app/theme/app_theme.dart';
import '../../document/assets/asset_store.dart';
import '../../document/model/document.dart';
import '../../document/model/fill.dart';
import '../../document/model/layer.dart';
import '../../document/model/layer_transform.dart';
import '../../l10n/app_localizations.dart';
import '../../projects/canvas_presets.dart';
import '../../projects/project_store.dart';
import '../../ui/widgets/pixora_logo.dart';
import '../editor/editor_page.dart';
import '../settings/settings_page.dart';
import 'widgets/new_canvas_dialog.dart';
import 'widgets/preset_card.dart';
import 'widgets/projects_section.dart';

String presetLabel(AppLocalizations l, String id) => switch (id) {
  'square' => l.presetSquare,
  'portrait' => l.presetPortrait,
  'story' => l.presetStory,
  'landscape' => l.presetLandscape,
  'youtube' => l.presetYoutube,
  'a4' => l.presetA4,
  'a3' => l.presetA3,
  'a4land' => l.presetA4Land,
  'a5' => l.presetA5,
  'letter' => l.presetLetter,
  'cover' => l.presetCover,
  'logo' => l.presetLogo,
  _ => id,
};

/// The projects screen: start something new, or continue a recent design.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final _services = AppScope.of(context);
  Future<List<ProjectSummary>>? _projects;
  StreamSubscription<PickedFile>? _openSub;
  bool _editorOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_projects == null) {
      _services.projects.addListener(_reload);
      _reload();
      _openSub = _services.platform.openedFiles.listen(_openExternal);
      // Files the app was launched with ("Open with", double-click).
      final pending = _services.platform.takePendingOpenedFiles();
      if (pending.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _openExternal(pending.first),
        );
      }
    }
  }

  @override
  void dispose() {
    unawaited(_openSub?.cancel());
    _services.projects.removeListener(_reload);
    super.dispose();
  }

  /// Imports a `.pixora` file handed over by the OS or picked by the user
  /// and opens it.
  Future<void> _openExternal(PickedFile file) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final project = await _services.projects.importArchive(file.bytes);
      if (!mounted) return;
      if (_editorOpen) {
        // Close the current editor first; it saves on the way out.
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
      await _openEditor(project);
    } on FormatException {
      messenger.showSnackBar(SnackBar(content: Text(l.invalidProject)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l.invalidProject}: $e')),
      );
    }
  }

  Future<void> _importProject() async {
    final file = await _services.platform.pickProjectFile();
    if (file != null) await _openExternal(file);
  }

  void _reload() => setState(() => _projects = _services.projects.list());

  Future<void> _openEditor(StoredProject project) async {
    _editorOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => EditorPage(project: project)),
    );
    _editorOpen = false;
  }

  void _createBlank(
    double w,
    double h, {
    PixFill? background,
    bool transparent = false,
    double dpi = 72,
  }) {
    final l = AppLocalizations.of(context);
    final doc = PixDocument(
      name: l.untitled,
      width: w,
      height: h,
      background: transparent ? null : (background ?? PixFill.white),
      dpi: dpi,
    );
    unawaited(_openEditor(StoredProject(doc, const {})));
  }

  Future<void> _createFromPhoto() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await _services.platform.pickImage();
    if (picked == null) return;
    try {
      final size = await measureImage(picked.bytes);
      // Very large photos are scaled down to keep editing fluid.
      final scale = math.min(1.0, 6000 / math.max(size.width, size.height));
      final w = (size.width * scale).roundToDouble();
      final h = (size.height * scale).roundToDouble();
      const assetId = 'photo';
      final layer = RasterLayer(
        LayerProps(
          name: l.image,
          transform: LayerTransform(
            x: w / 2,
            y: h / 2,
            scaleX: scale,
            scaleY: scale,
          ),
        ),
        assetId: assetId,
        width: size.width,
        height: size.height,
      );
      final name = picked.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      final doc = PixDocument(
        name: name.isEmpty ? l.untitled : name,
        width: w,
        height: h,
        layers: [layer],
      );
      await _openEditor(StoredProject(doc, {assetId: picked.bytes}));
    } catch (e, st) {
      debugPrint('Pixora: opening the photo failed: $e\n$st');
      messenger.showSnackBar(SnackBar(content: Text(l.imageOpenFailed)));
    }
  }

  Future<void> _custom() async {
    final result = await showNewCanvasDialog(context);
    if (result == null) return;
    _createBlank(
      result.width,
      result.height,
      transparent: result.transparent,
      dpi: result.dpi,
    );
  }

  Future<void> _openExisting(ProjectSummary s) async {
    final p = await _services.projects.load(s.id);
    if (p != null && mounted) await _openEditor(p);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final pad = width > 900 ? 40.0 : 20.0;
    // Phones get smaller preset cards, leaving the screen to the projects.
    final compact = width < 600;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          // iOS-style momentum and bounce on every platform: a softer,
          // more natural glide than the clamping default on Android, and
          // rows built ahead of time so nothing pops in while flinging.
          physics: _smoothScroll,
          scrollCacheExtent: const ScrollCacheExtent.pixels(900),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 16, pad - 8, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    const PixoraLogo(size: 40),
                    const SizedBox(width: 12),
                    Text(
                      'Pixora',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: l.importProject,
                      onPressed: _importProject,
                      icon: const Icon(Icons.file_open_rounded),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      tooltip: l.settings,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsPage(),
                        ),
                      ),
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 14, pad, 0),
              sliver: SliverToBoxAdapter(child: _Greeting(l: l)),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, compact ? 16 : 20, pad, 4),
              sliver: SliverToBoxAdapter(
                child: Text(
                  l.newProject,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: compact ? 138 : 176,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: _smoothScroll,
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.symmetric(horizontal: pad - 6),
                  children: [
                    PhotoCard(
                      label: l.openPhoto,
                      onTap: _createFromPhoto,
                      compact: compact,
                    ),
                    for (final p in kCanvasPresets)
                      PresetCard(
                        preset: p,
                        compact: compact,
                        label: presetLabel(l, p.id),
                        onTap: () =>
                            _createBlank(p.width, p.height, dpi: p.dpi),
                      ),
                    CustomSizeCard(
                      label: l.customSize,
                      onTap: _custom,
                      compact: compact,
                    ),
                  ],
                ),
              ),
            ),
            ProjectsSection(
              projects: _projects,
              pad: pad,
              empty: _EmptyProjects(l: l),
              onOpen: _openExisting,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.l});
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(PixTokens.radiusL),
            ),
            child: Icon(
              Icons.auto_awesome_mosaic_rounded,
              size: 40,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            l.noProjects,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l.noProjectsHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft gradient card with a greeting for the time of day.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.l});
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final h = DateTime.now().hour;
    final (text, icon) = h < 5 || h >= 18
        ? (l.greetEvening, Icons.nights_stay_rounded)
        : h < 12
        ? (l.greetMorning, Icons.wb_sunny_rounded)
        : (l.greetAfternoon, Icons.wb_twilight_rounded);
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - v)),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              scheme.primary,
              Color.lerp(scheme.primary, const Color(0xFF9B5CFF), 0.6)!,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.createToday,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scrolling for the home page (see its [CustomScrollView]).
const _smoothScroll = BouncingScrollPhysics(
  parent: AlwaysScrollableScrollPhysics(),
  decelerationRate: ScrollDecelerationRate.normal,
);
