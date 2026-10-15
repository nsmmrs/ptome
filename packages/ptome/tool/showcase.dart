/// The showcase corpus built whole (test/showcase, `doc/showcase.md`):
/// every work to HTML, EPUB and PDF (a PDF for each of its looks), into
/// `OUT/SLUG/`, with an index page, `OUT/index.html`, that links them and
/// shows the pages each work's NOTICE.md chooses beside the scans of the
/// printing its look follows. Not a test: whole works never run in
/// `dart test` (ADR-0025); each has an excerpt there
/// (test/showcase/showcase_test.dart).
///
///     dart run tool/showcase.dart [--out OUT] [--jobs N] [SLUG...]
///
/// OUT is `build/showcase` by default; the works are every folder of
/// test/showcase with a NOTICE.md, or those named. A work fails, and the
/// tool exits 1, when:
///
/// - a font its looks name isn't installed (`ptome doctor --check --look`;
///   `ptome doctor --look LOOK --looksdir test/showcase/SLUG` installs
///   them);
/// - a conversion reports a warning or an error;
/// - EPUBCheck finds an error or a warning in its EPUB (`EPUBCHECK`, the
///   jar, else the work folder's `tools/epubcheck-5.4.0`, fetched there
///   when missing);
/// - veraPDF finds its PDFs aren't PDF/UA-1 (`VERAPDF`, else the work
///   folder's `verapdf/verapdf`, else the path's).
///
/// The images a work lists in its `fetch.yml` (too large to commit) and
/// the scans its pages are compared with are fetched into the work
/// folder's `showcase` cache, each image checked by its SHA-256; the
/// pages are rendered by Poppler's pdftoppm. Each conversion's time is
/// printed.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:ptome/src/api/file_backends.dart';
import 'package:ptome/src/cli/doctor.dart';
import 'package:ptome/src/internal.dart';
import 'package:yaml/yaml.dart';

import 'showcase_import.dart' show Fetched, readFetched;

const String _corpus = 'test/showcase';

final String _work = '${Platform.environment['HOME']}/.cache/asciidart-work';

/// A page of a work's PDF to set beside a scan.
typedef Comparison = ({int page, String? look, String scan, String note});

/// A work of the corpus, as its NOTICE.md's front matter describes it.
final class Work {
  const new({
    required this.slug,
    required this.title,
    required this.source,
    required this.looks,
    required this.compare,
    required this.fetch,
  });

  /// The work at [dir], from its NOTICE.md and `fetch.yml`.
  factory read(Directory dir) {
    final slug = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final notice = File('${dir.path}/NOTICE.md').readAsStringSync();
    final match = RegExp(
      r'^---\n(.*?)\n---\n',
      dotAll: true,
    ).firstMatch(notice);
    if (match == null) {
      throw FormatException('$slug/NOTICE.md: no front matter');
    }
    final yaml = loadYaml(match[1]!);
    if (yaml case {
      'title': final String title,
      'source': final String source,
      'looks': final YamlList looks,
    }) {
      final fetchFile = File('${dir.path}/fetch.yml');
      return Work(
        slug: slug,
        title: title,
        source: source,
        looks: [for (final look in looks) '$look'],
        compare: [
          for (final entry in (yaml['compare'] as YamlList?) ?? YamlList())
            if (entry case {'page': final int page, 'scan': final String scan})
              (
                page: page,
                look: entry['look'] as String?,
                scan: scan,
                note: (entry['note'] as String?) ?? '',
              )
            else
              throw FormatException(
                '$slug/NOTICE.md: a comparison needs a page and a scan: '
                '$entry',
              ),
        ],
        fetch: fetchFile.existsSync()
            ? readFetched(fetchFile.readAsStringSync())
            : const [],
      );
    }
    throw FormatException(
      '$slug/NOTICE.md: the front matter needs a title, a source and looks',
    );
  }

  /// Its folder's name.
  final String slug;

  /// Its title.
  final String title;

  /// The AsciiDoc file of the whole work, in its folder.
  final String source;

  /// The looks its PDF is made in, the first the HTML's and EPUB's.
  final List<String> looks;

  /// The pages to set beside scans.
  final List<Comparison> compare;

  /// The images it fetches.
  final List<Fetched> fetch;

