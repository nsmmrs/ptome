/// The calendars dates are written in, other than the Gregorian: a day
/// (counted from 1970-01-01, the Unix epoch) as each counts it. The
/// arithmetic ones from their published definitions: the Islamic
/// calendar's tabular forms (the 30-year cycle with leap years 2, 5, 7,
/// 10, 13, 16, 18, 21, 24, 26 and 29), the Hebrew calendar's (Hillel II's
/// molad and postponements), the Coptic and Ethiopic calendars' (13 months,
/// a leap day every fourth year) and India's national calendar's (the
/// Calendar Reform Committee's, 1955), as Reingold and Dershowitz's
/// Calendrical Calculations sets them out; the Umm al-Qura calendar from
/// Saudi Arabia's published month lengths. Those that follow the sky by
/// their own definitions (lib/src/astronomy.dart): the Persian calendar's
/// year from the March equinox in Tehran, the astronomical Islamic
/// calendar's months from the new moons, and the Chinese and Korean
/// lunisolar calendars (GB/T 33661-2017's rules).
library;

import 'dart:math' as math;

import 'package:plain_unicode/src/astronomy.dart';
import 'package:plain_unicode/src/umalqura.g.dart' show umAlQuraMonths;

/// A day as a calendar counts it: its year (counted from the calendar's
/// epoch, so 0 and below before it), its month (from 1), whether that is a
/// leap month (the Chinese calendar's) and its day of the month.
typedef CalendarDay = ({int year, int month, bool leapMonth, int day});

/// [a] divided by [b], rounded down.
int _div(int a, int b) => (a / b).floor();

/// [a] modulo [b], from 0 to [b] - 1.
int _mod(int a, int b) => a - b * _div(a, b);

/// The day [y]-[m]-[d] of the proleptic Gregorian calendar, from
/// 1970-01-01.
int gregorianDay(int y, int m, int d) =>
    DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

/// The Gregorian date of [day] (from 1970-01-01).
DateTime gregorianDate(int day) => DateTime.utc(1970, 1, 1 + day);

// The Islamic calendar's tabular forms ------------------------------------

/// The civil form's epoch: 1 Muharram 1 AH, 16 July 622 in the Julian
/// calendar (a Friday); the astronomical (tbla) form's a day earlier.
final int _islamicEpoch = gregorianDay(622, 7, 19);

/// The day [y]-[m]-[d] of the tabular Islamic calendar ([astronomical]:
/// tbla's epoch).
int _islamicDay(int y, int m, int d, {bool astronomical = false}) =>
    _islamicEpoch -
    (astronomical ? 1 : 0) -
    1 +
    (y - 1) * 354 +
    _div(3 + 11 * y, 30) +
    29 * (m - 1) +
    _div(m, 2) +
    d;

/// [day] in the tabular Islamic calendar.
CalendarDay islamicTabular(int day, {bool astronomical = false}) {
  final epoch = _islamicEpoch - (astronomical ? 1 : 0);
  final y = _div(30 * (day - epoch) + 10646, 10631);
  final prior = day - _islamicDay(y, 1, 1, astronomical: astronomical);
  final m = _div(11 * prior + 330, 325);
  final d = day - _islamicDay(y, m, 1, astronomical: astronomical) + 1;
  return (year: y, month: m, leapMonth: false, day: d);
}

// Umm al-Qura ----------------------------------------------------------------

/// The first year the Umm al-Qura table has; 1 Muharram of it.
const int _umAlQuraFirst = 1300;
final int _umAlQuraStart = gregorianDay(1882, 11, 12);

/// [day] in the Umm al-Qura calendar: Saudi Arabia's, its months 29 or 30
/// days as its tables give them (1300 to 1600 AH); the tabular civil
/// calendar outside them.
CalendarDay islamicUmmAlQura(int day) {
  var start = _umAlQuraStart;
  if (day < start) return islamicTabular(day);
  for (var i = 0; i < umAlQuraMonths.length; i++) {
    final months = umAlQuraMonths[i];
    for (var m = 0; m < 12; m++) {
      final length = (months >> (11 - m)) & 1 == 1 ? 30 : 29;
      if (day < start + length) {
        return (
          year: _umAlQuraFirst + i,
          month: m + 1,
          leapMonth: false,
          day: day - start + 1,
        );
      }
      start += length;
    }
  }
  return islamicTabular(day);
}

