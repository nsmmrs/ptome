// Dates and times by language from CLDR 48.2, against ICU 78.3's
// DateFormat (tool/oracles/icu/icudate, Gregorian) for every locale CLDR
// has calendar data for: each date style alone, each time style alone and
// the pairs, at times of day that take each day period, in time zones at
// several offsets.
@TestOn('vm')
library;

import 'dart:io';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:plain_unicode/src/quotation_marks.dart' show cldrParent;
import 'package:test/test.dart';

const String _oracle = 'tool/oracles/icu/icudate';

/// The languages CLDR targets at basic coverage or more
/// (common/properties/coverageLevels.txt, 48.2): ICU 78.3 packages the
/// others' data trimmed (Afar's times, Rohingya's, Hawaiian's).
const Set<String> _coverage = {
  'af', 'ak', 'am', 'ar', 'as', 'ast', 'az', 'ba', 'bal-Latn', 'be', 'bg', //
  'bgc', 'bho', 'blo', 'bn', 'br', 'brx', 'bs', 'bs-Cyrl', 'bua', 'ca',
  'ceb', 'chr', 'cs', 'csw', 'cv', 'cy', 'da', 'de', 'doi', 'dsb', 'ee',
  'el', 'en', 'eo', 'es', 'et', 'eu', 'fa', 'ff-Adlm', 'fi', 'fil', 'fo',
  'fr', 'fy', 'ga', 'gaa', 'gd', 'gl', 'gu', 'ha', 'he', 'hi', 'hi-Latn',
  'hr', 'hsb', 'hu', 'hy', 'ia', 'id', 'ie', 'ig', 'ii', 'is', 'it', 'ja',
  'jv', 'ka', 'kea', 'kgp', 'kk', 'kk-Arab', 'km', 'kn', 'ko', 'kok',
  'kok-Latn', 'ks', 'ks-Deva', 'ku', 'kxv', 'kxv-Deva', 'kxv-Orya',
  'kxv-Telu', 'ky', 'lb', 'lij', 'lmo', 'lo', 'lt', 'lv', 'mai', 'mi', 'mk',
  'ml', 'mn', 'mni', 'mr', 'ms', 'mt', 'my', 'nds', 'ne', 'nl', 'nn', 'no',
  'nqo', 'nso', 'oc', 'om', 'or', 'pa', 'pcm', 'pl', 'pms', 'ps', 'pt', 'qu',
  'raj', 'rm', 'ro', 'ru', 'rw', 'sa', 'sah', 'sat', 'sc', 'scn', 'sd',
  'sd-Deva', 'shn', 'si', 'sk', 'sl', 'so', 'sq', 'sr', 'sr-Latn', 'st',
  'su', 'sv', 'sw', 'syr', 'szl', 'ta', 'te', 'tg', 'th', 'ti', 'tk', 'tn',
  'to', 'tr', 'tt', 'tyv', 'ug', 'uk', 'ur', 'uz', 'uz-Cyrl', 'vec', 'vi',
  'vmw', 'wo', 'xh', 'xnr', 'yo', 'yrl', 'yue', 'yue-Hans', 'za', 'zh',
  'zh-Hant', 'zu',
};

/// Whether [locale] is one of a covered language's (or script's).
bool _covered(String locale) {
  final parts = locale.split('-');
  return _coverage.contains(parts.first) ||
      (parts.length > 1 && _coverage.contains('${parts[0]}-${parts[1]}'));
}

/// The covered locales CLDR has calendar data for and ICU's data has
/// (it falls back otherwise).
List<String> _locales() {
  final locales = {
    for (final line in File(
      'vendor/cldr/48.2.0/calendars.tsv',
    ).readAsLinesSync())
      if (line.isNotEmpty &&
          !line.startsWith('#') &&
          line.split('\t')[1].startsWith('gregorian/'))
        line.split('\t').first,
  }.where((l) => l != 'root' && _covered(l)).toList();
  final has = Process.runSync('sh', [
    '-c',
    'printf "%s\\n" "\$@" | "$_oracle"',
    'sh',
    for (final l in locales) '?$l',
  ]);
  final present = '${has.stdout}'.split('\n');
  final kept = {
    for (final (i, l) in locales.indexed)
      if (present[i] == '1') l,
  };
  return locales..retainWhere(kept.contains);
}

