// Tai Tham, New Tai Lue, Tai Viet and Ahom, written without spaces and
// with no dictionary (ICU has none; no word list under a permissive
// licence exists): lines break between their orthographic syllables.
import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

List<int> _breaks(List<int> runes) {
  final text = String.fromCharCodes(runes);
  final offsets = lineBreakOffsets(text);
  return [
    for (var i = 0; i < offsets.length; i++)
      if (offsets.offsetAt(i) < text.length) offsets.offsetAt(i),
  ];
}

void main() {
  test('New Tai Lue: a vowel written before its consonant starts the '
      'syllable; finals and tones close it', () {
    // ᦀ ᦰ ᧁ ᧈ | ᦵ ᦁ | ᦂ ᦰ
    expect(
      _breaks([0x1980, 0x19b0, 0x19c1, 0x19c8, 0x19b5, 0x1981, 0x1982, 0x19b0]),
      [4, 6],
    );
  });

  test('Tai Viet, in visual order too', () {
    // ꪀ ꪰ | ꪵ ꪁ | ꪂ
    expect(_breaks([0xaa80, 0xaab0, 0xaab5, 0xaa81, 0xaa82]), [2, 4]);
  });

  test('Tai Tham: a stacked consonant stays with what it is stacked on, a '
      'killed one closes its syllable', () {
    // ᨠ ᩣ ᩠ ᨾ | ᨡ ᩡ
    expect(_breaks([0x1a20, 0x1a63, 0x1a60, 0x1a3e, 0x1a21, 0x1a61]), [4]);
    // ᨠ ᩡ ᨿ ᩺ | ᨡ
    expect(_breaks([0x1a20, 0x1a61, 0x1a3f, 0x1a7a, 0x1a21]), [4]);
  });

  test('Ahom, outside the Basic Multilingual Plane', () {
    // 𑜀 𑜠 𑜁 𑜫 | 𑜂 (two code units each)
    expect(_breaks([0x11700, 0x11720, 0x11701, 0x1172b, 0x11702]), [8]);
  });

  test("not without the dictionaries, nor in other scripts' runs", () {
    final text = String.fromCharCodes([0x1980, 0x19b0, 0x1981]);
    final rules = lineBreakOffsets(text, dictionary: false);
    expect(
      [for (var i = 0; i < rules.length; i++) rules.offsetAt(i)],
      [text.length],
    );
    expect(_breaks('abc'.codeUnits), isEmpty);
  });
}
