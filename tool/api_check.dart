/// Checks the public API of every package with a snapshot
/// (`packages/<package>/tool/api_surface.txt`), its public libraries the
/// package's top-level `lib/*.dart`, all in one analysis:
///
/// 1. It is closed: every type of the package that appears in an exported
///    signature (supertypes, constructor and method parameters, return
///    types, fields, typedefs) is itself exported by one of the public
///    libraries.
/// 2. It matches the snapshot (every exported name and public member with
///    its signature), so the public API changes only on purpose.
///    `--update` rewrites the snapshots.
///
/// Exits nonzero and lists the problems otherwise.
///
/// ```sh
/// dart run tool/api_check.dart [PACKAGE...] [--update]
/// ```
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

Future<void> main(List<String> args) async {
  final update = args.contains('--update');
  final only = {
    for (final a in args)
      if (!a.startsWith('-')) a,
  };
  final packages = [
    for (final entity in Directory(
      'packages',
    ).listSync()..sort((a, b) => a.path.compareTo(b.path)))
      if (entity is Directory &&
          File('${entity.path}/tool/api_surface.txt').existsSync() &&
          (only.isEmpty ||
              only.contains(
                entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
              )))
        entity.absolute,
  ];
  // (Absolute, normalized paths, which the analyzer requires: native
  // separators on Windows.)
  final libs = {
    for (final dir in packages)
      dir: [
        for (final file in Directory('${dir.path}/lib').listSync())
          if (file is File && file.path.endsWith('.dart'))
            File.fromUri(file.absolute.uri).path,
      ]..sort(),
  };
  final collection = AnalysisContextCollection(
    includedPaths: [for (final l in libs.values) ...l],
  );
  var passes = true;
  for (final dir in packages) {
    if (!await checkPackage(collection, dir, libs[dir]!, update: update)) {
      passes = false;
    }
  }
  exitCode = passes ? 0 : 1;
}

/// Checks the package at [dir] (its public libraries [libs], resolved in
/// [collection]); whether it passes. With [update], writes its snapshot.
Future<bool> checkPackage(
  AnalysisContextCollection collection,
  Directory dir,
  List<String> libs, {
  required bool update,
}) async {
  final package = dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
  var passes = true;
  final exported = <Element>{};
  for (final path in libs) {
    final session = collection.contextFor(path).currentSession;
    final result = await session.getResolvedLibrary(path);
    if (result is! ResolvedLibraryResult) {
      stdout.writeln('$package: cannot resolve $path');
      return false;
    }
    exported.addAll(result.element.exportNamespace.definedNames2.values);
  }
  final missing = <String, Set<String>>{};
  void checkElement(Element e, String where) {
    final uri = e.library?.uri.toString() ?? '';
    if (!uri.startsWith('package:$package/')) return;
    if (e.name == null || e.name!.startsWith('_')) return;
    if (exported.contains(e)) return;
    missing
        .putIfAbsent('${e.name} (${uri.split('/').last})', () => {})
        .add(where);
  }

  void checkType(DartType? type, String where) {
    if (type == null) return;
    final alias = type.alias;
    if (alias != null) {
      checkElement(alias.element, where);
      for (final a in alias.typeArguments) {
        checkType(a, where);
      }
    }
    if (type is InterfaceType) {
      checkElement(type.element, where);
      for (final a in type.typeArguments) {
        checkType(a, where);
      }
    } else if (type is FunctionType) {
      checkType(type.returnType, where);
      for (final p in type.formalParameters) {
        checkType(p.type, where);
      }
    }
  }

  for (final e in exported) {
    final name = e.name ?? '?';
    if (e is InterfaceElement) {
      checkType(e.supertype, '$name extends');
      for (final m in e.mixins) {
        checkType(m, '$name with');
      }
      for (final i in e.interfaces) {
        checkType(i, '$name implements');
      }
      for (final c in e.constructors) {
        if (c.isPrivate) continue;
        for (final p in c.formalParameters) {
          checkType(p.type, '$name.${c.name}(${p.name})');
        }
      }
      for (final f in e.fields) {
        if (f.isPrivate) continue;
        checkType(f.type, '$name.${f.name}');
      }
      for (final m in e.methods) {
        if (m.isPrivate) continue;
        checkType(m.returnType, '$name.${m.name}()');
        for (final p in m.formalParameters) {
          checkType(p.type, '$name.${m.name}(${p.name})');
        }
      }
    } else if (e is TopLevelFunctionElement) {
      checkType(e.returnType, '$name()');
      for (final p in e.formalParameters) {
        checkType(p.type, '$name(${p.name})');
      }
    } else if (e is TypeAliasElement) {
      checkType(e.aliasedType, 'typedef $name');
    } else if (e is TopLevelVariableElement) {
      checkType(e.type, name);
    }
  }
  final keys = missing.keys.toList()..sort();
  for (final k in keys) {
    final w = missing[k]!.toList()..sort();
    final more = w.length > 4 ? ' (+${w.length - 4})' : '';
    stdout.writeln('$package: $k  <- ${w.take(4).join('; ')}$more');
  }
  if (keys.isNotEmpty) {
    stdout.writeln('$package: ${keys.length} unexported types referenced');
    passes = false;
  }

  final surface = (exported.map(describe).toList()..sort()).join();
  final snapshot = File('${dir.path}/tool/api_surface.txt');
  if (update) {
    snapshot.writeAsStringSync(surface);
    stdout.writeln('$package: wrote ${snapshot.path}');
  } else if (!snapshot.existsSync() || snapshot.readAsStringSync() != surface) {
    stdout.writeln(
      '$package: the public API differs from tool/api_surface.txt; review '
      'the change and run: dart run tool/api_check.dart $package --update',
    );
    passes = false;
  } else {
    stdout.writeln('$package: public API matches tool/api_surface.txt');
  }
  return passes;
}

/// The snapshot lines for the exported element [e]: its declaration, then
/// one indented line per public member.
String describe(Element e) {
  final lines = <String>[_signature(e)];
  if (e is InterfaceElement) {
    for (final c in e.constructors) {
      if (!c.isPrivate && e is! EnumElement) lines.add('  ${_signature(c)}');
    }
    // Members of private mixins are public members of the class.
    final sources = [
      e,
      for (final m in e.mixins)
        if (m.element.isPrivate) m.element,
    ];
    for (final source in sources) {
      // Fields and getters/setters alike, as properties.
      for (final f in source.fields) {
        if (!f.isPrivate) lines.add('  ${_property(f)}');
      }
      for (final m in source.methods) {
        if (!m.isPrivate) lines.add('  ${_signature(m)}');
      }
    }
  } else if (e is ExtensionElement) {
    for (final f in e.fields) {
      if (!f.isPrivate) lines.add('  ${_property(f)}');
    }
    for (final m in e.methods) {
      if (!m.isPrivate) lines.add('  ${_signature(m)}');
    }
  }
  return '${[lines.first, ...(lines.skip(1).toList()..sort())].join('\n')}\n';
}

String _signature(Element e) => e.displayString();

String _property(FieldElement f) =>
    '${f.isStatic ? 'static ' : ''}${f.type} ${f.name}'
    '${f.setter == null ? '' : ' (settable)'}';
