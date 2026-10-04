import 'dart:math' as math;

import '../model/document.dart';
import '../model/effect.dart';
import '../model/layer.dart';

/// Photoshop's "Use Global Light": effects marked `global` (bevels, drop
/// and inner shadows, 3D extrusions) share the document's light. Moving
/// the light in any of them moves it in all of them; new ones start lit
/// from it.
abstract final class GlobalLight {
  /// Effect types that take a light.
  static const types = {'bevel', 'shadow', 'innerShadow', 'extrude'};

  static bool uses(LayerEffect e) =>
      types.contains(e.type) && e.number('global', 0) >= 1;

  /// The light an effect is lit from: (angle, altitude?) in Photoshop's
  /// convention (degrees, counter-clockwise from the right).
  static (double, double?)? lightOf(LayerEffect e) => switch (e.type) {
    'bevel' => (e.number('angle', 120), e.number('altitude', 30)),
    'extrude' => (e.number('lightAngle', 120), e.number('altitude', 30)),
    'innerShadow' => (e.number('angle', 120), null),
    'shadow' => _shadowLight(e),
    _ => null,
  };

  // A drop shadow falls away from the light: its offset points at
  // angle + 180°.
  static (double, double?)? _shadowLight(LayerEffect e) {
    final dx = e.number('dx', 12), dy = e.number('dy', 12);
    if (dx == 0 && dy == 0) return null;
    final a = math.atan2(dy, -dx) * 180 / math.pi + 180;
    return (_norm(a), null);
  }

  static double _norm(double a) {
    var v = a % 360;
    if (v > 180) v -= 360;
    if (v <= -180) v += 360;
    return double.parse(v.toStringAsFixed(2));
  }

  static bool _same(double a, double b) => (_norm(a - b)).abs() < 0.05;

  /// [e] lit from [angle] / [altitude].
  static LayerEffect withLight(LayerEffect e, double angle, double altitude) {
    switch (e.type) {
      case 'bevel':
        return e.copyWith(
          params: {...e.params, 'angle': angle, 'altitude': altitude},
        );
      case 'extrude':
        return e.copyWith(
          params: {...e.params, 'lightAngle': angle, 'altitude': altitude},
        );
      case 'innerShadow':
        return e.withParam('angle', angle);
      case 'shadow':
        final dx = e.number('dx', 12), dy = e.number('dy', 12);
        final d = math.sqrt(dx * dx + dy * dy);
        final r = (angle + 180) * math.pi / 180;
        return e.copyWith(
          params: {
            ...e.params,
            'dx': double.parse((d * math.cos(r)).toStringAsFixed(2)),
            'dy': double.parse((-d * math.sin(r)).toStringAsFixed(2)),
          },
        );
    }
    return e;
  }

  /// [after] with its global-light effects agreeing: an effect that moved
  /// its light (compared with [before]) moves the document's light and
  /// every other global effect; global effects that are new adopt the
  /// document's light.
  static PixDocument sync(PixDocument before, PixDocument after) {
    var angle = after.lightAngle, altitude = after.lightAltitude;
    final old = <String, LayerEffect>{
      for (final l in before.allLayers)
        for (final e in l.props.effects)
          if (uses(e)) e.id: e,
    };
    var moved = false, any = false;
    for (final l in after.allLayers) {
      for (final e in l.props.effects) {
        if (!uses(e)) continue;
        any = true;
        final was = old[e.id];
        if (was == null || !uses(was)) continue;
        final now = lightOf(e), then = lightOf(was);
        if (now == null || then == null) continue;
        final altChanged =
            now.$2 != null && then.$2 != null && now.$2 != then.$2;
        if (!_same(now.$1, then.$1) || altChanged) {
          angle = now.$1;
          if (now.$2 != null) altitude = now.$2!;
          moved = true;
        }
      }
    }
    if (!any) return after;
    // The document's light itself changed (from the global light control).
    if (!moved &&
        (after.lightAngle != before.lightAngle ||
            after.lightAltitude != before.lightAltitude)) {
      moved = true;
    }
    var changed = false;
    Layer relight(Layer l) {
      if (!l.props.effects.any(uses)) return l;
      var touched = false;
      final effects = [
        for (final e in l.props.effects)
          if (uses(e))
            () {
              final now = lightOf(e);
              final alt = now?.$2;
              if (now != null &&
                  _same(now.$1, angle) &&
                  (alt == null || alt == altitude)) {
                return e;
              }
              touched = true;
              return withLight(e, angle, altitude);
            }()
          else
            e,
      ];
      if (!touched) return l;
      changed = true;
      return l.withProps(l.props.copyWith(effects: effects));
    }

    final next = after.mapLayers(relight);
    if (!changed &&
        after.lightAngle == angle &&
        after.lightAltitude == altitude) {
      return after;
    }
    return (changed ? next : after).copyWith(
      lightAngle: angle,
      lightAltitude: altitude,
    );
  }
}
