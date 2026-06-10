/// Gregorian → Hijri conversion (Umm al-Qura approximation).
///
/// Pure-Dart, no external dependency. Accuracy is ±1 day vs. official
/// Saudi sightings, which is fine for a "today is X Ramadan" header.
/// Ported from the same algorithm used by Sahulat and Interact Pro.
const _hijriMonths = [
  'Muharram',
  'Safar',
  "Rabi' al-Awwal",
  "Rabi' al-Thani",
  'Jumada al-Awwal',
  'Jumada al-Thani',
  'Rajab',
  "Sha'ban",
  'Ramadan',
  'Shawwal',
  "Dhu al-Qi'dah",
  'Dhu al-Hijjah',
];

class HijriDate {
  final int year;
  final int month; // 1..12
  final int day; // 1..30
  const HijriDate(this.year, this.month, this.day);

  String get monthName => _hijriMonths[month - 1];

  @override
  String toString() => '$day $monthName $year AH';
}

/// Convert a Gregorian DateTime to Hijri using the Kuwaiti algorithm,
/// which closely approximates the Umm al-Qura calendar within ±1 day
/// for any modern date.
HijriDate gregorianToHijri(DateTime g) {
  // Algorithm: Robert van Gent's Kuwaiti algorithm, condensed.
  final y = g.year;
  final m = g.month;
  final d = g.day;

  int jd;
  if ((y > 1582) ||
      (y == 1582 && m > 10) ||
      (y == 1582 && m == 10 && d > 14)) {
    jd = ((1461 * (y + 4800 + ((m - 14) ~/ 12))) ~/ 4) +
        ((367 * (m - 2 - 12 * ((m - 14) ~/ 12))) ~/ 12) -
        ((3 * ((y + 4900 + ((m - 14) ~/ 12)) ~/ 100)) ~/ 4) +
        d -
        32075;
  } else {
    jd = 367 * y -
        ((7 * (y + 5001 + ((m - 9) ~/ 7))) ~/ 4) +
        ((275 * m) ~/ 9) +
        d +
        1729777;
  }

  final l1 = jd - 1948440 + 10632;
  final n = ((l1 - 1) ~/ 10631);
  final l2 = l1 - 10631 * n + 354;
  final j =
      (((10985 - l2) ~/ 5316)) * (((50 * l2) ~/ 17719)) +
          ((l2 ~/ 5670)) * (((43 * l2) ~/ 15238));
  final l3 = l2 -
      (((30 - j) ~/ 15)) * ((17719 * j) ~/ 50) -
      ((j ~/ 16)) * ((15238 * j) ~/ 43) +
      29;
  final month = (24 * l3) ~/ 709;
  final day = l3 - ((709 * month) ~/ 24);
  final year = 30 * n + j - 30;

  return HijriDate(year, month, day);
}

/// Convenience: "12 Ramadan 1446 AH" — used by the LocalContextCard.
String gregorianToHijriString(DateTime g) => gregorianToHijri(g).toString();
