/// The error a template's source can't be read with.
library;

/// A template that can't be read: a tag left open, a section closed by
/// another name, a bad delimiter change.
final class MustacheException implements Exception {
  /// The [message] about [source] at [offset].
  new(this.message, this.source, this.offset);

  /// What is wrong.
  final String message;

  /// The template's source.
  final String source;

  /// Where in [source], in UTF-16 code units.
  final int offset;

  /// The line of [offset], from 1.
  int get line => '\n'.allMatches(source.substring(0, offset)).length + 1;

  /// The column of [offset], from 1.
  int get column =>
      offset - (offset == 0 ? -1 : source.lastIndexOf('\n', offset - 1));

  @override
  String toString() =>
      'MustacheException: $message (line $line, column $column)';
}
