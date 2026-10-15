// Collation (UTS #10 with CLDR 48.2): the root order against CLDR's
// conformance test, every tailoring against ICU 78.3's collator, and an
// index's headings against ICU's AlphabeticIndex. ICU's answers are recorded
// in test/oracles/collation.json (test/support/oracles.dart; ORACLES=record
// asks it again).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

import 'support/oracles.dart';

const String _coll = 'tool/oracles/icu/icucoll';
const String _index = 'tool/oracles/icu/icuindex';

/// The oracle, which its answers depend on.
const String _version = 'ICU 78.3';

late final Oracle _recorded;

/// The [oracle]'s lines for [arguments], as recorded for [key].
List<String> _icu(String key, String oracle, List<String> arguments) =>
    _recorded
        .answer(
          key,
          inputs: [_version, oracle, ...arguments],
          oracle: () =>
              Process.runSync('sh', [
                    '-c',
                    r'printf "%s\n" "$@" | "$0"',
                    oracle,
                    ...arguments,
                  ], stdoutEncoding: utf8).stdout
                  as String,
        )
        .split('\n')
      ..removeLast();

/// A seed from [text] that is the same on every platform and SDK (a
/// string's hashCode isn't).
int _seed(String text) =>
    text.codeUnits.fold(17, (h, c) => (h * 31 + c) & 0x7fffffff);

/// [words] sorted by [collator], ties kept in their order.
List<String> _sorted(Collator collator, List<String> words) {
  final keyed =
      [for (final (i, w) in words.indexed) (i, w, collator.sortKey(w))]
        ..sort((a, b) {
          final c = a.$3.compareTo(b.$3);
          return c != 0 ? c : a.$1 - b.$1;
        });
  return [for (final (_, w, _) in keyed) w];
}

/// Whether [text]'s marks are in canonical order (as normalized text has
/// them: ICU leaves others as they are unless a tailoring normalizes, UTS
/// #10 reorders them), and, for Thai's shifted punctuation, no mark
/// follows a space, punctuation or a letter Thai makes variable (ฯ, ๆ):
/// ICU drops one after a space, keeps one after a hyphen.
bool _comparable(String text, {required bool shifted}) {
  var last = 0;
  String? previous;
  for (final r in text.runes) {
    final ccc = canonicalCombiningClass(r);
    if (ccc != 0 && ccc < last) return false;
    last = ccc;
    if (shifted &&
        isMark(r) &&
        previous != null &&
        RegExp(r'^[\p{P}\p{Z}ฯๆ]$', unicode: true).hasMatch(previous)) {
      return false;
    }
    previous = String.fromCharCode(r);
  }
  return true;
}

