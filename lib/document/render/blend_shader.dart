import 'dart:typed_data';
import 'dart:ui' as ui;

/// The blend-mode shader (shaders/blend.frag): Photoshop's modes the GPU
/// compositor lacks, composited with Photoshop's formulas.
class BlendShader {
  BlendShader._();

  static ui.FragmentProgram? program;

  /// The Curves / Levels lookup shader (shaders/lut.frag).
  static ui.FragmentProgram? lutProgram;

  /// The signed arithmetic shader (shaders/arith.frag).
  static ui.FragmentProgram? arithProgram;

  /// Loads the shader once (at startup). Without it those modes fall back
  /// to the nearest built-in mode.
  static Future<void> load() async {
    if (program == null) {
      try {
        program = await ui.FragmentProgram.fromAsset('shaders/blend.frag');
      } catch (_) {
        program = null;
      }
    }
    if (lutProgram == null) {
      try {
        lutProgram = await ui.FragmentProgram.fromAsset('shaders/lut.frag');
      } catch (_) {
        lutProgram = null;
      }
    }
    if (arithProgram == null) {
      try {
        arithProgram = await ui.FragmentProgram.fromAsset('shaders/arith.frag');
      } catch (_) {
        arithProgram = null;
      }
    }
  }

  /// [src] with each channel mapped through [lut] (interleaved R, G, B
  /// tables of 256 entries); null when the shader is unavailable.
  static ui.Image? lookup(ui.Image src, Uint8List lut) {
    final prog = lutProgram;
    if (prog == null) return null;
    // The table as a 256 x 1 image, one opaque pixel per level.
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    final paint = ui.Paint()..isAntiAlias = false;
    for (var i = 0; i < 256; i++) {
      paint.color = ui.Color.fromARGB(
        255,
        lut[i * 3],
        lut[i * 3 + 1],
        lut[i * 3 + 2],
      );
      c.drawRect(ui.Rect.fromLTWH(i.toDouble(), 0, 1, 1), paint);
    }
    final table = rec.endRecording().toImageSync(256, 1);
    final w = src.width, h = src.height;
    final shader = prog.fragmentShader()
      ..setFloat(0, w.toDouble())
      ..setFloat(1, h.toDouble())
      ..setImageSampler(0, src)
      ..setImageSampler(1, table);
    final r2 = ui.PictureRecorder();
    ui.Canvas(r2).drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..shader = shader,
    );
    final picture = r2.endRecording();
    final out = picture.toImageSync(w, h);
    picture.dispose();
    shader.dispose();
    table.dispose();
    return out;
  }

  /// `base + k·(a − b)` on straight colour, with [alpha]'s transparency
  /// (all the same size); [grey] (0..1) stands in for a flat base. Null
  /// when the shader is unavailable.
  static ui.Image? arith({
    ui.Image? base,
    double? grey,
    required ui.Image a,
    required ui.Image b,
    required double k,
    required ui.Image alpha,
  }) {
    final prog = arithProgram;
    if (prog == null) return null;
    final w = a.width, h = a.height;
    final shader = prog.fragmentShader()
      ..setFloat(0, w.toDouble())
      ..setFloat(1, h.toDouble())
      ..setFloat(2, k)
      ..setFloat(3, grey ?? -1)
      ..setImageSampler(0, base ?? a)
      ..setImageSampler(1, a)
      ..setImageSampler(2, b)
      ..setImageSampler(3, alpha);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..shader = shader,
    );
    final picture = recorder.endRecording();
    final out = picture.toImageSync(w, h);
    picture.dispose();
    shader.dispose();
    return out;
  }

  /// [src] composited onto [dst] (same size) with blend [code].
  static ui.Image composite(ui.Image src, ui.Image dst, int code, int seed) {
    final w = dst.width, h = dst.height;
    final shader = program!.fragmentShader()
      ..setFloat(0, w.toDouble())
      ..setFloat(1, h.toDouble())
      ..setFloat(2, code.toDouble())
      ..setFloat(3, (seed % 997) / 997)
      ..setImageSampler(0, src)
      ..setImageSampler(1, dst);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..shader = shader,
    );
    final picture = recorder.endRecording();
    final out = picture.toImageSync(w, h);
    picture.dispose();
    shader.dispose();
    return out;
  }
}
