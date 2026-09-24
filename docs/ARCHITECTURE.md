# Pixora architecture

The goal is a foundation that can grow to Photoshop-level power (and an AI
agent that can drive every feature) without rewrites. The rules below exist
for that reason.

```
lib/
  app/            App shell: theme, localization wiring, service scope
  core/           Platform detection & services, settings, utils
  document/       The design itself — pure data + rendering
    model/        PixDocument, Layer (sealed), LayerProps, LayerTransform, PixFill, LayerEffect
    effects/      EffectRegistry: what each effect type does
    render/       DocumentRenderer (canvas + export), text layout, shapes, color matrices
    assets/       AssetStore: encoded images + decoded GPU images
  editor/         Editing engine (no widgets)
    editor_controller.dart   single source of truth, undo/redo, selection
    history.dart             snapshot history
    actions/                 EditorAction + ActionRegistry (automation / AI API)
    tools/                   EditorTool, CanvasViewport, TransformTool
  ai/             AgentBridge: plugs an LLM into the ActionRegistry
  projects/       ProjectStore (files / memory), ProjectRepository, presets
  features/       Screens: splash, home (projects), editor, settings
  ui/widgets/     Reusable widgets (color picker, sliders, pressable, logo…)
  l10n/           ARB translations (ps, fa, ar, ur, en, es, fr, tr)
```

## 1. The document is immutable data

`PixDocument` holds canvas size, background and an ordered list of `Layer`s.
`Layer` is a **sealed** class (`RasterLayer`, `TextLayer`, `ShapeLayer`);
adding a kind (group, adjustment layer, vector path, smart object…) is a new
subclass, and the compiler then flags every `switch` that must handle it.

Common properties (name, visibility, lock, opacity, blend mode, transform,
effects) live in `LayerProps`, so tools that don't care about the layer kind
never need to.

All lookups/replacements go through `PixDocument` methods (`layerById`,
`replaceLayer`, `insertLayer`, `moveLayerTo` …). When groups arrive, only
those methods learn tree traversal.

Serialization is tolerant: missing fields get defaults, unknown layer kinds
and effect types are skipped instead of crashing, and `formatVersion` allows
forward migrations.

## 2. Every edit is a function; history is snapshots

`EditorController.apply(label, doc => newDoc)` records the previous snapshot.
Continuous gestures (drags, sliders, color dragging) call `preview(...)`
repeatedly and `commit(label)` once, producing a single undo step. Because
layers and assets are shared between snapshots, this is cheap, and undo can
never drift from the real state (there are no inverse operations to write).

## 3. Rendering: one renderer for everything

`DocumentRenderer.paint(canvas, doc)` draws in document coordinates. The
canvas widget just applies the viewport transform; thumbnails and export call
the same code (`renderImage`, `renderPng`). Per layer it composes:
transform → group layer for opacity/blend → shadows/glows → color matrix +
blur → content.

**Performance roadmap:** cache each layer as a `Picture`/`Image` keyed by its
value (layers are immutable, so equality is a perfect cache key); render
huge photos from mip-mapped tiles; move pixel kernels to fragment shaders.

## 4. Effects are data + a registry

`LayerEffect` is `{type, params}`. `EffectRegistry` maps a type to an
`EffectDefinition` which may contribute a color matrix, a blur, or shadows,
and declares its parameters (used by the UI *and* the AI tool schema).
New effects — curves, levels, fragment-shader filters, AI filters — register
a definition; the model and file format don't change.

## 5. Actions: the public API (and the AI seam)

`EditorAction`s are named, self-describing commands with JSON-schema
parameters (`layer.add_text`, `layer.set_props`, `effect.set`,
`document.resize`, `history.undo`, …). `ActionRegistry.toolSchemas()` returns
definitions in the shape LLM tool-use APIs expect; `AgentBridge` executes the
model's tool calls through the same controller as the UI, so agent edits are
undoable and appear live on the canvas.

Rule: *anything a user can do by hand should eventually be an action.*

## 6. Tools

`EditorTool` receives taps, scale gestures and hover, and paints an overlay.
If a tool doesn't claim a gesture, the canvas pans/zooms — every tool gets
navigation for free. `TransformTool` implements selection, move, pinch,
corner scaling, the rotate handle, smart guides and 45° snapping.
Next: brush/eraser (raster layers get editable pixel buffers), selection
(masks), crop, pen/vector.

## 7. Platform differences

`PlatformInfo` answers where we run (without `dart:io`, so it works on web).
`PlatformServices` hides real differences behind one interface; the
implementation is picked by conditional import (`_io.dart` vs `_web.dart`)
and then by `PlatformInfo` at runtime (mobile share sheet vs desktop save
dialog, documents vs app-support directory…).

## 8. UX principles

- Contextual dock: only tools relevant to the current selection.
- One-step actions (Text → type → Done).
- Every slider is live and double-tap resets it.
- Adaptive layout: phone (bottom dock, floating layer drawer) vs. wide
  (tool rail + side panel with layers and properties).
- Full RTL; text layers detect direction from their content.

## Roadmap

1. Layer groups, masks, clipping.
2. Brush / eraser / selection / crop tools.
3. Curves, levels, HSL per channel, vignette, sharpen (shaders).
4. Stickers, more fonts (downloadable), text on path, text background.
5. Layer render cache + tiled rendering for very large images.
6. AI agent (LLM backend implementing `AgentBackend`), background removal.
