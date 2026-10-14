/// The quotation marks of a language, from CLDR's `delimiters` (48.2,
/// resolved): the most specific of the language's locales that matches
/// (or the parent CLDR names for it, `parentLocales`), its script the
/// likely one (`likelySubtags`) where it names none; a language in
/// another script has the root's (CLDR's `nonlikelyScript` rule).
library;

import 'package:meta/meta.dart';

part 'quotation_marks.g.dart';

/// A language's quotation marks: the outer pair, and the pair for a
/// quotation inside a quotation.
@immutable
final class QuotationMarks {
  const new _(this.start, this.end, this.alternateStart, this.alternateEnd);

  /// The opening mark (`“` in English, `«` in French, `„` in German,
  /// `「` in Japanese).
  final String start;

  /// The closing mark.
  final String end;

  /// The opening mark of a quotation inside one (`‘` in English, `『` in
  /// Japanese).
  final String alternateStart;

  /// Its closing mark.
  final String alternateEnd;

  @override
  bool operator ==(Object other) =>
      other is QuotationMarks &&
      other.start == start &&
      other.end == end &&
      other.alternateStart == alternateStart &&
      other.alternateEnd == alternateEnd;

  @override
  int get hashCode => Object.hash(start, end, alternateStart, alternateEnd);

  @override
  String toString() => '$start…$end $alternateStart…$alternateEnd';
}

/// The quotation marks of [language] (a BCP 47 tag: `fr`, `de-CH`,
/// `zh-TW`, `sr-Latn`), CLDR's; the root locale's (English's `“ ” ‘ ’`)
/// for a language CLDR doesn't have.
QuotationMarks quotationMarks(String language) {
  for (final candidate in cldrLocales(language)) {
    // (A locale CLDR has, or one it names a parent for: `pt-FR`, `pt-PT`.)
    for (String? l = candidate; l != null; l = _parents[l]) {
      if (_locales[l] case final i?) return _marks[i];
      if (_parents[l] == 'root') return _marks[_locales['root']!];
    }
  }
  return _marks[_locales['root']!];
}

/// The CLDR locales [language] (a BCP 47 tag) matches, most specific
/// first, with hyphens (`zh-Hant-TW`, `zh-TW`, `zh-Hant`, `zh`): its
/// script, where it names none, the likely one (`likelySubtags`); a
/// language in another script than its likely one not matching the
/// language alone (CLDR's `nonlikelyScript` rule).
List<String> cldrLocales(String language) {
  final subtags = language.trim().replaceAll('_', '-').split('-');
  final lang = subtags.first.toLowerCase();
  String? script;
  String? region;
  for (final subtag in subtags.skip(1)) {
    // (Up to the variants, extensions and private use.)
    if (subtag.length == 1) break;
    if (script == null && region == null && subtag.length == 4) {
      script = subtag[0].toUpperCase() + subtag.substring(1).toLowerCase();
    } else if (region == null &&
        (subtag.length == 2 ||
            (subtag.length == 3 && int.tryParse(subtag) != null))) {
      region = subtag.toUpperCase();
    }
  }
  final likely =
      (region == null ? null : _scripts['$lang-$region']) ?? _scripts[lang];
  script ??= likely;
  final usual = script == likely;
  return [
    if (script != null && region != null) '$lang-$script-$region',
    if (region != null && usual) '$lang-$region',
    if (script != null) '$lang-$script',
    if (usual) lang,
  ];
}
