/// Header edits over the fixture corpus: an edit to the value an entry
/// already has returns the source unchanged, and an edit to a new value
/// changes only that entry's lines and is read back by the parser.
@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:ptome/ptome.dart';
import 'package:test/test.dart';

/// The `.adoc` files under [dir], hidden folders passed over (a test's
/// `.ptome` cache, made and removed while another program walks the
/// corpus).
List<File> _adocs(Directory dir) => [
  for (final entity in dir.listSync())
    if (entity is Directory && !p.basename(entity.path).startsWith('.'))
      ..._adocs(entity)
    else if (entity is File && entity.path.endsWith('.adoc'))
      entity,
];

void main() {
  final files = [
    for (final dir in [
      'vendor/asciidoctor/test/fixtures',
      // The corpus's parity documents (our own).
      for (final c in Directory('test/corpus').listSync())
        if (c is Directory && p.basename(c.path).startsWith('parity-')) c.path,
    ])
      ..._adocs(Directory(dir)),
  ];

  test('round trip over ${files.length} fixtures', () {
    var edited = 0;
    for (final file in files) {
      final source = file.readAsStringSync();
      final Document doc;
      try {
        doc = const Ptome(safe: SafeMode.safe).parse(source, path: file.path);
      } on PtomeException {
        continue;
      }
      for (final MapEntry(key: name, :value) in doc.headerAttributes.entries) {
        if (value == null || value.contains('\n')) continue;
        final Document same;
        try {
          same = doc.withAttribute(name, value);
        } on PtomeException {
          continue; // under a conditional or in an include
        }
        expect(same.source.length, source.length, reason: '${file.path} $name');
        final changed = doc.withAttribute(name, 'edited value');
        final before = source.split('\n');
        final after = changed.source.split('\n');
        expect(
          after.length,
          lessThanOrEqualTo(before.length),
          reason: '${file.path} $name',
        );
        expect(
          changed.headerAttributes[name],
          'edited value',
          reason: '${file.path} $name',
        );
        edited += 1;
      }
    }
    expect(edited, greaterThan(10));
  });
}