  /// The PDF in [look]'s file name.
  String pdfName(String look) => looks.length == 1 || look == looks.first
      ? '$slug.pdf'
      : '$slug-$look.pdf';
}

/// What building a work came to.
typedef Built = ({
  String slug,
  List<String> failures,
  List<String> times,
  List<String> outputs,
  List<({String page, String scan, String note})> pages,
});

Future<void> main(List<String> arguments) async {
  var out = 'build/showcase';
  var jobs = Platform.numberOfProcessors.clamp(1, 4);
  final named = <String>[];
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--out':
        out = arguments[++i];
      case '--jobs':
        jobs = int.parse(arguments[++i]);
      case final slug when !slug.startsWith('-'):
        named.add(slug);
      default:
        stderr.writeln('showcase: unknown option ${arguments[i]}');
        exit(64);
    }
  }
  final dirs = Directory(_corpus).listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final works = [
    for (final dir in dirs)
      if (File('${dir.path}/NOTICE.md').existsSync())
        if (named.isEmpty || named.contains(dir.uri.pathSegments[2]))
          Work.read(dir),
  ];
  if (works.isEmpty) {
    stderr.writeln('showcase: no works');
    exit(64);
  }
  final epubcheck = await _epubcheck();
  final verapdf = _verapdf();
  Directory(out).createSync(recursive: true);
  final absoluteOut = Directory(out).absolute.path;

  final results = <Built>[];
  final queue = [...works];
  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final slug = queue.removeAt(0).slug;
      final built = await _spawn(slug, absoluteOut, epubcheck, verapdf);
      results.add(built);
      stdout.writeln(
        '${built.failures.isEmpty ? 'ok  ' : 'FAIL'} $slug '
        '(${built.times.join(', ')})',
      );
      for (final failure in built.failures) {
        stdout.writeln('  $failure');
      }
    }
  }

  await Future.wait([for (var i = 0; i < jobs; i++) worker()]);
  results.sort((a, b) => a.slug.compareTo(b.slug));
  File('$out/index.html').writeAsStringSync(_index(works, results));
  final failed = results.where((r) => r.failures.isNotEmpty).length;
  stdout.writeln(
    '${works.length - failed} of ${works.length} works built clean; '
    'index: $out/index.html',
  );
  exit(failed == 0 ? 0 : 1);
}

/// [_build] in an isolate of its own (the logger is the process's), from
/// a function whose closure holds only what it is given.
Future<Built> _spawn(
  String slug,
  String out,
  String epubcheck,
  String verapdf,
) => Isolate.run(() => _build(slug, out, epubcheck, verapdf));

