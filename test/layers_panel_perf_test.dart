import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/app/theme/app_theme.dart';
import 'package:pixora/document/effects/effect_registry.dart';
import 'package:pixora/document/model/document.dart';
import 'package:pixora/document/model/fill.dart';
import 'package:pixora/document/model/layer.dart';
import 'package:pixora/document/model/layer_transform.dart';
import 'package:pixora/editor/editor_controller.dart';
import 'package:pixora/features/editor/widgets/layer_actions.dart';
import 'package:pixora/features/editor/widgets/layer_thumbs.dart';
import 'package:pixora/features/editor/widgets/layers_panel.dart';
import 'package:pixora/l10n/app_localizations.dart';

void main() {
  testWidgets('layers panel stays light with hundreds of layers', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 915));
    final editor = EditorController(
      document: PixDocument(
        name: 't',
        width: 1000,
        height: 1000,
        layers: [
          for (var i = 0; i < 300; i++)
            ShapeLayer(
              LayerProps(
                name: 'Layer $i',
                transform: const LayerTransform(x: 500, y: 500),
                effects: [
                  EffectRegistry.instance['shadow']!.create(const {}),
                  EffectRegistry.instance['bevel']!.create(const {}),
                ],
              ),
              shape: ShapeKind.values[i % 6],
              width: 400,
              height: 400,
              fill: PixFill.color(Color(0xFF000000 | (i * 9973) & 0xFFFFFF)),
            ),
        ],
      ),
    );
    final commands = LayerCommands(
      openPanel: (_) {},
      editText: (_) {},
      pickFont: (_) {},
      replaceImage: (_) {},
      cropImage: (_) {},
      deleteLayers: (_) {},
      changeIcon: (_) {},
      runAsync: (job) => job(),
      openEffects: (_) {},
      editEffect: (_, _, _) {},
    );
    Future<int> time(Future<void> Function() f) async {
      final sw = Stopwatch()..start();
      await f();
      return sw.elapsedMilliseconds;
    }

    Widget app(bool open) => MaterialApp(
      theme: AppTheme.light(Colors.indigo),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: open
            ? LayersPanel(editor: editor, commands: commands)
            : const SizedBox(),
      ),
    );

    Future<void> settle() async {
      // Thumbnails render a few per frame.
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
    }

    await t.pumpWidget(app(false));
    final first = await time(() => t.pumpWidget(app(true)));
    await settle();
    await t.pumpWidget(app(false));
    await t.pumpWidget(app(true));
    await settle();
    final rendered = LayerThumbs.instance.renders;
    expect(rendered, greaterThan(3));
    expect(rendered, lessThan(40)); // only the visible rows
    await t.pumpWidget(app(false));
    final reopen = await time(() => t.pumpWidget(app(true)));
    await settle();
    // Reopening reuses the bitmaps.
    expect(LayerThumbs.instance.renders, rendered);
    final select = await time(() async {
      editor.select(editor.document.layers.last.id);
      await t.pump();
    });
    final scroll = await time(() async {
      await t.drag(find.byType(Scrollable).last, const Offset(0, -600));
      await t.pump();
    });
    // ignore: avoid_print
    print(
      'open $first ms, reopen $reopen ms, select $select ms, '
      'scroll $scroll ms',
    );
    expect(reopen, lessThan(1500));
    expect(select, lessThan(1500));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
