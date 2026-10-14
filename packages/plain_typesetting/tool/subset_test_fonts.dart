/// Makes the script shaping tests' fonts (`test/fonts`) from the installed
/// Noto fonts, as `test/fixtures/scripts/fonts.txt` lists them: each
/// subset to the characters of its sample lines (with the space and the
/// dotted circle), its layout tables and every glyph they reach kept
/// (fontTools' pyftsubset, run through uv).
///
///     dart run tool/subset_test_fonts.dart [FONT_DIR [FONT...]]
///
/// FONT_DIR is where the Noto fonts are (`/usr/share/fonts/noto` by
/// default); with FONTs (test font names), only those are made; a font
/// fonts.txt names by an absolute path is read from
/// there (fonts not installed, kept in a cache: Noto Serif Tibetan from
/// google/fonts' `ofl/notoseriftibetan`), and `#n` names a collection's
/// face. The option `shaped` keeps only the glyphs HarfBuzz's shaping of
/// the lines gives (and the characters' own), not every glyph the layout
/// tables reach: an emoji font's sequences reach thousands (it needs the
/// native oracle, tool/oracles/harfbuzz-native).
library;

import 'dart:io';

void main(List<String> args) {
  final source = args.isNotEmpty ? args.first : '/usr/share/fonts/noto';
  final only = args.skip(1).toSet();
  final fixtures = Directory('test/fixtures/scripts');
  for (final line in File('${fixtures.path}/fonts.txt').readAsLinesSync()) {
    if (line.startsWith('#') || line.trim().isEmpty) continue;
    final fields = [for (final f in line.split('|')) f.trim()];
    final [font, from, lines, _] = fields.sublist(0, 4);
    if (only.isNotEmpty && !only.contains(font)) continue;
    // (Options after the fourth field: script tags renamed, `dev2=deva`;
    // `shaped`.)
    final options = fields.skip(4).toList();
    final retag = options.where((o) => o.contains('=')).firstOrNull;
    final text = StringBuffer(' ◌');
    for (final name in lines.split(' ')) {
      text.write(File('${fixtures.path}/$name').readAsStringSync());
    }
    final textFile = File('${Directory.systemTemp.path}/subset-text.txt')
      ..writeAsStringSync(text.toString());
    // (A path of its own, or a name in the font folder; `#n`: a
    // collection's face n.)
    final [file, ...face] = from.split('#');
    final path = file.startsWith('/') ? file : '$source/$file';
    final shaped = options.contains('shaped')
        ? _shapedGlyphs(path, text.toString())
        : null;
    final result = Process.runSync('uv', [
      'run',
      '-q',
      '--with',
      'fonttools',
      'pyftsubset',
      path,
      if (face.isNotEmpty) '--font-number=${face.first}',
      '--text-file=${textFile.path}',
      if (shaped != null) ...[
        '--gids=${shaped.join(',')}',
        '--no-layout-closure',
      ],
      '--layout-features=*',
      '--layout-scripts=*',
      '--name-IDs=*',
      '--notdef-outline',
      '--output-file=test/fonts/$font',
    ]);
    if (result.exitCode != 0) {
      throw StateError('pyftsubset $from: ${result.stderr}');
    }
    // Script tags renamed (`dev2=deva`), and a variable font pinned at
    // its default instance (the same glyphs, a quarter of the size).
    final [retagFrom, retagTo] = retag?.split('=') ?? ['', ''];
    final script = File('${Directory.systemTemp.path}/after-subset.py')
      ..writeAsStringSync('''
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
f = TTFont(sys.argv[1])
if sys.argv[2]:
    for table in ('GSUB', 'GPOS'):
        if table in f:
            for record in f[table].table.ScriptList.ScriptRecord:
                if record.ScriptTag == sys.argv[2]:
                    record.ScriptTag = sys.argv[3]
            f[table].table.ScriptList.ScriptRecord.sort(
                key=lambda r: r.ScriptTag)
if 'fvar' in f:
    f = instancer.instantiateVariableFont(
        f, {a.axisTag: None for a in f['fvar'].axes})
f.save(sys.argv[1])
''');
    final after = Process.runSync('uv', [
      'run',
      '-q',
      '--with',
      'fonttools',
      'python',
      script.path,
      'test/fonts/$font',
      if (retag != null) retagFrom.padRight(4) else '',
      if (retag != null) retagTo.padRight(4) else '',
    ]);
    if (after.exitCode != 0) {
      throw StateError('after subsetting $font: ${after.stderr}');
    }
    stdout.writeln(
      'test/fonts/$font: ${File('test/fonts/$font').lengthSync()} bytes',
    );
  }
}

/// The glyphs HarfBuzz gives for the lines of [text] in the font at
/// [path].
List<int> _shapedGlyphs(String path, String text) {
  final lines = [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line,
  ].join('\n');
  final process = Process.runSync('sh', [
    '-c',
    r'printf "%s\n" "$1" | "$0" "$2"',
    'tool/oracles/harfbuzz-native/hb-oracle',
    lines,
    path,
  ]);
  if (process.exitCode != 0) {
    throw StateError('hb-oracle $path: ${process.stderr}');
  }
  return {
    for (final m in RegExp(r'\[(\d+),').allMatches('${process.stdout}'))
      int.parse(m[1]!),
  }.toList()..sort();
}
