/// Dates and times as a language writes them, in its calendar: CLDR's
/// (48.2) date, time and date-time patterns of each length, month and day
/// names, eras, day periods and localized GMT offsets, interpreted as
/// UTS #35 (Part 4, Dates) has them and found through its aliases as Part
/// 1 (4.1.3) has them, the digits the language's numbering system's.
library;

import 'package:plain_unicode/src/counter_styles.dart'
    show CounterStyle, defaultNumberingSystem, numberingSystemDigits;
import 'package:plain_unicode/src/quotation_marks.dart'
    show cldrLocales, cldrNamesParent, cldrParent;

part 'date_format.g.dart';

/// The length of a date or time format: CLDR's `short` (`14/10/2026`),
/// `medium` (`14 Oct 2026`), `long` (`14 October 2026`) and `full`
/// (`Wednesday, 14 October 2026`).
enum DateStyle {
  /// `14/10/2026`.
  short,

  /// `14 Oct 2026`.
  medium,

  /// `14 October 2026`.
  long,

  /// `Wednesday, 14 October 2026`.
  full,
}

/// A calendar dates are written in: CLDR's calendar types, with their
/// BCP 47 names (`-u-ca-`).
enum CalendarSystem {
  /// The Gregorian calendar (`gregory`).
  gregorian('gregorian', 'gregory'),

  /// Japan's: the Gregorian calendar's months and days, its years counted
  /// in the imperial eras (令和8年 for 2026).
  japanese('japanese', 'japanese'),

  /// The Thai solar calendar: the Gregorian calendar's, its years counted
  /// from the Buddha's death (2569 BE for 2026).
  buddhist('buddhist', 'buddhist'),

  /// The Republic of China's (Minguo): the Gregorian calendar's, its years
  /// counted from 1912 (民國115年 for 2026).
  roc('roc', 'roc');

  new(this.cldrName, this.bcp47Name);

  /// CLDR's name (`gregorian`, `japanese`).
  final String cldrName;

  /// BCP 47's (`gregory`, `japanese`): a language tag's `-u-ca-`.
  final String bcp47Name;

  /// The calendar CLDR or BCP 47 calls [name], whatever its case, or null.
  static CalendarSystem? named(String name) {
    final lower = name.trim().toLowerCase();
    for (final calendar in values) {
      if (calendar.cldrName == lower || calendar.bcp47Name == lower) {
        return calendar;
      }
    }
    return null;
  }

  /// The calendar [language]'s `-u-ca-` extension names (`ja-u-ca-japanese`),
  /// or null.
  static CalendarSystem? ofLanguage(String language) {
    final subtags = language.toLowerCase().replaceAll('_', '-').split('-');
    final u = subtags.indexOf('u');
    if (u < 0) return null;
    for (var i = u + 1; i + 1 < subtags.length; i++) {
      if (subtags[i].length == 1) break;
      if (subtags[i] == 'ca') {
        // (A type may be two subtags: islamic-civil.)
        final rest = subtags.skip(i + 1).takeWhile((t) => t.length > 2);
        return named(rest.join('-')) ?? named(subtags[i + 1]);
      }
    }
    return null;
  }
}

/// [moment]'s date as [language] (a BCP 47 tag) writes it in [style]:
/// `2026年10月14日` in Japanese, `14. Oktober 2026` in German,
/// `١٤ أكتوبر ٢٠٢٦` in Egyptian Arabic. The wall-clock date is [moment]'s
/// at [offset] from UTC ([moment]'s own offset by default); the digits
/// [numberingSystem]'s (CLDR's id), else the language's default; the
/// calendar [calendar], else the one [language]'s `-u-ca-` names, else the
/// Gregorian (`令和8年10月14日` in Japanese's Japanese calendar).
String formatDate(
  DateTime moment,
  String language, {
  DateStyle style = DateStyle.long,
  Duration? offset,
  String? numberingSystem,
  CalendarSystem? calendar,
}) => _DateFormatter(language, numberingSystem, calendar).formatField(
  'dateFormats/${style.name}',
  moment,
  offset ?? moment.timeZoneOffset,
);

