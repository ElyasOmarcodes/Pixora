part of 'layer.dart';

/// Google Material Symbols style families.
enum IconStyle { outlined, rounded, sharp }

/// A vector icon. Its SVG path data is stored in the layer itself, so a
/// project keeps working offline wherever the icon came from.
@immutable
final class IconLayer extends Layer {
  IconLayer(
    super.props, {
    required this.iconName,
    required this.pathData,
    this.style = IconStyle.outlined,
    this.filled = false,
    this.weight = 400,
    this.viewBox = const Rect.fromLTWH(0, -960, 960, 960),
    this.width = 300,
    this.height = 300,
    PixFill? fill,
    this.strokeWidth = 0,
    this.strokeColor = const Color(0xFF000000),
  }) : fill = fill ?? PixFill.white;

  final String iconName;
  final IconStyle style;
  final bool filled;

  /// 100..700 (Material Symbols weight axis).
  final int weight;

  /// SVG `d` of the icon, in [viewBox] coordinates.
  final String pathData;
  final Rect viewBox;

  /// Size of the layer box (the icon keeps its aspect ratio inside).
  final double width;
  final double height;
  final PixFill fill;
  final double strokeWidth;
  final Color strokeColor;

  @override
  LayerKind get kind => LayerKind.icon;

  @override
  IconLayer withProps(LayerProps props) => copyWith(props: props);

  IconLayer copyWith({
    LayerProps? props,
    String? iconName,
    String? pathData,
    IconStyle? style,
    bool? filled,
    int? weight,
    Rect? viewBox,
    double? width,
    double? height,
    PixFill? fill,
    double? strokeWidth,
    Color? strokeColor,
  }) => IconLayer(
    props ?? this.props,
    iconName: iconName ?? this.iconName,
    pathData: pathData ?? this.pathData,
    style: style ?? this.style,
    filled: filled ?? this.filled,
    weight: weight ?? this.weight,
    viewBox: viewBox ?? this.viewBox,
    width: width ?? this.width,
    height: height ?? this.height,
    fill: fill ?? this.fill,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeColor: strokeColor ?? this.strokeColor,
  );

  @override
  Json contentToJson() => {
    'icon': iconName,
    if (style != IconStyle.outlined) 'style': style.name,
    if (filled) 'filled': true,
    if (weight != 400) 'weight': weight,
    'd': pathData,
    'vb': '${viewBox.left} ${viewBox.top} ${viewBox.width} ${viewBox.height}',
    'w': width,
    'h': height,
    'fill': fill.toJson(),
    if (strokeWidth > 0) 'strokeWidth': strokeWidth,
    if (strokeWidth > 0) 'strokeColor': writeColor(strokeColor),
  };

  static IconLayer fromJson(LayerProps props, Json m) {
    final vb = readString(
      m['vb'],
      '0 -960 960 960',
    ).split(RegExp(r'[\s,]+')).map((e) => double.tryParse(e) ?? 0).toList();
    return IconLayer(
      props,
      iconName: readString(m['icon'], 'icon'),
      pathData: readString(m['d']),
      style: readEnum(IconStyle.values, m['style'], IconStyle.outlined),
      filled: readBool(m['filled']),
      weight: readInt(m['weight'], 400).clamp(100, 700),
      viewBox: vb.length == 4
          ? Rect.fromLTWH(
              vb[0],
              vb[1],
              vb[2] <= 0 ? 1 : vb[2],
              vb[3] <= 0 ? 1 : vb[3],
            )
          : const Rect.fromLTWH(0, -960, 960, 960),
      width: readDouble(m['w'], 300),
      height: readDouble(m['h'], 300),
      fill: PixFill.fromJson(m['fill']),
      strokeWidth: readDouble(m['strokeWidth']),
      strokeColor: readColor(m['strokeColor']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IconLayer &&
      other.props == props &&
      other.iconName == iconName &&
      other.pathData == pathData &&
      other.style == style &&
      other.filled == filled &&
      other.weight == weight &&
      other.viewBox == viewBox &&
      other.width == width &&
      other.height == height &&
      other.fill == fill &&
      other.strokeWidth == strokeWidth &&
      other.strokeColor == strokeColor;

  @override
  int get hashCode => Object.hash(
    props,
    iconName,
    pathData,
    style,
    filled,
    weight,
    viewBox,
    width,
    height,
    fill,
    strokeWidth,
    strokeColor,
  );
}
