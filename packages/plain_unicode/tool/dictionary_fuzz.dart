/// Compares the dictionary word breaks with ICU's on random text: words of
/// each dictionary run together, with now and then a few letters no word
/// starts with and a space, broken by `lineBreaks` and by ICU's line break
/// iterator (the `icubreak` oracle: `tool/oracles/icu/setup.sh`).
///
/// ```sh
/// dart run tool/dictionary_fuzz.dart ICUBREAK [LINES_PER_SCRIPT] [SEED]
/// ```
///
/// With `--write`, it writes the lines and ICU's breaks (40 a script, seed
/// 1, unless given) to `test/fixtures/dictionary_breaks.txt` instead, for
/// the test that runs without ICU.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:plain_compression/plain_compression.dart';
import 'package:plain_unicode/plain_unicode.dart';
import 'package:plain_unicode/src/dictionaries.g.dart';

/// One item in this many is random letters, one a space.
const int _noise = 6;

const Map<String, (String, int, int)> _scripts = {
  'Thai': ('th', 0x0e01, 0x0e5b),
  'Laoo': ('lo', 0x0e81, 0x0edf),
  'Khmr': ('km', 0x1780, 0x17f9),
  'Mymr': ('my', 0x1000, 0x109f),
};

Future<void> main(List<String> arguments) async {
  final args = [...arguments];
  final write = args.remove('--write');
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/dictionary_fuzz.dart ICUBREAK [LINES] [SEED]',
    );
    exit(2);
  }
  final count = args.length > 1 ? int.parse(args[1]) : (write ? 40 : 2000);
  final random = Random(args.length > 2 ? int.parse(args[2]) : 1);
  var failures = 0;
  final golden = StringBuffer(
    '# Lines of Thai, Lao, Khmer and Myanmar dictionary words and a few\n'
    '# letters, each followed by the line break offsets ICU 78.3 gives it\n'
    "# (tool/dictionary_fuzz.dart --write; the words are ICU's).\n",
  );
  for (final MapEntry(key: script, value: (locale, first, last))
      in _scripts.entries) {
    final words = utf8
        .decode(brotliDecode(base64.decode(dictionaries[script]!)))
        .split('\n')
        .where((w) => w.isNotEmpty)
        .toList();
    String letters() => String.fromCharCodes([
      for (var i = random.nextInt(3) + 1; i > 0; i--)
        first + random.nextInt(last - first + 1),
    ]);
    final lines = [
      for (var n = 0; n < count; n++)
        [
          for (var i = random.nextInt(10) + 2; i > 0; i--)
            switch (random.nextInt(_noise)) {
              0 => letters(),
              1 => ' ',
              _ => words[random.nextInt(words.length)],
            },
        ].join().trim(),
    ].where((l) => l.isNotEmpty && !l.contains('  ')).toList();
    final process = await Process.start(args.first, [locale]);
    // (Read while writing: a long input fills the pipes otherwise.)
    final output = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .toList();
    process.stdin.write(lines.map((l) => '$l\n').join());
    await process.stdin.close();
    final expected = await output;
    if (write) {
      for (final (i, line) in lines.indexed) {
        golden
          ..writeln(line)
          ..writeln(expected[i]);
      }
      continue;
    }
    var failed = 0;
    for (final (i, line) in lines.indexed) {
      final actual = [0, for (final b in lineBreaks(line)) b.offset].join(' ');
      if (actual != expected[i]) {
        failed++;
        if (failed <= 5) {
          stdout
            ..writeln('$script: $line')
            ..writeln('  ICU:   ${expected[i]}')
            ..writeln('  ptome: $actual');
        }
      }
    }
    stdout.writeln('$script: ${lines.length - failed}/${lines.length} agree');
    failures += failed;
  }
  if (write) {
    final root = File(Platform.script.toFilePath()).parent.parent.path;
    File('$root/test/fixtures/dictionary_breaks.txt')
        .writeAsStringSync(golden.toString());
    return;
  }
  exitCode = failures == 0 ? 0 : 1;
}
