/// `ptome look`: commands about looks (ADR-0023). `ptome look explain`
/// prints what each item of a look became in each output, and what an
/// output left out and why.
library;

import 'package:ptome/src/cli/compat_config.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/look/explain.dart';
import 'package:ptome/src/look/loader.dart';

/// Usage text for `look` (printed by `--help` and on misuse).
const String lookUsage = '''
Usage: ptome look explain [options] [LOOK]

Prints what each token and style of a look became in each output: the PDF
theme's keys, HTML's custom properties and CSS, an EPUB's CSS; and what an
output left out, and why (a warning, when the look sets what the output
can't render). LOOK is a built-in look (ptome), a name found as
<LOOK>-look.yml in the looks folder, or a path ending in .yml; by default
the look ptome.yml or ~/.config/ptome/config.yml names, else ptome.

Options:
      --looksdir=DIR   the folder of the looks (default: the one ptome.yml
                       names, else the current folder)
      --format=FORMAT  the output to explain: pdf, html, epub3 (a list, or
                       the option given again; default: all three)
  -h, --help           show this help
''';

/// Runs `ptome look` with [args] (the arguments after `look`) and returns
/// the exit status: 0, 1 when the look can't be read, 64 on misuse.
int runLook(List<String> args, {StringSink? out, StringSink? err}) {
  final stdout = out ?? io.standardOutput;
  final stderr = err ?? io.standardError;
  int misuse(String message) {
    stderr
      ..writeln('ptome look: $message')
      ..write(lookUsage);
    return 64;
  }

  if (args.isEmpty) {
    stderr.write(lookUsage);
    return 64;
  }
  switch (args.first) {
    case '-h' || '--help':
      stdout.write(lookUsage);
      return 0;
    case 'explain':
      break;
    case final command:
      return misuse('unknown command $command');
  }
  String? name;
  String? looksDir;
  final outputs = <LookOutput>{};
  var manpage = false;
  final rest = args.sublist(1);
  for (var i = 0; i < rest.length; i++) {
    final arg = rest[i];
    // `--option=value`, or `--option value`.
    String? value(String option) {
      if (arg.startsWith('$option=')) return arg.substring(option.length + 1);
      if (arg == option && i + 1 < rest.length) return rest[++i];
      return null;
    }

    if (arg == '-h' || arg == '--help') {
      stdout.write(lookUsage);
      return 0;
    } else if (value('--looksdir') case final dir?) {
      looksDir = dir;
    } else if (value('--format') case final formats?) {
      for (final format in formats.split(',')) {
        if (format == 'manpage') {
          manpage = true;
        } else if (LookOutput.named(format) case final output?) {
          outputs.add(output);
        } else {
          return misuse('no output $format (pdf, html, epub3)');
        }
      }
    } else if (arg.startsWith('-')) {
      return misuse('unknown option $arg');
    } else if (name != null) {
      return misuse('one look at a time');
    } else {
      name = arg;
    }
  }
  if (name == null) {
    final configured = resolveLook(
      env: io.environment,
      startDir: io.currentDirectory,
      warn: (message) => stderr.writeln('ptome: WARNING: $message'),
    );
    name = configured?.look ?? 'ptome';
    looksDir ??= configured?.looksDir;
  }
  try {
    final look = LookLoader(looksDir: looksDir ?? io.currentDirectory)
        .load(name);
    if (manpage) {
      stdout.writeln(
        'manpage: a manual page takes no look; man and its pager set it.',
      );
      if (outputs.isEmpty) return 0;
      stdout.writeln();
    }
    stdout.write(
      explainLook(look, outputs.isEmpty ? {...LookOutput.values} : outputs),
    );
    return 0;
  } on LookException catch (e) {
    stderr.writeln('ptome look: $e');
    return 1;
  }
}
