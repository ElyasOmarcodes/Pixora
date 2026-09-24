import '../../core/utils/json.dart';
import '../../document/effects/effect_registry.dart';
import '../../document/model/blend.dart';
import '../../document/model/fill.dart';
import '../../document/model/layer.dart';
import '../../document/render/document_renderer.dart';
import '../editor_controller.dart';
import 'editor_action.dart';

/// Result of running an action, shaped for returning to an AI agent.
class ActionResult {
  const ActionResult.ok([this.data]) : error = null;
  const ActionResult.error(String this.error) : data = null;
  final Object? data;
  final String? error;
  bool get ok => error == null;
  Json toJson() =>
      ok ? {'ok': true, 'result': data} : {'ok': false, 'error': error};
}

/// Catalogue of every [EditorAction]. Plugins register more at startup.
class ActionRegistry {
  ActionRegistry() {
    for (final a in _builtIns) {
      register(a);
    }
  }

  final Map<String, EditorAction> _actions = {};

  Iterable<EditorAction> get all => _actions.values;
  EditorAction? operator [](String name) => _actions[name];

  void register(EditorAction action) => _actions[action.name] = action;

  List<Json> toolSchemas() => [for (final a in all) a.toToolSchema()];

  Future<ActionResult> execute(
    EditorController editor,
    String name,
    Json args,
  ) async {
    final action = _actions[name];
    if (action == null) return ActionResult.error('Unknown action "$name"');
    try {
      return ActionResult.ok(await action.run(editor, ActionArgs(args)));
    } on ActionException catch (e) {
      return ActionResult.error(e.message);
    } catch (e) {
      return ActionResult.error('Action "$name" failed: $e');
    }
  }
}

Layer _layer(EditorController e, ActionArgs a) {
  final id = a.optString('layer_id') ?? e.selectedId;
  final l = e.document.layerById(id);
  if (l == null) {
    throw ActionException('Layer not found: ${id ?? '(none selected)'}');
  }
  return l;
}

Json _layerSummary(Layer l) => {
  'id': l.id,
  'name': l.props.name,
  'kind': l.kind.name,
  'visible': l.props.visible,
  'locked': l.props.locked,
  'bounds': () {
    final b = layerDocumentBounds(l);
    return [b.left, b.top, b.width, b.height].map((v) => v.round()).toList();
  }(),
  if (l is TextLayer) 'text': l.text,
};

const _layerId = ActionParam(
  'layer_id',
  ActionParamType.string,
  description: 'Target layer id. Defaults to the selected layer.',
);

