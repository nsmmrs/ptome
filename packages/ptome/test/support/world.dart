/// The world each test file starts from where files share a program
/// (`tool/shard.dart --programs`, as the gate and CI run them): what a
/// file may change for the whole process — the installed fonts and the
/// folders searched for them, the global logger, whether parallel runs
/// nest — as a lone file's program starts with it.
library;

import 'package:ptome/src/font_index.dart';
import 'package:ptome/src/logging.dart';
import 'package:ptome/src/parallel.dart';

/// The world [resetWorld] last made, to tell a file that changed it.
late ({FontIndex fonts, LoggerBase logger}) _made;

/// Puts the world back as a program starts with it.
void resetWorld() {
  Fonts.extraDirectories = const [];
  Fonts.installed = null;
  LoggerManager.logger = null;
  Parallel.nested = false;
  _made = (fonts: Fonts.installed, logger: LoggerManager.logger);
}

/// Throws when declaring the tests of the file at [path] changed the world
/// (a file changes it in its `setUp`s, or the files declared after it
/// would start from its): run after [resetWorld], then the file's `main`.
void checkWorld(String path) {
  final made = _made;
  final changed = [
    if (!identical(Fonts.installed, made.fonts)) 'Fonts.installed',
    if (Fonts.extraDirectories.isNotEmpty) 'Fonts.extraDirectories',
    if (!identical(LoggerManager.logger, made.logger)) 'LoggerManager.logger',
    if (Parallel.nested) 'Parallel.nested',
  ];
  if (changed.isNotEmpty) {
    throw StateError(
      '$path changes ${changed.join(', ')} while declaring its tests: '
      'change it in a setUp or setUpAll',
    );
  }
}
