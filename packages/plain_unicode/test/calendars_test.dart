// The calendars that convert, against ICU 78.3's DateFormat
// (tool/oracles/icu/icudate): the Islamic calendar's tabular, Umm al-Qura
// and astronomical forms, the Hebrew, Persian, Coptic, Ethiopic, Indian
// national, Chinese and Korean calendars. Their days across three
// centuries, every eleventh, in English and a language that uses the
// calendar; and every covered locale's names and patterns on a few days.
//
// The calendars that follow the sky differ from ICU's, whose astronomy is
// less precise (its Persian calendar a 33-year cycle with corrections,
// its Chinese calendar in UTC+8 before 1929 too), only where an event
// falls within minutes of the moment that decides the day: a new moon or
// a major solar term near midnight, the March equinox near noon in
// Tehran. Each such difference is checked to be one. (Against the Hong
// Kong Observatory's tables, 1901 to 2100, ours agree in every month where
// ICU's differ but one of 1906: the almanac computed then set a new moon
// 8 minutes before midnight on the next day.)
@TestOn('vm')
library;

import 'dart:io';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:plain_unicode/src/astronomy.dart';
import 'package:plain_unicode/src/calendars.dart';
import 'package:test/test.dart';

import 'support/icu_dates.dart';

/// The calendars checked, and a language that writes dates in each.
const Map<CalendarSystem, String> _calendars = {
  CalendarSystem.islamicCivil: 'ar',
  CalendarSystem.islamicTbla: 'ar',
  CalendarSystem.islamicUmalqura: 'ar-SA',
  CalendarSystem.hebrew: 'he',
  CalendarSystem.coptic: 'ar-EG',
  CalendarSystem.ethiopic: 'am',
  CalendarSystem.ethiopicAmeteAlem: 'am',
  CalendarSystem.indian: 'hi',
  CalendarSystem.persian: 'fa',
  CalendarSystem.islamic: 'ar',
  CalendarSystem.chinese: 'zh',
  CalendarSystem.dangi: 'ko',
};

/// The calendars by the new moons, and the zones (hours from UT, on a
/// day) that ours and ICU's decide their days in.
final Map<CalendarSystem, List<double Function(int day)>> _zones = {
  CalendarSystem.islamic: [(_) => 0],
  CalendarSystem.chinese: [
    (day) => day < gregorianDay(1929, 1, 1) ? 1397 / 180 : 8,
    (_) => 8,
  ],
  CalendarSystem.dangi: [
    (day) => day < gregorianDay(1912, 1, 1) ? 8 : 9,
    (day) => day < gregorianDay(1912, 1, 1)
        ? (gregorianDate(day).year == 1897 ? 7 : 8)
        : 9,
  ],
};

/// Whether a new moon (or, with [terms], a major solar term) between days
/// [from] and [to] falls within 15 minutes of midnight in one of
/// [calendar]'s zones (60 after 2100, where ΔT is extrapolated and ICU's
/// astronomy, which leaves it out, drifts), or on different days in two.
bool _nearMidnight(
  CalendarSystem calendar,
  int from,
  int to, {
  bool terms = false,
}) {
  final events = <double>[
    for (var t = newMoonAfter(from - 1.0); t < to + 1; t = newMoonAfter(t)) t,
  ];
  if (terms) {
    for (var degrees = 0.0; degrees < 360; degrees += 30) {
      for (
        var t = sunReaches(degrees, from - 1.0);
        t < to + 1;
        t = sunReaches(degrees, t + 300)
      ) {
        events.add(t);
      }
    }
  }
  final zones = _zones[calendar]!;
  for (final t in events) {
    final days = {for (final zone in zones) (t + zone(t.floor()) / 24).floor()};
    if (days.length > 1) return true;
    for (final zone in zones) {
      final local = t + zone(t.floor()) / 24;
      final fraction = local - local.floor();
      final limit = gregorianDate(t.floor()).year > 2100 ? 60 : 15;
      if ((fraction < 0.5 ? fraction : 1 - fraction) * 1440 <= limit) {
        return true;
      }
    }
  }
  return false;
}

/// Whether [calendar]'s day [day] differing from ICU's is one that an
/// event near the moment that decides it explains: in the Persian
/// calendar, the year's March equinox within 15 minutes of noon in Tehran;
/// in the others, the month's first or last day off by one (a new moon
/// near it) or the leap month placed otherwise (a new moon or a major
/// solar term within two months).
bool _decidedNearTheMoment(CalendarSystem calendar, int day) {
  if (calendar == CalendarSystem.persian) {
    final year = persian(day).year;
    final equinox = sunReaches(0, gregorianDay(year + 621, 3, 1).toDouble());
    final tehran = equinox + 3.5 / 24;
    return ((tehran - tehran.floor() - 0.5) * 1440).abs() <= 15;
  }
  final ours = switch (calendar) {
    CalendarSystem.chinese => chinese(day),
    CalendarSystem.dangi => dangi(day),
    _ => islamicAstronomical(day),
  };
  // (The month's first day, or the next month's: the day its last.)
  final start = day - ours.day + 1;
  return _nearMidnight(calendar, start - 2, day + 2) ||
      (calendar != CalendarSystem.islamic &&
          _nearMidnight(calendar, start - 60, start + 60, terms: true));
}