/// Builds the work [slug] into OUT/[slug].
Future<Built> _build(
  String slug,
  String out,
  String epubcheck,
  String verapdf,
) async {
  final work = Work.read(Directory('$_corpus/$slug'));
  final failures = <String>[];
  final times = <String>[];
  final outputs = <String>[];
  final pages = <({String page, String scan, String note})>[];
  final stage = Directory('$out/$slug');
  if (stage.existsSync()) stage.deleteSync(recursive: true);
  _copy(Directory('$_corpus/$slug'), stage);

  // (The images too large to commit.)
  final client = HttpClient();
  try {
    Directory('${stage.path}/images').createSync(recursive: true);
    for (final image in work.fetch) {
      final bytes = await _cached(client, image.url, 'images');
      final digest = '${sha256.convert(bytes)}';
      if (digest != image.sha256) {
        failures.add('${image.name}: SHA-256 $digest, not ${image.sha256}');
        continue;
      }
      File('${stage.path}/images/${image.name}').writeAsBytesSync(bytes);
    }

    // (The fonts each look names.)
    for (final look in work.looks) {
      final report = StringBuffer();
      final status = await runDoctor(
        ['--check', '--look=$look', '--looksdir=${stage.path}'],
        out: report,
        err: report,
      );
      if (status != 0) {
        final missing = [
          for (final line in '$report'.split('\n'))
            if (RegExp(r'^\s+\S.*\bmissing\b').hasMatch(line)) line.trim(),
        ];
        failures.add(
          'look $look: fonts missing (ptome doctor --look $look '
          '--looksdir $_corpus/$slug): ${missing.join('; ')}',
        );
      }
    }
    if (failures.isNotEmpty) {
      return (
        slug: slug,
        failures: failures,
        times: times,
        outputs: outputs,
        pages: pages,
      );
    }

    final source = '${stage.path}/${work.source}';
    void convert(String backend, String file, {String? look}) {
      registerFileBackend(backend);
      final logger = MemoryLogger();
      LoggerManager.logger = logger;
      final watch = Stopwatch()..start();
      try {
        convertFile(
          source,
          AsciidoctorOptions(
            safe: SafeMode.unsafe,
            backend: backend,
            toFile: '${stage.path}/$file',
            attributes: {
              'reproducible': '',
              'look': ?look,
              if (backend == 'pdf') 'pdf-ua': '',
            },
          ),
        );
      } on Object catch (error) {
        failures.add('$file: $error');
      }
      times.add(
        '$file ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s',
      );
      outputs.add(file);
      for (final message in logger.messages) {
        if (message.severity.index >= Severity.warn.index) {
          final at = message.message.sourceLocation;
          failures.add(
            '$file: ${message.severity.name.toUpperCase()}: '
            '${at == null ? '' : '$at: '}${message.message.text}',
          );
        }
      }
    }

    convert('html5', '$slug.html');
    convert('epub3', '$slug.epub');
    for (final look in work.looks) {
      convert('pdf', work.pdfName(look), look: look);
    }

    final epub = '${stage.path}/$slug.epub';
    if (File(epub).existsSync()) {
      final check = Process.runSync('java', [
        '-jar',
        epubcheck,
        '--failonwarnings',
        '--quiet',
        epub,
      ]);
      if (check.exitCode != 0) {
        final report = '${check.stdout}${check.stderr}'.trim().split('\n');
        failures.add(
          '$slug.epub: EPUBCheck: ${report.take(20).join('\n    ')}',
        );
      }
    }
    for (final look in work.looks) {
      final pdf = '${stage.path}/${work.pdfName(look)}';
      if (!File(pdf).existsSync()) continue;
      final check = Process.runSync(verapdf, [
        '--flavour',
        'ua1',
        '--format',
        'text',
        pdf,
      ]);
      final report = '${check.stdout}'.trim();
      if (!report.startsWith('PASS')) {
        failures.add('${work.pdfName(look)}: veraPDF PDF/UA-1: $report');
      }
    }

    // (The pages beside their scans.)
    Directory('${stage.path}/pages').createSync(recursive: true);
    for (final (i, comparison) in work.compare.indexed) {
      final pdf =
          '${stage.path}/${work.pdfName(comparison.look ?? work.looks.first)}';
      final png = 'pages/page-${i + 1}';
      final render = Process.runSync('pdftoppm', [
        '-r',
        '96',
        '-f',
        '${comparison.page}',
        '-l',
        '${comparison.page}',
        '-singlefile',
        '-png',
        pdf,
        '${stage.path}/$png',
      ]);
      if (render.exitCode != 0) {
        failures.add('page ${comparison.page}: pdftoppm: ${render.stderr}');
        continue;
      }
      final extension =
          RegExp(
            r'\.(jpe?g|png|gif|webp)$',
            caseSensitive: false,
          ).firstMatch(Uri.parse(comparison.scan).path)?[1] ??
          'jpg';
      final scan = 'pages/scan-${i + 1}.$extension';
      try {
        File('${stage.path}/$scan')
            .writeAsBytesSync(await _cached(client, comparison.scan, 'scans'));
      } on Object catch (error) {
        failures.add('scan ${comparison.scan}: $error');
        continue;
      }
      pages.add((page: '$png.png', scan: scan, note: comparison.note));
    }
  } finally {
    client.close();
  }
  return (
    slug: slug,
    failures: failures,
    times: times,
    outputs: outputs,
    pages: pages,
  );
}

/// The bytes at [url], from the cache's [kind] folder, fetched into it
/// when not there.
Future<List<int>> _cached(HttpClient client, String url, String kind) async {
  final key = '${sha256.convert(utf8.encode(url))}';
  final file = File('$_work/showcase/$kind/$key');
  if (file.existsSync()) return file.readAsBytesSync();
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  if (response.statusCode != 200) {
    await response.drain<void>();
    throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
  }
  final bytes = [for (final chunk in await response.toList()) ...chunk];
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  return bytes;
}