/// Whether [icu] is [moment]'s date in [calendar] as [locale] writes it
/// in [date]'s style, and its time in [time]'s as [locale] or a parent
/// writes it in the Gregorian calendar (in [locale]'s digits), joined by
/// a date-time pattern of [date]'s length from [locale] or a parent (the
/// calendar's own, the generic or the Gregorian).
bool _joinedInChain(
  String locale,
  String icu,
  DateTime moment,
  Duration offset,
  DateStyle date,
  DateStyle time,
  CalendarSystem calendar,
) {
  final chain = [for (String? l = locale; l != null; l = cldrParent(l)) l];
  final datePart = formatDate(
    moment,
    locale,
    style: date,
    offset: offset,
    calendar: calendar,
  );
  final times = {
    for (final l in chain)
      formatTime(
        moment,
        l,
        style: time,
        offset: offset,
        // (In the locale's own digits.)
        numberingSystem: defaultNumberingSystem(locale),
      ),
  };
  final joiners = {'{1} {0}'};
  for (final [l, path, value] in _calendarLines) {
    if (!chain.contains(l)) continue;
    for (final kind in ['gregorian', 'generic', calendar.cldrName]) {
      for (final variant in const ['standard', 'atTime']) {
        if (path == '$kind/dateTimeFormats/${date.name}/$variant') {
          joiners.add(value);
        }
      }
    }
  }
  for (final joiner in joiners) {
    final pattern = joiner.replaceAll("''", '\u0001').replaceAll("'", '');
    for (final t in times) {
      final text = pattern
          .replaceAll('{1}', '\u0000')
          .replaceAll('{0}', t)
          .replaceAll('\u0000', datePart)
          .replaceAll('\u0001', "'");
      if (text == icu) return true;
    }
  }
  return false;
}

/// calendars.tsv's lines: a locale, a path, a value.
final List<List<String>> _calendarLines = [
  for (final line in File('vendor/cldr/48.2.0/calendars.tsv').readAsLinesSync())
    if (line.isNotEmpty && !line.startsWith('#')) line.split('\t'),
];

/// What ICU writes for each of [cases] (a locale, a date and a time
/// style, a moment, an offset in minutes, a calendar's BCP 47 name).
List<String> _icu(
  List<(String, DateStyle?, DateStyle?, DateTime, int, String)> cases,
) {
  final input = cases
      .map(
        (c) =>
            '${c.$1}\t${c.$2?.name ?? 'none'}\t${c.$3?.name ?? 'none'}\t'
            '${c.$4.millisecondsSinceEpoch}\t${c.$5}\t${c.$6}',
      )
      .join('\n');
  final dir = Directory.systemTemp.createTempSync('dates.');
  try {
    final file = File('${dir.path}/in.tsv')..writeAsStringSync('$input\n');
    final r = Process.runSync('sh', ['-c', '"$_oracle" < "${file.path}"']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return '${r.stdout}'.split('\n');
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
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

  test(
    "every locale as ICU 78.3's",
    () {
      final locales = _locales();
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
      for (final locale in locales) {
        for (final date in styles) {
          for (final time in styles) {
            if (date == null && time == null) continue;
            for (final (i, m) in moments.indexed) {
              cases.add((
                locale,
                date,
                time,
                m,
                offsets[i % offsets.length],
                'gregory',
              ));
            }
          }
        }
      }
      final theirs = _icu(cases);
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
    },
    tags: ['tools'],
    skip: File(_oracle).existsSync() ? false : 'run tool/oracles/icu/setup.sh',
  );

  test(
    'the Japanese, Buddhist and ROC calendars as ICU 78.3 writes them',
    () {
      final locales = _locales();
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
      final cases = [
        for (final calendar in CalendarSystem.values.skip(1))
          for (final locale in locales)
            for (final (date, time) in pairs)
              for (final m in moments)
                (locale, date, time, m, 540, calendar.bcp47Name),
      ];
      final theirs = _icu(cases);
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
            _joinedInChain(
              locale,
              theirs[i],
              m,
              offset,
              date,
              time,
              calendar,
            )) {
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
    },
    tags: ['tools'],
    skip: File(_oracle).existsSync() ? false : 'run tool/oracles/icu/setup.sh',
  );
}
