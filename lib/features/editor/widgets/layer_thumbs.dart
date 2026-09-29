import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../document/model/layer.dart';
import '../../../document/model/layer_transform.dart';
import '../../../document/render/document_renderer.dart';
import '../../../editor/editor_controller.dart';
import '../../../ui/widgets/checkerboard.dart';

/// Layer thumbnails for the layers panel, rendered once into small
/// bitmaps and reused.
///
/// Drawing every thumbnail live meant rendering each visible layer — with
/// all its effects — whenever the panel opened, scrolled or rebuilt, which
/// got heavy with many layers. Now:
///
/// * a bitmap is kept per layer (layers are immutable, so an unchanged
///   layer reuses it, also after the panel is closed and opened again);
/// * missing bitmaps are rendered a few per frame within a time budget, so
///   opening the panel stays smooth;
/// * a layer that is being edited keeps its old bitmap until the edits
///   pause, instead of re-rendering on every drag frame.
class LayerThumbs {
  LayerThumbs._();
  static final LayerThumbs instance = LayerThumbs._();

  /// Thumbnail size, px (sharp on 3× screens for the 42 px box).
  static const int size = 128;
  static const _maxEntries = 800;
  static const _settle = Duration(milliseconds: 220);

  /// Thumbnails rendered so far (for tests).
  int renders = 0;

  final LinkedHashMap<String, _Entry> _cache = LinkedHashMap();
  final LinkedHashMap<String, _Job> _queue = LinkedHashMap();
  bool _scheduled = false;
  Timer? _timer;

  /// The bitmap for [layer] (possibly of an older version of it while the
  /// new one renders); [onReady] runs once a newer bitmap exists.
  ui.Image? lookup(
    Layer layer,
    EditorController editor,
    int generation,
    VoidCallback onReady,
  ) {
    final hit = _cache.remove(layer.id);
    if (hit != null) _cache[layer.id] = hit;
    final fresh =
        hit != null &&
        identical(hit.layer, layer) &&
        hit.generation == generation;
    if (!fresh) {
      final waiting = _queue.remove(layer.id);
      _queue[layer.id] = _Job(
        layer,
        editor,
        generation,
        // A first thumbnail comes at once; an update waits for the edit to
        // pause (the old bitmap stays up meanwhile).
        hit == null ? DateTime(0) : DateTime.now().add(_settle),
        {...?waiting?.listeners, onReady},
      );
      _schedule();
    }
    return hit?.image;
  }

  /// How light [layer]'s thumbnail content is (0 black … 1 white), once
  /// measured; null while unknown or when it has no visible pixels.
  double? toneOf(String id) => _cache[id]?.tone;

