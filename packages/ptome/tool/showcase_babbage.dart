/// The showcase's table of logarithms (test/showcase/babbage), after
/// Babbage's Table of Logarithms of the Natural Numbers from 1 to 108000
/// (1827): the values computed here, not copied, written as AsciiDoc.
///
///     dart run tool/showcase_babbage.dart
///
/// The common logarithms of the numbers from 10,000 to 19,999 to seven
/// places, a row for each ten numbers as Babbage sets them: the first four
/// figures of the number (N.: in full at each ten, else the last), the
/// logarithms of the ten numbers that end
/// in 0 to 9 (the first in full, its first three figures apart; the others
/// their last four, the first three taken from the first column; where
/// those change within a row, the figures after the change marked), and
/// the difference between the logarithms of consecutive numbers there, in
/// units of the seventh place (D.). Each row's number is an anchor, so
/// that a page's head can give the range it holds.
library;

import 'dart:io';
import 'dart:math' as math;

const String _dir = 'test/showcase/babbage/text';

void main() {
  _write('$_dir/table.adoc', 1000, 2000);
  // (The excerpt's: three groups of five.)
  _write('$_dir/excerpt-table.adoc', 1000, 1015);
}

/// The table's rows from [from] to before [to] written to [path].
void _write(String path, int from, int to) {
  final out = StringBuffer()
    ..writeln('// Written by tool/showcase_babbage.dart: do not edit.')
    ..writeln()
    ..writeln(
      '[.logarithms,cols="^6,^10,9*^6,^5",options=header,'
      'grid=cols,frame=topbot]',
    )
    ..writeln('|===');
  // (Twelve columns: N., 0 to 9, D.)
  final head = ['N.', for (var d = 0; d < 10; d++) '$d', 'D.'];
  out.writeln(head.map((cell) => '|$cell').join(' '));
  for (var n = from; n < to; n++) {
    // (Seven places of each logarithm, as an integer: 0.0004341 is 4341.)
    final logs = [
      for (var d = 0; d < 10; d++)
        (math.log(n * 10 + d) / math.ln10 * 1e7).round(),
    ];
    final mantissa = [for (final log in logs) log - 40000000];
    final lead = mantissa.first ~/ 10000;
    final cells = <String>[
      // (The number in full at each ten, as Babbage sets it; else its
      // last figure.)
      '[[n$n,${n * 10}]]${n % 10 == 0 || n == from ? '$n' : '${n % 10}'}',
      '${_three(lead)} ${_four(mantissa.first % 10000)}',
      for (final m in mantissa.skip(1)) _figures(m, lead),
      '${logs[1] - logs[0]}',
    ];
    out
      ..writeln()
      ..writeln(cells.map((cell) => '|$cell').join(' '));
  }
  out.writeln('|===');
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('$out');
  stdout.writeln('wrote $path');
}

/// The last four figures of [mantissa], marked (`[.turn]`) where its
/// first three aren't [lead], the row's.
String _figures(int mantissa, int lead) => mantissa ~/ 10000 == lead
    ? _four(mantissa % 10000)
    : '[.turn]#${_four(mantissa % 10000)}#';

String _three(int value) => value.toString().padLeft(3, '0');

String _four(int value) => value.toString().padLeft(4, '0');
