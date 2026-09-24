import 'dart:async';

import '../../core/utils/json.dart';
import '../editor_controller.dart';

enum ActionParamType { string, number, integer, boolean, color, object }

/// Describes one argument of an [EditorAction].
class ActionParam {
  const ActionParam(
    this.name,
    this.type, {
    this.description = '',
    this.required = false,
    this.options,
    this.min,
    this.max,
  });

  final String name;
  final ActionParamType type;
  final String description;
  final bool required;
  final List<String>? options;
  final num? min;
  final num? max;

  Json toSchema() => {
    'type': switch (type) {
      ActionParamType.string || ActionParamType.color => 'string',
      ActionParamType.number => 'number',
      ActionParamType.integer => 'integer',
      ActionParamType.boolean => 'boolean',
      ActionParamType.object => 'object',
    },
    if (description.isNotEmpty) 'description': description,
    if (type == ActionParamType.color && description.isEmpty)
      'description': 'Color as #RRGGBB or #AARRGGBB',
    'enum': ?options,
    'minimum': ?min,
    'maximum': ?max,
  };
}

class ActionException implements Exception {
  ActionException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef ActionRunner = FutureOr<Object?> Function(
  EditorController editor,
  ActionArgs args,
);

/// A named, self-describing editor command.
///
/// Actions are the editor's public API: menus and shortcuts can call them,
/// macros can record them, and an AI agent receives their JSON schemas as
/// tools and invokes them by name. Anything the user can do by hand should
/// eventually be reachable as an action.
class EditorAction {
  const EditorAction({
    required this.name,
    required this.description,
    this.params = const [],
    required this.run,
  });

  final String name;
  final String description;
  final List<ActionParam> params;
  final ActionRunner run;

  /// JSON-schema tool definition (compatible with LLM tool-use APIs).
  Json toToolSchema() => {
    'name': name,
    'description': description,
    'input_schema': {
      'type': 'object',
      'properties': {for (final p in params) p.name: p.toSchema()},
      'required': [
        for (final p in params)
          if (p.required) p.name,
      ],
    },
  };
}

/// Typed accessors over raw JSON arguments with helpful errors.
class ActionArgs {
  ActionArgs(this.raw);
  final Json raw;

  bool has(String k) => raw.containsKey(k) && raw[k] != null;

  String string(String k) {
    final v = raw[k];
    if (v is String) return v;
    throw ActionException('Missing string argument "$k"');
  }

  String? optString(String k) => raw[k] is String ? raw[k] as String : null;

  double number(String k) {
    final v = raw[k];
    if (v is num) return v.toDouble();
    throw ActionException('Missing number argument "$k"');
  }

  double? optNumber(String k) =>
      raw[k] is num ? (raw[k] as num).toDouble() : null;

  bool? optBool(String k) => raw[k] is bool ? raw[k] as bool : null;
}