/// [cases] ours against ICU's: the cases that differ, other than those
/// ICU's resolution of the patterns or its astronomy explains.
List<String> _differing(
  List<(String, DateStyle?, DateStyle?, DateTime, int, String)> cases,
) {
  final theirs = icuDates(cases);
  final differ = <String>[];
  final decided = <(CalendarSystem, int), bool>{};
  for (final (i, (locale, date, time, m, minutes, name)) in cases.indexed) {
    final calendar = CalendarSystem.named(name)!;
    final offset = Duration(minutes: minutes);
    final ours = time == null
        ? formatDate(
            m,
            locale,
            style: date!,
            offset: offset,
            calendar: calendar,
          )
        : formatDateTime(
            m,
            locale,
            date: date!,
            time: time,
            offset: offset,
            calendar: calendar,
          );
    if (ours == theirs[i]) continue;
    // (Where ICU's resolution differs from LDML's: a time or a pattern
    // from a parent locale; see support/icu_dates.dart.)
    final explained = time == null
        ? writtenInChain(locale, theirs[i], m, offset, date, calendar)
        : joinedInChain(locale, theirs[i], m, offset, date, time, calendar);
    if (explained) continue;
    if (_zones.containsKey(calendar) || calendar == CalendarSystem.persian) {
      final wall = m.toUtc().add(offset);
      final day = gregorianDay(wall.year, wall.month, wall.day);
      if (decided[(calendar, day)] ??= _decidedNearTheMoment(calendar, day)) {
        continue;
      }
    }
    differ.add(
      '$locale $name ${date.name} ${time?.name} ${m.toIso8601String()}: '
      '"$ours" ICU "${theirs[i]}"',
    );
  }
  return differ;
}

void main() {
  final skip = File(icuDateOracle).existsSync()
      ? false
      : 'run tool/oracles/icu/setup.sh';

  test('everyday dates in each', () {
    final m = DateTime.utc(2026, 10, 14, 12);
    String date(String language, CalendarSystem calendar, [DateTime? at]) =>
        formatDate(at ?? m, language, calendar: calendar);
    // (Rosh Hashanah 5787 on 12 September 2026; Hebrew numerals, the
    // year without its thousands.)
    expect(date('he', CalendarSystem.hebrew), 'ג׳ בחשוון תשפ״ז');
    expect(date('en', CalendarSystem.hebrew), '3 Heshvan 5787');
    expect(
      date('en', CalendarSystem.hebrew, DateTime.utc(2024, 3, 20, 12)),
      '10 Adar II 5784',
    );
    expect(date('fa', CalendarSystem.persian), '۲۲ مهر ۱۴۰۵');
    expect(date('zh', CalendarSystem.chinese), '2026丙午年九月初五');
    // (The new moon of 10 October 2026, 23:50 in Beijing, 00:50 in Seoul.)
    expect(date('ko', CalendarSystem.dangi), '병오년 9월 4일');
    // (1987's leap sixth month.)
    expect(
      date('zh', CalendarSystem.chinese, DateTime.utc(1987, 8, 1, 12)),
      '1987丁卯年闰六月初七',
    );
    expect(
      date('ar', CalendarSystem.islamicUmalqura),
      '3 جمادى الأولى 1448 هـ',
    );
    expect(date('en', CalendarSystem.islamic), 'Jumada I 4, 1448 AH');
    expect(date('am', CalendarSystem.ethiopic), '4 ጥቅምት 2019 AM');
    expect(date('hi', CalendarSystem.indian), '22 अश्विन 1948 शक');
    expect(date('en', CalendarSystem.coptic), 'Baba 4, 1743 AM');
    expect(
      CalendarSystem.ofLanguage('fa-u-ca-persian'),
      CalendarSystem.persian,
    );
    expect(
      CalendarSystem.ofLanguage('ar-SA-u-ca-islamic-umalqura'),
      CalendarSystem.islamicUmalqura,
    );
    expect(CalendarSystem.named('ethioaa'), CalendarSystem.ethiopicAmeteAlem);
  });

  test(
    'their days, 1880 to 2180',
    () {
      final days = [
        for (
          var d = DateTime.utc(1880);
          d.isBefore(DateTime.utc(2180));
          d = d.add(const Duration(days: 11))
        )
          d.add(const Duration(hours: 12)),
      ];
      final cases = [
        for (final MapEntry(key: calendar, value: language)
            in _calendars.entries)
          for (final locale in ['en', language])
            for (final style in const [DateStyle.long, DateStyle.short])
              for (final d in days)
                (locale, style, null, d, 0, calendar.bcp47Name),
      ];
      final differ = _differing(cases);
      expect(
        differ,
        isEmpty,
        reason: '${differ.length}:\n${differ.take(30).join('\n')}',
      );
    },
    tags: ['tools'],
    skip: skip,
  );

  test(
    "every locale's names and patterns",
    () {
      final locales = icuDateLocales();
      final days = [
        for (final (y, m, d) in const [
          (2024, 3, 1),
          (2024, 3, 20),
          (2025, 3, 1),
          (2026, 10, 14),
          (2027, 1, 30),
        ])
          DateTime.utc(y, m, d, 12),
      ];
      const pairs = [
        (DateStyle.full, null),
        (DateStyle.long, null),
        (DateStyle.medium, null),
        (DateStyle.short, null),
        (DateStyle.long, DateStyle.short),
      ];
      final cases = [
        for (final calendar in _calendars.keys)
          for (final locale in locales)
            for (final (date, time) in pairs)
              for (final d in days)
                (locale, date, time, d, 180, calendar.bcp47Name),
      ];
      final differ = _differing(cases);
      expect(
        differ,
        isEmpty,
        reason: '${differ.length}:\n${differ.take(30).join('\n')}',
      );
    },
    tags: ['tools'],
    skip: skip,
  );
}
