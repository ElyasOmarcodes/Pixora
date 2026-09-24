/// Measurement units for sizes and rulers (like Photoshop's).
enum MeasureUnit { px, cm, mm, inch, pt, percent }

extension MeasureUnitX on MeasureUnit {
  /// Short suffix shown after numbers.
  String get suffix => switch (this) {
    MeasureUnit.px => 'px',
    MeasureUnit.cm => 'cm',
    MeasureUnit.mm => 'mm',
    MeasureUnit.inch => 'in',
    MeasureUnit.pt => 'pt',
    MeasureUnit.percent => '%',
  };

  /// Pixels per one unit at [dpi]. For percent, [reference] is 100 %.
  double pixelsPerUnit(double dpi, {double reference = 100}) => switch (this) {
    MeasureUnit.px => 1,
    MeasureUnit.cm => dpi / 2.54,
    MeasureUnit.mm => dpi / 25.4,
    MeasureUnit.inch => dpi,
    MeasureUnit.pt => dpi / 72,
    MeasureUnit.percent => reference / 100,
  };

  double toPx(double v, double dpi, {double reference = 100}) =>
      v * pixelsPerUnit(dpi, reference: reference);

  double fromPx(double px, double dpi, {double reference = 100}) =>
      px / pixelsPerUnit(dpi, reference: reference);

  /// Decimal places worth showing.
  int get decimals => switch (this) {
    MeasureUnit.px || MeasureUnit.pt || MeasureUnit.percent => 0,
    MeasureUnit.mm => 1,
    MeasureUnit.cm || MeasureUnit.inch => 2,
  };

  String format(double v) {
    final s = v.toStringAsFixed(decimals);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }
}