/// [moment]'s time of day as [language] writes it in [style] (`medium`:
/// `17:46:40`, `5:46:40 PM`; `long` with the time zone's localized GMT
/// offset).
String formatTime(
  DateTime moment,
  String language, {
  DateStyle style = DateStyle.medium,
  Duration? offset,
  String? numberingSystem,
  CalendarSystem? calendar,
}) => _DateFormatter(language, numberingSystem, calendar).formatField(
  'timeFormats/${style.name}',
  moment,
  offset ?? moment.timeZoneOffset,
);

/// [moment]'s date in [date]'s style and time of day in [time]'s, joined
/// as [language] joins them (its date-time pattern for [date]'s length,
/// the "at" one for `full` and `long` where it has one, as ICU does).
String formatDateTime(
  DateTime moment,
  String language, {
  DateStyle date = DateStyle.long,
  DateStyle time = DateStyle.medium,
  Duration? offset,
  String? numberingSystem,
  CalendarSystem? calendar,
}) {
  final formatter = _DateFormatter(language, numberingSystem, calendar);
  final at = offset ?? moment.timeZoneOffset;
  final datePart = formatter.formatField(
    'dateFormats/${date.name}',
    moment,
    at,
  );
  final timePart = formatter.formatField(
    'timeFormats/${time.name}',
    moment,
    at,
  );
  // ({1} the date, {0} the time; quoted text literal.)
  final out = StringBuffer();
  for (final (literal, text) in _segments(
    formatter.field('dateTimeFormats/${date.name}/atTime')!.$1,
  )) {
    out.write(
      literal
          ? text
          : text.replaceAll('{1}', '\u0000').replaceAll('{0}', timePart),
    );
  }
  return '$out'.replaceAll('\u0000', datePart);
}

/// [pattern]'s quoted and unquoted parts: whether literal, and the text
/// (`''` an apostrophe).
List<(bool, String)> _segments(String pattern) {
  final parts = <(bool, String)>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (var i = 0; i < pattern.length; i++) {
    final c = pattern[i];
    if (c == "'") {
      if (i + 1 < pattern.length && pattern[i + 1] == "'") {
        buffer.write("'");
        i++;
        continue;
      }
      if (buffer.isNotEmpty) parts.add((quoted, '$buffer'));
      buffer.clear();
      quoted = !quoted;
      continue;
    }
    buffer.write(c);
  }
  if (buffer.isNotEmpty) parts.add((quoted, '$buffer'));
  return parts;
}

/// A date in a calendar: its era, its year in the era, its month (from
/// 1), whether that is a leap month, and its day; and its year as the
/// Gregorian calendar counts it (`r`).
typedef _CalendarDate = ({
  int era,
  int year,
  int month,
  bool leapMonth,
  int day,
  int relatedYear,
});

/// A language's calendar fields, found through CLDR's parent locales and
/// root's aliases.
final class _DateFormatter {
  new(String language, [String? numberingSystem, CalendarSystem? calendar])
    : _chain = _chainOf(language),
      _calendar =
          calendar ??
          CalendarSystem.ofLanguage(language) ??
          CalendarSystem.gregorian,
      _digits =
          (numberingSystemDigits(numberingSystem ?? '') ??
                  numberingSystemDigits(defaultNumberingSystem(language))!)
              .runes
              .toList(),
      _rules = _rulesOf(language),
      _week = _weeks[_regionOf(language)] ?? _weeks['001']!;

  final List<String> _chain;

  /// The week's first day (1 Monday to 7 Sunday) and the fewest days of a
  /// year its first week has, in the language's region.
  final (int, int) _week;
  final CalendarSystem _calendar;
  final List<int> _digits;
  final List<(String, int, int?)> _rules;

  /// The locales [language]'s fields come from, most specific first: the
  /// first of its CLDR locales that CLDR has, then their parents.
  static List<String> _chainOf(String language) {
    final candidates = cldrLocales(language);
    final start = candidates.firstWhere(
      (l) => _calendars.containsKey(l) || cldrNamesParent(l),
      orElse: () => candidates.isEmpty ? 'root' : candidates.last,
    );
    return [for (String? l = start; l != null; l = cldrParent(l)) l];
  }

