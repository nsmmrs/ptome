/// The third-party notices of the npm package: what the JavaScript bundle
/// holds that is not ptome's own, each with its licence as its source
/// ships it.
///
/// - the Dart runtime and core libraries dart2js compiles in (the SDK's
///   LICENSE);
/// - every package ptome depends on, directly or not (dev dependencies
///   aside), with its LICENSE: pub.dev's and the workspace's `plain_`
///   packages alike (plain_highlighting's carries highlight.js's);
/// - the notices of what those packages embed or follow, vendored beside
///   them ([_vendored]): their comments don't survive dart2js.
///
///     dart run tool/npm_notices.dart [OUT]
///
/// writes OUT (by default build/npm/THIRD_PARTY_NOTICES.md);
/// tool/build-npm.sh runs it.
library;

import 'dart:convert';
import 'dart:io';

/// The notices of what the packages embed or follow, by package, each a
/// title, what it is in the bundle, and its file (relative to
/// `packages/`).
const List<(String, String, String, String)> _vendored = [
  (
    'plain_compression',
    'Brotli',
    "the Brotli decoder's dictionary and tables",
    'plain_compression/vendor/brotli/LICENSE',
  ),
  (
    'plain_fonts',
    'HarfBuzz',
    'the OpenType layout and the shaper (plain_fonts, plain_typesetting) '
        "follow HarfBuzz's",
    'plain_fonts/vendor/harfbuzz/COPYING',
  ),
  (
    'plain_typesetting',
    "Microsoft's Universal Shaping Engine data",
    'the vowel sequences the syllabic shapers mark with a dotted circle',
    'plain_typesetting/vendor/harfbuzz/ms-use/COPYING',
  ),
  (
    'plain_highlighting',
    'highlight.js styles',
    "the highlighting themes' colours",
    'plain_highlighting/vendor/highlight.js-styles/LICENSE',
  ),
  (
    'plain_hyphenation',
    'hyph-utf8 hyphenation patterns',
    'the hyphenation patterns, each under its own licence',
    'plain_hyphenation/vendor/hyph-utf8/NOTICES.md',
  ),
  (
    'plain_images',
    'RFC 6386 (VP8)',
    "the WebP decoder's VP8 tables",
    'plain_images/vendor/rfc6386/NOTICE',
  ),
  (
    'plain_pdf',
    'Adobe Core 14 AFM files',
    "the standard fonts' metrics",
    'plain_pdf/vendor/adobe-core14/MustRead.html',
  ),
  (
    'plain_pdf',
    'Adobe Glyph List',
    'glyph names',
    'plain_pdf/vendor/adobe-agl/glyphlist.txt',
  ),
  (
    'plain_unicode',
    'ICU',
    'the Thai, Lao, Khmer and Burmese word lists and their word breaking',
    'plain_unicode/vendor/icu/LICENSE',
  ),
  (
    'plain_unicode',
    'Unicode CLDR',
    'the quotation marks, collation tailorings and index characters by '
        'language',
    'plain_unicode/vendor/cldr/48.2.0/LICENSE',
  ),
  (
    'plain_unicode',
    'Unicode Character Database',
    'the line breaking, bidirectional, case mapping, character property '
        'and emoji tables',
    'plain_unicode/vendor/ucd/18.0.0/license.txt',
  ),
  (
    'ptome',
    'asciidoctor-epub3',
    "the EPUB stylesheets and images, and their fonts' and icons' licences",
    'ptome/vendor/asciidoctor-epub3/NOTICE.adoc',
  ),
  (
    'ptome',
    'Font Awesome (asciidoctor-pdf icon names)',
    "the icon names' maps",
    'ptome/vendor/asciidoctor-pdf/icons/fas/LICENSE',
  ),
];

