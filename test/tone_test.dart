import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/assets/asset_store.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/effects/tone.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/document/render/blend_shader.dart';
import 'package:pixora/document/render/document_renderer.dart';

void main() {
  test('curves: identity, negative, spline through its points', () {
    expect(ToneCurves.decode('rgb:0,0 255,255').isIdentity, isTrue);
    final neg = ToneCurves.decode(ToneCurves.presets['negative']);
    final lut = neg.lut();
    expect(lut[0], 255);
    expect(lut[255 * 3], 0);
    expect(lut[128 * 3 + 1], 127);
    final s = ToneCurves.sample(const [
      ui.Offset(0, 0),
      ui.Offset(64, 30),
      ui.Offset(192, 225),
      ui.Offset(255, 255),
    ]);
    expect(s[64], closeTo(30, 0.01));
    expect(s[192], closeTo(225, 0.01));
    // Monotonic S-curve between.
    for (var i = 1; i < 256; i++) {
      expect(s[i], greaterThanOrEqualTo(s[i - 1] - 1e-6));
    }
  });

  test('curves round-trip through the file text', () {
    final c = ToneCurves.decode(ToneCurves.presets['crossProcess']);
    final again = ToneCurves.decode(c.encode());
    expect(again.encode(), c.encode());
    expect(again.points[ToneChannel.red]!.length, 5);
  });

  test('levels: Photoshop formula', () {
    const lv = LevelsChannel(inBlack: 20, inWhite: 235, gamma: 1.5);
    expect(lv.apply(20), 0);
    expect(lv.apply(235), 255);
    expect(lv.apply(0), 0);
    // Gamma > 1 brightens midtones.
    expect(lv.apply(127.5), greaterThan(127.5));
    expect(LevelsChannel.gammaFor(lv.midPosition), closeTo(1.5, 1e-6));
    const out = LevelsChannel(outBlack: 30, outWhite: 200);
    expect(out.apply(0), 30);
    expect(out.apply(255), 200);
    expect(
      ToneLevels.autoPoints([
        for (var i = 0; i < 256; i++) i >= 40 && i <= 200 ? 100 : 0,
      ]),
      (40.0, 200.0),
    );
  });

  test('curves and levels change the rendered pixels', () async {
    await BlendShader.load();
    Future<List<int>> render(String type, Map<String, Object> p) async {
      final doc = PixDocument(
        name: 'd',
        width: 256,
        height: 8,
        layers: [
          ShapeLayer(
            LayerProps(
              name: 'g',
              transform: const LayerTransform(x: 128, y: 4),
              effects: [EffectRegistry.instance[type]!.create(p)],
            ),
            shape: ShapeKind.rectangle,
            width: 256,
            height: 8,
            fill: PixFill.color(const ui.Color(0xFF406080)),
          ),
        ],
      );
      final img = await DocumentRenderer(AssetStore()).renderImage(doc);
      final px = (await img.toByteData())!.buffer.asUint8List();
      const i = (4 * 256 + 128) * 4;
      return [px[i], px[i + 1], px[i + 2]];
    }

    expect(
      await render('curves', {'curves': ToneCurves.presets['negative']!}),
      [0xFF - 0x40, 0xFF - 0x60, 0xFF - 0x80],
    );
    final lv = await render('levels', {
      ToneLevels.param(ToneChannel.rgb, 'inWhite'): 128.0,
    });
    expect(lv[0], closeTo(0x80, 2));
    expect(lv[2], 255);
  });
}
