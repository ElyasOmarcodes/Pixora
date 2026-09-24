import 'dart:math' as math;
import 'dart:ui';

import 'layer.dart';

/// A move + rotate + uniform scale about [pivot] — the kind of transform a
/// user applies with drag, pinch and the rotate handle.
class Similarity {
  const Similarity({
    this.pivot = Offset.zero,
    this.translate = Offset.zero,
    this.rotation = 0,
    this.scale = 1,
  });

  final Offset pivot;
  final Offset translate;

  /// Radians, clockwise.
  final double rotation;
  final double scale;

  Offset apply(Offset p) {
    final d = p - pivot;
    final c = math.cos(rotation), s = math.sin(rotation);
    return pivot +
        Offset((d.dx * c - d.dy * s) * scale, (d.dx * s + d.dy * c) * scale) +
        translate;
  }
}

/// Applies [s] to a layer. Groups apply it to every descendant, so a group
/// (or a multi-selection) transforms as one rigid unit.
Layer applySimilarity(Layer layer, Similarity s) => switch (layer) {
  GroupLayer g => g.copyWith(
    children: [for (final c in g.children) applySimilarity(c, s)],
  ),
  _ => layer.update((p) {
    final t = p.transform;
    final pos = s.apply(t.position);
    return p.copyWith(
      transform: t.copyWith(
        x: pos.dx,
        y: pos.dy,
        rotation: t.rotation + s.rotation,
        scaleX: t.scaleX * s.scale,
        scaleY: t.scaleY * s.scale,
      ),
    );
  }),
};

/// Mirrors a layer across the vertical (horizontal = true) or horizontal
/// line through [axis].
Layer applyFlip(Layer layer, Offset axis, {required bool horizontal}) =>
    switch (layer) {
      GroupLayer g => g.copyWith(
        children: [
          for (final c in g.children)
            applyFlip(c, axis, horizontal: horizontal),
        ],
      ),
      _ => layer.update((p) {
        final t = p.transform;
        return p.copyWith(
          transform: horizontal
              ? t.copyWith(
                  x: 2 * axis.dx - t.x,
                  rotation: -t.rotation,
                  scaleX: -t.scaleX,
                )
              : t.copyWith(
                  y: 2 * axis.dy - t.y,
                  rotation: -t.rotation,
                  scaleY: -t.scaleY,
                ),
        );
      }),
    };
