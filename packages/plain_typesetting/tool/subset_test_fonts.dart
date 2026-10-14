/// Makes the script shaping tests' fonts (`test/fonts`) from the installed
/// Noto fonts, as `test/fixtures/scripts/fonts.txt` lists them: each
/// subset to the characters of its sample lines (with the space and the
/// dotted circle), its layout tables and every glyph they reach kept
/// (fontTools' pyftsubset, run through uv).
///
///     dart run tool/subset_test_fonts.dart [FONT_DIR]
///
/// FONT_DIR is where the Noto fonts are (`/usr/share/fonts/noto` by
/// default).
library;

import 'dart:io';

void main(List<String> args) {
  final source = args.isNotEmpty ? args.first : '/usr/share/fonts/noto';
  final fixtures = Directory('test/fixtures/scripts');
  for (final line in File('${fixtures.path}/fonts.txt').readAsLinesSync()) {
    if (line.startsWith('#') || line.trim().isEmpty) continue;
    final [font, from, lines, _] = [for (final f in line.split('|')) f.trim()];
    final text = StringBuffer(' ◌');
    for (final name in lines.split(' ')) {
      text.write(File('${fixtures.path}/$name').readAsStringSync());
    }
    final textFile = File('${Directory.systemTemp.path}/subset-text.txt')
      ..writeAsStringSync(text.toString());
    final result = Process.runSync('uv', [
      'run',
      '-q',
      '--with',
      'fonttools',
      'pyftsubset',
      '$source/$from',
      '--text-file=${textFile.path}',
      '--layout-features=*',
      '--layout-scripts=*',
      '--name-IDs=*',
      '--notdef-outline',
      '--output-file=test/fonts/$font',
    ]);
    if (result.exitCode != 0) {
      throw StateError('pyftsubset $from: ${result.stderr}');
    }
    stdout.writeln(
      'test/fonts/$font: ${File('test/fonts/$font').lengthSync()} bytes',
    );
  }
}
