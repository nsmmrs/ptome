// Quotation marks by language from CLDR, against ICU's
// ulocdata_getDelimiter for every CLDR locale and their languages with
// other regions and scripts.
@TestOn('vm')
library;

import 'dart:io';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

const String _oracle = 'tool/oracles/icu/icudelim';

String _marks(QuotationMarks m) =>
    [m.start, m.end, m.alternateStart, m.alternateEnd].join('\t');

void main() {
  test('everyday languages', () {
    expect(_marks(quotationMarks('en')), '“\t”\t‘\t’');
    expect(_marks(quotationMarks('fr')), '«\t»\t«\t»');
    expect(_marks(quotationMarks('de')), '„\t“\t‚\t‘');
    expect(_marks(quotationMarks('ja')), '「\t」\t『\t』');
    expect(_marks(quotationMarks('zh-TW')), '「\t」\t『\t』');
    expect(_marks(quotationMarks('zh')), '“\t”\t‘\t’');
    expect(_marks(quotationMarks('xx')), '“\t”\t‘\t’');
    expect(_marks(quotationMarks('')), '“\t”\t‘\t’');
  });

  test("every locale as ICU 78.3's", () {
    final locales = [
      for (final line in File(
        'vendor/cldr/48.2.0/delimiters.tsv',
      ).readAsLinesSync())
        if (line.isNotEmpty && !line.startsWith('#')) line.split('\t').first,
    ]..remove('root');
    final languages = {for (final l in locales) l.split('-').first};
    const regions = [
      'US',
      'GB',
      'FR',
      'CA',
      'CH',
      'DE',
      'CN',
      'TW',
      'HK',
      'MO',
      'SG',
      'RS',
      'BA',
      'IN',
      'PK',
      'MX',
      '419',
      'BR',
      'PT',
      'AU',
    ];
    const scripts = ['Latn', 'Cyrl', 'Arab', 'Hans', 'Hant', 'Deva'];
    final corpus = {
      ...locales,
      for (final l in languages) ...[
        l,
        for (final r in regions) '$l-$r',
        for (final s in scripts) '$l-$s',
      ],
      'zh-Hant-TW',
      'zh-Hans-TW',
      'sr-Latn-RS',
      'en-US-posix',
      'de-CH-1996',
      'pt-BR-x-private',
      'EN-gb',
      'en_AU',
      'xyz',
      'und',
    }.toList();
    final r = Process.runSync('sh', [
      '-c',
      r'printf "%s\n" "$@" | "$0"',
      _oracle,
      ...corpus,
    ]);
    final lines = (r.stdout as String).split('\n');
    // (ICU's data leaves out some of CLDR's locales, those below its
    // coverage level: what is said in them is not compared.)
    final missing = {
      for (final (i, tag) in corpus.indexed)
        if (locales.contains(tag) &&
            lines[i].split('\t').last.replaceAll('_', '-') != tag)
          tag,
    };
    final differ = <String>[];
    for (final (i, tag) in corpus.indexed) {
      if (missing.any((m) => tag == m || tag.startsWith('$m-'))) continue;
      final theirs = lines[i].split('\t').take(4).join('\t');
      final ours = _marks(quotationMarks(tag));
      if (ours != theirs) differ.add('$tag: ours $ours, ICU $theirs');
    }
    expect(missing.length, lessThan(200));
    expect(corpus.length, greaterThan(9000));
    expect(differ, isEmpty, reason: differ.take(400).join('\n'));
  }, skip: File(_oracle).existsSync() ? false : 'needs the ICU oracle');
}
