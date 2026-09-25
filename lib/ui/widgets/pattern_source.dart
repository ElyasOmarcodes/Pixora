import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../document/assets/asset_store.dart';

/// What the pattern picker can make patterns from, supplied by the editor:
/// the project's assets (where used patterns are stored) and optional
/// sources for Define Pattern.
class PatternSource extends InheritedWidget {
  const PatternSource({
    super.key,
    required this.assets,
    required this.pickImage,
    required this.fromLayer,
    required this.fromSelection,
    required this.hasLayer,
    required this.hasSelection,
    required super.child,
  });

  final AssetStore assets;

  /// Lets the user pick a photo (encoded bytes), or null if cancelled.
  final Future<Uint8List?> Function() pickImage;

  /// The selected layer rendered as PNG.
  final Future<Uint8List?> Function() fromLayer;

  /// The current pixel selection rendered as PNG.
  final Future<Uint8List?> Function() fromSelection;

  /// Whether there is a layer / a selection right now.
  final bool Function() hasLayer;
  final bool Function() hasSelection;

  static PatternSource? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PatternSource>();

  @override
  bool updateShouldNotify(PatternSource old) => assets != old.assets;
}
