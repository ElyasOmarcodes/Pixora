import 'package:flutter/material.dart';

import '../../ui/widgets/pix_slider.dart';

import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../app/theme/app_theme.dart';
import '../../core/platform/platform_services.dart';
import '../../core/settings/app_settings.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/widgets/pixora_logo.dart';
import '../../ui/widgets/pressable.dart';

const String kAppVersion = '0.18.0';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final settings = services.settings;
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Section(
                  title: l.language,
                  children: [_LanguagePicker(settings: settings)],
                ),
                _Section(
                  title: l.appearance,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        l.theme,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: const Icon(Icons.brightness_auto_rounded),
                            label: Text(l.themeSystem),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: const Icon(Icons.light_mode_rounded),
                            label: Text(l.themeLight),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: const Icon(Icons.dark_mode_rounded),
                            label: Text(l.themeDark),
                          ),
                        ],
                        selected: {settings.themeMode},
                        onSelectionChanged: (s) => settings.themeMode = s.first,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        l.accentColor,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (var i = 0; i < kAccentColors.length; i++)
                            Pressable(
                              scale: 0.88,
                              onTap: () => settings.accentIndex = i,
                              child: AnimatedContainer(
                                duration: PixTokens.fast,
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: kAccentColors[i],
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: settings.accentIndex == i
                                        ? Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                                child: settings.accentIndex == i
                                    ? const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                _Section(
                  title: l.editorSection,
                  children: [
                    SwitchListTile.adaptive(
                      value: settings.autosave,
                      title: Text(l.autosave),
                      subtitle: Text(l.autosaveHint),
                      secondary: const Icon(Icons.cloud_done_rounded),
                      onChanged: (v) => settings.autosave = v,
                    ),
                    SwitchListTile.adaptive(
                      value: settings.snapping,
                      title: Text(l.snapping),
                      subtitle: Text(l.snappingHint),
                      secondary: const Icon(Icons.straighten_rounded),
                      onChanged: (v) => settings.snapping = v,
                    ),
                    if (services.platform.info.supportsHaptics)
                      SwitchListTile.adaptive(
                        value: settings.haptics,
                        title: Text(l.haptics),
                        secondary: const Icon(Icons.vibration_rounded),
                        onChanged: (v) => settings.haptics = v,
                      ),
                  ],
                ),
                const _StorageSection(),
                _Section(
                  title: l.exportSection,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.image_rounded),
                      title: Text(l.defaultFormat),
                      trailing: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'png', label: Text('PNG')),
                          ButtonSegment(value: 'jpg', label: Text('JPG')),
                        ],
                        selected: {settings.exportFormat},
                        onSelectionChanged: (s) =>
                            settings.exportFormat = s.first,
                      ),
                    ),
                    if (settings.exportFormat == 'jpg')
                      ListTile(
                        leading: const Icon(Icons.high_quality_rounded),
                        title: Text('${l.quality}  ${settings.exportQuality}%'),
                        subtitle: PixSlider(
                          label: '',
                          value: settings.exportQuality.toDouble(),
                          min: 50,
                          max: 100,
                          format: (v) => '${v.round()}%',
                          onChanged: (v) => settings.exportQuality = v.round(),
                        ),
                      ),
                  ],
                ),
                _Section(
                  title: l.about,
                  children: [
                    ListTile(
                      leading: const PixoraLogo(size: 36),
                      title: const Text(
                        'Pixora',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(l.versionLabel(kAppVersion)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        l.aboutText,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.devices_rounded),
                      title: Text(l.platform),
                      trailing: Text(services.platform.info.toString()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, bottom: 8),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final current = settings.locale?.languageCode;
    Widget tile(String? code, String label) => RadioListTile<String?>.adaptive(
      value: code,
      title: Text(label),
      dense: true,
    );
    return RadioGroup<String?>(
      groupValue: current,
      onChanged: (v) => settings.locale = v == null ? null : Locale(v),
      child: Column(
        children: [
          tile(null, l.systemDefault),
          for (final (code, name) in kLanguages) tile(code, name),
        ],
      ),
    );
  }
}

/// Where projects and exported images are kept, with the option to move
/// the Pixora folder on desktops.
class _StorageSection extends StatefulWidget {
  const _StorageSection();

  @override
  State<_StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends State<_StorageSection> {
  bool _busy = false;

  Future<void> _setRoot(String? path) async {
    final services = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final store = await services.platform.openProjectStore(customRoot: path);
      services.settings.storageRoot = path;
      services.projects.setStore(store);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    final info = services.platform.storage;
    final theme = Theme.of(context);

    Widget pathTile(
      IconData icon,
      String title,
      String value, {
      bool copyable = true,
    }) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: SelectableText(
        value,
        textDirection: TextDirection.ltr,
        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
      ),
      trailing: copyable
          ? IconButton(
              tooltip: l.copyPath,
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l.pathCopied)));
              },
            )
          : null,
    );

    return _Section(
      title: l.storage,
      children: [
        pathTile(
          Icons.folder_special_rounded,
          l.projectsFolder,
          info.projectsPath,
        ),
        switch (info.exportDestination) {
          ExportDestination.gallery => pathTile(
            Icons.photo_library_rounded,
            l.exportsFolder,
            l.galleryAlbum,
            copyable: false,
          ),
          ExportDestination.folder => pathTile(
            Icons.image_rounded,
            l.exportsFolder,
            info.exportsPath ?? '',
          ),
          ExportDestination.download => const SizedBox.shrink(),
        },
        if (info.canChangeFolder)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final path = await services.platform.pickFolder();
                          if (path != null) await _setRoot(path);
                        },
                  icon: const Icon(Icons.drive_folder_upload_rounded),
                  label: Text(l.changeFolder),
                ),
                if (!info.isDefault)
                  TextButton(
                    onPressed: _busy ? null : () => _setRoot(null),
                    child: Text(l.resetFolder),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
