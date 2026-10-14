/// Times plain_hyphenation where its word cache doesn't help: a language's
/// startup (its patterns' family decompressed and its trie decoded) and
/// its cache misses (every word of `test/fixtures/words/<tag>.txt` once,
/// with a hyphenator of its own), for each language there; the median of
/// --runs after a warmup.
///
/// ```sh
/// dart compile exe benchmark/hyphenation.dart -o /tmp/hyph && /tmp/hyph
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart' show brotliDecode;
import 'package:plain_hyphenation/src/liang.dart';
import 'package:plain_hyphenation/src/patterns.g.dart';

void main(List<String> args) {
  final runs = args.isEmpty ? 21 : int.parse(args.first);
  final files = Directory('test/fixtures/words').listSync()
    ..sort((a, b) => a.path.compareTo(b.path));
  var startupTotal = 0.0;
  var missTotal = 0.0;
  var wordTotal = 0;
  for (final file in files) {
    final tag = file.uri.pathSegments.last.replaceAll('.txt', '');
    final entry = hyphenationPatterns[tag];
    if (entry == null) continue;
    final (left, right, family, at, length, exAt, exLength) = entry;
    final words = File(file.path)
        .readAsLinesSync()
        .where((w) => w.isNotEmpty)
        .toList();
    PatternHyphenator build() {
      final bytes = brotliDecode(base64Decode(patternFamilies[family]!));
      return compiledHyphenator(
        Uint8List.sublistView(bytes, at, at + length),
        exceptions: utf8.decode(
          Uint8List.sublistView(bytes, exAt, exAt + exLength),
        ),
        left: left,
        right: right,
      );
    }

    double median(List<int> xs) => (xs..sort())[xs.length ~/ 2] / 1000;
    final startups = <int>[];
    final misses = <int>[];
    var sink = 0;
    for (var r = -3; r < runs; r++) {
      final watch = Stopwatch()..start();
      final hyphenator = build();
      final built = watch.elapsedMicroseconds;
      watch.reset();
      for (final w in words) {
        sink += hyphenator.hyphenate(w).length;
      }
      final missed = watch.elapsedMicroseconds;
      if (r >= 0) {
        startups.add(built);
        misses.add(missed);
      }
    }
    final startup = median(startups);
    final miss = median(misses);
    startupTotal += startup;
    missTotal += miss;
    wordTotal += words.length;
    stdout.writeln(
      '${tag.padRight(10)} startup ${startup.toStringAsFixed(2)} ms  '
      '${words.length} misses ${miss.toStringAsFixed(2)} ms  '
      '(${(miss * 1000 / words.length).toStringAsFixed(2)} µs a word)'
      '${sink < 0 ? '' : ''}',
    );
  }
  stdout.writeln(
    'total      startup ${startupTotal.toStringAsFixed(1)} ms  '
    '$wordTotal misses ${missTotal.toStringAsFixed(1)} ms',
  );
}
