// (The same file in every package that uses it: tool/oracles_check.sh
// holds the copies alike.)

/// Outside tools' answers, recorded: a test that checks the code against an
/// oracle (HarfBuzz, ICU, a PDF validator...) asks for the oracle's answer
/// by a key and the inputs it depends on, and gets the answer recorded in
/// `test/oracles/<name>.json` (`.json.gz` for a large one), so that it runs
/// anywhere in a moment and the tool needn't be installed. An answer whose
/// inputs have changed since it was recorded is stale, and the test fails
/// until it is recorded again:
///
/// ```sh
/// ORACLES=record dart test test/harfbuzz_test.dart   # the tool installed
/// ```
///
/// which asks the oracle again for every answer the run asks for and
/// writes them into the file (keeping those it didn't ask for).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

/// The answers recorded for one test file, `test/oracles/<name>.json`.
final class Oracle {
  /// The answers of `test/oracles/[name].json`, or gzip-compressed in
  /// `.json.gz` when [compressed], written back at the end of the file's
  /// tests when recording.
  new(this.name, {this.compressed = false})
    : _file = File('test/oracles/$name.json${compressed ? '.gz' : ''}') {
    if (recording) tearDownAll(_write);
  }

  final String name;
  final bool compressed;
  final File _file;

  /// Whether the oracles are asked again (`ORACLES=record`).
  static final bool recording = Platform.environment['ORACLES'] == 'record';

  late final Map<String, ({String inputs, String answer})> _recorded = {
    if (_file.existsSync())
      for (final MapEntry(:key, :value)
          in (jsonDecode(_read()) as Map<String, Object?>).entries)
        if (value case {
          'inputs': final String inputs,
          'answer': final String answer,
        })
          key: (inputs: inputs, answer: answer),
  };

  final Map<String, ({String inputs, String answer})> _asked = {};

  /// The answer recorded for [key], whose [inputs] (strings and bytes)
  /// are what the oracle's answer depends on; when recording, [oracle]'s.
  String answer(
    String key, {
    required List<Object> inputs,
    required String Function() oracle,
  }) {
    final digest = _digest(inputs);
    if (recording) {
      final answer = oracle();
      _asked[key] = (inputs: digest, answer: answer);
      return answer;
    }
    final recorded = _recorded[key];
    if (recorded == null) {
      fail(
        'no answer recorded for "$key" in ${_file.path}: '
        'ORACLES=record dart test, with the oracle installed',
      );
    }
    if (recorded.inputs != digest) {
      fail(
        'the answer recorded for "$key" in ${_file.path} is for other '
        'inputs: ORACLES=record dart test, with the oracle installed',
      );
    }
    return recorded.answer;
  }

  /// [answer] for an oracle whose answer is JSON: [oracle]'s value,
  /// encoded when recorded and decoded when read.
  T json<T>(
    String key, {
    required List<Object> inputs,
    required T Function() oracle,
  }) => jsonDecode(
    answer(key, inputs: inputs, oracle: () => jsonEncode(oracle())),
  ) as T;

  /// The SHA-256 of [inputs], each a string or bytes, in order.
  static String _digest(List<Object> inputs) {
    final bytes = BytesBuilder(copy: false);
    for (final input in inputs) {
      final data = switch (input) {
        final String s => utf8.encode(s),
        final List<int> b => b,
        _ => throw ArgumentError.value(input, 'inputs', 'not text or bytes'),
      };
      // (Each input's length first, so that no two lists run together.)
      bytes
        ..add(utf8.encode('${data.length}:'))
        ..add(data);
    }
    return sha256.convert(bytes.takeBytes()).toString();
  }

  String _read() => compressed
      ? utf8.decode(gzip.decode(_file.readAsBytesSync()))
      : _file.readAsStringSync();

  void _write() {
    _file.parent.createSync(recursive: true);
    final answers = {..._recorded, ..._asked};
    final keys = answers.keys.toList()..sort();
    final json = const JsonEncoder.withIndent('  ').convert({
      for (final key in keys)
        key: {'inputs': answers[key]!.inputs, 'answer': answers[key]!.answer},
    });
    if (compressed) {
      _file.writeAsBytesSync(gzip.encode(utf8.encode('$json\n')));
    } else {
      _file.writeAsStringSync('$json\n');
    }
  }
}
