import 'dart:math' as math;
import 'dart:typed_data';

import 'mask_jobs.dart';
import 'pixel_ops.dart';

/// Surface normals of a shape's sides for lit 3D extrusions.
///
/// An extruded side at a point faces the way the shape's edge faces
/// there. The direction to the nearest edge is the gradient of the
/// distance field, so every pixel of the shape gets the outward normal
/// of its nearest edge — stamping the shape along the depth then shows
/// each side lit by its own normal, as a real 3D extrusion would be.
/// The normals depend on the shape alone; light and colours are applied
/// on the GPU, so moving the light is instant.
abstract final class ExtrudeEngine {
  /// Shape (alpha) → opaque RGB normal map: red = 0.5 + 0.5·nx,
  /// green = 0.5 + 0.5·ny (screen space, y down).
  static MaskCompute normals() =>
      (rgba, w, h) => [normalMap(alphaOf(rgba), w, h)];

  static Uint8List normalMap(Float32List alpha, int w, int h) {
    final n = w * h;
    final inside = Uint8List(n);
    for (var i = 0; i < n; i++) {
      inside[i] = alpha[i] >= 0.5 ? 1 : 0;
    }
    final d2 = edtSquared(inside, w, h, 0);
    var d = Float32List(n);
    for (var i = 0; i < n; i++) {
      d[i] = inside[i] == 1 ? math.sqrt(d2[i]) + alpha[i] - 1 : alpha[i] - 0.5;
    }
    // Smooth the field so pixel steps along slanted edges do not show
    // as streaks down the extruded sides.
    d = blur3(d, w, h, 2);
    var gxs = Float32List(n), gys = Float32List(n);
    for (var y = 0; y < h; y++) {
      final r0 = (y > 0 ? y - 1 : y) * w, r1 = (y < h - 1 ? y + 1 : y) * w;
      final row = y * w;
      for (var x = 0; x < w; x++) {
        final x0 = x > 0 ? x - 1 : x, x1 = x < w - 1 ? x + 1 : x;
        // Distance grows inwards, so the outward normal is −∇d.
        gxs[row + x] = -(d[row + x1] - d[row + x0]);
        gys[row + x] = -(d[r1 + x] - d[r0 + x]);
      }
    }
    gxs = blur3(gxs, w, h, 2);
    gys = blur3(gys, w, h, 2);
    final out = Uint8List(n * 3);
    for (var i = 0; i < n; i++) {
      final gx = gxs[i], gy = gys[i];
      final len = math.sqrt(gx * gx + gy * gy);
      final j = i * 3;
      if (len < 1e-6) {
        out[j] = 128;
        out[j + 1] = 128;
      } else {
        out[j] = (127.5 + 127.5 * gx / len).round().clamp(0, 255);
        out[j + 1] = (127.5 + 127.5 * gy / len).round().clamp(0, 255);
      }
    }
    return out;
  }
}
