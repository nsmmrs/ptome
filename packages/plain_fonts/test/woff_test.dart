// WOFF/WOFF2 fonts, checked against what the reference tools make of them:
// fixtures (made as test/fonts/README.md says), and round trips of test
// fonts of each kind through woff2_compress and woff2_decompress (their
// answers recorded in test/oracles/woff.json by test/support/oracles.dart;
// ORACLES=record asks them again).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:plain_fonts/plain_fonts.dart';
import 'package:test/test.dart';

import 'support/oracles.dart';

/// The oracle, which its answers depend on.
const String _woff2 = 'woff2 1.0.2';

/// The tables of the font [bytes], by tag.
Map<String, Uint8List> _tables(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  return {
    for (var i = 0; i < view.getUint16(4); i++)
      latin1.decode(
        bytes.sublist(12 + 16 * i, 16 + 16 * i),
      ): Uint8List.sublistView(
        bytes,
        view.getUint32(20 + 16 * i),
        view.getUint32(20 + 16 * i) + view.getUint32(24 + 16 * i),
      ),
  };
}

/// [head] without its checksum adjustment, which depends on the layout of
/// the whole file, and the flag a WOFF2 encoder sets (bit 11: the font was
/// transformed losslessly).
List<int> _head(Uint8List head) => [...head]
  ..fillRange(8, 12, 0)
  ..[16] &= ~0x08;

/// Expects the font [got] to have [want]'s tables, but for those named in
/// [except], and the head table's checksum adjustment.
void _expectTables(
  Uint8List got,
  Uint8List want, {
  Set<String> except = const {},
}) {
  final a = _tables(got);
  final b = _tables(want);
  expect(a.keys.toSet(), b.keys.toSet());
  for (final tag in b.keys) {
    if (except.contains(tag)) continue;
    expect(
      tag == 'head' ? _head(a[tag]!) : a[tag],
      tag == 'head' ? _head(b[tag]!) : b[tag],
      reason: tag,
    );
  }
}

/// Expects the sum of [font]'s words to be the one OpenType requires.
void _expectChecksum(Uint8List font) {
  final view = ByteData.sublistView(font);
  var sum = 0;
  for (var i = 0; i < font.length; i += 4) {
    sum = (sum + view.getUint32(i)) & 0xffffffff;
  }
  expect(sum, 0xb1b0afba);
}

Uint8List _read(String path) => File(path).readAsBytesSync();

/// The SHA-256 of each of [font]'s tables, by tag ([_head]'s for head).
Map<String, String> _tableDigests(Uint8List font) => {
  for (final MapEntry(:key, :value) in _tables(font).entries)
    key: '${sha256.convert(key == 'head' ? _head(value) : value)}',
};

/// What woff2_compress makes of the font [source] (named [name]), and the
/// digests of the tables woff2_decompress gives back from it.
Map<String, Object?> _woff2RoundTrip(String name, Uint8List source) {
  final tmp = Directory.systemTemp.createTempSync('woff_test.');
  try {
    final base = name.substring(0, name.length - 4);
    File('${tmp.path}/$name').writeAsBytesSync(source);
    final compress = Process.runSync('woff2_compress', ['${tmp.path}/$name']);
    if (compress.exitCode != 0) throw StateError('${compress.stderr}');
    final woff2 = File('${tmp.path}/$base.woff2');
    final reference = woff2.copySync('${tmp.path}/ref-$base.woff2');
    final decompress = Process.runSync('woff2_decompress', [reference.path]);
    if (decompress.exitCode != 0) throw StateError('${decompress.stderr}');
    return {
      'woff2': base64Encode(woff2.readAsBytesSync()),
      'tables': _tableDigests(_read('${tmp.path}/ref-$base.ttf')),
    };
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

void main() {
  final recorded = Oracle('woff');
  group('WOFF', () {
    final original = _read('test/fonts/notoserif-features.ttf');

    test('recognizes web fonts', () {
      expect(isWebFont(_read('test/fonts/notoserif-features.woff')), isTrue);
      expect(isWebFont(_read('test/fonts/notoserif-features.woff2')), isTrue);
      expect(isWebFont(original), isFalse);
      expect(isWebFont([0x77]), isFalse);
    });

    test('WOFF: the font, table for table', () {
      final font = decodeWebFont(_read('test/fonts/notoserif-features.woff'));
      _expectTables(font, original);
      _expectChecksum(font);
    });

    test('WOFF2: the tables, glyf and loca as the reference rebuilds them', () {
      for (final name in [
        'notoserif-features.woff2',
        // With the hmtx table transformed too (by fontTools).
        'notoserif-features-hmtx.woff2',
      ]) {
        final font = decodeWebFont(_read('test/fonts/$name'));
        _expectTables(font, original, except: {'glyf', 'loca'});
        final tables = _tables(font);
        // What woff2_decompress makes of them.
        expect(
          md5.convert(tables['glyf']!).toString(),
          '50826e51c81f3e990040338be187aa78',
        );
        expect(
          md5.convert(tables['loca']!).toString(),
          '3cb8921037db03f76bfb7e836b96653c',
        );
        _expectChecksum(font);
      }
    });

    test('WOFF2 with CFF outlines', () {
      final font = decodeWebFont(_read('test/fonts/libertinus-smcp.woff2'));
      _expectTables(font, _read('test/fonts/libertinus-smcp.otf'));
      _expectChecksum(font);
    });

    test('OpenTypeFont reads web fonts', () {
      final woff2 = OpenTypeFont.parse(
        _read('test/fonts/notoserif-features.woff2'),
      );
      final ttf = OpenTypeFont.parse(original);
      expect(woff2.familyName, ttf.familyName);
      expect(woff2.numGlyphs, ttf.numGlyphs);
      expect(woff2.unitsPerEm, ttf.unitsPerEm);
      expect(
        OpenTypeFont.parse(_read('test/fonts/notoserif-features.woff'))
            .postScriptName,
        ttf.postScriptName,
      );
    });

    test('malformed web fonts throw FontFormatExceptions', () {
      final woff2 = _read('test/fonts/notoserif-features.woff2');
      for (final bytes in [
        woff2.sublist(0, 30),
        woff2.sublist(0, woff2.length - 200),
        [...woff2]..fillRange(48, 60, 0xff),
        _read('test/fonts/notoserif-features.woff').sublist(0, 400),
      ]) {
        expect(() => decodeWebFont(bytes), throwsA(isA<FontFormatException>()));
      }
      expect(
        () => decodeWebFont(original),
        throwsA(isA<FontFormatException>()),
      );
    });

    test('decodes what woff2_compress makes of each kind of test font', () {
      // (TrueType outlines, kerned by GPOS and by a kern table; CFF, by
      // name and CID-keyed.)
      for (final name in const [
        'notoserif-features.ttf',
        'notoserif-kern-subtables.ttf',
        'libertinus-smcp.otf',
        'notoserif-cid.otf',
      ]) {
        final source = _read('test/fonts/$name');
        final theirs = recorded.json<Map<String, Object?>>(
          name,
          inputs: [_woff2, source],
          oracle: () => _woff2RoundTrip(name, source),
        );
        final font = decodeWebFont(base64Decode(theirs['woff2']! as String));
        expect(
          _tableDigests(font),
          theirs['tables'],
          reason: 'the tables woff2_decompress gives',
        );
        _expectChecksum(font);
      }
    });
  });
}
