/// Calendar conversions and localized date/time strings for the text
/// dialog's "Insert" tools: Gregorian, Hijri (lunar) and Solar Hijri
/// (Jalali — Afghanistan's and Iran's official calendar).
library;

/// Digit shapes for inserted numbers.
enum DigitStyle { latin, arabic, persian }

String applyDigits(String s, DigitStyle style) {
  if (style == DigitStyle.latin) return s;
  final zero = style == DigitStyle.arabic ? 0x0660 : 0x06F0;
  final b = StringBuffer();
  for (final c in s.runes) {
    b.writeCharCode(c >= 0x30 && c <= 0x39 ? zero + c - 0x30 : c);
  }
  return b.toString();
}

int _div(int a, int b) => (a / b).floor();

/// Julian day number of a Gregorian date.
int _gToJdn(int y, int m, int d) {
  final a = _div(14 - m, 12);
  final yy = y + 4800 - a;
  final mm = m + 12 * a - 3;
  return d +
      _div(153 * mm + 2, 5) +
      365 * yy +
      _div(yy, 4) -
      _div(yy, 100) +
      _div(yy, 400) -
      32045;
}

/// Solar Hijri (Jalali) date: (year, month 1–12, day). Uses the 33-year
/// arithmetic rule of jalaali-js, exact for 1178–3177 SH.
(int, int, int) toJalali(DateTime g) {
  final gy = g.year, gm = g.month, gd = g.day;
  const breaks = [
    -61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, 1210, //
    1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178,
  ];
  // jalCal: leap information and the Gregorian day of Farvardin 1.
  int jy = gy - 621;
  var jp = breaks[0];
  var leapJ = -14;
  var jm = 0;
  for (var i = 1; i < breaks.length; i++) {
    jm = breaks[i];
    final jump = jm - jp;
    if (jy < jm) break;
    leapJ += _div(jump, 33) * 8 + _div(jump % 33, 4);
    jp = jm;
  }
  var n = jy - jp;
  leapJ += _div(n, 33) * 8 + _div(n % 33 + 3, 4);
  final jump = jm - jp;
  if (jump % 33 == 4 && jump - n == 4) leapJ += 1;
  final leapG = _div(gy, 4) - _div((_div(gy, 100) + 1) * 3, 4) - 150;
  final march = 20 + leapJ - leapG;
  if (jump - n < 6) n = n - jump + _div(jump + 4, 33) * 33;
  var leap = ((n + 1) % 33 - 1) % 4;
  if (leap == -1) leap = 4;

  final jdn = _gToJdn(gy, gm, gd);
  final jdn1f = _gToJdn(gy, 3, march);
  var k = jdn - jdn1f;
  if (k >= 0) {
    if (k <= 185) {
      return (jy, 1 + _div(k, 31), k % 31 + 1);
    }
    k -= 186;
  } else {
    jy -= 1;
    k += 179;
    if (leap == 1) k += 1;
  }
  return (jy, 7 + _div(k, 30), k % 30 + 1);
}

/// Hijri (lunar) date by the tabular Islamic calendar: (year, month, day).
/// May differ by a day from local moon sighting.
(int, int, int) toHijri(DateTime g) {
  final jd = _gToJdn(g.year, g.month, g.day);
  var l = jd - 1948440 + 10632;
  final n = _div(l - 1, 10631);
  l = l - 10631 * n + 354;
  final j =
      _div(10985 - l, 5316) * _div(50 * l, 17719) +
      _div(l, 5670) * _div(43 * l, 15238);
  l =
      l -
      _div(30 - j, 15) * _div(17719 * j, 50) -
      _div(j, 16) * _div(15238 * j, 43) +
      29;
  final m = _div(24 * l, 709);
  final d = l - _div(709 * m, 24);
  final y = 30 * n + j - 30;
  return (y, m, d);
}

const hijriMonths = [
  'محرم', 'صفر', 'ربیع الاول', 'ربیع الثاني', 'جمادی الاولی', //
  'جمادی الثانیه', 'رجب', 'شعبان', 'رمضان', 'شوال', 'ذوالقعده', 'ذوالحجه',
];

const hijriMonthsArabic = [
  'محرّم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', //
  'جمادى الآخرة', 'رجب', 'شعبان', 'رمضان', 'شوّال', 'ذو القعدة', 'ذو الحجة',
];

/// Afghan (Dari) solar month names.
const solarMonthsAfghan = [
  'حمل', 'ثور', 'جوزا', 'سرطان', 'اسد', 'سنبله', //
  'میزان', 'عقرب', 'قوس', 'جدی', 'دلو', 'حوت',
];

/// Pashto solar month names.
const solarMonthsPashto = [
  'وری', 'غویی', 'غبرګولی', 'چنګاښ', 'زمری', 'وږی', //
  'تله', 'لړم', 'لیندۍ', 'مرغومی', 'سلواغه', 'کب',
];