Future<void> main(List<String> args) async {
  final ptome = File.fromUri(Platform.script).parent.parent;
  final packages = ptome.parent;
  final root = packages.parent;
  final out = File(
    args.isNotEmpty
        ? args.first
        : '${ptome.path}/build/npm/THIRD_PARTY_NOTICES.md',
  );

  // The packages ptome's code reaches, dev dependencies aside.
  final deps = await Process.run('dart', [
    'pub',
    'deps',
    '--json',
  ], workingDirectory: ptome.path);
  if (deps.exitCode != 0) {
    throw StateError('dart pub deps failed: ${deps.stderr}');
  }
  final graph = <String, List<String>>{};
  if (jsonDecode('${deps.stdout}') case {'packages': final List<Object?> all}) {
    for (final package in all) {
      // (A workspace package's `dependencies` has its dev dependencies
      // too; its `directDependencies`, those it runs with.)
      final dependencies = switch (package) {
        {'directDependencies': final List<Object?> direct} => direct,
        {'dependencies': final List<Object?> all} => all,
        _ => const <Object?>[],
      };
      if (package case {'name': final String name}) {
        graph[name] = [...dependencies.whereType<String>()];
      }
    }
  }
  final reached = <String>{};
  void reach(String name) {
    if (!reached.add(name)) return;
    graph[name]?.forEach(reach);
  }

  reach('ptome');
  reached.remove('ptome');

  // Where each package is.
  final config = jsonDecode(
    File('${root.path}/.dart_tool/package_config.json').readAsStringSync(),
  );
  final where = <String, Directory>{};
  if (config case {'packages': final List<Object?> all}) {
    for (final package in all) {
      if (package case {
        'name': final String name,
        'rootUri': final String uri,
      }) {
        where[name] = Directory.fromUri(
          Uri.parse('${root.uri}.dart_tool/').resolve(uri),
        );
      }
    }
  }

  final text = StringBuffer()
    ..writeln('# Third-party notices')
    ..writeln()
    ..writeln(
      "ptome's own licence is in LICENSE. The JavaScript bundle also holds "
      'the code and data below, under their own licences, each reproduced '
      'as its source ships it.',
    );
  void section(String title, String what, String body) {
    // (A fence longer than any run of backticks in the body: a Markdown
    // notice keeps its own.)
    final longest = RegExp('`+')
        .allMatches(body)
        .fold(0, (n, m) => m[0]!.length > n ? m[0]!.length : n);
    final fence = '`' * (longest < 3 ? 3 : longest + 1);
    text
      ..writeln()
      ..writeln('## $title')
      ..writeln()
      ..writeln(what)
      ..writeln()
      ..writeln(fence)
      ..writeln(body.trimRight())
      ..writeln(fence);
  }

  // The Dart SDK: `<sdk>/bin/dart`.
  final sdk = File(Platform.resolvedExecutable).parent.parent;
  section(
    'The Dart SDK',
    'The Dart runtime and core libraries dart2js compiles in.',
    File('${sdk.path}/LICENSE').readAsStringSync(),
  );
  for (final name in reached.toList()..sort()) {
    final dir = where[name];
    final license = dir == null
        ? null
        : [
            for (final file in [
              'LICENSE',
              'LICENSE.md',
              'LICENSE.txt',
              'COPYING',
            ])
              if (File('${dir.path}/$file').existsSync())
                File('${dir.path}/$file'),
          ].firstOrNull;
    if (license == null) {
      throw StateError('$name: no LICENSE in ${dir?.path}');
    }
    section(
      '$name (Dart package)',
      'The package $name.',
      license.readAsStringSync(),
    );
  }
  for (final (package, title, what, path) in _vendored) {
    if (package != 'ptome' && !reached.contains(package)) continue;
    final file = File('${packages.path}/$path');
    final body = switch (path) {
      // (The terms of the AFM files' page, as text, then the files' own
      // notices, which the terms ask to be kept.)
      final p when p.endsWith('MustRead.html') => [
        ...file
            .readAsStringSync()
            .replaceAll(RegExp('<[^>]*>'), '')
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty),
        '',
        "The AFM files' notices:",
        '',
        ...{
          for (final afm in file.parent.listSync().whereType<File>())
            if (afm.path.endsWith('.afm'))
              for (final line in afm.readAsLinesSync())
                if (line.startsWith('Notice ')) line.substring(7),
        }.toList()..sort(),
      ].join('\n'),
      // (The licence at the head of a data file, its `#` comments.)
      final p when p.endsWith('glyphlist.txt') =>
        file
            .readAsLinesSync()
            .takeWhile((line) => line.startsWith('#'))
            .map((line) => line.replaceFirst(RegExp('^# ?'), ''))
            .join('\n'),
      _ => file.readAsStringSync(),
    };
    section(title, 'In $package: $what.', body);
  }
  out
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text.toString());
  stdout.writeln('npm_notices: ${reached.length} packages, wrote ${out.path}');
}
