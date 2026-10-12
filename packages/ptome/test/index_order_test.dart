// The order of an index's terms: Asciidoctor's, and the two systems of
// The Chicago Manual of Style's indexing chapter.
import 'package:ptome/src/index_order.dart';
import 'package:test/test.dart';

List<String> _sorted(
  IndexOrder order,
  List<String> terms, {
  bool sub = false,
}) => [...terms]..sort((a, b) => order.compare(a, b, subentry: sub));

void main() {
  const terms = [
    'Newark',
    'New York',
    'new math',
    'New Deal',
    'news',
    'newspaper',
    'New Zealand',
  ];

  test('letter by letter: spaces count for nothing', () {
    expect(_sorted(IndexOrder.letterByLetter, terms), [
      'Newark',
      'New Deal',
      'new math',
      'news',
      'newspaper',
      'New York',
      'New Zealand',
    ]);
  });

  test('word by word: a word ends at a space and comes first', () {
    expect(_sorted(IndexOrder.wordByWord, terms), [
      'New Deal',
      'new math',
      'New York',
      'New Zealand',
      'Newark',
      'news',
      'newspaper',
    ]);
  });

  test('to the first comma, then the rest', () {
    for (final order in [IndexOrder.letterByLetter, IndexOrder.wordByWord]) {
      expect(_sorted(order, ['Smith Barney', 'Smith, John', 'Smith, Adam']), [
        'Smith, Adam',
        'Smith, John',
        'Smith Barney',
      ], reason: '$order');
    }
  });

  test('symbols, then numerals by their values, then letters', () {
    expect(
      _sorted(IndexOrder.wordByWord, [
        'apple',
        '10 Downing',
        '2 Kings',
        r'$ sign',
      ]),
      [r'$ sign', '2 Kings', '10 Downing', 'apple'],
    );
  });

  test('diacritics and punctuation count for nothing', () {
    expect(
      _sorted(IndexOrder.letterByLetter, ['elk', 'Élan', "e'en", 'eland']),
      ["e'en", 'Élan', 'eland', 'elk'],
    );
    expect(IndexOrder.letterByLetter.letterOf('Élan'), 'E');
    expect(IndexOrder.asciidoctor.letterOf('Élan'), 'É');
  });

  test("a subentry's opening preposition is passed over", () {
    expect(
      _sorted(IndexOrder.wordByWord, [
        'in poetry',
        'meter',
        'of the ballad',
      ], sub: true),
      ['of the ballad', 'meter', 'in poetry'],
    );
  });

  test("Asciidoctor's: case-insensitive, by the characters", () {
    expect(_sorted(IndexOrder.asciidoctor, terms), [
      'New Deal',
      'new math',
      'New York',
      'New Zealand',
      'Newark',
      'news',
      'newspaper',
    ]);
  });
}
