import '../core/utils/json.dart';
import '../editor/actions/action_registry.dart';
import '../editor/editor_controller.dart';

/// One tool call requested by a language model.
class AgentToolCall {
  const AgentToolCall(this.id, this.name, this.input);
  final String id;
  final String name;
  final Json input;
}

/// A backend that turns a user instruction into tool calls (an LLM client).
///
/// Not implemented yet — this is the seam where an AI provider plugs in.
/// It receives the editor's tool schemas and a callback to execute calls,
/// and loops until the model is done.
abstract interface class AgentBackend {
  Future<String> run({
    required String instruction,
    required List<Json> tools,
    required Future<Json> Function(AgentToolCall call) execute,
  });
}

/// Connects an [AgentBackend] to an open editor.
///
/// Everything the agent does goes through [ActionRegistry], i.e. through the
/// same code paths as the UI, so agent edits are undoable, respect locks and
/// show up live on the canvas.
class AgentBridge {
  AgentBridge({required this.editor, required this.actions});

  final EditorController editor;
  final ActionRegistry actions;

  List<Json> get toolSchemas => actions.toolSchemas();

  Future<Json> execute(AgentToolCall call) async =>
      (await actions.execute(editor, call.name, call.input)).toJson();

  Future<String> ask(AgentBackend backend, String instruction) => backend.run(
    instruction: instruction,
    tools: toolSchemas,
    execute: execute,
  );
}
