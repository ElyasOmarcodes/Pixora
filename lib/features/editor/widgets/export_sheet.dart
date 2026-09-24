import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../app/app_scope.dart';
import '../../../core/platform/platform_services.dart';
import '../../../document/model/document.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';

/// Encodes the document as PNG or JPEG at the given scale.
Future<Uint8List> encodeDocument(
  EditorController editor,
  PixDocument doc, {
  required String format,
  required double scale,
  int quality = 92,
}) async {
  final renderer = editor.renderer;
  if (format == 'png') {
    final image = await renderer.renderImage(doc, scale: scale);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
  final image = await renderer.renderImage(
    doc,
    scale: scale,
    matte: const Color(0xFFFFFFFF),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final w = image.width, h = image.height;
  image.dispose();
  final raster = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: data!.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodeJpg(raster, quality: quality));
}

Future<void> showExportSheet(BuildContext context, EditorController editor) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExportSheet(editor: editor),
    );

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.editor});
  final EditorController editor;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late final _services = AppScope.of(context);
  late String _format = _services.settings.exportFormat;
  late int _quality = _services.settings.exportQuality;
  double _scale = 1;
  bool _busy = false;

  Future<void> _run({required bool share}) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final doc = widget.editor.document;
      final bytes = await encodeDocument(
        widget.editor,
        doc,
        format: _format,
        scale: _scale,
        quality: _quality,
      );
      final safe = doc.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final name = '${safe.isEmpty ? 'pixora' : safe}.$_format';
      final mime = _format == 'png' ? 'image/png' : 'image/jpeg';
      if (share) {
        await _services.platform.share(bytes, name, mime);
        nav.pop();
      } else {
        final outcome = await _services.platform.saveFile(bytes, name, mime);
        if (outcome == SaveOutcome.cancelled) return;
        nav.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              outcome == SaveOutcome.saved ? l.exportDone : l.exportFailed,
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${l.exportFailed}: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final doc = widget.editor.document;
    final w = (doc.width * _scale).round(), h = (doc.height * _scale).round();
    final shareFirst = _services.platform.prefersShare;

    final saveBtn = _busy
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          )
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.export,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Text(l.format, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 'png',
                label: Text('PNG'),
                icon: Icon(Icons.image_rounded),
              ),
              ButtonSegment(
                value: 'jpg',
                label: Text('JPG'),
                icon: Icon(Icons.photo_rounded),
              ),
            ],
            selected: {_format},
            onSelectionChanged: (s) => setState(() => _format = s.first),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(l.size, style: theme.textTheme.labelLarge),
              const Spacer(),
              Text(
                '$w × $h px',
                textDirection: TextDirection.ltr,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<double>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0.5, label: Text('0.5×')),
              ButtonSegment(value: 1, label: Text('1×')),
              ButtonSegment(value: 2, label: Text('2×')),
            ],
            selected: {_scale},
            onSelectionChanged: (s) => setState(() => _scale = s.first),
          ),
          if (_format == 'jpg') ...[
            const SizedBox(height: 16),
            Text('${l.quality}  $_quality%', style: theme.textTheme.labelLarge),
            Slider(
              value: _quality.toDouble(),
              min: 50,
              max: 100,
              divisions: 50,
              onChanged: (v) => setState(() => _quality = v.round()),
            ),
          ],
          const SizedBox(height: 20),
          if (saveBtn != null)
            saveBtn
          else
            Row(
              children: [
                Expanded(
                  child: _button(
                    primary: !shareFirst,
                    onPressed: () => _run(share: false),
                    icon: Icons.download_rounded,
                    label: l.saveToDevice,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _button(
                    primary: shareFirst,
                    onPressed: () => _run(share: true),
                    icon: Icons.ios_share_rounded,
                    label: l.share,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _button({
    required bool primary,
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) => primary
      ? FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        )
      : OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        );
}
