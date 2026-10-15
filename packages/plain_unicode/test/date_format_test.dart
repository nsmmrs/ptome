// Dates and times by language from CLDR 48.2, against ICU 78.3's
// DateFormat (tool/oracles/icu/icudate, Gregorian) for every locale CLDR
// has calendar data for: each date style alone, each time style alone and
// the pairs, at times of day that take each day period, in time zones at
// several offsets.
@TestOn('vm')
library;

import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

import 'support/icu_dates.dart';
import 'support/oracles.dart';

late final Oracle _recorded;

void main() {
  _recorded = Oracle('date_format', compressed: true);
  final moment = DateTime.utc(2026, 10, 14, 17, 46, 40);

  test('everyday languages', () {
    expect(formatDate(moment, 'ja'), '2026年10月14日');
    expect(formatDate(moment, 'de'), '14. Oktober 2026');
    expect(formatDate(moment, 'fr'), '14 octobre 2026');
    expect(formatDate(moment, 'en'), 'October 14, 2026');
    expect(formatDate(moment, 'en-GB'), '14 October 2026');
    expect(formatDate(moment, 'ar-EG'), '١٤ أكتوبر ٢٠٢٦');
    expect(formatDate(moment, 'zh'), '2026年10月14日');
    expect(formatDate(moment, 'de', style: DateStyle.short), '14.10.26');
    expect(
      formatDate(moment, 'fi', style: DateStyle.full),
      'keskiviikko 14. lokakuuta 2026',
    );
    expect(formatTime(moment, 'de'), '17:46:40');
    expect(
      formatTime(
        moment,
        'ja',
        style: DateStyle.long,
        offset: const Duration(hours: 9),
      ),
      '2:46:40 GMT+9',
    );
    // (UTC: the GMT zero format, UTS #35.)
    expect(
      formatTime(moment, 'en', style: DateStyle.long),
      '5:46:40\u202fPM GMT',
    );
    // (Hawaiian's months in lower-case roman numerals, its pattern's
    // numbers="M=romanlow".)
    expect(formatDate(moment, 'haw', style: DateStyle.short), '14/x/26');
    expect(
      formatDateTime(moment, 'zh-Hant', offset: const Duration(hours: 8)),
      '2026年10月15日 凌晨1:46:40',
    );
  });

  test('the calendars of eras, from -u-ca- or named', () {
    expect(formatDate(moment, 'ja-u-ca-japanese'), '令和8年10月14日');
    expect(formatDate(DateTime.utc(2019, 5), 'ja-u-ca-japanese'), '令和元年5月1日');
    expect(
      formatDate(
        DateTime.utc(2019, 4, 30),
        'ja',
        calendar: CalendarSystem.japanese,
      ),
      '平成31年4月30日',
    );
    expect(
      formatDate(
        moment,
        'en',
        style: DateStyle.full,
        calendar: CalendarSystem.japanese,
      ),
      'Wednesday, October 14, 8 Reiwa',
    );
    expect(formatDate(moment, 'th-u-ca-buddhist'), '14 ตุลาคม 2569');
    expect(formatDate(moment, 'zh-Hant-u-ca-roc'), '民國115年10月14日');
    expect(formatDate(DateTime.utc(1900), 'zh-Hant-u-ca-roc'), '民國前12年1月1日');
    expect(
      CalendarSystem.ofLanguage('ja-JP-u-ca-japanese'),
      CalendarSystem.japanese,
    );
    expect(
      CalendarSystem.ofLanguage('th-u-nu-thai-ca-buddhist'),
      CalendarSystem.buddhist,
    );
    expect(CalendarSystem.ofLanguage('ja'), isNull);
    expect(CalendarSystem.named('gregory'), CalendarSystem.gregorian);
    expect(CalendarSystem.named('Japanese'), CalendarSystem.japanese);
  });

  test("every locale as ICU 78.3's", () {
    final locales = icuDateLocales(_recorded);
    expect(locales.length, greaterThan(300));
    // (Midnight, early morning, noon, afternoon and evening; zones from
    // UTC, ahead and behind, by whole and part hours.)
    final moments = [
      DateTime.utc(2026, 10, 14, 17, 46, 40),
      DateTime.utc(2026, 1, 3),
      DateTime.utc(2026, 6, 21, 12),
      DateTime.utc(2026, 3, 9, 6, 5, 9),
      DateTime.utc(1999, 12, 31, 21, 30),
    ];
    // (Not UTC: ICU writes a nameless zone at no offset `GMT+0`, where
    // UTS #35 has the GMT zero format, `GMT`; tested apart.)
    const offsets = [60, 540, -330, 345];
    const styles = [null, ...DateStyle.values];
    final cases = <(String, DateStyle?, DateStyle?, DateTime, int, String)>[];
    // (Each locale's styles at a moment each, the moments taken in turn:
    // every style at every moment, across the locales.)
    for (final (l, locale) in locales.indexed) {
      var n = l;
      for (final date in styles) {
        for (final time in styles) {
          if (date == null && time == null) continue;
          final i = n++ % moments.length;
          cases.add((
            locale,
            date,
            time,
            moments[i],
            offsets[i % offsets.length],
            'gregory',
          ));
        }
      }
    }
    final theirs = icuDates(_recorded, 'gregorian', cases);
    final differ = <String>[];
    for (final (i, (locale, date, time, m, minutes, _)) in cases.indexed) {
      final offset = Duration(minutes: minutes);
      final ours = switch ((date, time)) {
        (final d?, null) => formatDate(m, locale, style: d, offset: offset),
        (null, final t?) => formatTime(m, locale, style: t, offset: offset),
        (final d?, final t?) => formatDateTime(
          m,
          locale,
          date: d,
          time: t,
          offset: offset,
        ),
        _ => '',
      };
      // (ICU keeps a locale's "at" date-time patterns as one array, so
      // French in Mali, with standard patterns of its own and no "at"
      // ones, takes French's whole: French's short pattern, where
      // LDML resolves the root's alias from Mali's own.)
      final mali = locale == 'fr-ML' && date != null && time != null;
      if (ours != theirs[i] && !mali) {
        differ.add(
          '$locale ${date?.name} ${time?.name} $m $minutes: '
          '"$ours" ICU "${theirs[i]}"',
        );
      }
    }
    expect(differ, isEmpty, reason: differ.take(20).join('\n'));
  });

  test('the Japanese, Buddhist and ROC calendars as ICU 78.3 writes them', () {
    final locales = icuDateLocales(_recorded);
    // (Each side of the Heisei, Reiwa, Showa and Minguo eras' starts, at
    // noon in Tokyo; and today.)
    final moments = [
      for (final (y, m, d) in [
        (2019, 4, 30),
        (2019, 5, 1),
        (1989, 1, 7),
        (1989, 1, 8),
        (1926, 12, 24),
        (1926, 12, 25),
        (1911, 12, 31),
        (1912, 1, 1),
        (2026, 10, 14),
      ])
        DateTime.utc(y, m, d, 3),
    ];
    const pairs = [
      (DateStyle.full, null),
      (DateStyle.long, null),
      (DateStyle.medium, null),
      (DateStyle.short, null),
      (DateStyle.long, DateStyle.short),
    ];
    // (Every moment in the calendar's own language; in the others, a
    // moment for each style, taken in turn.)
    final cases = [
      for (final (calendar, home) in const [
        (CalendarSystem.japanese, 'ja'),
        (CalendarSystem.buddhist, 'th'),
        (CalendarSystem.roc, 'zh-Hant'),
      ])
        for (final (l, locale) in locales.indexed)
          for (final (p, (date, time)) in pairs.indexed)
            for (final (i, m) in moments.indexed)
              if (locale == home || i == (l + p) % moments.length)
                (locale, date, time, m, 540, calendar.bcp47Name),
    ];
    final theirs = icuDates(_recorded, 'Japanese, Buddhist and ROC', cases);
    final differ = <String>[];
    for (final (i, (locale, date, time, m, minutes, name)) in cases.indexed) {
      final calendar = CalendarSystem.named(name)!;
      final offset = Duration(minutes: minutes);
      final ours = time == null
          ? formatDate(
              m,
              locale,
              style: date,
              offset: offset,
              calendar: calendar,
            )
          : formatDateTime(
              m,
              locale,
              date: date,
              time: time,
              offset: offset,
              calendar: calendar,
            );
      // (ICU keeps a calendar's date and time patterns in one array,
      // resolved where the array is, and takes the Gregorian calendar's
      // "at" pattern where the calendar has none: its time and joiner
      // may come from a parent locale's Gregorian or generic data where
      // LDML's aliases take the locale's own. Allowed only as that: our
      // date, a time as a locale of the chain writes it, joined by a
      // pattern of the chain's.)
      if (ours != theirs[i] &&
          time != null &&
          joinedInChain(locale, theirs[i], m, offset, date, time, calendar)) {
        continue;
      }
      if (ours != theirs[i]) {
        differ.add(
          '$locale $name ${date.name} ${time?.name} $m: '
          '"$ours" ICU "${theirs[i]}"',
        );
      }
    }
    expect(
      differ,
      isEmpty,
      reason: '${differ.length}:\n${differ.take(30).join('\n')}',
    );
  });
}
