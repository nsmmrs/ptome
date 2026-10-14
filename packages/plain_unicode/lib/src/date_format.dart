/// Dates and times as a language writes them, in the Gregorian calendar:
/// CLDR's (48.2) date, time and date-time patterns of each length, month
/// and day names, day periods and localized GMT offsets, interpreted as
/// UTS #35 (Part 4, Dates) has them, the digits the language's numbering
/// system's.
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

/// [moment]'s date as [language] (a BCP 47 tag) writes it in [style]:
/// `2026年10月14日` in Japanese, `14. Oktober 2026` in German,
/// `١٤ أكتوبر ٢٠٢٦` in Egyptian Arabic. The wall-clock date is [moment]'s
/// at [offset] from UTC ([moment]'s own offset by default); the digits
/// [numberingSystem]'s (CLDR's id), else the language's default.
String formatDate(
  DateTime moment,
  String language, {
  DateStyle style = DateStyle.long,
  Duration? offset,
  String? numberingSystem,
}) => _DateFormatter(
  language,
  numberingSystem,
).formatField('df.${style.name}', moment, offset ?? moment.timeZoneOffset);

/// [moment]'s time of day as [language] writes it in [style] (`medium`:
/// `17:46:40`, `5:46:40 PM`; `long` with the time zone's localized GMT
/// offset).
String formatTime(
  DateTime moment,
  String language, {
  DateStyle style = DateStyle.medium,
  Duration? offset,
  String? numberingSystem,
}) => _DateFormatter(
  language,
  numberingSystem,
).formatField('tf.${style.name}', moment, offset ?? moment.timeZoneOffset);

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
}) {
  final formatter = _DateFormatter(language, numberingSystem);
  final at = offset ?? moment.timeZoneOffset;
  final datePart = formatter.formatField('df.${date.name}', moment, at);
  final timePart = formatter.formatField('tf.${time.name}', moment, at);
  // ({1} the date, {0} the time; quoted text literal.)
  final out = StringBuffer();
  for (final (literal, text) in _segments(
    formatter.field('dtfat.${date.name}')!,
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

/// A language's calendar fields, found through CLDR's parent locales.
final class _DateFormatter {
  new(String language, [String? numberingSystem])
    : _chain = _chainOf(language),
      _digits =
          (numberingSystemDigits(numberingSystem ?? '') ??
                  numberingSystemDigits(defaultNumberingSystem(language))!)
              .runes
              .toList(),
      _rules = _rulesOf(language);

  final List<String> _chain;
  final List<int> _digits;
  final List<(String, int, int?)> _rules;

  /// The locales [language]'s fields come from, most specific first: the
  /// first of its CLDR locales that CLDR has, then their parents.
  static List<String> _chainOf(String language) {
    final candidates = cldrLocales(language);
    final start = candidates.firstWhere(
      (l) => _gregorian.containsKey(l) || cldrNamesParent(l),
      orElse: () => candidates.isEmpty ? 'root' : candidates.last,
    );
    return [for (String? l = start; l != null; l = cldrParent(l)) l];
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

  /// [moment] at [offset] by the pattern [key] (`df.long`, `tf.short`),
  /// with the numbering it gives some fields.
  String formatField(String key, DateTime moment, Duration offset) => format(
    field(key)!,
    moment,
    offset,
    numbers: _fieldOf(key, '$key#numbers'),
  );

  /// The value of [numbers] from the locale [key] comes from (a pattern's
  /// numbering belongs to that pattern).
  String? _fieldOf(String key, String numbers) {
    for (final l in _chain) {
      if (_gregorian[l] case final fields? when fields.containsKey(key)) {
        return fields[numbers];
      }
    }
    return null;
  }

  /// The value of [key] (`df.long`, `M10`, `dwed`, `am`...), the root's
  /// aliases followed: abbreviated names as the wide ones, stand-alone as
  /// format, the "at" date-time pattern as the standard one.
  String? field(String key) {
    for (final l in _chain) {
      if (_gregorian[l]?[key] case final value?) return value;
    }
    final alias = switch (key) {
      _ when key.startsWith('dtfat.') => 'dtf.${key.substring(6)}',
      _ when key.startsWith('SD') => 'D${key.substring(2)}',
      _ when key.startsWith('sd') => 'd${key.substring(2)}',
      _ when key.startsWith('m') => 'M${key.substring(1)}',
      _ when key.startsWith('d') && key.length == 4 => 'D${key.substring(1)}',
      _ => null,
    };
    return alias == null ? null : field(alias);
  }

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

  /// [moment] at [offset] by [pattern] (UTS #35, Part 4, 8), the
  /// pattern's own numbering for some fields where it gives one
  /// ([numbers]: `M=romanlow`).
  String format(
    String pattern,
    DateTime moment,
    Duration offset, {
    String? numbers,
  }) {
    final overrides = <String, String>{
      for (final part in (numbers ?? '').split(';'))
        if (part.contains('=')) part.split('=')[0]: part.split('=')[1],
    };
    final wall = moment.toUtc().add(offset);
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
        if (overrides[c] case final system? when j - i <= 2) {
          out.write(_numbered(c, wall, system));
        } else {
          out.write(_field(c, j - i, wall, offset, hasMinute, hasSecond));
        }
        i = j;
      }
    }
    return '$out';
  }

  String _field(
    String letter,
    int count,
    DateTime wall,
    Duration offset,
    bool hasMinute,
    bool hasSecond,
  ) {
    final day = _days[wall.weekday - 1];
    return switch (letter) {
      'G' => field(wall.year > 0 ? 'era1' : 'era0') ?? '',
      'y' =>
        count == 2 ? _number(wall.year % 100, 2) : _number(wall.year, count),
      'M' || 'L' => switch (count) {
        1 || 2 => _number(wall.month, count),
        3 => field('m${wall.month}') ?? _number(wall.month),
        _ => field('M${wall.month}') ?? _number(wall.month),
      },
      'd' => _number(wall.day, count),
      'E' => count == 4 ? field('D$day')! : field('d$day')!,
      'c' => count == 4 ? field('SD$day')! : field('sd$day')!,
      'a' => field(wall.hour < 12 ? 'am' : 'pm')!,
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

  /// Numeric field [letter] of [wall] in the numbering system [system]
  /// (CLDR's: `romanlow` in lower-case roman numerals).
  String _numbered(String letter, DateTime wall, String system) {
    final value = switch (letter) {
      'M' || 'L' => wall.month,
      'd' => wall.day,
      'y' => wall.year,
      _ => 0,
    };
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
    for (final (period, from, before) in _rules) {
      if (before == null && exact && wall.hour * 60 == from) {
        if (field('p.$period') case final name?) return name;
      }
    }
    for (final (period, from, before) in _rules) {
      if (before == null) continue;
      final inside = from < before
          ? minutes >= from && minutes < before
          : minutes >= from || minutes < before;
      if (inside) {
        if (field('p.$period') case final name?) return name;
      }
    }
    return field(wall.hour < 12 ? 'am' : 'pm')!;
  }

  /// [offset] in the localized GMT format (`GMT+9`, long `GMT+09:00`;
  /// `GMT` for none).
  String _gmt(Duration offset, {required bool long}) {
    if (offset == Duration.zero) return field('gmtZero') ?? 'GMT';
    final hourFormat = (field('hour') ?? '+HH:mm;-HH:mm').split(';');
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
    return (field('gmt') ?? 'GMT{0}').replaceFirst('{0}', text);
  }
}
