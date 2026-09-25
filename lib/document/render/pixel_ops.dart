import 'dart:typed_data';

// Per-pixel helpers shared by the layer-style engines.

/// Squared Euclidean distance from each pixel to the nearest pixel whose
/// [set] value is [target] (Felzenszwalb & Huttenlocher, two 1D passes).
Float32List edtSquared(Uint8List set, int w, int h, int target) {
  const inf = 1e20;
  final n = w * h;
  // Vertical pass: on a binary image a 1D distance is just the gap to the
  // nearest target pixel in the column — two sweeps, in memory order.
  final col = Float32List(n);
  final run = Float32List(w)..fillRange(0, w, inf);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      final r = set[row + x] == target ? 0.0 : run[x] + 1;
      run[x] = r;
      col[row + x] = r;
    }
  }
  run.fillRange(0, w, inf);
  for (var y = h - 1; y >= 0; y--) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      final r = set[row + x] == target ? 0.0 : run[x] + 1;
      run[x] = r;
      final c = col[row + x];
      final m = c < r ? c : r;
      col[row + x] = m >= inf ? inf : m * m;
    }
  }
  // Horizontal pass: lower envelope of parabolas (Felzenszwalb &
  // Huttenlocher), row by row.
  final f = Float32List(w);
  final v = Int32List(w);
  final z = Float32List(w + 1);
  final grid = Float32List(n);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      f[x] = col[row + x];
    }
    var k = 0;
    v[0] = 0;
    z[0] = -inf;
    z[1] = inf;
    for (var q = 1; q < w; q++) {
      final fq = f[q] + q * q;
      var vk = v[k];
      var s = (fq - (f[vk] + vk * vk)) / (2 * (q - vk));
      while (s <= z[k]) {
        k--;
        vk = v[k];
        s = (fq - (f[vk] + vk * vk)) / (2 * (q - vk));
      }
      k++;
      v[k] = q;
      z[k] = s;
      z[k + 1] = inf;
    }
    k = 0;
    for (var q = 0; q < w; q++) {
      while (z[k + 1] < q) {
        k++;
      }
      final dq = q - v[k];
      grid[row + q] = dq * dq + f[v[k]];
    }
  }
  return grid;
}

/// Three box blurs (≈ Gaussian) of radius [r].
Float32List blur3(Float32List src, int w, int h, int r) {
  if (r <= 0) return Float32List.fromList(src);
  final a = Float32List(src.length), b = Float32List(src.length);
  _boxInto(src, b, a, w, h, r);
  _boxInto(a, b, a, w, h, r);
  _boxInto(a, b, a, w, h, r);
  return a;
}

Float32List boxBlur(Float32List src, int w, int h, int r) {
  final out = Float32List(src.length);
  if (r <= 0) return out..setAll(0, src);
  _boxInto(src, Float32List(src.length), out, w, h, r);
  return out;
}

/// One (2r+1)² box blur of [src] into [out] ([tmp] is scratch; [out] may
/// be [src]). Edges repeat the border pixel.
void _boxInto(
  Float32List src,
  Float32List tmp,
  Float32List out,
  int w,
  int h,
  int r,
) {
  final inv = 1 / (2 * r + 1);
  // Rows → tmp.
  for (var y = 0; y < h; y++) {
    final row = y * w;
    final first = src[row], last = src[row + w - 1];
    var sum = first * (r + 1);
    for (var k = 1; k <= r; k++) {
      sum += k < w ? src[row + k] : last;
    }
    for (var x = 0; x < w; x++) {
      tmp[row + x] = sum * inv;
      final add = x + r + 1, sub = x - r;
      sum +=
          (add < w ? src[row + add] : last) -
          (sub > 0 ? src[row + sub] : first);
    }
  }
  // Columns → out, row by row (memory order) with running column sums.
  final sums = Float64List(w);
  for (var x = 0; x < w; x++) {
    final first = tmp[x], last = tmp[(h - 1) * w + x];
    var sum = first * (r + 1);
    for (var k = 1; k <= r; k++) {
      sum += k < h ? tmp[k * w + x] : last;
    }
    sums[x] = sum;
  }
  final lastRow = (h - 1) * w;
  for (var y = 0; y < h; y++) {
    final row = y * w;
    final add = y + r + 1, sub = y - r;
    final addRow = add < h ? add * w : lastRow;
    final subRow = sub > 0 ? sub * w : 0;
    for (var x = 0; x < w; x++) {
      final v = sums[x];
      out[row + x] = v * inv;
      sums[x] = v + tmp[addRow + x] - tmp[subRow + x];
    }
  }
}