  /// Measures the thumbnail's alpha-weighted lightness off the frame
  /// (a 24 px copy read back asynchronously), then bumps [tones].
  Future<void> _measure(_Entry entry) async {
    const n = 24;
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(
      entry.image,
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      const Rect.fromLTWH(0, 0, n + 0.0, n + 0.0),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final pic = rec.endRecording();
    final small = pic.toImageSync(n, n);
    pic.dispose();
    final data = await small.toByteData();
    small.dispose();
    if (data == null) return;
    final tone = thumbLightness(data.buffer.asUint8List());
    if (tone == entry.tone) return;
    entry.tone = tone;
    tones.value++;
  }

  /// Bumped whenever a thumbnail's measured lightness changes.
  final ValueNotifier<int> tones = ValueNotifier(0);

  /// Stops notifying [onReady] (its widget went away).
  void forget(String id, VoidCallback onReady) =>
      _queue[id]?.listeners.remove(onReady);

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _run())
      ..ensureVisualUpdate();
  }

  void _run() {
    _scheduled = false;
    final now = DateTime.now();
    final sw = Stopwatch()..start();
    DateTime? next;
    final ready = <_Job>[];
    for (final job in _queue.values.toList()) {
      if (job.listeners.isEmpty) {
        _queue.remove(job.layer.id);
        continue;
      }
      if (job.notBefore.isAfter(now)) {
        if (next == null || job.notBefore.isBefore(next)) next = job.notBefore;
        continue;
      }
      // ~6 ms of rendering per frame, at least one thumbnail.
      if (sw.elapsedMilliseconds > 6 && ready.isNotEmpty) {
        _schedule();
        break;
      }
      _queue.remove(job.layer.id);
      renders++;
      final entry = _Entry(
        job.layer,
        job.generation,
        _render(job.layer, job.editor),
        _cache[job.layer.id]?.tone,
      );
      _cache[job.layer.id] = entry;
      ready.add(job);
      _measure(entry);
    }
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    for (final job in ready) {
      for (final f in job.listeners) {
        f();
      }
    }
    if (next != null && !_scheduled) {
      _timer?.cancel();
      _timer = Timer(next.difference(now), _schedule);
    }
  }

  /// Draws one layer fitted into the thumbnail: leaves un-transformed,
  /// groups as they appear on the canvas. Like Photoshop, the thumbnail
  /// shows the layer's content without its layer styles (they are listed
  /// under the row) — so no effect silhouettes are computed for it, and
  /// the canvas's effect caches stay untouched.
  static ui.Image _render(Layer layer, EditorController editor) {
    LayerProps bare(LayerProps p) => p.copyWith(
      opacity: 1,
      visible: true,
      clip: false,
      effects: const [],
      clearStroke: true,
    );
    Layer strip(Layer l) => l is GroupLayer
        ? GroupLayer(
            l.props.copyWith(effects: const [], clearStroke: true),
            children: [for (final c in l.children) strip(c)],
            expanded: l.expanded,
          )
        : l.withProps(l.props.copyWith(effects: const [], clearStroke: true));
    final Layer plain;
    if (layer is GroupLayer) {
      plain = strip(layer).update(bare);
    } else {
      final t = layer.props.transform;
      plain = layer.withProps(
        bare(layer.props).copyWith(
          transform: LayerTransform(
            scaleX: t.scaleX.sign,
            scaleY: t.scaleY.sign,
          ),
        ),
      );
    }
    final box = layerLocalRect(plain);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (!box.isEmpty) {
      final s = size.toDouble();
      final fit = math.min((s - 8) / box.width, (s - 8) / box.height);
      canvas
        ..translate(s / 2, s / 2)
        ..scale(fit)
        ..translate(-box.center.dx, -box.center.dy);
      // No shared raster cache: thumbnails must not evict the canvas's
      // bitmaps.
      DocumentRenderer(
        editor.assets,
        pixelScale: fit,
      ).paintLayer(canvas, plain);
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size, size);
    picture.dispose();
    return image;
  }
}

class _Entry {
  _Entry(this.layer, this.generation, this.image, this.tone);
  final Layer layer;
  final int generation;
  final ui.Image image;
  double? tone;
}

/// Alpha-weighted perceived lightness (0..1) of premultiplied RGBA
/// pixels; null when nearly nothing is visible.
double? thumbLightness(Uint8List rgba) {
  var sum = 0.0, weight = 0.0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final a = rgba[i + 3];
    if (a == 0) continue;
    // Un-premultiply, then perceived lightness ≈ √(relative luminance).
    final r = rgba[i] / a, g = rgba[i + 1] / a, b = rgba[i + 2] / a;
    final lum = 0.2126 * r * r + 0.7152 * g * g + 0.0722 * b * b;
    sum += math.sqrt(lum) * a;
    weight += a;
  }
  if (weight < 255 * 2) return null;
  return sum / weight;
}

