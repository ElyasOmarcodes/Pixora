import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/render/color_matrix.dart';

void main() {
  test('crop state round-trips through JSON', () {
    const s = CropState(
      quarterTurns: 3,
      flipH: true,
      flipV: true,
      straighten: -12.5,
      rect: Rect.fromLTRB(0.1, 0.2, 0.8, 0.9),
      ellipse: true,
      resolution: 0.5,
    );
    expect(CropState.fromJson(s.toJson()), s);
  });

  test('image layer keeps its original source and crop', () {
    final layer = RasterLayer(
      LayerProps(name: 'Photo'),
      assetId: 'as_new',
      width: 100,
      height: 50,
      sourceAssetId: 'as_orig',
      crop: const CropState(rect: Rect.fromLTRB(0, 0, 0.5, 0.5)),
    );
    final back = Layer.fromJson(layer.toJson()) as RasterLayer;
    expect(back.sourceAssetId, 'as_orig');
    expect(back.crop, layer.crop);
    expect(back.copyWith(clearCrop: true).crop, isNull);
  });

  List<double> apply(List<double> m, List<double> rgb) => [
    for (var r = 0; r < 3; r++)
      m[r * 5] * rgb[0] +
          m[r * 5 + 1] * rgb[1] +
          m[r * 5 + 2] * rgb[2] +
          m[r * 5 + 4],
  ];

  test('colour fill modes', () {
    const red = Color(0xFFFF0000);
    // Fill replaces every pixel with the colour.
    final fill = ColorMatrix.colorFill(red, 1, 0);
    expect(apply(fill, [10, 200, 30]), [255, 0, 0]);
    // Tint keeps luminance: white stays the full colour, black stays black.
    final tint = ColorMatrix.colorFill(red, 1, 1);
    expect(apply(tint, [255, 255, 255])[0], closeTo(255, 0.01));
    expect(apply(tint, [0, 0, 0]), [0, 0, 0]);
    // Multiply darkens by the colour channels.
    final mul = ColorMatrix.colorFill(red, 1, 2);
    expect(apply(mul, [100, 100, 100]), [100, 0, 0]);
    // Zero strength is the identity.
    expect(apply(ColorMatrix.colorFill(red, 0, 0), [1, 2, 3]), [1, 2, 3]);
  });
}