// The Hebrew calendar --------------------------------------------------------

/// The day before 1 Tishri 1 AM: 7 October 3761 BCE in the Julian
/// calendar (proleptic), counted from 1970-01-01.
const int _hebrewEpoch = -1373427 - 719163;

/// Whether [y] is a leap year (13 months): 7 of every 19.
bool hebrewLeapYear(int y) => _mod(7 * y + 1, 19) < 7;

/// The days from the epoch to the molad of Tishri of [y], postponed a day
/// where it falls on a Sunday, Wednesday or Friday.
int _hebrewElapsedDays(int y) {
  final months = _div(235 * y - 234, 19);
  final parts = 12084 + 13753 * months;
  final day = 29 * months + _div(parts, 25920);
  return _mod(3 * (day + 1), 7) < 3 ? day + 1 : day;
}

/// The further postponement of [y]'s new year that keeps the years 353 to
/// 355 or 383 to 385 days long.
int _hebrewYearDelay(int y) {
  final previous = _hebrewElapsedDays(y - 1);
  final present = _hebrewElapsedDays(y);
  final next = _hebrewElapsedDays(y + 1);
  if (next - present == 356) return 2;
  if (present - previous == 382) return 1;
  return 0;
}

/// The day of 1 Tishri [y].
int _hebrewNewYear(int y) =>
    _hebrewEpoch + _hebrewElapsedDays(y) + _hebrewYearDelay(y);

/// The months of [y], CLDR's numbering (1 Tishri, 6 Adar I in a leap year
/// only, 7 Adar or Adar II, 8 Nisan to 13 Elul), with their lengths.
List<(int, int)> _hebrewMonths(int y) {
  final length = _hebrewNewYear(y + 1) - _hebrewNewYear(y);
  // (A year 355 or 385 days long has a long Heshvan; 353 or 383, a short
  // Kislev.)
  final heshvan = length % 10 == 5 ? 30 : 29;
  final kislev = length % 10 == 3 ? 29 : 30;
  return [
    (1, 30),
    (2, heshvan),
    (3, kislev),
    (4, 29),
    (5, 30),
    if (hebrewLeapYear(y)) (6, 30),
    (7, 29),
    (8, 30),
    (9, 29),
    (10, 30),
    (11, 29),
    (12, 30),
    (13, 29),
  ];
}

/// [day] in the Hebrew calendar (its months CLDR's numbering).
CalendarDay hebrew(int day) {
  // (The year from the mean year's length, then the right one.)
  var y = _div(day - _hebrewEpoch, 366) + 1;
  while (_hebrewNewYear(y + 1) <= day) {
    y++;
  }
  while (_hebrewNewYear(y) > day) {
    y--;
  }
  var start = _hebrewNewYear(y);
  for (final (month, length) in _hebrewMonths(y)) {
    if (day < start + length) {
      return (year: y, month: month, leapMonth: false, day: day - start + 1);
    }
    start += length;
  }
  throw StateError('day $day outside year $y');
}

// The Coptic and Ethiopic calendars -----------------------------------------

/// 1 Thout 1 of the Era of Martyrs: 29 August 284 in the Julian calendar.
const int _copticEpoch = 103605 - 719163;

/// 1 Mäskäräm 1 of the Year of Mercy: 29 August 8 in the Julian calendar.
const int _ethiopicEpoch = 2796 - 719163;

/// [day] in a calendar of twelve 30-day months and a thirteenth of five
/// days (six every fourth year), from [epoch].
CalendarDay _alexandrian(int day, int epoch) {
  int dayOf(int y, int m, int d) =>
      epoch - 1 + 365 * (y - 1) + _div(y, 4) + 30 * (m - 1) + d;
  final y = _div(4 * (day - epoch) + 1463, 1461);
  final m = _div(day - dayOf(y, 1, 1), 30) + 1;
  return (year: y, month: m, leapMonth: false, day: day + 1 - dayOf(y, m, 1));
}