  /// [language]'s region: its own, else its language's (and script's)
  /// likely one.
  static String _regionOf(String language) {
    final subtags = language.trim().replaceAll('_', '-').split('-');
    String? script;
    for (final subtag in subtags.skip(1)) {
      if (subtag.length == 1) break;
      if (subtag.length == 4 && script == null) {
        script = subtag[0].toUpperCase() + subtag.substring(1).toLowerCase();
      } else if (subtag.length == 2 ||
          (subtag.length == 3 && int.tryParse(subtag) != null)) {
        return subtag.toUpperCase();
      }
    }
    final lang = subtags.first.toLowerCase();
    return _likelyRegions['$lang-$script'] ?? _likelyRegions[lang] ?? '001';
  }

  /// The year [wall]'s week belongs to (`Y`): week 1 the first that has
  /// at least the region's fewest days of the year, weeks starting on its
  /// first day (UTS #35, Part 4, 8.1). (In the Gregorian calendar's weeks,
  /// whose years the calendars of eras share.)
  int _weekYear(DateTime wall) {
    final (first, fewest) = _week;
    DateTime weekOne(int year) {
      final january = DateTime.utc(year);
      final into = (january.weekday - first + 7) % 7;
      final start = january.subtract(Duration(days: into));
      return 7 - into >= fewest ? start : start.add(const Duration(days: 7));
    }

    final day = DateTime.utc(wall.year, wall.month, wall.day);
    if (day.isBefore(weekOne(wall.year))) return wall.year - 1;
    if (!day.isBefore(weekOne(wall.year + 1))) return wall.year + 1;
    return wall.year;
  }

  /// The day periods' rules of [language]'s locale, else of its language
  /// (CLDR gives them by language: `zh` for `zh-Hant`).
  static List<(String, int, int?)> _rulesOf(String language) {
    for (final candidate in cldrLocales(language)) {
      if (_dayPeriods[candidate] case final rules?) return rules;
    }
    final subtag = language.trim().replaceAll('_', '-').split('-').first;
    return _dayPeriods[subtag.toLowerCase()] ?? const [];
  }

  /// [moment] at [offset] by the calendar's pattern at [path]
  /// (`dateFormats/long`, `timeFormats/short`), with the numbering it
  /// gives some fields.
  String formatField(String path, DateTime moment, Duration offset) {
    final (pattern, numbers) = field('$path/standard')!;
    return format(pattern, moment, offset, numbers: numbers);
  }

  /// The calendar's field at [path] (`months/format/wide/10`,
  /// `dateFormats/long/standard`) and the numbering its pattern gives,
  /// if any.
  (String, String?)? field(String path) =>
      _lookup('${_calendar.cldrName}/$path');

  /// The value at [path] in the first locale of the chain that has it;
  /// else, where root has an alias for a part of the path, the value at
  /// the path it names, looked for in the chain again (UTS #35, Part 1,
  /// 4.1.3).
  (String, String?)? _lookup(String path) {
    var at = path;
    for (var hops = 0; hops < 8; hops++) {
      for (final l in _chain) {
        final fields = _calendars[l];
        if (fields?[at] case final value?) {
          return (value, fields!['$at#numbers']);
        }
      }
      final next = _alias(at);
      if (next == null) return null;
      at = next;
    }
    return null;
  }

  /// [path] with its longest part that root aliases replaced, or null.
  static String? _alias(String path) {
    for (var cut = path.length; cut > 0; cut = path.lastIndexOf('/', cut - 1)) {
      if (_aliases[path.substring(0, cut)] case final to?) {
        return '$to${path.substring(cut)}';
      }
    }
    return null;
  }

  /// The text at [path], or null.
  String? _text(String path) => field(path)?.$1;

  static const List<String> _days = [
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
    'sun',
  ];

  /// [n] in the language's digits, at least [width] of them.
  String _number(int n, [int width = 1]) {
    final text = n.abs().toString().padLeft(width, '0');
    final digits = [for (final c in text.codeUnits) _digits[c - 0x30]];
    return '${n < 0 ? '-' : ''}${String.fromCharCodes(digits)}';
  }

  /// The wall-clock date [wall] (a Gregorian date) in the calendar.
  _CalendarDate _date(DateTime wall) {
    final (era, year) = _era(wall.year, wall.month, wall.day);
    return (
      era: era,
      year: year,
      month: wall.month,
      leapMonth: false,
      day: wall.day,
      relatedYear: wall.year,
    );
  }

