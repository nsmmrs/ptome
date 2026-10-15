// Counter styles: the examples CSS Counter Styles Level 3 gives (its
// longhand table, the first 120 simplified Chinese numbers, the Ethiopic
// examples), every style against WeasyPrint's counter() and list markers
// (tool/oracles/weasyprint: its own definitions for CSS's predefined
// styles, the vendored rules for the Ready-made ones, read from its
// laid-out boxes; its answers recorded in test/oracles/counter_styles.json.gz,
// test/support/oracles.dart, ORACLES=record asking it again), and the
// default numbering systems CLDR gives languages.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

import 'support/oracles.dart';

/// The oracle, which its answers depend on.
const String _weasyprint = 'WeasyPrint 70.0';

/// The longest representation compared (WeasyPrint caps a
/// representation's length, as CSS lets it).
const int _compared = 60;

String _format(String style, int value) =>
    CounterStyle.named(style)!.format(value);

void main() {
  test("the longhand styles' table (7.1)", () {
    const values = [0, 1, 2, 3, 10, 11, 99, 100, 101, 6001];
    const table = {
      'japanese-informal': '〇 一 二 三 十 十一 九十九 百 百一 六千一',
      'japanese-formal': '零 壱 弐 参 壱拾 壱拾壱 九拾九 壱百 壱百壱 六阡壱',
      'korean-hangul-formal': '영 일 이 삼 일십 일십일 구십구 일백 일백일 육천일',
      'korean-hanja-informal': '零 一 二 三 十 十一 九十九 百 百一 六千一',
      'korean-hanja-formal': '零 壹 貳 參 壹拾 壹拾壹 九拾九 壹百 壹百壹 六仟壹',
      'simp-chinese-informal': '零 一 二 三 十 十一 九十九 一百 一百零一 六千零一',
      'simp-chinese-formal': '零 壹 贰 叁 壹拾 壹拾壹 玖拾玖 壹佰 壹佰零壹 陆仟零壹',
      'trad-chinese-informal': '零 一 二 三 十 十一 九十九 一百 一百零一 六千零一',
      'trad-chinese-formal': '零 壹 貳 參 壹拾 壹拾壹 玖拾玖 壹佰 壹佰零壹 陸仟零壹',
    };
    for (final MapEntry(key: style, value: row) in table.entries) {
      expect(
        [for (final v in values) _format(style, v)].join(' '),
        row,
        reason: style,
      );
    }
    expect(_format('cjk-ideographic', 6001), '六千零一');
    // (The range is -9999 to 9999, cjk-decimal beyond; the negative sign
    // the style's.)
    expect(_format('simp-chinese-informal', -12), '负十二');
    expect(_format('trad-chinese-formal', -1), '負壹');
    expect(_format('japanese-informal', 10000), '一〇〇〇〇');
    expect(_format('korean-hangul-formal', -2), '마이너스 이');
    expect(CounterStyle.named('simp-chinese-informal')!.marker(3), '三、');
  });

  test('the first 120 simplified Chinese numbers (7.1.3)', () {
    const tens = ['', '十', '二十', '三十', '四十', '五十', '六十', '七十', '八十', '九十'];
    const units = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
    for (var n = 1; n <= 120; n++) {
      final expected = n < 100
          ? tens[n ~/ 10] + units[n % 10]
          : '一百${n == 100
                ? ''
                : n < 110
                ? '零${units[n % 10]}'
                : tens[(n % 100) ~/ 10] == '十'
                ? '一十${units[n % 10]}'
                : tens[(n % 100) ~/ 10] + units[n % 10]}';
      expect(_format('simp-chinese-informal', n), expected, reason: '$n');
    }
  });

  test('Ethiopic numerals (7.2)', () {
    expect(_format('ethiopic-numeric', 1), '፩');
    expect(_format('ethiopic-numeric', 100), '፻');
    expect(_format('ethiopic-numeric', 78010092), '፸፰፻፩፼፺፪');
    expect(_format('ethiopic-numeric', 780100000092), '፸፰፻፩፼፼፺፪');
    expect(CounterStyle.named('ethiopic-numeric')!.marker(2), '፪/ ');
    // (Defined from 1.)
    expect(_format('ethiopic-numeric', 0), '0');
  });

  test('ranges, fallbacks, pads and extended styles', () {
    expect(_format('lower-roman', 3999), 'mmmcmxcix');
    expect(_format('lower-roman', 4000), '4000');
    expect(_format('decimal-leading-zero', 7), '07');
    expect(_format('decimal-leading-zero', -7), '-7');
    expect(_format('hebrew', 15), 'טו');
    expect(_format('hebrew', 11000), '11000');
    expect(_format('cjk-earthly-branch', 13), '13');
    expect(_format('upper-alpha', 703), 'AAA');
    expect(CounterStyle.named('lower-russian')!.marker(2), 'б) ');
    expect(CounterStyle.named('Upper-Roman')!.name, 'upper-roman');
    expect(CounterStyle.named('no-such-style'), isNull);
    expect(CounterStyle.names, contains('ethiopic-numeric'));
    expect(CounterStyle.names.length, greaterThan(200));
  });

  test('styles for the numbering systems, and their CSS', () {
    expect(CounterStyle.forNumberingSystem('arab')!.name, 'arabic-indic');
    expect(CounterStyle.forNumberingSystem('arabext')!.name, 'persian');
    expect(CounterStyle.forNumberingSystem('latn')!.name, 'decimal');
    expect(CounterStyle.forNumberingSystem('deva')!.name, 'devanagari');
    final chakma = CounterStyle.forNumberingSystem('cakm')!;
    expect(chakma.name, 'numbering-cakm');
    expect(chakma.format(12), '𑄷𑄸');
    expect(chakma.predefined, isFalse);
    expect(CounterStyle.forNumberingSystem('nope'), isNull);
    expect(CounterStyle.named('hiragana')!.predefined, isTrue);
    expect(CounterStyle.named('hangul')!.predefined, isFalse);
    expect(
      CounterStyle.named('lower-russian')!.cssRule,
      startsWith(
        '@counter-style lower-russian { system: alphabetic; symbols: '
        '"а" "б"',
      ),
    );
  });

  test('default numbering systems (CLDR 48.2)', () {
    expect(defaultNumberingSystem('ar'), 'latn');
    expect(defaultNumberingSystem('ar-EG'), 'arab');
    expect(defaultNumberingSystem('ar-MA'), 'latn');
    expect(defaultNumberingSystem('fa'), 'arabext');
    expect(defaultNumberingSystem('ur'), 'latn');
    expect(defaultNumberingSystem('ur-IN'), 'arabext');
    expect(defaultNumberingSystem('mr'), 'deva');
    expect(defaultNumberingSystem('hi'), 'latn');
    expect(defaultNumberingSystem('bn'), 'beng');
    expect(defaultNumberingSystem('my'), 'mymr');
    expect(defaultNumberingSystem('dz'), 'tibt');
    expect(defaultNumberingSystem('pa-Arab'), 'arabext');
    expect(defaultNumberingSystem('ja'), 'latn');
    expect(defaultNumberingSystem('ar-EG-u-nu-latn'), 'latn');
    expect(defaultNumberingSystem('en-u-nu-thai'), 'thai');
    expect(formatDigits(2026, 'arab'), '٢٠٢٦');
    expect(formatDigits(-7, 'deva'), '-७');
    expect(formatDigits(5, 'nope'), '5');
    expect(numberingSystemDigits('hanidec'), '〇一二三四五六七八九');
  });

  final recorded = Oracle('counter_styles', compressed: true);
  test("every style as WeasyPrint's counter() and markers write it", () {
    const values = [
      -3, 0, 1, 2, 3, 4, 5, 9, 10, 11, 12, 13, 14, 15, 16, 19, 20, 21, //
      25, 26, 27, 28, 47, 48, 49, 50, 60, 61, 99, 100, 101, 110, 111, 499,
      999, 1000, 1001, 1234, 3999, 4000, 4999, 6001, 9999, 10000, 10999,
      11000, 19999, 20000, 78010092,
    ];
    // Section 7's algorithms, which WeasyPrint doesn't have; and the
    // CJK cycles, fixed in CSS Counter Styles 3 (6.4), alphabetic in
    // WeasyPrint as in CSS 2.1's era.
    const unlike = {
      'simp-chinese-informal',
      'simp-chinese-formal',
      'trad-chinese-informal',
      'trad-chinese-formal',
      'cjk-ideographic',
      'ethiopic-numeric',
      'cjk-earthly-branch',
      'cjk-heavenly-stem',
    };
    // CSS's own styles from WeasyPrint's definitions, the Ready-made
    // ones from the vendored rules.
    final css3 = File('vendor/w3c/css-counter-styles-3.css').readAsStringSync();
    final predefined = {
      for (final m in RegExp(r'@counter-style\s+([\w-]+)').allMatches(css3))
        m[1]!,
    };
    final readyMade = File('vendor/w3c/predefined-counter-styles.css')
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    final css = StringBuffer();
    for (final m in RegExp(
      r'@counter-style\s+([\w-]+)\s*\{[^}]*\}',
    ).allMatches(readyMade)) {
      if (!predefined.contains(m[1])) css.write(m[0]);
    }
    final styles = [
      for (final name in CounterStyle.names)
        if (!unlike.contains(name)) name,
    ];
    // (And each style's own rule, as cssRule writes it, under another
    // name: the same numbers from it.)
    for (final name in styles.toList()) {
      css.write(
        CounterStyle.named(name)!.cssRule
            .replaceFirst('@counter-style $name ', '@counter-style x-$name '),
      );
      styles.add('x-$name');
    }
    final input = jsonEncode({
      'css': '$css',
      'styles': styles,
      'values': values,
    });
    final theirs = recorded.json<List<Object?>>(
      'every style',
      inputs: [
        _weasyprint,
        File('tool/oracles/weasyprint/counters.py').readAsStringSync(),
        input,
      ],
      oracle: () => _weasyprintCounters(input),
    );
    final differ = <String>[];
    for (final (i, style) in styles.indexed) {
      final counter = CounterStyle.named(
        style.startsWith('x-') ? style.substring(2) : style,
      )!;
      final row = theirs[i]! as List<Object?>;
      for (final (j, v) in values.indexed) {
        final [their, theirMarker] = (row[j]! as List<Object?>).cast<String>();
        final ours = counter.format(v);
        final marker = counter.marker(v);
        // (WeasyPrint caps a representation's length, as CSS lets it.)
        if (ours.runes.length > _compared) continue;
        // (WeasyPrint's Korean markers keep a second space after the
        // negative sign, its counter() one: the escape in `"\C2A4  "`
        // takes one, as CSS's syntax has it.)
        final korean = style.startsWith('korean-') && v < 0;
        if (ours != their ||
            (marker != theirMarker &&
                !(korean && theirMarker == marker.replaceFirst(' ', '  ')))) {
          differ.add(
            '$style $v: ours "$ours" "$marker", '
            'WeasyPrint "$their" "$theirMarker"',
          );
        }
      }
    }
    expect(differ, isEmpty, reason: differ.take(20).join('\n'));
  });
}

