// Brotli streams the brotli tool made (fixtures, made as test/brotli's
// README says, and its streams at every quality, recorded in
// test/oracles/brotli.json by test/support/oracles.dart; ORACLES=record
// asks the tool again); damaged streams are rejected.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart';
import 'package:test/test.dart';

import 'support/oracles.dart';

/// The oracle, which its answers depend on.
const String _brotli = 'brotli 1.2.0';

/// The brotli tool's stream for [data] at [quality] and [window], as
/// recorded for [key].
Uint8List _brotliStream(
  Oracle recorded,
  String key,
  List<int> data,
  int quality,
  int window,
) => base64Decode(
  recorded.answer(
    key,
    inputs: [_brotli, data, '$quality', '$window'],
    oracle: () {
      final tmp = Directory.systemTemp.createTempSync('brotli.');
      try {
        final input = File('${tmp.path}/input')..writeAsBytesSync(data);
        final output = '${input.path}.br';
        final run = Process.runSync('brotli', [
          '-f',
          '-q',
          '$quality',
          '-w',
          '$window',
          '-o',
          output,
          input.path,
        ]);
        if (run.exitCode != 0) throw StateError('${run.stderr}');
        return base64Encode(File(output).readAsBytesSync());
      } finally {
        tmp.deleteSync(recursive: true);
      }
    },
  ),
);

Uint8List _read(String path) => File(path).readAsBytesSync();

void main() {
  final recorded = Oracle('brotli');
  group('Brotli', () {
    final words = _read('test/brotli/words.txt');
    test('static dictionary words and their transforms', () {
      expect(brotliDecode(_read('test/brotli/words.txt.br')), words);
    });

    test('a small window, and a fast quality', () {
      final repeated = [for (var i = 0; i < 40; i++) ...words];
      expect(brotliDecode(_read('test/brotli/words-x40-w10.br')), repeated);
      expect(brotliDecode(_read('test/brotli/words-x40-q1.br')), repeated);
    });

    test('expanded as far as asked, then on from there', () {
      final reader = BrotliReader(_read('test/brotli/words.txt.br'));
      expect(reader.length, 0);
      reader.readTo(100);
      // (Whole commands: at least as far, not to the end.)
      expect(reader.length, greaterThanOrEqualTo(100));
      expect(reader.length, lessThan(words.length));
      expect(reader.done, isFalse);
      expect(reader.output, words.sublist(0, reader.length));
      for (var target = 200; !reader.done; target += 97) {
        reader.readTo(target);
        expect(
          reader.length,
          reader.done ? words.length : greaterThanOrEqualTo(target),
        );
      }
      expect(reader.output, words);
      reader.readTo(1 << 40);
      expect(reader.length, words.length);
    });

    test('empty and one-byte streams', () {
      expect(brotliDecode([0x3f]), isEmpty);
      expect(brotliDecode([0x0f, 0x00, 0x80, 0x78, 0x03]), [0x78]);
    });

    test('malformed streams throw FormatExceptions', () {
      final stream = _read('test/brotli/words.txt.br');
      expect(
        () => brotliDecode(stream.sublist(0, stream.length ~/ 2)),
        throwsFormatException,
      );
      final random = Random(1);
      for (var i = 0; i < 300; i++) {
        final bytes = [...stream];
        bytes[random.nextInt(bytes.length)] ^= 1 << random.nextInt(8);
        try {
          brotliDecode(bytes);
        } on FormatException {
          // Expected (unless the flip still makes a stream).
        }
      }
    });

    test('decodes what the brotli tool makes, at every quality', () {
      final random = Random(2);
      final inputs = {
        'words': utf8.encode(
          [
            for (var i = 0; i < 3000; i++)
              const ['the', 'The', 'time', 'world', 'Hello', '"', '.'][random
                  .nextInt(7)],
          ].join(' '),
        ),
        'random': [for (var i = 0; i < 7000; i++) random.nextInt(256)],
        // Structured binary data.
        'binary': [
          for (var i = 0; i < 6000; i++) (i * i ~/ 7 + (i >> 8)) & 0xff,
        ],
      };
      for (final MapEntry(key: name, value: data) in inputs.entries) {
        for (final (quality, window) in [
          (0, 16),
          (2, 10),
          (5, 18),
          (9, 22),
          (11, 24),
        ]) {
          final stream = _brotliStream(
            recorded,
            '$name at quality $quality, window $window',
            data,
            quality,
            window,
          );
          expect(
            brotliDecode(stream),
            data,
            reason: '$name at quality $quality',
          );
        }
      }
    });
  });

  test('damaged streams are decoded or rejected with FormatExceptions', () {
    final random = Random(20261006);
    for (final file in Directory('test/brotli').listSync().whereType<File>()) {
      if (!file.path.endsWith('.br')) continue;
      final bytes = file.readAsBytesSync();
      for (var i = 0; i < 400; i++) {
        final copy = Uint8List.fromList(bytes);
        for (var k = 0; k < 1 + random.nextInt(8); k++) {
          copy[random.nextInt(copy.length)] = random.nextInt(256);
        }
        final input = i.isEven
            ? copy
            : Uint8List.sublistView(copy, 0, random.nextInt(copy.length));
        try {
          brotliDecode(input);
        } on FormatException {
          // Rejected, as it should be (or decoded: a flip can still make a
          // stream).
        }
      }
    }
  });
}
