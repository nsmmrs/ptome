// The Medina mushaf, line for line (tool/mushaf.dart): 604 pages of 15
// lines, each page as the mushaf has it. Its data and font are fetched
// into a cache, never committed, so without them the test is skipped.
@TestOn('vm')
@Tags(['slow'])
library;

import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:test/test.dart';

final String _cache =
    Platform.environment['MUSHAF_DIR'] ??
    '${Platform.environment['HOME']}/.cache/asciidart-work/mushaf';

/// Whether the cache has the font and every page's words.
bool get _fetched =>
    File('$_cache/UthmanicHafs1Ver18.ttf').existsSync() &&
    File('$_cache/chapters.json').existsSync() &&
    Directory('$_cache/pages').existsSync() &&
    Directory('$_cache/pages').listSync().length == 604;

void main() {
  test(
    'every page as the mushaf has it: 604, no line wrapped or moved on',
    () {
      registerPdf();
      final work = Directory.systemTemp.createTempSync('mushaf.');
      addTearDown(() => work.deleteSync(recursive: true));
      // (Everything fetched: the tool only writes the document and theme.)
      final generate = Process.runSync(Platform.resolvedExecutable, [
        'run',
        'tool/mushaf.dart',
        _cache,
      ]);
      expect(generate.exitCode, 0, reason: '${generate.stderr}');
      final logger = MemoryLogger();
      final previous = LoggerManager.logger;
      LoggerManager.logger = logger;
      try {
        convertFile(
          '$_cache/mushaf.adoc',
          AsciidoctorOptions(
            safe: SafeMode.unsafe,
            backend: 'pdf',
            toDir: work.path,
          ),
        );
      } finally {
        LoggerManager.logger = previous;
      }
      expect([
        for (final m in logger.messages)
          if (m.severity.index >= Severity.warn.index) '${m.message}',
      ], isEmpty);
      // A line too wide for the measure would wrap, a page of 15 lines
      // then run onto another.
      final info = Process.runSync('pdfinfo', ['${work.path}/mushaf.pdf']);
      expect(info.stdout, matches(RegExp(r'Pages:\s+604\n')));
      // The last page's last words, and the Fatiha on the first.
      final last = Process.runSync('pdftotext', [
        '-f',
        '604',
        '-l',
        '604',
        '${work.path}/mushaf.pdf',
        '-',
      ]);
      expect('${last.stdout}', contains('سورة الناس'));
      final first = Process.runSync('pdftotext', [
        '-l',
        '1',
        '${work.path}/mushaf.pdf',
        '-',
      ]);
      expect('${first.stdout}', contains('سورة الفاتحة'));
    },
    skip: _fetched
        ? false
        : 'needs the mushaf data (dart run tool/mushaf.dart)',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
