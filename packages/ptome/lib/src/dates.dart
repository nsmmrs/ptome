/// Dates as the document's language writes them (Ptome; not under
/// `asciidoctor-compat`): the "Last updated" date and time and an ISO
/// `revdate` in CLDR's patterns for the language (`2026年10月14日`,
/// `14. Oktober 2026`, `١٤ أكتوبر ٢٠٢٦`), in the length `date-format`
/// names and the calendar `calendar` (or `lang`'s `-u-ca-`) names
/// (`令和8年10月14日`). The attributes themselves (`docdate`,
/// `localdatetime`...) stay ISO, as programs and formats read them.
library;

import 'package:plain_unicode/plain_unicode.dart';
import 'package:ptome/src/compat.dart';
import 'package:ptome/src/document.dart';
import 'package:ptome/src/numbering.dart';

/// The calendar [document] shows dates in: `calendar` (CLDR's name or
/// BCP 47's: `japanese`, `buddhist`, `roc`), else the one `lang`'s
/// `-u-ca-` names (`ja-u-ca-japanese`), else (or for a name it doesn't
/// know) the Gregorian.
CalendarSystem documentCalendar(Document document) =>
    CalendarSystem.named(document.attr('calendar') ?? '') ??
    CalendarSystem.ofLanguage(document.attr('lang') ?? '') ??
    CalendarSystem.gregorian;

/// The length [document] shows dates in: `date-format` (`short`,
/// `medium`, `long`, `full`; `iso` as written), by default `long` in a
/// document whose `lang` isn't English or whose calendar isn't the
/// Gregorian, else as written (null).
DateStyle? documentDateStyle(Document document) {
  if (anyAsciidoctorCompat(document)) return null;
  final lang = document.attr('lang')?.trim().toLowerCase() ?? '';
  return switch (document.attr('date-format')?.trim().toLowerCase()) {
    'short' => DateStyle.short,
    'medium' => DateStyle.medium,
    'long' => DateStyle.long,
    'full' => DateStyle.full,
    null
        when (lang.isNotEmpty && lang != 'en' && !lang.startsWith('en-')) ||
            documentCalendar(document) != CalendarSystem.gregorian =>
      DateStyle.long,
    _ => null,
  };
}

/// An ISO date (`2026-10-14`), with a time and its zone as
/// `docdatetime` writes them (`17:46:40 +0200`, `UTC`).
final RegExp _iso = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})'
  r'(?: (\d{2}):(\d{2}):(\d{2})(?: (UTC|[+-]\d{4}))?)?$',
);

/// [text] (an ISO date, or date and time) as [document] shows dates
/// ([documentDateStyle]), its time in the language's long time format
/// (with the zone's offset); [text] as it is otherwise.
String shownDate(Document document, String text) {
  final style = documentDateStyle(document);
  final m = _iso.firstMatch(text.trim());
  if (style == null || m == null) return text;
  final lang = document.attr('lang') ?? 'en';
  final calendar = documentCalendar(document);
  final zone = m[7];
  final offset = zone == null || zone == 'UTC'
      ? Duration.zero
      : Duration(
              hours: int.parse(zone.substring(1, 3)),
              minutes: int.parse(zone.substring(3)),
            ) *
            (zone.startsWith('-') ? -1 : 1);
  int part(int i) => int.parse(m[i] ?? '0');
  // (The wall-clock time, back to the moment it is at that offset.)
  final moment = DateTime.utc(
    part(1),
    part(2),
    part(3),
    part(4),
    part(5),
    part(6),
  ).subtract(offset);
  final system = numberingSystem(document);
  return m[4] == null
      ? formatDate(
          moment,
          lang,
          style: style,
          offset: offset,
          numberingSystem: system,
          calendar: calendar,
        )
      : formatDateTime(
          moment,
          lang,
          date: style,
          time: zone == null ? DateStyle.medium : DateStyle.long,
          offset: offset,
          numberingSystem: system,
          calendar: calendar,
        );
}
