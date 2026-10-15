/// What test/resvg_test.dart and tool/resvg_suite.dart share: a resvg
/// case drawn on a page of its own, and the comparison of that page, as
/// Poppler rasterizes it, with resvg's PNG of the case.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plain_pdf/plain_pdf.dart';
import 'package:plain_svg/plain_svg.dart';
import 'package:plain_typesetting/plain_typesetting.dart';

/// The SVG [file] drawn on a page of [width] by [height] (the size of
/// resvg's PNG of it, which draws its cases 300 pixels wide), the image
/// fitted in it, saved deterministically; null for one that can't be
/// read.
Uint8List? resvgPage(File file, double width, double height) {
  final SvgImage svg;
  try {
    svg = SvgImage.parse(
      utf8.decode(file.readAsBytesSync(), allowMalformed: true),
      fonts: standardSvgFont,
      rasters: readSvgRaster,
      pixelSize: 1,
      images: (href) {
        final uri = file.parent.uri.resolve(href);
        if (uri.scheme != 'file') return null;
        final image = File.fromUri(uri);
        return image.existsSync() ? image.readAsBytesSync() : null;
      },
    );
  } on FormatException {
    return null;
  }
  final document = PdfDocument();
  final page = document.addPage(Rect(0, 0, width, height));
  try {
    svg.paint(page.canvas, Rect(0, 0, width, height));
  } on Object {
    // (A page left as it is: a case drawn wrong.)
  }
  return document.save(options: const PdfWriterOptions(deterministic: true));
}

/// The width and height of the PNG [png].
(double, double) pngSize(Uint8List png) {
  final header = ByteData.sublistView(png, 16, 24);
  return (header.getUint32(0).toDouble(), header.getUint32(4).toDouble());
}

/// Whether the page [pdf] (one page) as pdftoppm rasterizes it and the
/// PNG [png] flattened on white by ImageMagick are drawn alike: the same
/// size, and at most 1% of the pixels apart by more than a quarter of a
/// channel's range (edges are smoothed differently).
bool drawnAlike(Uint8List pdf, Uint8List png) {
  final dir = Directory.systemTemp.createTempSync('resvg.');
  try {
    File('${dir.path}/page.pdf').writeAsBytesSync(pdf);
    File('${dir.path}/ref.png').writeAsBytesSync(png);
    final raster = Process.runSync('pdftoppm', [
      '-r',
      '72',
      '-singlefile',
      '${dir.path}/page.pdf',
      '${dir.path}/page',
    ]);
    if (raster.exitCode != 0) throw StateError('${raster.stderr}');
    final flatten = Process.runSync('magick', [
      '${dir.path}/ref.png',
      '-background',
      'white',
      '-alpha',
      'remove',
      '-depth',
      '8',
      '${dir.path}/ref.ppm',
    ]);
    if (flatten.exitCode != 0) throw StateError('${flatten.stderr}');
    return _alike(
      _ppm(File('${dir.path}/page.ppm').readAsBytesSync()),
      _ppm(File('${dir.path}/ref.ppm').readAsBytesSync()),
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// The width, height and RGB samples of the binary PPM [bytes].
(int, int, Uint8List) _ppm(Uint8List bytes) {
  var at = 0;
  bool space(int b) => b == 0x20 || b == 0x0a || b == 0x0d || b == 0x09;
  String token() {
    while (space(bytes[at])) {
      at++;
    }
    final start = at;
    while (!space(bytes[at])) {
      at++;
    }
    return latin1.decode(bytes.sublist(start, at));
  }

  if (token() != 'P6') throw const FormatException('not a binary PPM');
  final width = int.parse(token());
  final height = int.parse(token());
  if (token() != '255') throw const FormatException('not 8 bits a sample');
  at++;
  return (width, height, Uint8List.sublistView(bytes, at));
}

bool _alike((int, int, Uint8List) a, (int, int, Uint8List) b) {
  final (aw, ah, asamples) = a;
  final (bw, bh, bsamples) = b;
  if (aw != bw || ah != bh || asamples.length < aw * ah * 3) return false;
  if (bsamples.length < aw * ah * 3) return false;
  var apart = 0;
  for (var i = 0; i < aw * ah * 3; i += 3) {
    for (var c = 0; c < 3; c++) {
      if ((asamples[i + c] - bsamples[i + c]).abs() > 64) {
        apart++;
        break;
      }
    }
  }
  return apart <= aw * ah / 100;
}