final List<EditorAction> _builtIns = [
  EditorAction(
    name: 'document.describe',
    description:
        'Returns the canvas size and a summary of every layer (bottom to top).',
    run: (e, a) => {
      'name': e.document.name,
      'width': e.document.width,
      'height': e.document.height,
      'selected': e.selectedId,
      'layers': [for (final l in e.document.layers) _layerSummary(l)],
    },
  ),
  EditorAction(
    name: 'document.get_json',
    description: 'Returns the full document as JSON.',
    run: (e, a) => e.document.toJson(),
  ),
  EditorAction(
    name: 'document.set_background',
    description:
        'Sets the canvas background to a color or a linear gradient; '
        'pass transparent=true to clear it.',
    params: const [
      ActionParam('color', ActionParamType.color),
      ActionParam(
        'color2',
        ActionParamType.color,
        description: 'Second color; makes a gradient.',
      ),
      ActionParam('angle', ActionParamType.number, min: 0, max: 360),
      ActionParam('transparent', ActionParamType.boolean),
    ],
    run: (e, a) {
      if (a.optBool('transparent') ?? false) {
        e.setBackground(null);
        return null;
      }
      final c1 = readColor(a.string('color'));
      final c2 = a.optString('color2');
      e.setBackground(
        c2 == null
            ? PixFill.color(c1)
            : PixFill.linear([
                c1,
                readColor(c2),
              ], angle: a.optNumber('angle') ?? 135),
      );
      return null;
    },
  ),
  EditorAction(
    name: 'document.resize',
    description: 'Changes canvas size in pixels.',
    params: const [
      ActionParam(
        'width',
        ActionParamType.number,
        required: true,
        min: 1,
        max: 16384,
      ),
      ActionParam(
        'height',
        ActionParamType.number,
        required: true,
        min: 1,
        max: 16384,
      ),
      ActionParam('scale_content', ActionParamType.boolean),
    ],
    run: (e, a) {
      e.resizeCanvas(
        a.number('width'),
        a.number('height'),
        scaleContent: a.optBool('scale_content') ?? true,
      );
      return null;
    },
  ),
  EditorAction(
    name: 'layer.add_text',
    description: 'Adds a text layer centred on the canvas and selects it.',
    params: const [
      ActionParam('text', ActionParamType.string, required: true),
      ActionParam('color', ActionParamType.color),
      ActionParam('font_size', ActionParamType.number, min: 1),
    ],
    run: (e, a) {
      final l = e.addText(
        a.string('text'),
        color: a.has('color') ? readColor(a.string('color')) : null,
      );
      final size = a.optNumber('font_size');
      if (size != null) {
        e.updateLayer(l.id, (x) => (x as TextLayer).copyWith(fontSize: size));
      }
      return l.id;
    },
  ),
  EditorAction(
    name: 'layer.add_shape',
    description: 'Adds a shape layer centred on the canvas and selects it.',
    params: [
      ActionParam(
        'shape',
        ActionParamType.string,
        required: true,
        options: [for (final s in ShapeKind.values) s.name],
      ),
      const ActionParam('color', ActionParamType.color),
    ],
    run: (e, a) {
      final kind = readEnum(
        ShapeKind.values,
        a.string('shape'),
        ShapeKind.rectangle,
      );
      return e
          .addShape(
            kind,
            color: a.has('color') ? readColor(a.string('color')) : null,
          )
          .id;
    },
  ),
  EditorAction(
    name: 'layer.select',
    description:
        'Selects a layer (or clears the selection when layer_id is omitted).',
    params: const [ActionParam('layer_id', ActionParamType.string)],
    run: (e, a) {
      e.select(a.optString('layer_id'));
      return e.selectedId;
    },
  ),
  EditorAction(
    name: 'layer.delete',
    description: 'Deletes a layer.',
    params: const [_layerId],
    run: (e, a) {
      e.deleteLayer(_layer(e, a).id);
      return null;
    },
  ),
  EditorAction(
    name: 'layer.duplicate',
    description: 'Duplicates a layer and returns the new layer id.',
    params: const [_layerId],
    run: (e, a) => e.duplicateLayer(_layer(e, a).id)?.id,
  ),
  EditorAction(
    name: 'layer.arrange',
    description: 'Changes the stacking order of a layer.',
    params: [
      _layerId,
      ActionParam(
        'to',
        ActionParamType.string,
        required: true,
        options: [for (final v in LayerArrange.values) v.name],
      ),
    ],
    run: (e, a) {
      e.arrange(
        _layer(e, a).id,
        readEnum(LayerArrange.values, a.string('to'), LayerArrange.forward),
      );
      return null;
    },
  ),
  EditorAction(
    name: 'layer.align',
    description: 'Aligns a layer to an edge or the centre of the canvas.',
    params: [
      _layerId,
      ActionParam(
        'to',
        ActionParamType.string,
        required: true,
        options: [for (final v in LayerAlign.values) v.name],
      ),
    ],
    run: (e, a) {
      e.align(
        _layer(e, a).id,
        readEnum(LayerAlign.values, a.string('to'), LayerAlign.centerH),
      );
      return null;
    },
  ),
  EditorAction(
    name: 'layer.set_props',
    description:
        'Sets common layer properties. Position is the layer centre in '
        'canvas pixels, rotation in degrees, scale is uniform.',
    params: [
      _layerId,
      const ActionParam('name', ActionParamType.string),
      const ActionParam('x', ActionParamType.number),
      const ActionParam('y', ActionParamType.number),
      const ActionParam('rotation', ActionParamType.number),
      const ActionParam('scale', ActionParamType.number, min: 0.01),
      const ActionParam('opacity', ActionParamType.number, min: 0, max: 1),
      const ActionParam('visible', ActionParamType.boolean),
      const ActionParam('locked', ActionParamType.boolean),
      ActionParam(
        'blend_mode',
        ActionParamType.string,
        options: [for (final b in PixBlendMode.values) b.name],
      ),
    ],
    run: (e, a) {
      final l = _layer(e, a);
      e.updateProps(l.id, (p) {
        var t = p.transform;
        if (a.has('x')) t = t.copyWith(x: a.number('x'));
        if (a.has('y')) t = t.copyWith(y: a.number('y'));
        if (a.has('rotation')) {
          t = t.copyWith(
            rotation: a.number('rotation') * 3.141592653589793 / 180,
          );
        }
        if (a.has('scale')) {
          final s = a.number('scale');
          t = t.copyWith(
            scaleX: t.scaleX.isNegative ? -s : s,
            scaleY: t.scaleY.isNegative ? -s : s,
          );
        }
        return p.copyWith(
          name: a.optString('name'),
          opacity: a.optNumber('opacity')?.clamp(0.0, 1.0),
          visible: a.optBool('visible'),
          locked: a.optBool('locked'),
          blendMode: a.has('blend_mode')
              ? readEnum(
                  PixBlendMode.values,
                  a.string('blend_mode'),
                  p.blendMode,
                )
              : null,
          transform: t,
        );
      }, label: 'set_props');
      return null;
    },
  ),
  EditorAction(
    name: 'text.set',
    description: 'Edits a text layer.',
    params: [
      _layerId,
      const ActionParam('text', ActionParamType.string),
      const ActionParam('color', ActionParamType.color),
      const ActionParam('font_size', ActionParamType.number, min: 1),
      const ActionParam('font_family', ActionParamType.string),
      const ActionParam(
        'font_weight',
        ActionParamType.integer,
        min: 100,
        max: 900,
      ),
      const ActionParam('stroke_width', ActionParamType.number, min: 0),
      const ActionParam('stroke_color', ActionParamType.color),
      ActionParam(
        'align',
        ActionParamType.string,
        options: [for (final v in PixTextAlign.values) v.name],
      ),
    ],
    run: (e, a) {
      final l = _layer(e, a);
      if (l is! TextLayer) {
        throw ActionException('Layer ${l.id} is not a text layer');
      }
      e.updateLayer(
        l.id,
        (_) => l.copyWith(
          text: a.optString('text'),
          fill: a.has('color')
              ? PixFill.color(readColor(a.string('color')))
              : null,
          fontSize: a.optNumber('font_size'),
          fontFamily: a.optString('font_family'),
          fontWeight: a.optNumber('font_weight')?.round(),
          strokeWidth: a.optNumber('stroke_width'),
          strokeColor: a.has('stroke_color')
              ? readColor(a.string('stroke_color'))
              : null,
          align: a.has('align')
              ? readEnum(PixTextAlign.values, a.string('align'), l.align)
              : null,
        ),
        label: 'text',
      );
      return null;
    },
  ),
  EditorAction(
    name: 'effect.set',
    description:
        'Adds or updates an effect on a layer. '
        'Types: ${EffectRegistry.instance.all.map((d) => d.type).join(', ')}.',
    params: [
      _layerId,
      ActionParam(
        'type',
        ActionParamType.string,
        required: true,
        options: [for (final d in EffectRegistry.instance.all) d.type],
      ),
      const ActionParam(
        'params',
        ActionParamType.object,
        description:
            'Map of parameter name to value (numbers, or #RRGGBB colors).',
      ),
    ],
    run: (e, a) {
      final l = _layer(e, a);
      final type = a.string('type');
      final def = EffectRegistry.instance[type];
      if (def == null) throw ActionException('Unknown effect "$type"');
      final params = readMap(a.raw['params']);
      if (params.isEmpty) {
        params[def.params.first.key] = def.params.first.defaultValue;
      }
      for (final entry in params.entries) {
        final spec = def.param(entry.key);
        if (spec == null) {
          throw ActionException('Effect "$type" has no param "${entry.key}"');
        }
        final Object v = spec.kind == EffectParamKind.color
            ? readColor(entry.value).toARGB32()
            : readDouble(entry.value).clamp(spec.min, spec.max);
        e.setEffectParam(l.id, type, entry.key, v);
      }
      return null;
    },
  ),
  EditorAction(
    name: 'effect.remove',
    description: 'Removes an effect type from a layer.',
    params: [
      _layerId,
      const ActionParam('type', ActionParamType.string, required: true),
    ],
    run: (e, a) {
      e.removeEffectType(_layer(e, a).id, a.string('type'));
      return null;
    },
  ),
  EditorAction(
    name: 'history.undo',
    description: 'Undoes the last edit.',
    run: (e, a) {
      e.undo();
      return null;
    },
  ),
  EditorAction(
    name: 'history.redo',
    description: 'Redoes the last undone edit.',
    run: (e, a) {
      e.redo();
      return null;
    },
  ),
];