/// Iranian solar month names.
const solarMonthsIran = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', //
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];

/// Gregorian month names as used in Afghanistan (Pashto and Dari).
const gregorianMonthsAfghan = [
  'جنوري', 'فبروري', 'مارچ', 'اپریل', 'می', 'جون', //
  'جولای', 'اګست', 'سپتمبر', 'اکتوبر', 'نومبر', 'دسمبر',
];

const gregorianMonthsEnglish = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Weekday names, Monday first (DateTime.weekday − 1).
const weekdaysPashto = [
  'دوشنبه',
  'سه‌شنبه',
  'چهارشنبه',
  'پنجشنبه',
  'جمعه',
  'شنبه',
  'یکشنبه',
];
const weekdaysPersian = [
  'دوشنبه',
  'سه‌شنبه',
  'چهارشنبه',
  'پنجشنبه',
  'جمعه',
  'شنبه',
  'یکشنبه',
];
const weekdaysArabic = [
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];
const weekdaysEnglish = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
  'Sunday',
];

String _two(int v) => v.toString().padLeft(2, '0');

/// One insertable value: what it is and the text it inserts.
class InsertItem {
  const InsertItem(this.group, this.text);
  final InsertGroup group;
  final String text;
}

enum InsertGroup { gregorian, hijri, solar, time, weekday, symbols }

/// Everything the Insert sheet offers for [now] in [lang] (a language
/// code), with digits shaped as [digits].
List<InsertItem> insertItems(DateTime now, String lang, DigitStyle digits) {
  final rtl = lang == 'ps' || lang == 'fa' || lang == 'ar' || lang == 'ur';
  String d(String s) => applyDigits(s, digits);
  final gm = rtl
      ? (lang == 'ar' ? gregorianMonthsArabic : gregorianMonthsAfghan)
      : gregorianMonthsEnglish;
  final (jy, jm, jd) = toJalali(now);
  final (hy, hm, hd) = toHijri(now);
  final weekdays = switch (lang) {
    'ps' => weekdaysPashto,
    'fa' || 'ur' => weekdaysPersian,
    'ar' => weekdaysArabic,
    _ => weekdaysEnglish,
  };
  final wd = weekdays[now.weekday - 1];
  final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
  final amPm = rtl
      ? (now.hour < 12 ? 'ق.ظ' : 'ب.ظ')
      : (now.hour < 12 ? 'AM' : 'PM');
  return [
    InsertItem(
      InsertGroup.gregorian,
      d('${now.day} ${gm[now.month - 1]} ${now.year}'),
    ),
    InsertItem(
      InsertGroup.gregorian,
      d('${now.year}/${_two(now.month)}/${_two(now.day)}'),
    ),
    InsertItem(
      InsertGroup.gregorian,
      d('${_two(now.day)}.${_two(now.month)}.${now.year}'),
    ),
    InsertItem(
      InsertGroup.hijri,
      d(
        '$hd ${(lang == 'ar' ? hijriMonthsArabic : hijriMonths)[hm - 1]} '
        '$hy ${rtl ? 'هـ.ق' : 'AH'}',
      ),
    ),
    InsertItem(InsertGroup.hijri, d('$hy/${_two(hm)}/${_two(hd)}')),
    InsertItem(
      InsertGroup.solar,
      d('$jd ${solarMonthsAfghan[jm - 1]} $jy ${rtl ? 'هـ.ش' : 'SH'}'),
    ),
    InsertItem(
      InsertGroup.solar,
      d('$jd ${solarMonthsPashto[jm - 1]} $jy ${rtl ? 'لمریز' : 'SH'}'),
    ),
    InsertItem(InsertGroup.solar, d('$jd ${solarMonthsIran[jm - 1]} $jy')),
    InsertItem(InsertGroup.solar, d('$jy/${_two(jm)}/${_two(jd)}')),
    InsertItem(InsertGroup.time, d('${_two(now.hour)}:${_two(now.minute)}')),
    InsertItem(InsertGroup.time, d('$hour12:${_two(now.minute)} $amPm')),
    InsertItem(
      InsertGroup.time,
      d('${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}'),
    ),
    InsertItem(InsertGroup.weekday, wd),
    InsertItem(
      InsertGroup.weekday,
      d('$wd، ${now.day} ${gm[now.month - 1]} ${now.year}'),
    ),
    for (final s in const [
      '﷽', 'ﷺ', '©', '®', '™', '«»', '•', '…', '—', '★', '☆', '♥', //
      '✓', '✗', '→', '←', '↑', '↓', '°', '±', '×', '÷', '№', '%', '٪',
    ])
      InsertItem(InsertGroup.symbols, s),
  ];
}

const gregorianMonthsArabic = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', //
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];
