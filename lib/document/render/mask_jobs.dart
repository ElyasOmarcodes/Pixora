import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// CPU work that turns a shape (straight RGBA, 4 bytes per pixel: the
/// shape in alpha, extra data such as a texture in the colour channels)
/// into masks of the same size: grey coverage (1 byte per pixel) or opaque
/// colour (3 bytes per pixel, for gradient fills).
typedef MaskCompute = List<Uint8List> Function(Uint8List rgba, int w, int h);

/// The alpha channel of straight RGBA pixels, 0..1.
Float32List alphaOf(Uint8List rgba) {
  final a = Float32List(rgba.length ~/ 4);
  for (var i = 0; i < a.length; i++) {
    a[i] = rgba[i * 4 + 3] / 255;
  }
  return a;
}

/// 0..1 amounts to bytes.
Uint8List toBytes(Float32List v) {
  final out = Uint8List(v.length);
  for (var i = 0; i < v.length; i++) {
    out[i] = (v[i] * 255).round().clamp(0, 255);
  }
  return out;
}

/// Masks computed for one request, laid over [rect] (layer space).
class MaskResult {
  MaskResult(this.masks, this.rect);
  final List<ui.Image> masks;
  final Rect rect;
}

/// How urgently a request runs.
enum MaskLane {
  /// Small, fast version shown while a slider is moving.
  preview,

  /// Full resolution, started once the settings stop changing.
  full,

  /// Export: at once, never replaced by newer requests.
  now,
}

class _Req {
  _Req(this.key, this.slot, this.seq, this.alpha, this.rect, this.compute);
  final Object key;
  final Object slot;
  final int seq;
  final ui.Image alpha;
  final Rect rect;
  final MaskCompute compute;
  final Completer<void> done = Completer<void>();
}

/// Runs heavy per-pixel layer-style work (bevels, precise glows…) in the
/// background and caches the results, built for live editing:
///
/// * **no freezes** — the maths runs on a background isolate (on the web,
///   where there are none, the small preview keeps it light);
/// * **no flicker** — while new settings compute, the last result for the
///   same effect ([latest]) keeps showing;
/// * **no backlog** — each effect runs one job per lane; newer requests
///   replace queued ones, and full-resolution work waits until a slider
///   rests, while a quick low-resolution preview follows it live.
///
/// Listeners are told whenever a result lands, so the canvas repaints.
class MaskJobCache extends ChangeNotifier {
  MaskJobCache._();
  static final MaskJobCache instance = MaskJobCache._();

  /// Full-resolution work starts after the settings rest this long.
  static const settle = Duration(milliseconds: 90);

  static const _maxEntries = 40;

  final LinkedHashMap<Object, MaskResult> _done = LinkedHashMap();
  final Map<Object, _Req> _waiting = {}; // by key: queued or running
  final Map<(Object, MaskLane), _Req> _running = {};
  final Map<(Object, MaskLane), _Req> _queued = {};
  final Map<Object, Timer> _timers = {};
  final Map<Object, (int, MaskResult)> _latest = {};
  int _seq = 0;

  MaskResult? lookup(Object key) {
    final hit = _done.remove(key);
    if (hit != null) _done[key] = hit;
    return hit;
  }

  /// The most recent result for [slot] (an effect on a layer), whatever
  /// its settings — shown while newer settings compute.
  MaskResult? latest(Object slot) => _latest[slot]?.$2;

  bool isPending(Object key) => _waiting.containsKey(key);

  /// Completes when [key] has been computed (or dropped).
  Future<void> wait(Object key) async {
    final r = _waiting[key];
    if (r != null) await r.done.future;
  }