  /// The era of the Gregorian date [y]-[m]-[d] in a calendar that counts
  /// the Gregorian calendar's years by eras (CLDR's era data), and its
  /// year in that era: the latest era begun by the date, else the era
  /// counted backwards that it is in.
  (int, int) _era(int y, int m, int d) {
    final eras = _eras[_calendar.cldrName] ?? const [];
    final day = (y, m, d);
    bool notAfter((int, int, int) a, (int, int, int) b) =>
        a.$1 < b.$1 ||
        (a.$1 == b.$1 && (a.$2 < b.$2 || (a.$2 == b.$2 && a.$3 <= b.$3)));
    (int, int)? best;
    var bestStart = (0, 0, 0);
    for (final (era, ey, em, ed, backwards) in eras) {
      if (backwards) continue;
      final start = (ey, em, ed);
      if (notAfter(start, day) &&
          (best == null || notAfter(bestStart, start))) {
        best = (era, y - ey + 1);
        bestStart = start;
      }
    }
    if (best != null) return best;
    for (final (era, ey, em, ed, backwards) in eras) {
      if (backwards && notAfter(day, (ey, em, ed))) return (era, ey - y + 1);
    }
    return (1, y);
  }

  /// [moment] at [offset] by [pattern] (UTS #35, Part 4, 8), the
  /// pattern's own numbering where it gives one ([numbers]: `y=jpanyear`
  /// for a field, `hanidec` for all).
  String format(
    String pattern,
    DateTime moment,
    Duration offset, {
    String? numbers,
  }) {
    final overrides = <String, String>{
      for (final part in (numbers ?? '').split(';'))
        if (part.contains('='))
          part.split('=')[0]: part.split('=')[1]
        else if (part.isNotEmpty)
          '': part,
    };
    final wall = moment.toUtc().add(offset);
    final date = _date(wall);
    final out = StringBuffer();
    var hasMinute = false;
    var hasSecond = false;
    for (final (literal, text) in _segments(pattern)) {
      if (!literal) {
        hasMinute |= text.contains('m');
        hasSecond |= text.contains('s');
      }
    }
    for (final (literal, text) in _segments(pattern)) {
      if (literal) {
        out.write(text);
        continue;
      }
      var i = 0;
      while (i < text.length) {
        final c = text[i];
        if (!RegExp('[A-Za-z]').hasMatch(c)) {
          out.write(c);
          i++;
          continue;
        }
        var j = i;
        while (j < text.length && text[j] == c) {
          j++;
        }
        final system = overrides[c] ?? overrides[''];
        out.write(
          system != null && _numeric(c, j - i)
              ? _numbered(c, j - i, wall, date, system)
              : _field(c, j - i, wall, date, offset, hasMinute, hasSecond),
        );
        i = j;
      }
    }
    return '$out';
  }

  /// Whether [letter] repeated [count] times is a number.
  static bool _numeric(String letter, int count) => switch (letter) {
    'M' || 'L' => count <= 2,
    'y' || 'd' || 'r' => true,
    _ => false,
  };

