/// Auto-detection matches highlight.js: for upstream's detection samples
/// and markup inputs, `highlightAuto` picks the same language, with the
/// same relevance and runner-up, as highlight.js 11.12.0
/// (`test/reference/detect.json`, from `tool/generate/reference.mjs`):
/// every detection sample, every fourth markup input (each a language's
/// own test, in markup_test.dart), split across `detect_<n>_test.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:plain_highlighting/plain_highlighting.dart';
import 'package:test/test.dart';

/// The detection tests: those of every [parts]th input, from the
/// [part]th.
void detectTests({required int part, required int parts}) {
  final reference = (jsonDecode(
    File('test/reference/detect.json').readAsStringSync(),
  ) as Map<String, Object?>).cast<String, Map<String, Object?>>();
  final paths = [
    for (final (i, path) in reference.keys.indexed)
      if (path.startsWith('detect/') || i % 4 == 0) path,
  ];
  for (final (i, path) in paths.indexed) {
    if (i % parts != part) continue;
    final expected = reference[path]!;
    test(path, () {
      final code = File('vendor/highlight.js/test/$path').readAsStringSync();
      final result = highlighting.highlightAuto(code);
      expect(
        (
          language: result.language,
          relevance: result.relevance,
          secondBest: result.secondBest?.language,
        ),
        (
          language: expected['language'],
          relevance: expected['relevance'],
          secondBest: expected['secondBest'],
        ),
      );
    });
  }
}
