part of '../converter.dart';

// Theme values.

extension _ThemeValues on PdfConverter {
  String? _s(String key) => _theme.string(key);
  num? _n(String key) => _theme.number(key);

  /// [key] as a length in points: a number, or in the modern engine also
  /// a multiple of [emSize] (`1.5em`) or of the root font size (`2rem`).
  double? _length(String key, double emSize) => switch (_theme.value(key)) {
    ThemeNumber(:final value) => value.toDouble(),
    ThemeString(:final value) => switch (RegExp(
      r'^(\d+(?:\.\d+)?|\.\d+)(r?em)$',
    ).firstMatch(value)) {
      final m? => double.parse(m[1]!) * (m[2] == 'em' ? emSize : _rootFontSize),
      null => null,
    },
    _ => null,
  };
  ThemeColor? _c(String key) => themeColor(_theme.value(key));
}
