// The shaping properties against the files they are generated from, read
// here afresh for every code point; canonical decomposition and
// composition against the conformance test, NormalizationTest.txt (its
// NFD and NFC columns, normalized with them).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

const String _ucd = 'vendor/ucd/18.0.0';

/// Each code point's value of the property [file] lists, [missing] where
/// it lists none.
List<String> _property(String file, String missing) {
  final values = List.filled(0x110000, missing);
  for (final line in File('$_ucd/$file').readAsLinesSync()) {
    final data = line.split('#').first.trim();
    if (data.isEmpty) continue;
    final fields = data.split(';').map((s) => s.trim()).toList();
    final bounds = fields.first.split('..');
    for (
      var c = int.parse(bounds.first, radix: 16);
      c <= int.parse(bounds.last, radix: 16);
      c++
    ) {
      values[c] = fields[1];
    }
  }
  return values;
}

/// [name] as the enumerations name their values (`Consonant_Dead`:
/// `consonantDead`).
String _camel(String name) {
  final words = name.split('_');
  return [
    words.first.toLowerCase(),
    for (final w in words.skip(1))
      if (w.isNotEmpty) w[0].toUpperCase() + w.substring(1).toLowerCase(),
  ].join();
}

/// [text]'s canonical decomposition, its marks in canonical order.
List<int> _nfd(List<int> text) {
  final out = <int>[];
  void decompose(int c) {
    switch (canonicalDecomposition(c)) {
      case (final first, final second):
        decompose(first);
        if (second != null) decompose(second);
      case null:
        out.add(c);
    }
  }

  text.forEach(decompose);
  // Canonical ordering: a stable sort of each run of marks.
  for (var i = 0; i < out.length;) {
    if (canonicalCombiningClass(out[i]) == 0) {
      i++;
      continue;
    }
    var end = i;
    while (end < out.length && canonicalCombiningClass(out[end]) != 0) {
      end++;
    }
    final run = out.sublist(i, end).indexed.toList()
      ..sort((a, b) {
        final d = canonicalCombiningClass(a.$2) - canonicalCombiningClass(b.$2);
        return d != 0 ? d : a.$1 - b.$1;
      });
    out.setRange(i, end, [for (final (_, c) in run) c]);
    i = end;
  }
  return out;
}

/// [text] canonically composed (NFC).
List<int> _nfc(List<int> text) {
  final out = _nfd(text);
  var starter = -1;
  var i = 0;
  while (i < out.length) {
    final ccc = canonicalCombiningClass(out[i]);
    if (starter >= 0) {
      // Blocked by a mark of the same class or higher, or by a starter
      // after the last.
      var blocked = false;
      if (i > starter + 1) {
        final previous = canonicalCombiningClass(out[i - 1]);
        blocked = previous == 0 || previous >= ccc;
      }
      if (!blocked) {
        if (canonicalComposition(out[starter], out[i]) case final c?) {
          out
            ..[starter] = c
            ..removeAt(i);
          continue;
        }
      }
    }
    if (ccc == 0) starter = i;
    i++;
  }
  return out;
}

void main() {
  test('each property, for every code point, as its file has it', () {
    final category = _property('DerivedGeneralCategory.txt', 'Cn');
    final script = _property('Scripts.txt', 'Unknown');
    final syllabic = _property('IndicSyllabicCategory.txt', 'Other');
    final positional = _property('IndicPositionalCategory.txt', 'NA');
    final ignorable = <int>{};
    for (final line in File(
      '$_ucd/DerivedCoreProperties.txt',
    ).readAsLinesSync()) {
      if (!line.contains('; Default_Ignorable_Code_Point')) continue;
      final bounds = line.split(';').first.trim().split('..');
      for (
        var c = int.parse(bounds.first, radix: 16);
        c <= int.parse(bounds.last, radix: 16);
        c++
      ) {
        ignorable.add(c);
      }
    }
    // (Spot checks of the long names: Scripts.txt and the Indic files
    // give them, the enumerations camel-case them.)
    const shortCategories = {
      'Lu': GeneralCategory.uppercaseLetter,
      'Mn': GeneralCategory.nonspacingMark,
      'Cn': GeneralCategory.unassigned,
    };
    final wrong = <String>[];
    for (var c = 0; c < 0x110000; c++) {
      if (shortCategories[category[c]] case final gc?
          when generalCategory(c) != gc) {
        wrong.add('${c.toRadixString(16)} gc');
      }
      if (indicSyllabicCategory(c).name != _camel(syllabic[c])) {
        wrong.add('${c.toRadixString(16)} InSC');
      }
      final pc = positional[c] == 'NA' ? 'Not_Applicable' : positional[c];
      if (indicPositionalCategory(c).name != _camel(pc)) {
        wrong.add('${c.toRadixString(16)} InPC');
      }
      if (isDefaultIgnorable(c) != ignorable.contains(c)) {
        wrong.add('${c.toRadixString(16)} DI');
      }
      if (wrong.length > 20) break;
    }
    expect(wrong, isEmpty);
    expect(scriptOf(0x41), 'Latn');
    expect(scriptOf(0x0915), 'Deva');
    expect(scriptOf(0x0700), 'Syrc');
    expect(scriptOf(0x0301), 'Zinh');
    expect(scriptOf(0x0020), 'Zyyy');
    expect(scriptOf(0x0378), 'Zzzz');
    // Every code point Scripts.txt names a script for has one.
    expect([
      for (var c = 0; c < 0x110000; c++)
        if (script[c] != 'Unknown' && scriptOf(c) == 'Zzzz') c,
    ], isEmpty);
    expect(verticalOrientation(0x41), VerticalOrientation.rotated);
    expect(verticalOrientation(0x4e00), VerticalOrientation.upright);
    expect(verticalOrientation(0x3001), VerticalOrientation.transformedUpright);
    expect(isMark(0x093f), isTrue);
    expect(isMark(0x0915), isFalse);
  });

  test('NormalizationTest.txt: NFD and NFC, from the canonical mappings', () {
    final lines = utf8
        .decode(
          gzip.decode(
            File('test/unicode/NormalizationTest.txt.gz').readAsBytesSync(),
          ),
        )
        .split('\n');
    var checked = 0;
    final wrong = <String>[];
    for (final line in lines) {
      final data = line.split('#').first.trim();
      if (data.isEmpty || data.startsWith('@')) continue;
      final columns = [
        for (final field in data.split(';').take(5))
          [for (final c in field.trim().split(' ')) int.parse(c, radix: 16)],
      ];
      final [source, nfc, nfd, _, _] = columns;
      // NFD and NFC of the source and of the NFC and NFD columns
      // (the canonical forms; the compatibility ones are not ours).
      for (final input in [source, nfc, nfd]) {
        if ('${_nfd(input)}' != '$nfd') wrong.add('NFD $data');
        if ('${_nfc(input)}' != '$nfc') wrong.add('NFC $data');
      }
      checked++;
      if (wrong.length > 10) break;
    }
    expect(wrong, isEmpty);
    expect(checked, greaterThan(19000));
  });
}
