// Emoji (UTS #51, Unicode 18.0.0): the properties from emoji-data.txt,
// and every sequence of emoji-test.txt found whole where it is shown as
// an emoji.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

void main() {
  test('the properties', () {
    expect(isEmojiPresentation(0x1f600), isTrue); // 😀
    expect(isEmojiPresentation(0x2764), isFalse); // ❤
    expect(isEmoji(0x2764), isTrue);
    expect(isEmoji(0x31), isTrue); // 1, a keycap's base
    expect(isEmoji(0x41), isFalse);
    expect(isEmojiModifier(0x1f3fd), isTrue);
    expect(isEmojiModifierBase(0x1f44d), isTrue); // 👍
    expect(isEmojiModifierBase(0x1f600), isFalse);
    expect(isExtendedPictographic(0x1fbff), isFalse);
    expect(isExtendedPictographic(0x1faff), isTrue); // reserved
  });

  test("every sequence of emoji-test.txt that's shown as an emoji", () {
    final lines = const LineSplitter().convert(
      utf8.decode(
        gzip.decode(File('test/unicode/emoji-test.txt.gz').readAsBytesSync()),
      ),
    );
    var checked = 0;
    final wrong = <String>[];
    for (final line in lines) {
      final m = RegExp(
        r'^([0-9A-F ]+?)\s*; (fully-qualified|minimally-qualified|'
        'unqualified|component)',
      ).firstMatch(line);
      if (m == null) continue;
      final runes = [for (final c in m[1]!.split(' ')) int.parse(c, radix: 16)];
      // (Fully qualified: shown as an emoji, all of it. Unqualified, one
      // character: text by default; else it's still one sequence, shown
      // as an emoji.)
      final expected = switch (m[2]) {
        'unqualified' when runes.length == 1 => 0,
        _ => runes.length,
      };
      final text = 'a${String.fromCharCodes(runes)}b'.runes.toList();
      if (emojiSequenceLength(text, 1) != expected) wrong.add(m[1]!);
      checked++;
    }
    expect(wrong, isEmpty, reason: wrong.take(10).join('\n'));
    expect(checked, greaterThan(5000));
  });

  test('text and emoji presentation', () {
    int length(String text) => emojiSequenceLength(text.runes.toList(), 0);
    expect(length('1'), 0);
    expect(length('1\u{fe0f}\u{20e3}x'), 3);
    expect(length('❤'), 0);
    expect(length('❤\u{fe0f}'), 2);
    expect(length('😀\u{fe0e}'), 0);
    expect(length('🇯🇵🇫🇷'), 2);
    expect(length('🇯'), 0);
    expect(length('👍🏽 '), 2);
    expect(length('👨‍👩‍👧x'), 5);
    expect(length('👨‍'), 1);
    expect(length('a'), 0);
  });
}