/// [day] in the Coptic calendar.
CalendarDay coptic(int day) => _alexandrian(day, _copticEpoch);

/// [day] in the Ethiopic calendar (years of the Year of Mercy).
CalendarDay ethiopic(int day) => _alexandrian(day, _ethiopicEpoch);

// India's national calendar -------------------------------------------------

/// [day] in India's national calendar (Saka): its year starting on 22
/// March (21 in a Gregorian leap year) of the Gregorian year 78 later;
/// Chaitra 30 days (31 in such a year), the next five months 31, the
/// last six 30.
CalendarDay indian(int day) {
  final date = gregorianDate(day);
  bool leap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
  int newYear(int y) => gregorianDay(y, 3, leap(y) ? 21 : 22);
  var gy = date.year;
  if (day < newYear(gy)) gy--;
  var into = day - newYear(gy);
  final lengths = [
    if (leap(gy)) 31 else 30,
    31, 31, 31, 31, 31, //
    30, 30, 30, 30, 30, 30,
  ];
  for (final (i, length) in lengths.indexed) {
    if (into < length) {
      return (year: gy - 78, month: i + 1, leapMonth: false, day: into + 1);
    }
    into -= length;
  }
  throw StateError('day $day outside year ${gy - 78}');
}

// The Persian calendar -------------------------------------------------------

final Map<int, int> _nowruzes = {};

/// The day Persian year [y] starts on (Nowruz): the day, in Iran's
/// standard time (UTC+3:30, the 52.5°E meridian), of the March equinox if
/// it comes before noon, else the next day.
int _nowruz(int y) => _nowruzes[y] ??= () {
  final equinox = sunReaches(0, gregorianDay(y + 621, 3, 1).toDouble());
  final local = equinox + 3.5 / 24;
  final day = local.floor();
  return local - day < 0.5 ? day : day + 1;
}();

/// [day] in the Persian (Solar Hijri) calendar: its first six months 31
/// days, the next five 30, the last 29 or 30.
CalendarDay persian(int day) {
  var y = gregorianDate(day).year - 621;
  if (day < _nowruz(y)) y--;
  final into = day - _nowruz(y);
  if (into < 186) {
    return (
      year: y,
      month: into ~/ 31 + 1,
      leapMonth: false,
      day: into % 31 + 1,
    );
  }
  final rest = into - 186;
  return (year: y, month: 7 + rest ~/ 30, leapMonth: false, day: rest % 30 + 1);
}

// The astronomical Islamic calendar -------------------------------------------

/// [day] in the Islamic calendar by the new moons: each month from the
/// first day whose midnight (UT) is at or after its new moon, numbered
/// from the Hijra (the civil calendar's epoch).
CalendarDay islamicAstronomical(int day) {
  final start = newMoonAtOrBefore(day.toDouble()).ceil();
  final months = ((start - _islamicEpoch) / synodicMonth).round();
  return (
    year: _div(months, 12) + 1,
    month: _mod(months, 12) + 1,
    leapMonth: false,
    day: day - start + 1,
  );
}

// The Chinese and Korean calendars --------------------------------------------

/// The Chinese calendar's epoch: the year that 2637 years before the
/// Gregorian calendar's 1 starts in (R&D's 15 February -2636).
final int _chineseEpoch = gregorianDay(-2636, 2, 15);

/// A lunisolar calendar of China's rules (GB/T 33661-2017) kept in a
/// time zone: months from the new moons' days, the month with the winter
/// solstice the eleventh, and in a year of 13 months between two such
/// months the first with no major solar term (no multiple of 30° of the
/// Sun's longitude) a leap month repeating the one before.
final class _Lunisolar {
  new(this.offset);

  /// The zone's offset from UT, in days, at a moment.
  final double Function(double days) offset;

  final Map<int, int> _solstices = {};

  /// The day (in the zone) of [moment].
  int _day(double moment) => (moment + offset(moment)).floor();

  /// The moment (UT) [day] starts in the zone.
  double _midnight(int day) => day - offset(day.toDouble());