  /// Asks for [key]: [compute] runs over [alpha] (the shape, drawn over
  /// [rect]) in [lane] for [slot]. [alpha] is owned (and disposed) here.
  void request(
    Object key,
    Object slot,
    ui.Image alpha,
    Rect rect,
    MaskCompute compute, {
    MaskLane lane = MaskLane.full,
  }) {
    if (_done.containsKey(key) || _waiting.containsKey(key)) {
      alpha.dispose();
      return;
    }
    final laneSlot = lane == MaskLane.now ? (key, lane) : (slot, lane);
    final req = _Req(key, slot, ++_seq, alpha, rect, compute);
    _waiting[key] = req;
    final old = _queued.remove(laneSlot);
    if (old != null) _drop(old);
    _queued[laneSlot] = req;
    if (lane == MaskLane.full) {
      _timers.remove(laneSlot)?.cancel();
      _timers[laneSlot] = Timer(settle, () {
        _timers.remove(laneSlot);
        _pump(laneSlot);
      });
    } else {
      _pump(laneSlot);
    }
  }

  void _drop(_Req r) {
    if (identical(_waiting[r.key], r)) _waiting.remove(r.key);
    r.alpha.dispose();
    if (!r.done.isCompleted) r.done.complete();
  }

  void _pump((Object, MaskLane) laneSlot) {
    if (_running.containsKey(laneSlot)) return; // picked up when it ends
    final req = _queued.remove(laneSlot);
    if (req == null) return;
    _running[laneSlot] = req;
    unawaited(
      _run(req).then((result) {
        _running.remove(laneSlot);
        if (identical(_waiting[req.key], req)) _waiting.remove(req.key);
        if (result != null) {
          _done[req.key] = result;
          while (_done.length > _maxEntries) {
            final k = _done.keys.first;
            final evicted = _done.remove(k)!;
            _release(evicted);
          }
          final prev = _latest[req.slot];
          if (prev == null || prev.$1 <= req.seq) {
            _latest[req.slot] = (req.seq, result);
            if (prev != null) _release(prev.$2);
          }
          notifyListeners();
        }
        if (!req.done.isCompleted) req.done.complete();
        if (!_timers.containsKey(laneSlot)) _pump(laneSlot);
      }),
    );
  }

  /// Disposes a result's images once nothing refers to it any more.
  void _release(MaskResult r) {
    if (_done.values.any((d) => identical(d, r))) return;
    if (_latest.values.any((l) => identical(l.$2, r))) return;
    for (final m in r.masks) {
      m.dispose();
    }
  }

  Future<MaskResult?> _run(_Req req) async {
    try {
      final w = req.alpha.width, h = req.alpha.height;
      final data = await req.alpha.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      req.alpha.dispose();
      if (data == null) return null;
      final rgba = data.buffer.asUint8List();
      final fn = req.compute;
      final masks = kIsWeb
          ? fn(rgba, w, h)
          : await compute(_runCompute, (fn, rgba, w, h));
      final images = <ui.Image>[];
      for (final m in masks) {
        images.add(
          m.length == w * h * 3
              ? await colorImage(m, w, h)
              : await greyImage(m, w, h),
        );
      }
      return MaskResult(images, req.rect);
    } catch (e) {
      debugPrint('Pixora: effect mask failed: $e');
      return null;
    }
  }

  static List<Uint8List> _runCompute((MaskCompute, Uint8List, int, int) job) =>
      job.$1(job.$2, job.$3, job.$4);

  /// A coverage mask as an image (grey = alpha: valid whether the engine
  /// reads the pixels as premultiplied or not). Colour is applied when
  /// drawing, with a `srcIn` colour filter.
  static Future<ui.Image> greyImage(Uint8List amount, int w, int h) {
    final px = Uint8List(w * h * 4);
    for (var i = 0; i < amount.length; i++) {
      final v = amount[i];
      final j = i * 4;
      px[j] = v;
      px[j + 1] = v;
      px[j + 2] = v;
      px[j + 3] = v;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }

  /// Opaque colours (valid either way too), for gradient-filled effects.
  static Future<ui.Image> colorImage(Uint8List rgb, int w, int h) {
    final px = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      final j = i * 4, k = i * 3;
      px[j] = rgb[k];
      px[j + 1] = rgb[k + 1];
      px[j + 2] = rgb[k + 2];
      px[j + 3] = 255;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }
}
