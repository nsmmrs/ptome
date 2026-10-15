/// resvg's whole reference-render suite, drawn and compared as
/// test/resvg_test.dart compares the cases test/resvg holds: lists the
/// cases drawn alike that test/resvg doesn't hold yet, and those it holds
/// that aren't any more. Run by hand (the suite is fetched, not
/// committed):
///
/// ```sh
/// tool/fetch_resvg_tests.sh          # into ~/.cache/asciidart-work
/// dart run tool/resvg_suite.dart [DIR]
/// ```
library;

import 'dart:io';

import '../test/support/resvg.dart';

void main(List<String> arguments) {
  final suite = arguments.isNotEmpty
      ? arguments.first
      : '${Platform.environment['HOME']}/.cache/asciidart-work/resvg/repo/'
            'crates/resvg/tests/tests';
  final held = {
    for (final line in File('test/resvg/cases.txt').readAsLinesSync())
      if (line.isNotEmpty && !line.startsWith('#')) line.split(' ').first,
  };
  final alike = <String>{};
  var cases = 0;
  for (final entity in Directory(suite).listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.svg')) continue;
    final base = entity.path.substring(0, entity.path.length - 4);
    final png = File('$base.png');
    if (!png.existsSync()) continue;
    cases++;
    final bytes = png.readAsBytesSync();
    final (width, height) = pngSize(bytes);
    final pdf = resvgPage(entity, width, height);
    if (pdf != null && drawnAlike(pdf, bytes)) {
      alike.add(base.substring(suite.length + 1));
    }
  }
  final gained = alike.difference(held).toList()..sort();
  final lost = held.difference(alike).toList()..sort();
  stdout.writeln(
    '${alike.length} of $cases cases drawn alike; '
    '${gained.length} new, ${lost.length} no longer',
  );
  for (final name in gained) {
    stdout.writeln('  new: $name');
  }
  for (final name in lost) {
    stdout.writeln('  no longer: $name');
  }
  exit(lost.isEmpty ? 0 : 1);
}
