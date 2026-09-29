import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/render/filter_engine.dart';
import 'package:pixora/features/editor/widgets/layer_thumbs.dart';

Future<Uint8List> _pixels(ui.Image img) async =>
    (await img.toByteData())!.buffer.asUint8List();

/// A 200×100 image: an opaque red square on the left half.
ui.Image _source() {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(
    const Rect.fromLTWH(20, 20, 80, 60),
    Paint()..color = const Color(0xFFFF0000),
  );
  return rec.endRecording().toImageSync(200, 100);
}

DispersionFilter _filter(Map<String, Object> p) => EffectRegistry
    .instance['dispersion']!
    .create(p)
    .let(
      (e) =>
          EffectRegistry.instance['dispersion']!.filter!(
                e,
                const Rect.fromLTWH(20, 20, 80, 60),
              )!
              as DispersionFilter,
    );

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

int _alphaIn(Uint8List px, int w, Rect r) {
  var n = 0;
  for (var y = r.top.toInt(); y < r.bottom; y++) {
    for (var x = r.left.toInt(); x < r.right; x++) {
      if (px[(y * w + x) * 4 + 3] > 40) n++;
    }
  }
  return n;
}

void main() {
  test('particles fly in the chosen direction and leave holes', () async {
    final src = _source();
    final out = FilterEngine.apply(src, const Rect.fromLTWH(0, 0, 200, 100), [
      FilterStep(
        _filter({
          'angle': 0,
          'distance': 60,
          'size': 4,
          'density': 100,
          'erode': 100,
          'start': 20,
          'transition': 40,
          'spread': 0,
        }),
      ),
    ]);
    final px = await _pixels(out);
    // Right of the square, where there was nothing: particles.
    expect(
      _alphaIn(px, 200, const Rect.fromLTWH(104, 20, 60, 60)),
      greaterThan(80),
    );
    // Left of the square: nothing flew backwards.
    expect(_alphaIn(px, 200, const Rect.fromLTWH(0, 0, 18, 100)), 0);
    // The far side of the square dissolved, the near side stayed.
    final near = _alphaIn(px, 200, const Rect.fromLTWH(22, 22, 12, 56));
    final far = _alphaIn(px, 200, const Rect.fromLTWH(86, 22, 12, 56));
    // (Particles from further left land there too.)
    expect(near, greaterThan(far * 2));
  });

  test('same seed, same pattern; another seed, another', () async {
    Future<Uint8List> run(int seed) async => _pixels(
      FilterEngine.apply(_source(), const Rect.fromLTWH(0, 0, 200, 100), [
        FilterStep(_filter({'seed': seed, 'distance': 50, 'size': 5})),
      ]),
    );
    final a = await run(1), b = await run(1), c = await run(2);
    expect(a, b);
    expect(a, isNot(c));
  });

  test('thumbnail backdrop turns light for dark layers', () {
    Uint8List fill(int v) => Uint8List.fromList([
      for (var i = 0; i < 64; i++) ...[v, v, v, 255],
    ]);
    const darkA = Color(0xFF2A2A2A), darkB = Color(0xFF222222);
    final black = thumbLightness(fill(0))!;
    expect(black, lessThan(0.05));
    final (a, _) = thumbBackdrop(black, darkA, darkB);
    expect(a.computeLuminance(), greaterThan(0.5));
    // A bright layer keeps the theme's dark board.
    expect(thumbBackdrop(thumbLightness(fill(250)), darkA, darkB).$1, darkA);
    // A white layer on a light board gets a dark one.
    const lightA = Color(0xFFFFFFFF), lightB = Color(0xFFE8E8E8);
    final (c, _) = thumbBackdrop(thumbLightness(fill(255)), lightA, lightB);
    expect(c.computeLuminance(), lessThan(0.1));
    // Fully transparent: no opinion.
    expect(thumbLightness(Uint8List(64 * 4)), isNull);
  });
}