/// Copies [from]'s files into [to].
void _copy(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync()) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    switch (entity) {
      case final Directory dir:
        _copy(dir, Directory('${to.path}/$name'));
      case final File file:
        file.copySync('${to.path}/$name');
    }
  }
}

const String _epubcheckZip =
    'https://github.com/w3c/epubcheck/releases/download/v5.4.0/'
    'epubcheck-5.4.0.zip';

/// EPUBCheck's jar: EPUBCHECK, else the work folder's, fetched when
/// missing.
Future<String> _epubcheck() async {
  if (Platform.environment['EPUBCHECK'] case final jar?) return jar;
  final dir = '$_work/tools';
  final jar = '$dir/epubcheck-5.4.0/epubcheck.jar';
  if (File(jar).existsSync()) return jar;
  stdout.writeln('fetching EPUBCheck 5.4.0 into $dir');
  Directory(dir).createSync(recursive: true);
  final zip = '$dir/epubcheck.zip';
  final fetch = Process.runSync('curl', ['-sSLo', zip, _epubcheckZip]);
  final unzip = fetch.exitCode == 0
      ? Process.runSync('unzip', ['-q', '-o', zip, '-d', dir])
      : fetch;
  if (unzip.exitCode != 0 || !File(jar).existsSync()) {
    stderr.writeln('showcase: no EPUBCheck: ${unzip.stderr}');
    exit(1);
  }
  return jar;
}

/// veraPDF's command: VERAPDF, else the work folder's, else the path's.
String _verapdf() =>
    Platform.environment['VERAPDF'] ??
    ['$_work/verapdf/verapdf']
        .firstWhere((path) => File(path).existsSync(), orElse: () => 'verapdf');

/// The index page: each work, its files, its failures, its pages beside
/// their scans.
String _index(List<Work> works, List<Built> results) {
  String escape(String text) => const HtmlEscape().convert(text);
  final byslug = {for (final result in results) result.slug: result};
  final out = StringBuffer()
    ..writeln('<!doctype html>')
    ..writeln('<html lang="en"><head><meta charset="utf-8">')
    ..writeln('<meta name="viewport" content="width=device-width">')
    ..writeln('<title>Showcase</title>')
    ..writeln('<style>')
    ..writeln(
      'body{font:16px/1.5 system-ui,sans-serif;margin:2rem auto;'
      'max-width:80rem;padding:0 1rem}'
      '.pair{display:flex;gap:1rem;align-items:flex-start;flex-wrap:wrap}'
      '.pair figure{margin:0;flex:1 1 20rem}'
      '.pair img{width:100%;border:1px solid #ccc}'
      '.fail{color:#a00}',
    )
    ..writeln('</style></head><body>')
    ..writeln('<h1>Showcase</h1>');
  for (final work in works) {
    final built = byslug[work.slug];
    out.writeln('<section><h2>${escape(work.title)}</h2>');
    if (built == null) continue;
    final links = [
      for (final file in built.outputs)
        '<a href="${work.slug}/$file">$file</a>',
      '<a href="${work.slug}/NOTICE.md">NOTICE</a>',
    ];
    out.writeln(
      '<p>${links.join(' · ')} (${escape(built.times.join(', '))})</p>',
    );
    if (built.failures.isNotEmpty) {
      out.writeln('<ul class="fail">');
      for (final failure in built.failures) {
        out.writeln('<li><pre>${escape(failure)}</pre></li>');
      }
      out.writeln('</ul>');
    }
    for (final page in built.pages) {
      out
        ..writeln('<h3>${escape(page.note)}</h3><div class="pair">')
        ..writeln(
          '<figure><img src="${work.slug}/${page.page}" alt="ptome">'
          '<figcaption>ptome</figcaption></figure>',
        )
        ..writeln(
          '<figure><img src="${work.slug}/${page.scan}" alt="scan">'
          '<figcaption>The printing</figcaption></figure>',
        )
        ..writeln('</div>');
    }
    out.writeln('</section>');
  }
  out.writeln('</body></html>');
  return '$out';
}
