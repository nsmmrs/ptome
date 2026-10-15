/// The ICU 78.3 date oracle (tool/oracles/icu/icudate) and what the date
/// tests share: the locales to compare, ICU's text for a batch of cases
/// (its answers recorded, oracles.dart), and the one way ICU's resolution may
/// differ from LDML's.
library;

import 'dart:io';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:plain_unicode/src/quotation_marks.dart' show cldrParent;

import 'oracles.dart';

const String icuDateOracle = 'tool/oracles/icu/icudate';

/// The oracle, which its answers depend on.
const String _version = 'ICU 78.3';

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
List<String> icuDateLocales(Oracle recorded) {
  final locales = {
    for (final line in File(
      'vendor/cldr/48.2.0/calendars.tsv',
    ).readAsLinesSync())
      if (line.isNotEmpty &&
          !line.startsWith('#') &&
          line.split('\t')[1].startsWith('gregorian/'))
        line.split('\t').first,
  }.where((l) => l != 'root' && _covered(l)).toList();
  final present = recorded
      .answer(
        'the locales ICU has',
        inputs: [_version, ...locales],
        oracle: () =>
            Process.runSync('sh', [
                  '-c',
                  'printf "%s\\n" "\$@" | "$icuDateOracle"',
                  'sh',
                  for (final l in locales) '?$l',
                ]).stdout
                as String,
      )
      .split('\n');
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
bool joinedInChain(
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
  final joiners = {
    '{1} {0}',
    for (final l in chain)
      for (final kind in ['gregorian', 'generic', calendar.cldrName])
        for (final variant in const ['standard', 'atTime'])
          ...?_joinerPatterns[l]?['$kind/dateTimeFormats/${date.name}/$variant'],
  };
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

/// calendars.tsv's date-time patterns: by locale, by path, the values.
final Map<String, Map<String, List<String>>> _joinerPatterns = () {
  final patterns = <String, Map<String, List<String>>>{};
  for (final line in File(
    'vendor/cldr/48.2.0/calendars.tsv',
  ).readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.split('\t') case [final l, final path, final value]
        when path.contains('/dateTimeFormats/')) {
      ((patterns[l] ??= {})[path] ??= []).add(value);
    }
  }
  return patterns;
}();

/// What ICU writes for each of [cases] (a locale, a date and a time
/// style, a moment, an offset in minutes, a calendar's BCP 47 name).
List<String> icuDates(
  Oracle recorded,
  String key,
  List<(String, DateStyle?, DateStyle?, DateTime, int, String)> cases,
) {
  final input = cases
      .map(
        (c) =>
            '${c.$1}\t${c.$2?.name ?? 'none'}\t${c.$3?.name ?? 'none'}\t'
            '${c.$4.millisecondsSinceEpoch}\t${c.$5}\t${c.$6}',
      )
      .join('\n');
  return recorded
      .answer(
        key,
        inputs: [_version, input],
        oracle: () {
          final dir = Directory.systemTemp.createTempSync('dates.');
          try {
            final file = File('${dir.path}/in.tsv')
              ..writeAsStringSync('$input\n');
            final r = Process.runSync('sh', [
              '-c',
              '"$icuDateOracle" < "${file.path}"',
            ]);
            if (r.exitCode != 0) throw StateError('${r.stderr}');
            return r.stdout as String;
          } finally {
            dir.deleteSync(recursive: true);
          }
        },
      )
      .split('\n');
}

/// Whether [icu] is [moment]'s date in [calendar] in [date]'s style as a
/// parent of [locale] writes it, in [locale]'s digits: ICU, which keeps a
/// calendar's patterns in one array, takes a parent's (resolved there)
/// where LDML's aliases take the locale's own generic pattern.
bool writtenInChain(
  String locale,
  String icu,
  DateTime moment,
  Duration offset,
  DateStyle date,
  CalendarSystem calendar,
) {
  for (var l = cldrParent(locale); l != null; l = cldrParent(l)) {
    final text = formatDate(
      moment,
      l,
      style: date,
      offset: offset,
      calendar: calendar,
      numberingSystem: defaultNumberingSystem(locale),
    );
    if (text == icu) return true;
  }
  return false;
}
