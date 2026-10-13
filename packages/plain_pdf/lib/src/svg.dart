/// What SVG images (plain_svg) take from a PDF: the standard fonts for
/// their text, and PDF images for their raster images.
library;

import 'dart:typed_data';

import 'package:plain_pdf/src/fonts/fonts.dart';
import 'package:plain_pdf/src/images/images.dart';

/// The standard font for an SVG's font [family] (a plain_svg
/// `SvgFontResolver`): Times, Helvetica or Courier for the generic
/// families and their common names, in [bold] and [italic]; null for
/// other families.
PdfFont? standardSvgFont(
  String family, {
  required bool bold,
  required bool italic,
}) {
  final base = switch (family.toLowerCase()) {
    'serif' || 'times' || 'times new roman' || 'times-roman' => 'Times',
    'sans-serif' ||
    'helvetica' ||
    'arial' ||
    'liberation sans' ||
    'dejavu sans' ||
    'verdana' => 'Helvetica',
    'monospace' || 'courier' || 'courier new' => 'Courier',
    _ => null,
  };
  if (base == null) return null;
  final name = switch ((base, bold, italic)) {
    ('Times', false, false) => 'Times-Roman',
    ('Times', true, false) => 'Times-Bold',
    ('Times', false, true) => 'Times-Italic',
    ('Times', true, true) => 'Times-BoldItalic',
    (_, false, false) => base,
    (_, true, false) => '$base-Bold',
    (_, false, true) => '$base-Oblique',
    (_, true, true) => '$base-BoldOblique',
  };
  return StandardFont.named(name);
}

/// The JPEG or PNG image in [bytes] for an SVG's `<image>` (a plain_svg
/// `SvgRasterReader`); throws a [FormatException] when it isn't one.
PdfImage readSvgRaster(Uint8List bytes) {
  try {
    return PdfImage.parse(bytes);
  } on ImageFormatException catch (error) {
    throw FormatException(error.message);
  }
}