/// The checkerboard colours to show a thumbnail of lightness [tone] on:
/// the theme's own ([a], [b]) unless the content would melt into them
/// (a black layer on a dark theme, a white one on a light theme) — then a
/// clearly lighter or darker board.
(Color, Color) thumbBackdrop(double? tone, Color a, Color b) {
  if (tone == null) return (a, b);
  double light(Color c) => math.sqrt(c.computeLuminance());
  final board = (light(a) + light(b)) / 2;
  if ((tone - board).abs() >= 0.28) return (a, b);
  return tone < 0.5
      ? (const Color(0xFFF2F2F2), const Color(0xFFD6D6D6))
      : (const Color(0xFF2E2E2E), const Color(0xFF1E1E1E));
}

/// A transparency checkerboard that turns light or dark so [layer]'s
/// thumbnail stays visible on it.
class ThumbBackdrop extends StatefulWidget {
  const ThumbBackdrop({
    super.key,
    required this.layer,
    required this.editor,
    required this.a,
    required this.b,
    this.cell = 5,
    this.builder,
  });
  final Layer layer;
  final EditorController editor;
  final Color a, b;
  final double cell;

  /// Builds with the chosen colours instead of painting a board.
  final Widget Function(BuildContext context, Color a, Color b)? builder;

  @override
  State<ThumbBackdrop> createState() => _ThumbBackdropState();
}

class _ThumbBackdropState extends State<ThumbBackdrop> {
  @override
  void initState() {
    super.initState();
    LayerThumbs.instance.tones.addListener(_ready);
  }

  @override
  void didUpdateWidget(ThumbBackdrop old) {
    super.didUpdateWidget(old);
    if (old.layer.id != widget.layer.id) {
      LayerThumbs.instance.forget(old.layer.id, _ready);
    }
  }

  @override
  void dispose() {
    LayerThumbs.instance.tones.removeListener(_ready);
    LayerThumbs.instance.forget(widget.layer.id, _ready);
    super.dispose();
  }

  void _ready() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Queues the thumbnail (and its measuring) if it isn't there yet.
    LayerThumbs.instance.lookup(
      widget.layer,
      widget.editor,
      _LayerThumbImageState._generation,
      _ready,
    );
    final (a, b) = thumbBackdrop(
      LayerThumbs.instance.toneOf(widget.layer.id),
      widget.a,
      widget.b,
    );
    final builder = widget.builder;
    if (builder != null) return builder(context, a, b);
    return SizedBox.expand(
      child: CheckerboardBox(a: a, b: b, cell: widget.cell),
    );
  }
}

class _Job {
  _Job(
    this.layer,
    this.editor,
    this.generation,
    this.notBefore,
    this.listeners,
  );
  final Layer layer;
  final EditorController editor;
  final int generation;
  final DateTime notBefore;
  final Set<VoidCallback> listeners;
}

/// A cached layer thumbnail (see [LayerThumbs]).
class LayerThumbImage extends StatefulWidget {
  const LayerThumbImage({super.key, required this.layer, required this.editor});
  final Layer layer;
  final EditorController editor;

  @override
  State<LayerThumbImage> createState() => _LayerThumbImageState();
}

class _LayerThumbImageState extends State<LayerThumbImage> {
  /// Bumped when assets change (an image finished decoding).
  static int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.editor.assets.addListener(_onAssets);
  }

  @override
  void didUpdateWidget(LayerThumbImage old) {
    super.didUpdateWidget(old);
    if (old.editor != widget.editor) {
      old.editor.assets.removeListener(_onAssets);
      widget.editor.assets.addListener(_onAssets);
    }
    if (old.layer.id != widget.layer.id) {
      LayerThumbs.instance.forget(old.layer.id, _ready);
    }
  }

  @override
  void dispose() {
    widget.editor.assets.removeListener(_onAssets);
    LayerThumbs.instance.forget(widget.layer.id, _ready);
    super.dispose();
  }

  void _onAssets() {
    _generation++;
    if (mounted) setState(() {});
  }

  void _ready() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final image = LayerThumbs.instance.lookup(
      widget.layer,
      widget.editor,
      _generation,
      _ready,
    );
    if (image == null) return const SizedBox.expand();
    return RawImage(
      image: image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