  /// The day of the first new moon on or after [day].
  int _newMoonOnOrAfter(int day) => _day(newMoonAfter(_midnight(day) - 1e-7));

  /// The day of the last new moon before [day].
  int _newMoonBefore(int day) => _day(newMoonAtOrBefore(_midnight(day) - 1e-7));

  /// The day of the winter solstice on or before [day].
  int _solsticeOnOrBefore(int day) {
    final y = gregorianDate(day).year;
    int solstice(int year) => _solstices[year] ??= _day(
      sunReaches(270, gregorianDay(year, 11, 1).toDouble()),
    );
    final w = solstice(y);
    return w <= day ? w : solstice(y - 1);
  }

  /// The major solar term last begun when [day] starts (1 to 12: 1 the
  /// Sun's longitude 330°, 11 the winter solstice's 270°).
  int _majorTerm(int day) {
    final degrees = sunLongitude(_midnight(day)) * 180 / math.pi;
    return _mod(2 + (degrees / 30).floor() - 1, 12) + 1;
  }

  /// Whether the month starting on [day] has no major solar term.
  bool _noMajorTerm(int day) =>
      _majorTerm(day) == _majorTerm(_newMoonOnOrAfter(day + 1));

  final Map<int, List<(int, int, bool)>> _suis = {};

  /// The months from the month 11 that contains the winter solstice on
  /// day [solstice] to the next month 11 (included): each one's first
  /// day, number and whether it is a leap month. Thirteen months in
  /// between: the first with no major solar term the leap month.
  List<(int, int, bool)> _sui(int solstice) => _suis[solstice] ??= () {
    final next = _solsticeOnOrBefore(solstice + 370);
    final last = _newMoonBefore(next + 1);
    final starts = [_newMoonBefore(solstice + 1)];
    while (starts.last < last) {
      starts.add(_newMoonOnOrAfter(starts.last + 1));
    }
    final leapYear = starts.length == 14;
    final months = <(int, int, bool)>[(starts.first, 11, false)];
    var leapFound = false;
    for (final start in starts.skip(1)) {
      final previous = months.last.$2;
      if (leapYear && !leapFound && _noMajorTerm(start)) {
        leapFound = true;
        months.add((start, previous, true));
      } else {
        months.add((start, previous % 12 + 1, false));
      }
    }
    return months;
  }();

  /// [day] in the calendar: its year counted from the epoch (R&D's
  /// elapsed years: 4663 for the year starting in 2026).
  CalendarDay at(int day) {
    var months = _sui(_solsticeOnOrBefore(day));
    // (After the next month 11's start, before its solstice: that one's.)
    if (day >= months.last.$1) months = _sui(_solsticeOnOrBefore(day + 40));
    var (start, month, leap) = months.first;
    for (final m in months) {
      if (m.$1 > day) break;
      (start, month, leap) = m;
    }
    final elapsed = (1.5 - month / 12 + (day - _chineseEpoch) / tropicalYear)
        .floor();
    return (year: elapsed, month: month, leapMonth: leap, day: day - start + 1);
  }
}

/// China's calendar: in Beijing's local mean time (116°25'E) until 1929,
/// UTC+8 since (as Calendrical Calculations and the Hong Kong
/// Observatory's tables have it).
final _Lunisolar _china = _Lunisolar(
  (days) => days < _china1929 ? 1397 / 180 / 24 : 8 / 24,
);
final int _china1929 = gregorianDay(1929, 1, 1);

/// Korea's: in UTC+8 until 1912, UTC+9 since (as the Korean Astronomy and
/// Space Science Institute's tables have it).
final _Lunisolar _korea = _Lunisolar(
  (days) => days < _korea1912 ? 8 / 24 : 9 / 24,
);
final int _korea1912 = gregorianDay(1912, 1, 1);

/// [day] in the Chinese calendar, its year R&D's elapsed years (the
/// Gregorian year it starts in plus 2637).
CalendarDay chinese(int day) => _china.at(day);

/// [day] in the Korean calendar (Dangi), its year as [chinese]'s.
CalendarDay dangi(int day) => _korea.at(day);
