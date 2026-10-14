/// The numbers a document generates, in its language's numerals (Ptome;
/// not under `asciidoctor-compat`): its sections', captions', footnotes'
/// and list items' numbers in the numbering system CLDR gives its
/// language (Arabic-Indic digits in Egyptian Arabic, Persian ones in
/// Persian, Devanagari in Marathi) or the one `numbering-system` names;
/// and an ordered list in any counter style CSS defines (`[hiragana]`,
/// `[cjk-ideographic]`, `[hebrew]`, `[lower-russian]`...).
library;

import 'package:plain_unicode/plain_unicode.dart';
import 'package:ptome/src/compat.dart';
import 'package:ptome/src/context.dart';
import 'package:ptome/src/document.dart';
import 'package:ptome/src/list.dart';

/// The ordered list styles Asciidoctor knows, which keep its numbering.
const Set<String> _asciidoctorStyles = {
  'arabic',
  'decimal',
  'loweralpha',
  'upperalpha',
  'lowerroman',
  'upperroman',
  'lowergreek',
  'unstyled',
  'unnumbered',
  'no-bullet',
  'none',
};

/// The numbering system (CLDR's id: `latn`, `arab`, `arabext`, `deva`...)
/// [document] writes its generated numbers in: `numbering-system` where it
/// names one, else the default of its `lang` (CLDR's
/// `defaultNumberingSystem`, `-u-nu-` honored); `latn` under
/// `asciidoctor-compat` or without a language.
String numberingSystem(Document document) {
  if (anyAsciidoctorCompat(document)) return 'latn';
  if (document.attr('numbering-system')?.trim().toLowerCase() case final id?
      when numberingSystemDigits(id) != null) {
    return id;
  }
  return switch (document.attr('lang')) {
    final lang? when lang.trim().isNotEmpty => defaultNumberingSystem(lang),
    _ => 'latn',
  };
}

/// [text] with its digits 0 to 9 in [document]'s [numberingSystem].
String localDigits(Document document, String text) {
  final system = numberingSystem(document);
  if (system == 'latn') return text;
  final digits = numberingSystemDigits(system)!.runes.toList();
  return String.fromCharCodes([
    for (final c in text.runes)
      if (c >= 0x30 && c <= 0x39) digits[c - 0x30] else c,
  ]);
}

/// The counter style of the ordered list [list] (Ptome's): the style it
/// names where CSS defines one Asciidoctor doesn't know (`hiragana`), or,
/// numbered in decimal in a document whose [numberingSystem] isn't
/// `latn`, that system's; null where Asciidoctor's numbering stands (and
/// under `asciidoctor-compat`).
CounterStyle? listCounterStyle(ListBlock list) {
  final document = list.document;
  if (document is! Document || anyAsciidoctorCompat(document)) return null;
  final style = list.style;
  if (style != null && !_asciidoctorStyles.contains(style)) {
    return CounterStyle.named(style);
  }
  if (style == null || style == 'arabic' || style == 'decimal') {
    final system = numberingSystem(document);
    if (system != 'latn') return CounterStyle.forNumberingSystem(system);
  }
  return null;
}

/// The `@counter-style` rules of the counter styles [document]'s ordered
/// lists use that browsers don't predefine (CSS Counter Styles 3);
/// empty where they use none.
String counterStyleCss(Document document, CompatFormat format) {
  if (asciidoctorCompat(document, format)) return '';
  final rules = <String, String>{};
  for (final block in document.findBy(
    context: BlockContext.olist,
    traverseDocuments: true,
  )) {
    if (block is! ListBlock) continue;
    final style = listCounterStyle(block);
    if (style == null || style.predefined) continue;
    rules[style.name] ??= style.cssRule;
  }
  return rules.values.map((rule) => '$rule\n').join();
}
