/// A utility class for working with the built-in stylesheets.
///
/// Dart port of `lib/asciidoctor/stylesheets.rb`.
///
/// Stylesheet data comes from the compile-time
/// embedded data in [EmbeddedData] (see `tool/embed_data.dart`). The returned
/// strings are identical: file contents with trailing whitespace stripped.
library;

import 'package:ptome/src/data.g.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/logging.dart';
import 'package:ptome/src/look/css.dart';
import 'package:ptome/src/look/loader.dart';
import 'package:ptome/src/look/model.dart';

/// A utility class for working with the built-in stylesheets.
///
/// See the library documentation for an overview.
class Stylesheets {
  /// Creates a stylesheets helper. Prefer [Stylesheets.instance].
  new();

  /// File name of the default Asciidoctor stylesheet.
  static const String defaultStylesheetName = 'asciidoctor.css';

  /// The shared [Stylesheets] instance (created lazily on first access).
  static final Stylesheets instance = Stylesheets();

  /// The value of the `stylesheet` attribute that names Asciidoctor's
  /// stylesheet as it is, without Ptome's house rules (ADR-0011).
  static const String classicStylesheetKey = 'asciidoctor';

  /// The value of the `stylesheet` attribute that names the stylesheet of
  /// Asciidoctor's latest stable release (2.0.26), which
  /// `asciidoctor-compat` uses for HTML.
  static const String stableStylesheetKey = 'asciidoctor-2.0.26';

  /// Whether [key] names one of the stylesheets Ptome carries (Asciidoctor's,
  /// or the stable release's).
  static bool isAsciidoctor(String? key) =>
      key == classicStylesheetKey || key == stableStylesheetKey;

  String? _primaryStylesheetData;
  String? _classicStylesheetData;
  String? _stableStylesheetData;

  /// The file name of the primary stylesheet.
  String get primaryStylesheetName => defaultStylesheetName;

  /// The default stylesheet: the house look's ([primaryStylesheetFor]).
  String get primaryStylesheetData => _primaryStylesheetData ??=
      primaryStylesheetFor(LookLoader().load('ptome'));

  /// The default stylesheet for [look] (ADR-0023): Asciidoctor's, then
  /// the look's CSS, then the device rules that hold no values, then the
  /// CSS the look writes itself.
  String primaryStylesheetFor(Look look) {
    final css = lookCss(look, CssTarget.html, warn: LoggerManager.logger.warn);
    final own = lookOwnCss(look, CssTarget.html);
    return '$classicStylesheetData\n${css.trimRight()}\n'
        '${_rstrip(EmbeddedData.file('stylesheets/ptome-device.css'))}'
        '${own.isEmpty ? '' : '\n$own'}';
  }

  /// Asciidoctor's default stylesheet, as it is (`stylesheet=asciidoctor`).
  String get classicStylesheetData => _classicStylesheetData ??= _rstrip(
    EmbeddedData.file('stylesheets/asciidoctor-default.css'),
  );

  /// The stylesheet of Asciidoctor's latest stable release
  /// (`stylesheet=asciidoctor-2.0.26`, data/stylesheets/asciidoctor-2.0.26.css,
  /// as the 2.0.26 gem has it).
  String get stableStylesheetData => _stableStylesheetData ??= _rstrip(
    EmbeddedData.file('stylesheets/asciidoctor-2.0.26.css'),
  );

  /// The built-in stylesheet for a `stylesheet` attribute of [key]: the
  /// classic one for [classicStylesheetKey], the stable release's for
  /// [stableStylesheetKey], else the default ([look]'s, or the house
  /// look's).
  String dataFor(String? key, {Look? look}) => switch (key) {
    classicStylesheetKey => classicStylesheetData,
    stableStylesheetKey => stableStylesheetData,
    _ => look == null ? primaryStylesheetData : primaryStylesheetFor(look),
  };

  /// The Google Fonts families the built-in stylesheet of [key] is set in
  /// (the `webfonts` attribute's default): the stable release's monospace
  /// face is Droid Sans Mono, the others' Noto Sans Mono; then [look]'s
  /// (ADR-0023).
  String webfontsFor(String? key, {Look? look}) => [
    'Open+Sans:300,300italic,400,400italic,600,600italic',
    'Noto+Serif:400,400italic,700,700italic',
    '${key == stableStylesheetKey ? 'Droid' : 'Noto'}+Sans+Mono:400,700',
    for (final family in look?.webfonts ?? const <String>[])
      family.replaceAll(' ', '+'),
  ].join('%7C');

  /// Writes the built-in stylesheet for a `stylesheet` attribute of [key]
  /// (with [look]) to [targetDir].
  void writePrimaryStylesheet([
    String targetDir = '.',
    String? key,
    Look? look,
  ]) {
    io.writeString(
      '$targetDir/$primaryStylesheetName',
      dataFor(key, look: look),
    );
  }
}

/// Strips trailing ASCII whitespace and null bytes (unlike Dart's
/// `trimRight`, this leaves non-ASCII
/// whitespace untouched).
String _rstrip(String value) =>
    value.replaceAll(RegExp('[\x00 \t\n\v\f\r]+\$'), '');
