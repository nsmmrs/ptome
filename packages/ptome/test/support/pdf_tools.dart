// (The same file in every package that uses it: tool/oracles_check.sh
// holds the copies alike.)

/// The tools the tests check their PDF files with (qpdf, Poppler,
/// librsvg, ImageMagick), their runs recorded (oracles.dart): each a
/// function of the file's bytes and the tool's options, so a file that
/// changes is checked again when recording.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'oracles.dart';

/// The tools, which their answers depend on.
const String qpdfVersion = 'qpdf 12.4.1';
const String popplerVersion = 'Poppler 26.08.0';
const String rsvgVersion = 'librsvg 2.62.3';
const String magickVersion = 'ImageMagick 7.1.2-31';

/// qpdf's check of [pdf].
ToolRun qpdfCheck(Oracle recorded, List<int> pdf) => recorded.run(
  'qpdf',
  ['--check', 'in.pdf'],
  version: qpdfVersion,
  files: {'in.pdf': pdf},
);

/// qpdf's QDF form of [pdf] (its objects uncompressed, in order), as
/// Latin-1 text.
String qpdfQdf(Oracle recorded, List<int> pdf) => recorded
    .run(
      'qpdf',
      ['--qdf', '--object-streams=disable', 'in.pdf', '-'],
      version: qpdfVersion,
      files: {'in.pdf': pdf},
    )
    .stdoutLatin1;

/// Poppler's [tool] (pdftotext, pdfinfo, pdffonts...) with [options]
/// before the file, and [after] it, on [pdf].
ToolRun poppler(
  Oracle recorded,
  String tool,
  List<int> pdf, {
  List<String> options = const [],
  List<String> after = const [],
}) => recorded.run(
  tool,
  [...options, 'in.pdf', ...after],
  version: popplerVersion,
  files: {'in.pdf': pdf},
);

/// pdftotext's text of [pdf] (UTF-8).
String pdftotext(
  Oracle recorded,
  List<int> pdf, {
  List<String> options = const [],
}) => poppler(
  recorded,
  'pdftotext',
  pdf,
  options: ['-enc', 'UTF-8', ...options],
  after: ['-'],
).stdout;

/// pdftoppm's rendering of [pdf] with [options] (a page each, by
/// `-f`/`-l`): the file it writes, PPM, PGM (`-gray`) or PNG (`-png`).
Uint8List pdftoppm(Oracle recorded, List<int> pdf, List<String> options) {
  final extension = options.contains('-png')
      ? 'png'
      : options.contains('-gray')
      ? 'pgm'
      : options.contains('-mono')
      ? 'pbm'
      : 'ppm';
  final run = recorded.run(
    'pdftoppm',
    [...options, '-singlefile', 'in.pdf', 'out'],
    version: popplerVersion,
    files: {'in.pdf': pdf},
  );
  final page = run.outputs['out.$extension'];
  if (page == null) throw StateError('pdftoppm: ${run.stderr}');
  return page;
}

/// The version of the tool [executable], which its answers depend on.
String _versionOf(String executable) => switch (executable) {
  'qpdf' => qpdfVersion,
  'rsvg-convert' => rsvgVersion,
  'magick' || 'mogrify' || 'convert' || 'compare' => magickVersion,
  _ => popplerVersion,
};

/// [Process.runSync] of a tool, recorded ([Oracle.run]): an argument that
/// is a file's path is given to it as `in0`, `in1`... (its
/// extension kept), an absolute one whose file doesn't exist yet as
/// `out0`, `out1`...
/// (an output, or the prefix of the outputs pdftoppm names), and what it
/// writes there is written back under the names asked for.
ProcessResult recordedRunSync(
  Oracle recorded,
  String executable,
  List<String> arguments, {
  Encoding? stdoutEncoding = systemEncoding,
}) {
  final files = <String, List<int>>{};
  final outputs = <String, String>{};
  String extension(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot) : '';
  }

  // (ImageMagick's frame index after a path: `file.gif[0]`.)
  final frame = RegExp(r'\[\d+\]$');
  final staged = [
    for (final argument in arguments)
      if (argument.replaceFirst(frame, '') case final path
          when !argument.startsWith('-') && File(path).existsSync())
        () {
          final name = 'in${files.length}${extension(path)}';
          files[name] = File(path).readAsBytesSync();
          return '$name${argument.substring(path.length)}';
        }()
      else if (File(argument).isAbsolute && File(argument).parent.existsSync())
        () {
          final name = 'out${outputs.length}';
          outputs[name] = argument;
          return '$name${extension(argument)}';
        }()
      else
        argument,
  ];
  final run = recorded.run(
    executable,
    staged,
    version: _versionOf(executable),
    files: files,
  );
  for (final MapEntry(key: written, value: bytes) in run.outputs.entries) {
    for (final MapEntry(key: name, value: path) in outputs.entries) {
      if (!written.startsWith(name)) continue;
      final asked = path.substring(0, path.length - extension(path).length);
      File('$asked${written.substring(name.length)}').writeAsBytesSync(bytes);
    }
  }
  final stdout = switch (stdoutEncoding) {
    null => run.stdoutBytes,
    // (The recording machine's system encoding: UTF-8, whatever this
    // one's is.)
    final encoding when identical(encoding, systemEncoding) => utf8.decode(
      run.stdoutBytes,
      allowMalformed: true,
    ),
    final encoding => encoding.decode(run.stdoutBytes),
  };
  return ProcessResult(0, run.exitCode, stdout, run.stderr);
}
