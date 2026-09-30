import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../../../ui/widgets/pix_slider.dart';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../../app/app_scope.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/imaging/image_formats.dart';
import '../../../core/imaging/svg_export.dart';
import '../../../core/platform/platform_services.dart';
import '../../../document/model/layer.dart';
import '../../../document/model/document.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/pressable.dart';

/// Export formats: extension → MIME type.
const exportFormats = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'webp': 'image/webp',
  'pdf': 'application/pdf',
  'svg': 'image/svg+xml',
  'tiff': 'image/tiff',
  'bmp': 'image/bmp',
};

/// Encodes the document as [format] (see [exportFormats]) at [width] ×
/// [height] pixels.
Future<Uint8List> encodeDocument(
  EditorController editor,
  PixDocument doc, {
  required String format,
  required int width,
  required int height,
  int quality = 92,
  bool lossless = true,
  bool cmyk = false,
  PlatformServices? platform,
}) async {
  final renderer = editor.renderer;
  if (format == 'png') {
    final image = await renderer.renderImage(doc, width: width, height: height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
  if (format == 'svg') {
    final svg = await SvgExport.build(doc, renderer, scale: width / doc.width);
    return Uint8List.fromList(utf8.encode(svg));
  }
  final opaque = format == 'jpg' || format == 'pdf';
  final image = await renderer.renderImage(
    doc,
    width: width,
    height: height,
    matte: opaque ? const Color(0xFFFFFFFF) : null,
  );
  // The system's encoder where there is one (Android, browsers): encoding
  // big pictures in Dart took long and, at high sizes, ran out of memory.
  if (format == 'webp' || format == 'jpg') {
    final native = await platform?.encodeNative(
      image,
      format,
      quality: quality,
      lossless: format == 'webp' && lossless,
    );
    if (native != null) {
      image.dispose();
      return native;
    }
  }
  final data = await image.toByteData(
    format: opaque
        ? ui.ImageByteFormat.rawRgba
        : ui.ImageByteFormat.rawStraightRgba,
  );
  final w = image.width, h = image.height;
  image.dispose();
  final rgba = data!.buffer.asUint8List();
  switch (format) {
    case 'jpg':
      // JPEG encoding takes seconds for big images: off the UI thread.
      return compute(_encodeJpg, (rgba, w, h, quality));
    case 'pdf':
      // Same physical size whatever the pixel size chosen.
      return ImageFormats.encodePdf(
        rgba,
        w,
        h,
        dpi: doc.dpi * w / doc.width,
        cmyk: cmyk,
        title: doc.name,
      );
    default:
      return ImageFormats.encodeRaster(
        format,
        rgba,
        w,
        h,
        quality: quality,
        lossless: lossless,
        dpi: doc.dpi * w / doc.width,
      );
  }
}

Uint8List _encodeJpg((Uint8List, int, int, int) job) {
  final (rgba, w, h, quality) = job;
  final raster = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgba.buffer,
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

/// Size presets, as the longest side in pixels (original = canvas size).
enum _SizePreset {
  original(0),
  custom(0),
  low(720),
  medium(1080),
  high(1440),
  veryHigh(2160),
  max(4096);

  const _SizePreset(this.longSide);
  final int longSide;
}

/// "Save image": format, size and quality, then save to the gallery /
/// Pixora folder or share.
class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.editor});
  final EditorController editor;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late final _services = AppScope.of(context);
  late String _format =
      exportFormats.containsKey(_services.settings.exportFormat)
      ? _services.settings.exportFormat
      : 'png';
  late int _quality = _services.settings.exportQuality;
  bool _lossless = true;
  bool _cmyk = false;
  late final _customName = TextEditingController(
    text: _isCustomName ? _doc.exportName! : _doc.name,
  );

  bool get _isCustomName {
    final n = _doc.exportName;
    return n != null && !n.startsWith(PixDocument.exportNameLayerPrefix);
  }

  _SizePreset _preset = _SizePreset.original;
  bool _lockRatio = true;
  late final _w = TextEditingController(text: '${_doc.width.round()}');
  late final _h = TextEditingController(text: '${_doc.height.round()}');
  bool _busy = false;

  PixDocument get _doc => widget.editor.document;

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    _customName.dispose();
    super.dispose();
  }

  (int, int) get _size {
    final d = _doc;
    switch (_preset) {
      case _SizePreset.original:
        return (d.width.round(), d.height.round());
      case _SizePreset.custom:
        final w = int.tryParse(_w.text) ?? d.width.round();
        final h = int.tryParse(_h.text) ?? d.height.round();
        return (w.clamp(1, 16384), h.clamp(1, 16384));
      default:
        final k = _preset.longSide / math.max(d.width, d.height);
        return (
          math.max(1, (d.width * k).round()),
          math.max(1, (d.height * k).round()),
        );
    }
  }

  void _onCustom(bool widthChanged) {
    if (!_lockRatio) return setState(() {});
    final ratio = _doc.width / _doc.height;
    if (widthChanged) {
      final w = int.tryParse(_w.text);
      if (w != null) _h.text = '${math.max(1, (w / ratio).round())}';
    } else {
      final h = int.tryParse(_h.text);
      if (h != null) _w.text = '${math.max(1, (h * ratio).round())}';
    }
    setState(() {});
  }

  String _presetLabel(AppLocalizations l, _SizePreset p) => switch (p) {
    _SizePreset.original => l.sizeOriginal,
    _SizePreset.custom => l.sizeCustom,
    _SizePreset.low => l.sizeLow,
    _SizePreset.medium => l.sizeMedium,
    _SizePreset.high => l.sizeHigh,
    _SizePreset.veryHigh => l.sizeVeryHigh,
    _SizePreset.max => l.sizeMax,
  };

  Future<void> _run(String mode) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    // Remember the choices for next time.
    _services.settings
      ..exportFormat = _format
      ..exportQuality = _quality;
    try {
      // Let the progress indicator appear before the work starts.
      await WidgetsBinding.instance.endOfFrame;
      final (w, h) = _size;
      final bytes = await encodeDocument(
        widget.editor,
        _doc,
        format: _format,
        width: w,
        height: h,
        quality: _quality,
        lossless: _lossless,
        cmyk: _cmyk,
        platform: _services.platform,
      );
      final name = '${_doc.exportFileName}.$_format';
      final mime = exportFormats[_format]!;
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
    final scheme = theme.colorScheme;
    final platform = _services.platform;
    final (w, h) = _size;
    final saveLabel =
        platform.storage.exportDestination == ExportDestination.gallery
        ? l.galleryAlbum
        : l.saveToDevice;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.image_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  l.saveImage,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ---- quick share
            _SectionTitle(l.quickShare),
            Pressable(
              onTap: _busy ? null : () => _run('share'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.tertiary],
                  ),
                  borderRadius: BorderRadius.circular(PixTokens.radiusL),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.send_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l.shareHint,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ---- format
            _SectionTitle(l.imageFormat),
            LayoutBuilder(
              builder: (context, box) {
                final cw = (box.maxWidth - 10) / 2;
                final cards = [
                  ('png', Icons.layers_clear_rounded, l.pngTransparent),
                  ('jpg', Icons.photo_rounded, l.jpgBackground),
                  ('webp', Icons.public_rounded, l.fmtWebp),
                  ('pdf', Icons.picture_as_pdf_rounded, l.fmtPdf),
                  ('svg', Icons.polyline_rounded, l.fmtSvg),
                  ('tiff', Icons.print_rounded, l.fmtTiff),
                  ('bmp', Icons.grid_on_rounded, l.fmtBmp),
                ];
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (f, icon, sub) in cards)
                      SizedBox(
                        width: cw,
                        child: _ChoiceCard(
                          selected: _format == f,
                          icon: icon,
                          title: f.toUpperCase(),
                          subtitle: sub,
                          onTap: () => setState(() => _format = f),
                        ),
                      ),
                  ],
                );
              },
            ),
            // ---- format options
            AnimatedSize(
              duration: PixTokens.medium,
              curve: PixTokens.emphasized,
              child: switch (_format) {
                'webp' => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.fmtLossless),
                    value: _lossless,
                    onChanged: (v) => setState(() => _lossless = v),
                  ),
                ),
                'pdf' => Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionTitle(l.pdfColor),
                      SegmentedButton<bool>(
                        segments: [
                          const ButtonSegment(
                            value: false,
                            label: Text('RGB'),
                            icon: Icon(Icons.monitor_rounded),
                          ),
                          const ButtonSegment(
                            value: true,
                            label: Text('CMYK'),
                            icon: Icon(Icons.print_rounded),
                          ),
                        ],
                        selected: {_cmyk},
                        onSelectionChanged: (v) =>
                            setState(() => _cmyk = v.first),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_cmyk ? l.pdfCmykHint : l.pdfRgbHint}\n${l.pdfPageSize((_doc.width / _doc.dpi * 2.54).toStringAsFixed(1), (_doc.height / _doc.dpi * 2.54).toStringAsFixed(1), _doc.dpi.round().toString())}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                'svg' => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    l.svgHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                _ => const SizedBox(width: double.infinity),
              },
            ),
            const SizedBox(height: 18),

            // ---- file name
            _SectionTitle(l.fileName),
            _FileNameSection(
              editor: widget.editor,
              custom: _customName,
              extension: _format,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 18),

            // ---- size
            Row(
              children: [
                Expanded(child: _SectionTitle(l.dimensions)),
                Text(
                  '$w × $h px',
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _SizePreset.values)
                  ChoiceChip(
                    label: Text(_presetLabel(l, p)),
                    selected: _preset == p,
                    onSelected: (_) => setState(() {
                      if (p == _SizePreset.custom) {
                        final (cw, ch) = _size;
                        _w.text = '$cw';
                        _h.text = '$ch';
                      }
                      _preset = p;
                    }),
                  ),
              ],
            ),
            AnimatedSize(
              duration: PixTokens.medium,
              curve: PixTokens.emphasized,
              child: _preset != _SizePreset.custom
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _w,
                              keyboardType: TextInputType.number,
                              textDirection: TextDirection.ltr,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(labelText: l.width),
                              onChanged: (_) => _onCustom(true),
                            ),
                          ),
                          IconButton(
                            tooltip: l.keepRatio,
                            isSelected: _lockRatio,
                            onPressed: () =>
                                setState(() => _lockRatio = !_lockRatio),
                            icon: const Icon(Icons.link_off_rounded),
                            selectedIcon: const Icon(Icons.link_rounded),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _h,
                              keyboardType: TextInputType.number,
                              textDirection: TextDirection.ltr,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(labelText: l.height),
                              onChanged: (_) => _onCustom(false),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            // ---- JPEG quality
            AnimatedSize(
              duration: PixTokens.medium,
              curve: PixTokens.emphasized,
              child: !(_format == 'jpg' || (_format == 'webp' && !_lossless))
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: PixSlider(
                        label: l.quality,
                        value: _quality.toDouble(),
                        min: 50,
                        max: 100,
                        defaultValue: 92,
                        format: (v) => '${v.round()}%',
                        onChanged: (v) => setState(() => _quality = v.round()),
                      ),
                    ),
            ),
            const SizedBox(height: 20),

            if (_busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      onPressed: () => _run('save'),
                      icon: const Icon(Icons.download_rounded),
                      label: Text(
                        saveLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (!platform.info.isWeb) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: () => _run('saveAs'),
                        icon: const Icon(Icons.save_as_rounded),
                        label: Text(
                          l.saveAs,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Project name · a text layer's text (kept in sync) · custom — stored in
/// the document, so the choice stays with the project.
class _FileNameSection extends StatelessWidget {
  const _FileNameSection({
    required this.editor,
    required this.custom,
    required this.extension,
    required this.onChanged,
  });
  final EditorController editor;
  final TextEditingController custom;
  final String extension;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final doc = editor.document;
    final n = doc.exportName;
    final mode = n == null
        ? 0
        : n.startsWith(PixDocument.exportNameLayerPrefix)
        ? 1
        : 2;
    final texts = [
      for (final x in doc.allLayers)
        if (x is TextLayer && x.text.trim().isNotEmpty) x,
    ].reversed.toList();
    final boundId = mode == 1
        ? n!.substring(PixDocument.exportNameLayerPrefix.length)
        : null;
    void set(String? v) {
      editor.setExportName(v);
      onChanged();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: 0,
              icon: const Icon(Icons.folder_rounded, size: 18),
              label: Text(l.fileNameProject),
            ),
            ButtonSegment(
              value: 1,
              icon: const Icon(Icons.text_fields_rounded, size: 18),
              label: Text(l.fileNameLayer),
            ),
            ButtonSegment(
              value: 2,
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: Text(l.fileNameCustom),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (v) => switch (v.first) {
            0 => set(null),
            1 when texts.isNotEmpty => set(
              '${PixDocument.exportNameLayerPrefix}${texts.first.id}',
            ),
            1 => onChanged(),
            _ => set(custom.text.trim().isEmpty ? doc.name : custom.text),
          },
        ),
        const SizedBox(height: 10),
        if (mode == 1)
          texts.isEmpty
              ? Text(l.noTextLayers)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: texts.any((t) => t.id == boundId)
                          ? boundId
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: [
                        for (final t in texts)
                          DropdownMenuItem(
                            value: t.id,
                            child: Text(
                              t.text.replaceAll('\n', ' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) => id == null
                          ? null
                          : set('${PixDocument.exportNameLayerPrefix}$id'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.fileNameLayerHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        if (mode == 2)
          TextField(
            controller: custom,
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (v) => set(v.trim().isEmpty ? doc.name : v),
          ),
        const SizedBox(height: 8),
        // What the file will be called.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.description_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${editor.document.exportFileName}.$extension',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      child: AnimatedContainer(
        duration: PixTokens.fast,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.1)
              : scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(PixTokens.radiusM),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The save sheet: project (save changes / save as new / export file) and
/// image (opens the image export).
Future<void> showSaveSheet(
  BuildContext context, {
  required bool saved,
  required VoidCallback onSaveChanges,
  required VoidCallback onSaveAsCopy,
  required VoidCallback onExportProject,
  required VoidCallback onSaveImage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) {
      final l = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      void pick(VoidCallback f) {
        Navigator.pop(context);
        f();
      }

      Widget tile(
        IconData icon,
        String title,
        String? subtitle,
        VoidCallback? onTap,
      ) => ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle),
        enabled: onTap != null,
        onTap: onTap == null ? null : () => pick(onTap),
      );

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: Text(
                  l.save,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Card(
                color: scheme.primary.withValues(alpha: 0.06),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.inventory_2_rounded,
                            color: scheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l.project,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    tile(
                      saved ? Icons.cloud_done_rounded : Icons.save_rounded,
                      l.saveChanges,
                      saved ? l.allSaved : l.unsavedChanges,
                      saved ? null : onSaveChanges,
                    ),
                    tile(
                      Icons.library_add_rounded,
                      l.saveAsCopy,
                      null,
                      onSaveAsCopy,
                    ),
                    tile(
                      Icons.ios_share_rounded,
                      l.exportProject,
                      '.pixora',
                      onExportProject,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Card(
                color: scheme.tertiary.withValues(alpha: 0.07),
                child: tile(
                  Icons.image_rounded,
                  l.saveImage,
                  'PNG · JPG · WEBP · PDF · SVG · TIFF · BMP',
                  onSaveImage,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
