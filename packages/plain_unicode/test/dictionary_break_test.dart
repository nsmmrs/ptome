import 'dart:io';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

/// The lines of `test/fixtures/dictionary_breaks.txt` and the breaks ICU
/// 78.3 gives each (the start, 0, included).
List<(String, String)> _golden() {
  final lines = File('test/fixtures/dictionary_breaks.txt')
      .readAsLinesSync()
      .where((l) => !l.startsWith('#'))
      .toList();
  return [
    for (var i = 0; i + 1 < lines.length; i += 2) (lines[i], lines[i + 1]),
  ];
}

String _breaks(String text) =>
    [0, for (final b in lineBreaks(text)) b.offset].join(' ');

void main() {
  test("words of Thai, Lao, Khmer and Myanmar break as ICU's", () {
    final cases = _golden();
    expect(cases.length, greaterThanOrEqualTo(140));
    final failures = [
      for (final (text, expected) in cases)
        if (_breaks(text) case final actual when actual != expected)
          '$text\n  ICU   $expected\n  ptome $actual',
    ];
    expect(failures, isEmpty, reason: failures.take(10).join('\n'));
  });

  test('a Thai sentence breaks between its words', () {
    // ภาษา|ไทย|สวัสดี|ครับ
    expect(_breaks('ภาษาไทยสวัสดีครับ'), '0 4 7 13 17');
  });

  test('a word never ends before a combining mark', () {
    const text = 'ກິນເຂົ້າແລ້ວບໍ';
    for (final b in lineBreaks(text)) {
      if (b.offset < text.length) {
        expect(isMark(text.codeUnitAt(b.offset)), isFalse, reason: '$b');
      }
    }
  });

  test('without the dictionaries, a run of class SA does not break', () {
    expect(lineBreaks('ภาษาไทยสวัสดีครับ', dictionary: false), [
      const LineBreak(17, mandatory: true),
    ]);
    final offsets = lineBreakOffsets('ภาษาไทย', dictionary: false);
    expect(offsets.length, 1);
  });

  test('the dictionaries leave other scripts alone', () {
    expect(_breaks('a b ภาษาไทย'), '0 2 4 8 11');
  });
}
