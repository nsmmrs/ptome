/// resvg's reference renders as the oracle of SVG drawn in a PDF: each
/// case test/resvg holds (those drawn alike: its README) drawn on a page
/// of its own, rasterized by pdftoppm and compared with resvg's PNG of it
/// (flattened on white by ImageMagick). The comparisons are recorded in
/// test/oracles/resvg.json.gz (test/support/oracles.dart; ORACLES=record
/// compares again, with resvg's PNGs fetched by tool/fetch_resvg_tests.sh,
/// RESVG_TESTS where it put them).
@TestOn('vm')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'support/oracles.dart';
import 'support/pdf_tools.dart';
import 'support/resvg.dart';

/// Where tool/fetch_resvg_tests.sh puts resvg's cases and PNGs.
final String _suite =
    Platform.environment['RESVG_TESTS'] ??
    '${Platform.environment['HOME']}/.cache/asciidart-work/resvg/repo/'
        'crates/resvg/tests/tests';

void main() {
  final recorded = Oracle('resvg', compressed: true);
  final cases = [
    for (final line in File('test/resvg/cases.txt').readAsLinesSync())
      if (line.isNotEmpty && !line.startsWith('#'))
        if (line.split(' ') case [
          final name,
          final width,
          final height,
          final digest,
        ])
          (name, double.parse(width), double.parse(height), digest),
  ];

  test('SVG drawn as resvg draws it', () {
    final apart = <String>[];
    for (final (name, width, height, digest) in cases) {
      final pdf = resvgPage(File('test/resvg/tests/$name.svg'), width, height);
      if (pdf == null) {
        apart.add('$name (not read)');
        continue;
      }
      final alike = recorded.json<bool>(
        name,
        inputs: [popplerVersion, magickVersion, digest, pdf],
        oracle: () {
          final png = File('$_suite/$name.png').readAsBytesSync();
          if ('${sha256.convert(png)}' != digest) {
            throw StateError('$name: not the PNG test/resvg/cases.txt has');
          }
          return drawnAlike(pdf, png);
        },
      );
      if (!alike) apart.add(name);
    }
    expect(cases, hasLength(greaterThan(700)));
    expect(apart, isEmpty, reason: 'drawn alike no longer');
  });
}