  String _field(
    String letter,
    int count,
    DateTime wall,
    _CalendarDate date,
    Duration offset,
    bool hasMinute,
    bool hasSecond,
  ) {
    final day = _days[wall.weekday - 1];
    String month(String context) {
      final width = count == 3 ? 'abbreviated' : 'wide';
      final leap = date.leapMonth ? '-leap' : '';
      return _text('months/$context/$width/${date.month}$leap') ??
          _number(date.month);
    }

    return switch (letter) {
      'G' =>
        _text(
              'eras/${switch (count) {
                4 => 'eraNames',
                5 => 'eraNarrow',
                _ => 'eraAbbr',
              }}/${date.era}',
            ) ??
            '',
      'y' =>
        count == 2 ? _number(date.year % 100, 2) : _number(date.year, count),
      'r' => _number(date.relatedYear, count),
      'Y' =>
        count == 2
            ? _number(_weekYear(wall) % 100, 2)
            : _number(_weekYear(wall), count),
      'M' => count <= 2 ? _number(date.month, count) : month('format'),
      'L' => count <= 2 ? _number(date.month, count) : month('stand-alone'),
      'd' => _number(date.day, count),
      'E' => _text('days/format/${count == 4 ? 'wide' : 'abbreviated'}/$day')!,
      'c' => _text(
        'days/stand-alone/${count == 4 ? 'wide' : 'abbreviated'}/$day',
      )!,
      'a' => _text(
        'dayPeriods/format/abbreviated/${wall.hour < 12 ? 'am' : 'pm'}',
      )!,
      'B' => _dayPeriod(wall, hasMinute, hasSecond),
      'h' => _number(wall.hour % 12 == 0 ? 12 : wall.hour % 12, count),
      'H' => _number(wall.hour, count),
      'K' => _number(wall.hour % 12, count),
      'k' => _number(wall.hour == 0 ? 24 : wall.hour, count),
      'm' => _number(wall.minute, count),
      's' => _number(wall.second, count),
      'z' || 'O' || 'v' => _gmt(offset, long: count >= 4),
      _ => letter * count,
    };
  }

  /// Numeric field [letter] of [date] in the numbering system [system]
  /// (CLDR's: `romanlow` in lower-case roman numerals, `jpanyear` the
  /// first year of an era as 元).
  String _numbered(
    String letter,
    int count,
    DateTime wall,
    _CalendarDate date,
    String system,
  ) {
    final value = switch (letter) {
      'M' || 'L' => date.month,
      'd' => date.day,
      'y' => count == 2 ? date.year % 100 : date.year,
      'r' => date.relatedYear,
      _ => 0,
    };
    if (system == 'jpanyear') return value == 1 ? '元' : _number(value);
    final style = system == 'romanlow'
        ? CounterStyle.named('lower-roman')
        : CounterStyle.forNumberingSystem(system);
    return style?.format(value) ?? _number(value);
  }

  /// The flexible day period of [wall] (`B`): noon or midnight where the
  /// language has them and the time is exactly then (as far as the pattern
  /// shows it), else the period whose rule takes the time, else AM or PM.
  String _dayPeriod(DateTime wall, bool hasMinute, bool hasSecond) {
    final minutes = wall.hour * 60 + wall.minute;
    final exact =
        (!hasMinute || wall.minute == 0) && (!hasSecond || wall.second == 0);
    String? named(String period) =>
        _text('dayPeriods/format/abbreviated/$period');
    for (final (period, from, before) in _rules) {
      if (before == null && exact && wall.hour * 60 == from) {
        if (named(period) case final name?) return name;
      }
    }
    for (final (period, from, before) in _rules) {
      if (before == null) continue;
      final inside = from < before
          ? minutes >= from && minutes < before
          : minutes >= from || minutes < before;
      if (inside) {
        if (named(period) case final name?) return name;
      }
    }
    return named(wall.hour < 12 ? 'am' : 'pm')!;
  }

  /// [offset] in the localized GMT format (`GMT+9`, long `GMT+09:00`;
  /// `GMT` for none).
  String _gmt(Duration offset, {required bool long}) {
    String? zone(String name) => _lookup('zone/$name')?.$1;
    if (offset == Duration.zero) return zone('gmtZeroFormat') ?? 'GMT';
    final hourFormat = (zone('hourFormat') ?? '+HH:mm;-HH:mm').split(';');
    var format = offset.isNegative ? hourFormat[1] : hourFormat[0];
    final minutes = offset.inMinutes.abs() % 60;
    final hours = offset.inMinutes.abs() ~/ 60;
    if (long) {
      // (The long form: two-digit hours, as ICU writes them, whatever the
      // hour format has.)
      if (!format.contains('HH')) format = format.replaceFirst('H', 'HH');
    } else {
      // (The short form: the hours unpadded, the minutes only if any.)
      format = format.replaceFirst('HH', 'H');
      if (minutes == 0) {
        format = format.replaceFirst(RegExp('[^H+-]*mm'), '');
      }
    }
    final text = format
        .replaceFirst('HH', _number(hours, 2))
        .replaceFirst('H', _number(hours))
        .replaceFirst('mm', _number(minutes, 2));
    return (zone('gmtFormat') ?? 'GMT{0}').replaceFirst('{0}', text);
  }
}