void main() {
  _recorded = Oracle('collation');
  test("the root order: every line of CLDR's conformance test", () {
    final lines = const LineSplitter().convert(
      utf8.decode(
        gzip.decode(
          File('test/unicode/CollationTest_CLDR_NON_IGNORABLE_SHORT.txt.gz')
              .readAsBytesSync(),
        ),
      ),
    );
    final root = Collator('und');
    CollationKey? previous;
    var checked = 0;
    final wrong = <String>[];
    for (final line in lines) {
      final data = line.split('#').first.trim();
      if (data.isEmpty || data.startsWith('@')) continue;
      final key = root.sortKey(
        String.fromCharCodes([
          for (final c in data.split(' ')) int.parse(c, radix: 16),
        ]),
      );
      if (previous != null && previous.compareTo(key) > 0) wrong.add(data);
      previous = key;
      checked++;
      if (wrong.length > 10) break;
    }
    expect(wrong, isEmpty);
    expect(checked, greaterThan(200000));
  });

  test('everyday orders', () {
    expect(_sorted(Collator('de'), ['Zebra', 'Äpfel', 'Apfel', 'Bär']), [
      'Apfel',
      'Äpfel',
      'Bär',
      'Zebra',
    ]);
    expect(_sorted(Collator('sv'), ['öl', 'zebra', 'ål', 'alla', 'äpple']), [
      'alla',
      'zebra',
      'ål',
      'äpple',
      'öl',
    ]);
    expect(_sorted(Collator('es'), ['ñu', 'nube', 'oso']), [
      'nube',
      'ñu',
      'oso',
    ]);
    // (Pinyin: ài, ān, bā, zhōng; strokes: 一 1, 八 2, 中 4.)
    expect(_sorted(Collator('zh'), ['中', '八', '安', '爱']), ['爱', '安', '八', '中']);
    expect(_sorted(Collator('zh-TW'), ['中', '八', '一']), ['一', '八', '中']);
    expect(_sorted(Collator('ja'), ['さくら', 'あめ', 'かさ', 'アメ']), [
      'あめ',
      'アメ',
      'かさ',
      'さくら',
    ]);
    expect(Collator('fr-CA').locale, 'fr_CA');
    expect(Collator('zh-u-co-stroke').locale, 'zh@stroke');
    expect(Collator('xx').locale, 'root');
  });

  test('every tailoring as ICU orders it', () {
    final differ = <String>[];
    var compared = 0;
    for (final locale in Collator.tailoredLocales) {
      final tag = locale.replaceAll('_', '-').replaceFirst('@', '-u-co-');
      final collator = Collator(tag);
      final random = Random(_seed(locale));
      final tailored = collator.tailoredStrings.toList()..shuffle(random);
      final pick = tailored.take(150).toList();
      if (pick.isEmpty) continue;
      const extra = ['a', 'A', 'z', 'Z', '1', '9', ' ', '-', '.', 'é', 'Ab'];
      String any(List<String> from) => from[random.nextInt(from.length)];
      final shifted = locale == 'th';
      final words =
          <String>{
              ...pick,
              ...extra,
              for (var i = 0; i < 150; i++) any(pick) + any(extra),
              for (var i = 0; i < 100; i++) any(extra) + any(pick),
              for (var i = 0; i < 100; i++) any(pick) + any(pick),
            }.where((w) => _comparable(w, shifted: shifted)).toList()
            ..shuffle(random);
      final lines = _icu('collate $tag', _coll, [tag, ...words]);
      // (ICU's data leaves out some locales' tailorings: those aren't
      // compared.)
      final actual = lines.removeAt(0);
      if (actual.isEmpty || actual == 'root') continue;
      final ours = _sorted(collator, words);
      compared++;
      for (var i = 0; i < ours.length; i++) {
        if (ours[i] != lines[i]) {
          differ.add('$locale: ${ours[i]} where ICU has ${lines[i]}');
          break;
        }
      }
    }
    expect(compared, greaterThan(90));
    expect(differ, isEmpty, reason: differ.take(10).join('\n'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('index headings', () {
    expect(Collator('sv').indexLabels.last, 'Ö');
    expect(Collator('ja').indexLabels, [
      'あ',
      'か',
      'さ',
      'た',
      'な',
      'は',
      'ま',
      'や',
      'ら',
      'わ',
    ]);
    expect(Collator('zh').indexLabel('中国'), 'Z');
    expect(Collator('zh').indexLabel('apple'), 'A');
    expect(Collator('zh-TW').indexLabel('人'), '2劃');
    expect(Collator('ko').indexLabel('한국'), 'ㅎ');
    expect(Collator('de').indexLabel('Äpfel'), 'A');
    expect(Collator('de').indexLabel('1984'), isNull);
    expect(Collator('ru').indexLabel('apple'), isNull);
  });

  test("index headings as ICU's AlphabeticIndex has them", () {
    const words = [
      '中国',
      '日本',
      '北京',
      '上海',
      '人',
      '爱',
      'Åsa',
      'zebra',
      'apple',
      'Émile',
      'öl',
      'ñu',
      '아이',
      '한국',
      'Яблоко',
      'Ёж',
      'αβ',
      'Ωμέγα',
      'مرحبا',
      'あい',
      'かき',
      'カタ',
      'ゃ',
      '1',
      '!',
      'ß',
      'Ćevap',
      'Çay',
      'İstanbul',
      'Łódź',
      'Ångström',
      'Øre',
      'Ærø',
      'ch',
      'll',
      'ŋ',
      'þorn',
    ];
    final differ = <String>[];
    for (final tag in [
      'zh',
      'zh-u-co-stroke',
      'zh-Hant',
      'ja',
      'ko',
      'sv',
      'de',
      'ru',
      'el',
      'ar',
      'fr',
      'es',
      'da',
      'cs',
      'pl',
      'tr',
      'en',
      'is',
      'lt',
      'hr',
      'fi',
    ]) {
      final collator = Collator(tag);
      final lines = _icu('index $tag', _index, [tag, ...words]);
      final labels = lines.removeAt(0);
      if (collator.indexLabels.join(' ') != labels) {
        differ.add('$tag: ${collator.indexLabels.join(' ')} for $labels');
      }
      for (final (i, word) in words.indexed) {
        final ours = collator.indexLabel(word) ?? '';
        if (ours != lines[i]) differ.add('$tag $word: $ours for ${lines[i]}');
      }
    }
    expect(differ, isEmpty, reason: differ.take(10).join('\n'));
  });
}
