// The Unicode Bidirectional Algorithm against Unicode's conformance
// tests (UAX #9, Unicode 18.0.0): BidiTest.txt (sequences of classes,
// each with the paragraph directions it holds for) and
// BidiCharacterTest.txt (texts, bracket pairs among them).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plain_unicode/plain_unicode.dart';
import 'package:test/test.dart';

List<String> _lines(String name) => const LineSplitter().convert(
  utf8.decode(gzip.decode(File('test/unicode/$name').readAsBytesSync())),
);

/// The levels and visual order of a line as the tests give them: `x` for
/// a character removed by rule X9, the order of the others.
(List<String>, List<int>) _resolved(BidiText bidi, int length) {
  final line = bidi.lineLevels(0, length);
  final removed = <int>{};
  for (var i = 0; i < length; i++) {
    if (_isRemoved(bidi, i)) removed.add(i);
  }
  final levels = [
    for (var i = 0; i < length; i++)
      if (removed.contains(i)) 'x' else '${line[i]}',
  ];
  final order = [
    for (final i in bidi.visualOrder(0, length))
      if (!removed.contains(i)) i,
  ];
  return (levels, order);
}

late List<BidiClass> _current;

bool _isRemoved(BidiText bidi, int i) => switch (_current[i]) {
  BidiClass.lre ||
  BidiClass.rle ||
  BidiClass.lro ||
  BidiClass.rlo ||
  BidiClass.pdf ||
  BidiClass.bn => true,
  _ => false,
};

void main() {
  test('BidiTest.txt', () {
    var levels = <String>[];
    var order = <int>[];
    var cases = 0;
    final failures = <String>[];
    for (final line in _lines('BidiTest.txt.gz')) {
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('@Levels:')) {
        levels = line.substring(8).trim().split(RegExp(r'\s+'));
        if (levels.length == 1 && levels.first.isEmpty) levels = [];
        continue;
      }
      if (line.startsWith('@Reorder:')) {
        final text = line.substring(9).trim();
        order = text.isEmpty
            ? []
            : [for (final s in text.split(RegExp(r'\s+'))) int.parse(s)];
        continue;
      }
      final [input, bits] = line.split(';');
      final names = input.trim().split(' ');
      _current = [
        for (final name in names) BidiClass.values.byName(name.toLowerCase()),
      ];
      final classes = Uint8List.fromList([for (final c in _current) c.index]);
      final set = int.parse(bits.trim());
      for (final (bit, direction) in [
        (1, null),
        (2, TextDirection.ltr),
        (4, TextDirection.rtl),
      ]) {
        if (set & bit == 0) continue;
        cases++;
        final bidi = BidiText.classes(classes, direction: direction);
        final (gotLevels, gotOrder) = _resolved(bidi, classes.length);
        if (gotLevels.join(' ') != levels.join(' ') ||
            gotOrder.join(' ') != order.join(' ')) {
          if (failures.length < 20) {
            failures.add(
              '$input ($direction): levels ${gotLevels.join(' ')} '
              '(want ${levels.join(' ')}), order ${gotOrder.join(' ')} '
              '(want ${order.join(' ')})',
            );
          }
        }
      }
    }
    expect(failures, isEmpty, reason: '$cases cases');
  });

  test('BidiCharacterTest.txt', () {
    var cases = 0;
    final failures = <String>[];
    for (final line in _lines('BidiCharacterTest.txt.gz')) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final [points, direction, level, levels, order] = line.split(';');
      final text = String.fromCharCodes([
        for (final p in points.trim().split(' ')) int.parse(p, radix: 16),
      ]);
      // (Each test's characters in the BMP: one code unit each.)
      if (text.length != points.trim().split(' ').length) continue;
      _current = [for (final unit in text.codeUnits) bidiClass(unit)];
      cases++;
      final bidi = BidiText(
        text,
        direction: switch (direction) {
          '0' => TextDirection.ltr,
          '1' => TextDirection.rtl,
          _ => null,
        },
      );
      final (gotLevels, gotOrder) = _resolved(bidi, text.length);
      final wantOrder = order.trim().isEmpty ? '' : order.trim();
      if (bidi.paragraphLevel(0).toString() != level ||
          gotLevels.join(' ') != levels.trim() ||
          gotOrder.join(' ') != wantOrder) {
        if (failures.length < 20) {
          failures.add(
            '$points ($direction): level ${bidi.paragraphLevel(0)} '
            '(want $level), levels ${gotLevels.join(' ')} '
            '(want ${levels.trim()}), order ${gotOrder.join(' ')} '
            '(want $wantOrder)',
          );
        }
      }
    }
    expect(failures, isEmpty, reason: '$cases cases');
  });

  test('properties: classes, mirrors, joining types', () {
    expect(bidiClass(0x41), BidiClass.l);
    expect(bidiClass(0x5d0), BidiClass.r);
    expect(bidiClass(0x627), BidiClass.al);
    expect(bidiClass(0x660), BidiClass.an);
    expect(bidiClass(0x30), BidiClass.en);
    expect(bidiClass(0x5e9f), BidiClass.l);
    // (Unassigned in a right-to-left block: R, as the @missing lines say.)
    expect(bidiClass(0x5ff), BidiClass.r);
    expect(bidiMirror(0x28), 0x29);
    expect(bidiMirror(0xab), 0xbb);
    expect(bidiMirror(0x41), 0x41);
    expect(joiningType(0x628), JoiningType.dualJoining);
    expect(joiningType(0x627), JoiningType.rightJoining);
    expect(joiningType(0x64e), JoiningType.transparent);
    expect(joiningType(0x640), JoiningType.joinCausing);
    expect(joiningType(0x41), JoiningType.nonJoining);
    expect(canonicalCombiningClass(0x41), 0);
    expect(canonicalCombiningClass(0x651), 33); // shadda
    expect(canonicalCombiningClass(0x650), 32); // kasra
    expect(canonicalCombiningClass(0x5bc), 21); // dagesh
    expect(canonicalCombiningClass(0x301), 230);
    expect(hasRightToLeft('plain text'), isFalse);
    expect(hasRightToLeft('see שלום'), isTrue);
    expect(hasRightToLeft('رقم'), isTrue);
    expect(hasRightToLeft('\u0661'), isTrue); // an Arabic-Indic digit (AN)
    expect(hasRightToLeft('Ελληνικά'), isFalse);
  });
}
