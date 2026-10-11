/// Where the CLI finds the settings the command line doesn't give: the
/// `asciidoctor-compat` setting (ADR-0015: the `PTOME_COMPAT` environment
/// variable, the project's `ptome.yml`, the user's `ptome/config.yml`)
/// and the look (ADR-0023: `look:` in the same files).
library;

import 'dart:convert';

import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/path_resolver.dart';
import 'package:yaml/yaml.dart';

/// The file name of a project's configuration.
const String projectConfigName = 'ptome.yml';

/// The `asciidoctor-compat` value from the first place that sets it: the
/// `PTOME_COMPAT` variable of [env], `compat:` in the nearest
/// [projectConfigName] in [startDir] or a directory above it, `compat:`
/// in `$XDG_CONFIG_HOME/ptome/config.yml` (`~/.config/...`). Null when
/// none does. Problems with a file are reported through [warn].
String? resolveCompat({
  required Map<String, String> env,
  required String startDir,
  required void Function(String message) warn,
}) {
  if (env['PTOME_COMPAT'] case final value?) return value;
  for (final path in _configFiles(env, startDir)) {
    if (_compatIn(path, warn) case final value?) return value;
  }
  return null;
}

/// The look a configuration file names (ADR-0023), with the folder its
/// look files are found in: `look:` in the nearest [projectConfigName] in
/// [startDir] or a directory above it, else in the user's
/// `ptome/config.yml`; looked for in the file's `looksdir:` (relative to
/// the file), else beside it. Null when none names one. Problems with a
/// file are reported through [warn].
({String look, String looksDir})? resolveLook({
  required Map<String, String> env,
  required String startDir,
  required void Function(String message) warn,
}) {
  for (final path in _configFiles(env, startDir)) {
    final config = _config(path, warn);
    if (config == null) continue;
    final dir = _dirname(path);
    switch ((config['look'], config['looksdir'])) {
      case (null, _):
        continue;
      case (final String look, null):
        return (look: look, looksDir: dir);
      case (final String look, final String looksDir):
        return (
          look: look,
          looksDir: PathResolver().systemPath(looksDir, start: dir),
        );
      case (final look, final looksDir):
        warn(
          '$path: look: and looksdir: are names or paths, not '
          '${look is String ? looksDir : look}',
        );
        return null;
    }
  }
  return null;
}

/// The configuration files to read, in order: the project's (the nearest
/// [projectConfigName] in [startDir] or above; no directory above it is
/// searched), then the user's.
List<String> _configFiles(Map<String, String> env, String startDir) {
  final files = <String>[];
  for (var dir = _absolute(startDir); ; dir = _parent(dir)) {
    final path = dir.endsWith('/')
        ? '$dir$projectConfigName'
        : '$dir/$projectConfigName';
    if (io.isFile(path)) {
      files.add(path);
      break;
    }
    if (_parent(dir) == dir) break;
  }
  final configHome = switch (env['XDG_CONFIG_HOME']) {
    final dir? when dir.isNotEmpty => dir,
    _ => switch (env['HOME']) {
      final home? => '$home/.config',
      _ => null,
    },
  };
  if (configHome != null) {
    final path = '$configHome/ptome/config.yml';
    if (io.isFile(path)) files.add(path);
  }
  return files;
}

/// The configuration file at [path], or null when it is empty or isn't
/// one (reported).
YamlMap? _config(String path, void Function(String message) warn) {
  final YamlNode config;
  try {
    config = loadYamlNode(
      utf8.decode(io.readBytes(path)),
      sourceUrl: Uri.file(path),
    );
  } on Exception catch (error) {
    warn('$path: not a configuration file ($error)');
    return null;
  }
  if (config case YamlScalar(value: null)) return null;
  if (config is! YamlMap) {
    warn('$path: not a configuration file (expected keys and values)');
    return null;
  }
  return config;
}

/// The `compat:` value of the configuration file at [path] as an
/// attribute value, or null when the file doesn't set it.
String? _compatIn(String path, void Function(String message) warn) {
  final config = _config(path, warn);
  if (config == null) return null;
  return switch (config['compat']) {
    null => null,
    final bool on => '$on',
    final String formats => formats,
    final YamlList formats when formats.every((f) => f is String) =>
      formats.join(','),
    final other => () {
      warn(
        '$path: compat: expected true, false or a list of formats, '
        'not $other',
      );
      return null;
    }(),
  };
}

/// The absolute, normalized form of [path], with forward slashes.
String _absolute(String path) {
  final resolver = PathResolver();
  return resolver.expandPath(
    resolver.isRoot(path)
        ? path
        : resolver.joinPath([io.currentDirectory, path]),
  );
}

/// The folder [path] is in.
String _dirname(String path) {
  final slash = path.lastIndexOf('/');
  return slash <= 0 ? '/' : path.substring(0, slash);
}

/// The directory above [dir] (the root is its own).
String _parent(String dir) {
  final slash = dir.lastIndexOf('/');
  if (slash < 0 || slash == dir.length - 1) return dir;
  final parent = dir.substring(0, slash);
  return parent.isEmpty || parent.endsWith(':') ? '$parent/' : parent;
}
