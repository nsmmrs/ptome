part of '../converter.dart';

/// The theme keys of a category, read as their types: `sidebar`'s
/// `border_width`, `heading_h2`'s `font_size`; each the first of
/// [prefixes] that sets it (a role's heading keys, then the level's, then
/// every heading's). Read where they are used: the theme in force then
/// may have a role's keys laid over it.
final class _Keys {
  const new(this._converter, this.prefixes);

  final PdfConverter _converter;

  /// The categories, the first that sets a key giving it.
  final List<String> prefixes;

  /// The value of [key], if a category sets it.
  ThemeValue? value(String key) {
    for (final prefix in prefixes) {
      if (_converter._theme.value('${prefix}_$key') case final value?) {
        return value;
      }
    }
    return null;
  }

  /// [key] as text.
  String? string(String key) {
    for (final prefix in prefixes) {
      if (_converter._s('${prefix}_$key') case final value?) return value;
    }
    return null;
  }

  /// [key] as a number.
  num? number(String key) {
    for (final prefix in prefixes) {
      if (_converter._n('${prefix}_$key') case final value?) return value;
    }
    return null;
  }

  /// [key] as a color.
  ThemeColor? color(String key) {
    for (final prefix in prefixes) {
      if (_converter._c('${prefix}_$key') case final value?) return value;
    }
    return null;
  }

  /// [key] as a length, in points (ems of [size]).
  double? length(String key, double size) {
    for (final prefix in prefixes) {
      if (_converter._length('${prefix}_$key', size) case final value?) {
        return value;
      }
    }
    return null;
  }

  /// [key] as tracking, in ems of text [size] points.
  double? letterSpacing(String key, double size) {
    for (final prefix in prefixes) {
      if (_converter._letterSpacing('${prefix}_$key', size) case final value?) {
        return value;
      }
    }
    return null;
  }
}
