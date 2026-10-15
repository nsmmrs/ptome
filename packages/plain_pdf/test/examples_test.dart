// The examples run and write valid PDF files (qpdf's checks recorded in
// test/oracles/examples.json, test/support/oracles.dart; ORACLES=record
// asks it again).
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../example/booklet.dart' as booklet;
import '../example/plain_pdf_example.dart' as hello;
import '../example/report.dart' as report;
import '../example/svg_chart.dart' as chart;
import 'support/oracles.dart';
import 'support/pdf_tools.dart';

void main() {
  final recorded = Oracle('examples');
  late Directory dir;
  setUpAll(() => dir = Directory.systemTemp.createTempSync('libpdf.'));
  tearDownAll(() => dir.deleteSync(recursive: true));

  for (final (name, run) in [
    ('hello', hello.main),
    ('report', report.main),
    ('svg_chart', chart.main),
    ('booklet', booklet.main),
  ]) {
    test(name, () {
      final path = '${dir.path}/$name.pdf';
      run([path]);
      final bytes = File(path).readAsBytesSync();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final check = qpdfCheck(recorded, bytes);
      expect(check.exitCode, 0, reason: check.stdout);
    });
  }
}
