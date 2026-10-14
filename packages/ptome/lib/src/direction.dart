/// A document's direction and writing mode for HTML and EPUB (Ptome; not
/// under `asciidoctor-compat`): `:dir: rtl` (as HTML's `dir`) and
/// `:writing-mode:` (`vertical-rl`, `vertical-lr`, as CSS's), and the
/// stylesheet that sets them.
library;

import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/compat.dart';
import 'package:ptome/src/document.dart';
import 'package:ptome/src/inline_tree.dart';

/// `rtl` where [document] is written right to left, else null.
String? documentDirection(Document document, CompatFormat format) {
  if (asciidoctorCompat(document, format)) return null;
  return document.attr('dir')?.trim().toLowerCase() == 'rtl' ? 'rtl' : null;
}

/// `vertical-rl` or `vertical-lr` where [document] is written in vertical
/// lines, else null.
String? documentWritingMode(Document document, CompatFormat format) {
  if (asciidoctorCompat(document, format)) return null;
  return switch (document.attr('writing-mode')?.trim().toLowerCase()) {
    final mode? when mode == 'vertical-rl' || mode == 'vertical-lr' => mode,
    _ => null,
  };
}

/// Whether [document]'s pages turn to the left (EPUB's
/// `page-progression-direction="rtl"`): written right to left, or in
/// vertical lines following to the left.
bool pagesTurnLeft(Document document, CompatFormat format) =>
    documentDirection(document, format) == 'rtl' ||
    documentWritingMode(document, format) == 'vertical-rl';

/// The rules that set [document]'s writing modes (its own, its blocks'
/// `vertical-rl`, `vertical-lr` and `horizontal-tb` roles, the `tcy`
/// role's tate-chu-yoko), with the `-epub-` and `-webkit-` prefixes older
/// reading systems need; empty where it has none.
String writingModeCss(Document document, CompatFormat format) {
  if (asciidoctorCompat(document, format)) return '';
  final mode = documentWritingMode(document, format);
  final roles = _hasRole(document, const {
    'vertical-rl',
    'vertical-lr',
    'horizontal-tb',
  });
  if (mode == null && !roles) return '';
  String writing(String value) =>
      '-epub-writing-mode:$value;-webkit-writing-mode:$value;'
      'writing-mode:$value';
  final out = StringBuffer();
  if (mode != null) {
    out
      ..write('html{${writing(mode)}}\n')
      // (Tables and code set across, upright in the columns: JLREQ
      // 4.4.2.)
      ..write(
        '${_upright.join(',')},${_upright.map((s) => '$s *').join(',')}'
        '{${writing('horizontal-tb')}}\n',
      );
  }
  out
    ..write('.vertical-rl{${writing('vertical-rl')}}\n')
    ..write('.vertical-lr{${writing('vertical-lr')}}\n')
    ..write('.horizontal-tb{${writing('horizontal-tb')}}\n')
    ..write(
      '.tcy{-epub-text-combine:horizontal;-webkit-text-combine:horizontal;'
      'text-combine-upright:all}\n',
    );
  return out.toString();
}

/// The blocks set across in a vertical document: tables, listings and
/// literal blocks, as HTML (`tableblock`, `listingblock`) and EPUB
/// (`table`, `figure.listing`, `pre`) mark them up.
const List<String> _upright = [
  'table.tableblock',
  '.listingblock',
  '.literalblock',
  'div.table',
  'figure.listing',
  'pre',
];

bool _hasRole(AbstractBlock block, Set<String> roles) {
  for (final child in block.blocks) {
    if (child.roles.any(roles.contains)) return true;
    if (_hasRole(child, roles)) return true;
  }
  return false;
}

/// Whether [document]'s HTML or EPUB text sets its short numbers across
/// its vertical lines (tate-chu-yoko, [combineDigitsIn]): written in
/// vertical lines, in HTML or EPUB (the PDF sets them so itself).
bool combinesDigits(Document document) {
  final format = CompatFormat.named(document.attr('backend') ?? 'html5');
  return switch (format) {
    CompatFormat.html ||
    CompatFormat.epub => documentWritingMode(document, format!) != null,
    _ => false,
  };
}

/// [text] (substituted text: markup and character references in it) with
/// each number of one or two digits standing alone in a `tcy` span, set
/// across its vertical line (JLREQ 3.2.5): the reading systems that read
/// CSS's `text-combine-upright: all` combine it, few read `digits`.
String combineDigitsIn(String text) {
  if (!_digit.hasMatch(text)) return text;
  return InlineRun.replace(
    text,
    _digits,
    (m) => m[1] != null ? m[0]! : '<span class="tcy">${m[0]}</span>',
  );
}

final RegExp _digit = RegExp('[0-9]');

/// Markup and character references (kept whole), then a number of one
/// or two digits not inside a word or a longer number.
final RegExp _digits = RegExp(
  '(<[^>]*>|&#?[A-Za-z0-9]+;)|(?<![0-9A-Za-z.,#&])[0-9]{1,2}'
  '(?![0-9A-Za-z]|[.,][0-9])',
);