/// WeasyPrint's counter() and marker for each style and value of [input]
/// (`{css, styles, values}`), with the interpreter its `weasyprint`
/// script runs.
List<Object?> _weasyprintCounters(String input) {
  final script =
      // hermetic: recording only (the oracle's closure)
      Process.runSync('sh', ['-c', 'command -v weasyprint']).stdout as String;
  final python = File(script.trim())
      .readAsLinesSync()
      .first
      .replaceFirst('#!', '')
      .trim();
  final dir = Directory.systemTemp.createTempSync('counters.');
  try {
    final file = File('${dir.path}/in.json')..writeAsStringSync(input);
    final process = Process.runSync('sh', [
      '-c',
      r'"$0" -I tool/oracles/weasyprint/counters.py < "$1"',
      python,
      file.path,
    ], stdoutEncoding: utf8);
    if (process.exitCode != 0) throw StateError('${process.stderr}');
    // (A representation longer than the test compares, cut short.)
    String cut(Object? text) =>
        String.fromCharCodes((text! as String).runes.take(_compared + 1));
    return [
      for (final row in jsonDecode(process.stdout as String) as List<Object?>)
        [
          for (final cell in row! as List<Object?>)
            [for (final text in cell! as List<Object?>) cut(text)],
        ],
    ];
  } finally {
    dir.deleteSync(recursive: true);
  }
}
