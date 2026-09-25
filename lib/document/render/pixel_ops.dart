import 'dart:math' as math;
import 'dart:typed_data';

// Per-pixel helpers shared by the layer-style engines.

/// Squared Euclidean distance from each pixel to the nearest pixel whose
/// [set] value is [target] (Felzenszwalb & Huttenlocher, two 1D passes).
Float32List edtSquared(Uint8List set, int w, int h, int target) {
  const inf = 1e20;
  final f = Float32List(math.max(w, h));
  final d = Float32List(math.max(w, h));
  final v = Int32List(math.max(w, h));
  final z = Float32List(math.max(w, h) + 1);
  final grid = Float32List(w * h);
  for (var i = 0; i < w * h; i++) {
    grid[i] = set[i] == target ? 0 : inf;
  }
  void pass(int len) {
    var k = 0;
    v[0] = 0;
    z[0] = -inf;
    z[1] = inf;
    for (var q = 1; q < len; q++) {
      var s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
      while (s <= z[k]) {
        k--;
        s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
      }
      k++;
      v[k] = q;
      z[k] = s;
      z[k + 1] = inf;
    }
    k = 0;
    for (var q = 0; q < len; q++) {
      while (z[k + 1] < q) {
        k++;
      }
      final dq = q - v[k];
      d[q] = dq * dq + f[v[k]];
    }
  }

  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      f[y] = grid[y * w + x];
    }
    pass(h);
    for (var y = 0; y < h; y++) {
      grid[y * w + x] = d[y];
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      f[x] = grid[y * w + x];
    }
    pass(w);
    for (var x = 0; x < w; x++) {
      grid[y * w + x] = d[x];
    }
  }
  return grid;
}

/// Three box blurs (≈ Gaussian) of radius [r].
Float32List blur3(Float32List src, int w, int h, int r) {
  var a = src;
  for (var k = 0; k < 3; k++) {
    a = boxBlur(a, w, h, r);
  }
  return a;
}

Float32List boxBlur(Float32List src, int w, int h, int r) {
  final tmp = Float32List(src.length), out = Float32List(src.length);
  final n = 2 * r + 1;
  for (var y = 0; y < h; y++) {
    final row = y * w;
    var sum = 0.0;
    for (var k = -r; k <= r; k++) {
      sum += src[row + k.clamp(0, w - 1)];
    }
    for (var x = 0; x < w; x++) {
      tmp[row + x] = sum / n;
      sum +=
          src[row + math.min(w - 1, x + r + 1)] - src[row + math.max(0, x - r)];
    }
  }
  for (var x = 0; x < w; x++) {
    var sum = 0.0;
    for (var k = -r; k <= r; k++) {
      sum += tmp[k.clamp(0, h - 1) * w + x];
    }
    for (var y = 0; y < h; y++) {
      out[y * w + x] = sum / n;
      sum +=
          tmp[math.min(h - 1, y + r + 1) * w + x] -
          tmp[math.max(0, y - r) * w + x];
    }
  }
  return out;
}
