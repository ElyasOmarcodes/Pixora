import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/ids.dart';
import '../../core/utils/json.dart';

/// One effect instance attached to a layer (an adjustment, filter or style).
///
/// The effect is pure data: [type] names an [EffectDefinition] in the
/// `EffectRegistry`, and [params] holds its values. Keeping behaviour out of
/// the model means new effects can be added without touching the project
/// format, and unknown effects (from a newer version) survive a round trip.
@immutable
class LayerEffect {
  LayerEffect({
    String? id,
    required this.type,
    this.enabled = true,
    Map<String, Object> params = const {},
  }) : id = id ?? newId('fx'),
       params = Map.unmodifiable(params);

  final String id;
  final String type;
  final bool enabled;

  /// Parameter values: `num` for scalar params, `int` ARGB for colors,
  /// `String` for ids (patterns).
  final Map<String, Object> params;

  double number(String key, double fallback) {
    final v = params[key];
    return v is num ? v.toDouble() : fallback;
  }

  /// A text param (e.g. a pattern id), or [fallback].
  String? string(String key, [String? fallback]) {
    final v = params[key];
    return v is String ? v : fallback;
  }

  Color color(String key, Color fallback) {
    final v = params[key];
    return v is int ? Color(v) : fallback;
  }

  LayerEffect copyWith({bool? enabled, Map<String, Object>? params}) =>
      LayerEffect(
        id: id,
        type: type,
        enabled: enabled ?? this.enabled,
        params: params ?? this.params,
      );

  LayerEffect withParam(String key, Object value) =>
      copyWith(params: {...params, key: value});

  Json toJson() => {
    'id': id,
    'type': type,
    if (!enabled) 'enabled': false,
    'params': params,
  };

  static LayerEffect fromJson(Json json) {
    final raw = readMap(json['params']);
    return LayerEffect(
      id: readString(json['id'], newId('fx')),
      type: readString(json['type'], 'unknown'),
      enabled: readBool(json['enabled'], true),
      params: {
        for (final e in raw.entries)
          if (parseScalar(e.value) case final Object v
              when v is num || v is String)
            e.key: v,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LayerEffect &&
      other.id == id &&
      other.type == type &&
      other.enabled == enabled &&
      mapEquals(other.params, params);

  @override
  int get hashCode => Object.hash(id, type, enabled, params.length);
}
