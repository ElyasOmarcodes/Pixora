import 'dart:ui' as ui;

/// The blend-mode shader (shaders/blend.frag): Photoshop's modes the GPU
/// compositor lacks, composited with Photoshop's formulas.
class BlendShader {
  BlendShader._();

  static ui.FragmentProgram? program;

  /// Loads the shader once (at startup). Without it those modes fall back
  /// to the nearest built-in mode.
  static Future<void> load() async {
    if (program != null) return;
    try {
      program = await ui.FragmentProgram.fromAsset('shaders/blend.frag');
    } catch (_) {
      program = null;
    }
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
