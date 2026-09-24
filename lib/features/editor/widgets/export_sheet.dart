import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// [mode]: 'save' = default place (gallery / Pixora folder), 'share',
  /// or 'saveAs' = choose a location.
  Future<void> _run(String mode) async {
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
      final platform = _services.platform;
      switch (mode) {
        case 'share':
          await platform.share(bytes, name, mime);
          nav.pop();
        case 'saveAs':
          final outcome = await platform.saveFileAs(bytes, name, mime);
          if (outcome == SaveOutcome.cancelled) return;
          nav.pop();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                outcome == SaveOutcome.saved ? l.exportDone : l.exportFailed,
              ),
            ),
          );
        default:
          final r = await platform.exportImage(bytes, name, mime);
          nav.pop();
          final msg = r.outcome != SaveOutcome.saved
              ? l.exportFailed
              : switch (r.destination) {
                  ExportDestination.gallery => l.savedToGallery,
                  ExportDestination.folder => l.savedToFolder(r.location ?? ''),
                  ExportDestination.download => l.exportDone,
                };
          messenger.showSnackBar(
            SnackBar(
              content: Text(msg),
              action: r.location == null
                  ? null
                  : SnackBarAction(
                      label: l.copyPath,
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: r.location!)),
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
    final platform = _services.platform;
    final saveLabel = switch (platform.storage.exportDestination) {
      ExportDestination.gallery => l.galleryAlbum,
      _ => l.saveToDevice,
    };

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
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: () => _run('save'),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(saveLabel),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _run('share'),
                        icon: const Icon(Icons.ios_share_rounded),
                        label: Text(l.share),
                      ),
                    ),
                    if (!platform.info.isWeb) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _run('saveAs'),
                          icon: const Icon(Icons.save_as_rounded),
                          label: Text(l.saveAs),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}
