/// Quotation marks in the text's language (Ptome; not under
/// `asciidoctor-compat`).
library;

import 'package:plain_unicode/plain_unicode.dart'
    show QuotationMarks, quotationMarks;
import 'package:ptome/src/abstract_node.dart';
import 'package:ptome/src/compat.dart';
import 'package:ptome/src/document.dart';

/// The quotation marks of [node]'s language (its own `lang`, its block's,
/// the document's), CLDR's, for AsciiDoc's typographic quotes; null where
/// they are English's `“ ” ‘ ’` (written as Asciidoctor writes them), where
/// no language is given, or where `asciidoctor-compat` names [format].
QuotationMarks? languageQuotationMarks(AbstractNode node, CompatFormat format) {
  final document = switch (node) {
    final Document d => d,
    _ => node.document,
  };
  if (document is! Document || asciidoctorCompat(document, format)) {
    return null;
  }
  String? language;
  for (AbstractNode? n = node; n != null; n = n.parent) {
    if (n.attributes['lang'] case final lang? when lang.isNotEmpty) {
      language = lang;
      break;
    }
  }
  language ??= document.attr('lang');
  if (language == null || language.isEmpty) return null;
  final marks = quotationMarks(language);
  return marks == _english ? null : marks;
}

final QuotationMarks _english = quotationMarks('en');
