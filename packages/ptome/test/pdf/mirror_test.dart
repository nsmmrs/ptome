// Ptome's `mirror` role (FEAT-yq6kff): a block set mirrored, left to
// right, as Through the Looking-Glass prints Jabberwocky; its page's
// content read back by qpdf, recorded in test/oracles/pdf_mirror.json.gz
// (test/support/oracles.dart; ORACLES=record asks it again).
@TestOn('vm')
library;

import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

import '../support/oracles.dart';
import '../support/pdf_tools.dart';
import '../vendored_fonts.dart';

late final Oracle _recorded;

/// A verse block with [roles], converted in asciidoctor-pdf's
/// theme (its fonts vendored); the page's content, uncompressed.
String _content(String roles, {Map<String, String> attributes = const {}}) {
  final pdf = asciidoc.convertToBytes(
    '''
= Mirrored

Before.

[verse$roles]
____
’Twas brillig, and the slithy toves
  Did gyre and gimble in the wabe;
____

After.
''',
    backend: Backend.pdf,
    attributes: {'pdf-theme': 'default', 'reproducible': '', ...attributes},
  );
  return qpdfQdf(_recorded, pdf);
}

/// The transformation matrices [content] sets (`cm`).
List<String> _matrices(String content) => [
  for (final m in RegExp(
    r'(-?[\d.]+ -?[\d.]+ -?[\d.]+ -?[\d.]+ -?[\d.]+ -?[\d.]+) cm',
  ).allMatches(content))
    m[1]!,
];

void main() {
  _recorded = Oracle('pdf_mirror', compressed: true);
  setUpAll(useVendoredFonts);

  test('the block painted turned over, the rest as it was', () {
    final mirrored = _matrices(_content('.mirror'));
    final plain = _matrices(_content(''));
    final flips = mirrored.where((m) => m.startsWith('-1 0 0 1 ')).toList();
    expect(flips, hasLength(1), reason: '$mirrored');
    expect(plain.where((m) => m.startsWith('-1 0 0 1 ')), isEmpty);
    // (Turned about the middle of the text block: x' = 2·left + width − x,
    // asciidoctor-pdf's A4 text block from 48.24 to 547.04.)
    expect(double.parse(flips.single.split(' ')[4]), closeTo(595.28, 0.01));
  });

  test('beside another role (BUG-ldy580)', () {
    final named = _matrices(_content('.mirror.jabberwocky'));
    expect(named.where((m) => m.startsWith('-1 0 0 1 ')), hasLength(1));
  });

  test('not under asciidoctor-compat', () {
    final compat = _matrices(
      _content('.mirror', attributes: const {'asciidoctor-compat': 'pdf'}),
    );
    expect(compat.where((m) => m.startsWith('-1 0 0 1 ')), isEmpty);
  });
}
