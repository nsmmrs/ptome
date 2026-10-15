// Case mapping tailored by language (SpecialCasing.txt): Turkish and Azeri
// dotted and dotless i, Lithuanian's dot above, against ICU's (its
// answers recorded in test/oracles/case_language.json, test/support/oracles.dart;
// ORACLES=record asks it again).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

import 'support/oracles.dart';

const String _icu = 'tool/oracles/icu/icucase';

/// The oracle, which its answers depend on.
const String _version = 'ICU 78.3';

void main() {
  final recorded = Oracle('case_language');
  test('Turkish and Azeri i', () {
    expect(upperCase('istanbul', language: 'tr'), 'İSTANBUL');
    expect(lowerCase('ISTANBUL', language: 'tr'), 'ıstanbul');
    expect(lowerCase('İzmir', language: 'az-Latn'), 'izmir');
    // (A capital I with a combining dot above: the dot goes.)
    expect(lowerCase('İ', language: 'tr'), 'i');
    expect(upperCase('istanbul'), 'ISTANBUL');
  });

  test("Lithuanian's dot above", () {
    expect(lowerCase('Ì', language: 'lt'), 'i̇̀');
    expect(lowerCase('Í', language: 'lt'), 'i̇́');
    expect(upperCase('i̇', language: 'lt'), 'I');
    expect(upperCase('i̇'), 'İ');
  });

  test('random text maps as ICU maps it', () {
    const alphabet = [
      'I',
      'i',
      'İ',
      'ı',
      'J',
      'j',
      'Į',
      'į',
      'Ì',
      'Í',
      'Ĩ',
      'a',
      'A',
      ' ',
      'Σ',
      'ß',
      '̀',
      '́',
      '̃',
      '̇',
      '̈',
      '̨',
      '̣',
      '̖',
      'ǰ',
      'ⁱ',
    ];
    final random = Random(7);
    final lines = <(String, String, String)>[];
    for (final language in const ['tr', 'az', 'lt', 'en', 'tr-TR', 'lt-LT']) {
      for (final mode in const ['upper', 'lower']) {
        for (var n = 0; n < 400; n++) {
          final text = [
            for (var k = random.nextInt(8) + 1; k > 0; k--)
              alphabet[random.nextInt(alphabet.length)],
          ].join();
          lines.add((language, mode, text));
        }
      }
    }
    final input = [for (final (l, m, t) in lines) '$l\t$m\t$t'];
    final theirs = recorded
        .answer(
          'languages',
          inputs: [_version, ...input],
          oracle: () =>
              Process.runSync('sh', [
                    '-c',
                    r'printf "%s\n" "$@" | "$0"',
                    _icu,
                    ...input,
                  ], stdoutEncoding: utf8).stdout
                  as String,
        )
        .split('\n');
    final differ = <String>[];
    for (final (i, (language, mode, text)) in lines.indexed) {
      final ours = mode == 'upper'
          ? upperCase(text, language: language)
          : lowerCase(text, language: language, finalSigma: true);
      if (ours != theirs[i]) {
        String hex(String s) =>
            s.runes.map((c) => c.toRadixString(16)).join(' ');
        differ.add(
          '$language $mode ${hex(text)}: ours ${hex(ours)}, '
          'ICU ${hex(theirs[i])}',
        );
      }
    }
    expect(differ, isEmpty, reason: differ.take(10).join('\n'));
  });
}
