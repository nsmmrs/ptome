// Reading fonts (the fixtures in test/fonts, made as its README says),
// subsetting them, and rejecting damaged ones.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:plain_fonts/plain_fonts.dart';
import 'package:test/test.dart';

Uint8List _read(String name) => File('test/fonts/$name').readAsBytesSync();

void main() {
  test('OpenType tables are read', () {
    final font = OpenTypeFont.parse(_read('notoserif-regular-latin.ttf'));
    expect(font.unitsPerEm, anyOf(1000, 2048));
    expect(font.postScriptName, 'NotoSerif');
    expect(font.familyName, 'Noto Serif');
    expect(font.glyphFor(0x41), isNot(0));
    expect(font.isTrueType, isTrue);
    expect(font.ascender, greaterThan(0));
    expect(font.typoAscender, isNotNull);
    expect(font.typoDescender, lessThan(0));
  });

  test('kern table pairs, from all subtables or one', () {
    final font = OpenTypeFont.parse(_read('notoserif-kern-subtables.ttf'));
    int glyph(String char) => font.glyphFor(char.codeUnitAt(0));
    // A later subtable's pair wins; one subtable alone gives its own.
    expect(font.kernTablePair(glyph('A'), glyph('V')), -40);
    expect(font.kernTablePair(glyph('A'), glyph('V'), subtable: 0), -80);
    expect(font.kernTablePair(glyph('T'), glyph('o'), subtable: 0), isNull);
    expect(font.kernTablePair(glyph('T'), glyph('o'), subtable: 1), -60);
    expect(font.kernTablePair(glyph('T'), glyph('o'), subtable: 2), isNull);
  });

  test('OpenType features', () {
    final font = OpenTypeFont.parse(_read('notoserif-features.ttf'));
    expect(font.hasFeature('onum'), isTrue);
    expect(font.hasFeature('zero'), isFalse);
    expect(font.singleSubstitutions('onum'), isNotEmpty);
  });

  test('TrueType subsets keep the glyphs used, and their ids', () {
    final font = OpenTypeFont.parse(_read('notoserif-regular-latin.ttf'));
    final used = [for (final c in 'Hi'.codeUnits) font.glyphFor(c)];
    final glyphs = glyphClosure(font, used);
    expect(glyphs, containsAll([0, ...used]));
    final subset = OpenTypeFont.parse(subsetTrueType(font, glyphs));
    expect(subset.numGlyphs, font.numGlyphs);
    expect(subset.bytes.length, lessThan(font.bytes.length ~/ 2));
    expect(subset.glyphBounds(used.first), font.glyphBounds(used.first));
  });

  test("a subset's checksums are OpenType's", () {
    // Each table record's checksum that of its table (the head table's
    // taken with its checkSumAdjustment 0), and the whole file summing to
    // 0xB1B0AFBA with the adjustment in place.
    final font = OpenTypeFont.parse(_read('notoserif-regular-latin.ttf'));
    final file = subsetTrueType(
      font,
      glyphClosure(font, [font.glyphFor(0x41)]),
    );
    final view = ByteData.sublistView(file);
    int sum(int from, int length) {
      var total = 0;
      for (var i = 0; i < length; i += 4) {
        var word = 0;
        for (var k = 0; k < 4; k++) {
          word = word << 8 | (i + k < length ? file[from + i + k] : 0);
        }
        total = (total + word) & 0xffffffff;
      }
      return total;
    }

    for (var t = 0; t < view.getUint16(4); t++) {
      final record = 12 + 16 * t;
      final tag = String.fromCharCodes(file.sublist(record, record + 4));
      final offset = view.getUint32(record + 8);
      final length = view.getUint32(record + 12);
      var expected = sum(offset, length);
      if (tag == 'head') {
        expected = (expected - view.getUint32(offset + 8)) & 0xffffffff;
      }
      expect(view.getUint32(record + 4), expected, reason: tag);
    }
    expect(sum(0, file.length), 0xb1b0afba);
  });

  test('a simple font subset maps its one-byte codes to its glyphs', () {
    final font = OpenTypeFont.parse(_read('notoserif-regular-latin.ttf'));
    final codes = {
      32: font.glyphFor(0x20),
      33: font.glyphFor(0x48),
      34: font.glyphFor(0x69),
    };
    final subset = OpenTypeFont.parse(
      subsetTrueType(font, glyphClosure(font, codes.values), codes: codes),
    );
    for (final MapEntry(key: code, value: glyph) in codes.entries) {
      expect(subset.glyphFor(0xf000 + code), glyph);
    }
    expect(subset.glyphFor(0xf000 + 35), 0);
  });

  test('CFF subsets keep the glyphs used', () {
    for (final name in ['notoserif-cff.otf', 'notoserif-cid.otf']) {
      final font = OpenTypeFont.parse(_read(name));
      final cff = font.table('CFF ')!;
      final glyphs = glyphClosure(font, [font.glyphFor(0x48)]);
      final subset = subsetCff(cff, glyphs);
      expect(subset, isNotNull, reason: name);
      expect(subset!.length, lessThan(cff.length), reason: name);
    }
  });

  test('damaged fonts are read or rejected with FontFormatExceptions', () {
    final random = Random(20261007);
    for (final name in [
      'notoserif-regular-latin.ttf',
      'notoserif-cff.otf',
      'libertinus-smcp.otf',
      'notoserif-features.woff2',
      'notoserif-features.woff',
    ]) {
      final bytes = _read(name);
      for (var i = 0; i < 150; i++) {
        final copy = Uint8List.fromList(bytes);
        for (var k = 0; k < 1 + random.nextInt(8); k++) {
          copy[random.nextInt(copy.length)] = random.nextInt(256);
        }
        final input = i.isEven
            ? copy
            : Uint8List.sublistView(copy, 0, random.nextInt(copy.length));
        try {
          final font = OpenTypeFont.parse(input);
          for (var c = 0x20; c < 0x7f; c++) {
            final glyph = font.glyphFor(c);
            font
              ..advance(glyph)
              ..kerning(glyph, font.glyphFor(c + 1));
          }
          if (font.isTrueType) {
            subsetTrueType(font, glyphClosure(font, [font.glyphFor(0x41)]));
          }
        } on FontFormatException {
          // Rejected, as it should be.
        }
      }
    }
  });
}
