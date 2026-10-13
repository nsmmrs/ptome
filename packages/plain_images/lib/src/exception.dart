/// What is wrong with an image file.
library;

/// An image file that can't be read: damaged, or of a format plain_images
/// doesn't read ([unsupportedFormat]).
final class ImageFormatException extends FormatException {
  /// An exception with [message], about the byte at [offset] if given.
  const new(String message, {this.unsupportedFormat, int? offset})
    : super(message, null, offset);

  /// The name of the format the file is in when plain_images recognizes
  /// it but doesn't read it (`AVIF`, `HEIC`, ...), else null.
  final String? unsupportedFormat;

  @override
  String toString() => 'ImageFormatException: $message';
}
