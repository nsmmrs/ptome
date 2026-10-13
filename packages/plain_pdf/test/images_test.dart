import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:plain_images/plain_images.dart';
import 'package:plain_pdf/plain_pdf.dart';
import 'package:plain_typesetting/plain_typesetting.dart';
import 'package:test/test.dart';

/// A one-page PDF showing [image] at one point per pixel, filling the
/// page.
Uint8List imagePdf(PdfImage image, {PdfWriterOptions? options}) =>
    pagePdf(image.width, image.height, (writer) {
      image.writeTo(writer);
      return image.reference(writer);
    }, options: options);

/// A one-page PDF of [w] by [h] points filled with the image XObject
/// [image] writes.
Uint8List pagePdf(
  int w,
  int h,
  PdfRef Function(PdfWriter writer) image, {
  PdfWriterOptions? options,
}) {
  final out = BytesBuilder(copy: false);
  final writer = PdfWriter(
    out.add,
    options: options ?? const PdfWriterOptions(deterministic: true),
  );
  final pages = writer.reserve();
  final content = writer.write(
    PdfStream(ascii.encode('q $w 0 0 $h 0 0 cm /Im1 Do Q')),
  );
  final page = writer.write(
    PdfDict({
      'Type': const PdfName('Page'),
      'Parent': pages,
      'MediaBox': PdfArray([
        const PdfInt(0),
        const PdfInt(0),
        PdfInt(w),
        PdfInt(h),
      ]),
      'Resources': PdfDict({
        'XObject': PdfDict({'Im1': image(writer)}),
      }),
      'Contents': content,
    }),
  );
  final catalog = writer.reserve();
  writer
    ..write(
      PdfDict({
        'Type': const PdfName('Pages'),
        'Kids': PdfArray([page]),
        'Count': const PdfInt(1),
      }),
      pages,
    )
    ..write(
      PdfDict({'Type': const PdfName('Catalog'), 'Pages': pages}),
      catalog,
    )
    ..close(root: catalog);
  return out.takeBytes();
}

bool _has(String tool) => Process.runSync('which', [tool]).exitCode == 0;

/// ImageMagick: `magick` (version 7), or `convert` (version 6).
final String? _magick = _has('magick')
    ? 'magick'
    : _has('convert')
    ? 'convert'
    : null;

final bool _tools = _has('qpdf') && _has('pdftoppm') && _magick != null;

/// An RGB raster: width, height and 8-bit samples.
typedef Raster = (int, int, Uint8List);

/// The raster of a binary PPM (P6, maximum 255).
Raster parsePpm(Uint8List bytes) {
  final fields = <String>[];
  var at = 0;
  while (fields.length < 4) {
    while (bytes[at] == 0x23 || _space(bytes[at])) {
      if (bytes[at] == 0x23) {
        while (bytes[at] != 0x0a) {
          at++;
        }
      }
      at++;
    }
    final start = at;
    while (!_space(bytes[at])) {
      at++;
    }
    fields.add(ascii.decode(bytes.sublist(start, at)));
  }
  expect(fields[0], 'P6');
  expect(fields[3], '255');
  return (
    int.parse(fields[1]),
    int.parse(fields[2]),
    Uint8List.sublistView(bytes, at + 1),
  );
}

bool _space(int b) => b == 0x20 || b == 0x0a || b == 0x0d || b == 0x09;

/// The PDF's page as poppler renders it, a pixel per point: rendered at
/// four times the size and sampled at the center of each 4×4 block (at
/// one to one, poppler's image sampling lands a pixel off).
Raster render(Directory dir, Uint8List pdf) {
  final file = File('${dir.path}/t.pdf')..writeAsBytesSync(pdf);
  final check = Process.runSync('qpdf', ['--check', file.path]);
  expect(check.exitCode, 0, reason: '${check.stdout}${check.stderr}');
  final result = Process.runSync('pdftoppm', [
    '-r',
    '288',
    '-singlefile',
    file.path,
    '${dir.path}/page',
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  final (w, h, samples) = parsePpm(
    File('${dir.path}/page.ppm').readAsBytesSync(),
  );
  final out = Uint8List((w ~/ 4) * (h ~/ 4) * 3);
  for (var y = 0; y < h ~/ 4; y++) {
    for (var x = 0; x < w ~/ 4; x++) {
      final from = ((4 * y + 2) * w + 4 * x + 2) * 3;
      out.setRange(
        (y * (w ~/ 4) + x) * 3,
        (y * (w ~/ 4) + x + 1) * 3,
        samples,
        from,
      );
    }
  }
  return (w ~/ 4, h ~/ 4, out);
}

/// [path] as ImageMagick decodes it, composited on white (with
/// [flatten], on its canvas: a GIF frame's offset).
Raster reference(String path, {bool flatten = false}) {
  final result = Process.runSync(_magick!, [
    path,
    '-background',
    'white',
    if (flatten) '-flatten',
    '-alpha',
    'remove',
    '-alpha',
    'off',
    '-depth',
    '8',
    'ppm:-',
  ], stdoutEncoding: null);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return parsePpm(Uint8List.fromList(result.stdout as List<int>));
}

/// The mean and the largest absolute difference between samples.
(double, int) difference(Raster a, Raster b) {
  expect((a.$1, a.$2), (b.$1, b.$2), reason: 'dimensions');
  var sum = 0;
  var max = 0;
  for (var i = 0; i < a.$3.length; i++) {
    final d = (a.$3[i] - b.$3[i]).abs();
    sum += d;
    if (d > max) max = d;
  }
  return (sum / a.$3.length, max);
}

final List<File> _pngSuite =
    Directory('../plain_images/test/images/pngsuite')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

String _name(File file) => file.uri.pathSegments.last;

void main() {
  group('PngSuite', () {
    late Directory dir;
    setUpAll(() => dir = Directory.systemTemp.createTempSync('libpdf.'));
    tearDownAll(() => dir.deleteSync(recursive: true));

    for (final file in _pngSuite) {
      final name = _name(file);
      if (name.startsWith('x')) {
        // Damaged files: rejected, with a reason.
        test('$name is rejected', () {
          expect(
            () => PdfImage.parse(file.readAsBytesSync()),
            throwsA(isA<ImageFormatException>()),
          );
        });
        continue;
      }
      test(
        '$name renders as decoded',
        () {
          final image = PdfImage.parse(file.readAsBytesSync());
          final (mean, max) = difference(
            render(dir, imagePdf(image)),
            reference(file.path),
          );
          expect(mean, lessThan(1), reason: 'mean difference');
          expect(max, lessThanOrEqualTo(2), reason: 'largest difference');
        },
        skip: _tools ? false : 'needs qpdf, pdftoppm and ImageMagick',
        tags: ['pdf-tools'],
      );
    }
  });

  group('GIF and BMP', () {
    late Directory dir;
    setUpAll(() => dir = Directory.systemTemp.createTempSync('libpdf.'));
    tearDownAll(() => dir.deleteSync(recursive: true));

    for (final (folder, extension) in [('gif', '.gif'), ('bmp', '.bmp')]) {
      final files =
          Directory('../plain_images/test/images/$folder')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith(extension))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final name = _name(file);
        // (ImageMagick expands 1- and 4-bit alpha wrongly; plain_images
        // checks those bitmaps itself.)
        if (name.startsWith('argb')) continue;
        test(
          '$name renders as decoded',
          () {
            final image = PdfImage.parse(file.readAsBytesSync());
            final (mean, max) = difference(
              render(dir, imagePdf(image)),
              reference('${file.path}[0]', flatten: true),
            );
            expect(mean, lessThan(1), reason: 'mean difference');
            expect(max, lessThanOrEqualTo(2), reason: 'largest difference');
          },
          skip: _tools ? false : 'needs qpdf, pdftoppm and ImageMagick',
          tags: ['pdf-tools'],
        );
      }
    }
  });

  group('JPEG', () {
    late Directory dir;
    setUpAll(() => dir = Directory.systemTemp.createTempSync('libpdf.'));
    tearDownAll(() => dir.deleteSync(recursive: true));

    for (final name in [
      'gray',
      'rgb-baseline',
      'rgb-progressive',
      'rgb-420',
      'cmyk',
      'exif-orientation-6',
    ]) {
      test(
        '$name passes through and renders as decoded',
        () {
          final path = '../plain_images/test/images/jpeg/$name.jpg';
          final bytes = File(path).readAsBytesSync();
          final image = PdfImage.parse(bytes);
          final pdf = imagePdf(image);
          expect(_contains(pdf, bytes), isTrue, reason: 'embedded as it is');
          // CMYK is compared with poppler's own rendering of the samples
          // ImageMagick decodes, so only the data (and its inversion) is
          // compared, not two CMYK-to-RGB conversions.
          final expected = name == 'cmyk'
              ? render(dir, _rawCmykPdf(path, image.width, image.height))
              : reference(path);
          final (mean, max) = difference(render(dir, pdf), expected);
          expect(mean, lessThan(2), reason: 'mean difference');
          expect(max, lessThanOrEqualTo(8), reason: 'largest difference');
        },
        skip: _tools ? false : 'needs qpdf, pdftoppm and ImageMagick',
        tags: ['pdf-tools'],
      );
    }
  });

  test('JPEG that DCTDecode reads passes through; other JPEG is decoded', () {
    String pdfOf(String name) => latin1.decode(
      imagePdf(
        PdfImage.parse(
          File('../plain_images/test/images/jpeg-suite/$name')
              .readAsBytesSync(),
        ),
      ),
    );
    expect(pdfOf('sample-2x2.jpg'), contains('/DCTDecode'));
    expect(pdfOf('progressive.jpg'), contains('/DCTDecode'));
    for (final name in [
      'precision-12.jpg',
      'arithmetic.jpg',
      'lossless-1.jpg',
    ]) {
      final pdf = pdfOf(name);
      expect(pdf, isNot(contains('/DCTDecode')), reason: name);
      expect(pdf, contains('/FlateDecode'), reason: name);
    }
    expect(pdfOf('precision-12.jpg'), contains('/BitsPerComponent 16'));
  });

  test('an opaque PNG passes through without decoding', () {
    final bytes = File('../plain_images/test/images/pngsuite/basn2c08.png')
        .readAsBytesSync();
    final image = PdfImage.parse(bytes);
    final pdf = latin1.decode(imagePdf(image));
    expect(pdf, contains('/Predictor 15'));
    expect(pdf, isNot(contains('/SMask')));
    expect(_contains(imagePdf(image), (image.file as PngFile).data), isTrue);
  });

  test('alpha becomes a soft mask', () {
    final image = PdfImage.parse(
      File('../plain_images/test/images/pngsuite/basn6a08.png')
          .readAsBytesSync(),
    );
    expect(latin1.decode(imagePdf(image)), contains('/SMask'));
  });

  test('uncompressed output carries the samples as they are', () {
    final image = PdfImage.parse(
      File('../plain_images/test/images/pngsuite/basi0g08.png')
          .readAsBytesSync(),
    );
    final pdf = latin1.decode(
      imagePdf(
        image,
        options: const PdfWriterOptions(
          compress: false,
          compact: false,
          deterministic: true,
        ),
      ),
    );
    expect(pdf, contains('/Length ${32 * 32}'));
    expect(pdf, isNot(contains('/FlateDecode')));
  });

  test('a payload encoded elsewhere writes the same bytes', () {
    for (final name in ['basn6a08', 'basi0g08', 'tbbn3p08']) {
      List<int> bytes() =>
          File('../plain_images/test/images/pngsuite/$name.png')
              .readAsBytesSync();
      final image = PdfImage.parse(Uint8List.fromList(bytes()));
      expect(image.reencodes, isTrue, reason: name);
      const options = PdfWriterOptions(deterministic: true);
      final reference = imagePdf(image, options: options);
      final other = PdfImage.parse(Uint8List.fromList(bytes()))
        ..payload = PdfImage.parse(Uint8List.fromList(bytes())).encode(options);
      expect(imagePdf(other, options: options), reference, reason: name);
      // A payload for other compression isn't used.
      final stale = PdfImage.parse(Uint8List.fromList(bytes()))
        ..payload = PdfImage.parse(Uint8List.fromList(bytes()))
            .encode(const PdfWriterOptions(compress: false));
      expect(imagePdf(stale, options: options), reference, reason: name);
    }
    expect(
      PdfImage.parse(
        File('../plain_images/test/images/pngsuite/basn2c08.png')
            .readAsBytesSync(),
      ).reencodes,
      isFalse,
    );
  });

  test('images of the same file share one XObject', () {
    final bytes = File('../plain_images/test/images/pngsuite/basn2c08.png')
        .readAsBytesSync();
    final document = PdfDocument();
    for (var i = 0; i < 3; i++) {
      document
          .addPage(const Rect(0, 0, 100, 100))
          .canvas
          .image(
            PdfImage.parse(Uint8List.fromList(bytes)),
            const Rect(0, 0, 32, 32),
          );
    }
    final pdf = latin1.decode(
      document.save(
        options: const PdfWriterOptions(deterministic: true, compact: false),
      ),
    );
    expect(RegExp('/Subtype /Image').allMatches(pdf).length, 1);
  });

  test('anything else is not an image', () {
    expect(
      () => PdfImage.parse(Uint8List.fromList(ascii.encode('GIF89a'))),
      throwsA(isA<ImageFormatException>()),
    );
    expect(
      () => PdfImage.parse(Uint8List.fromList(ascii.encode('not an image'))),
      throwsA(isA<ImageFormatException>()),
    );
  });
}

/// A page showing the CMYK samples ImageMagick decodes from [path], as an
/// uncompressed DeviceCMYK image.
Uint8List _rawCmykPdf(String path, int width, int height) {
  final result = Process.runSync(_magick!, [
    path,
    '-depth',
    '8',
    'cmyk:-',
  ], stdoutEncoding: null);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return pagePdf(
    width,
    height,
    (writer) => writer.write(
      PdfStream(
        result.stdout as List<int>,
        dict: PdfDict({
          'Type': const PdfName('XObject'),
          'Subtype': const PdfName('Image'),
          'Width': PdfInt(width),
          'Height': PdfInt(height),
          'ColorSpace': const PdfName('DeviceCMYK'),
          'BitsPerComponent': const PdfInt(8),
        }),
      ),
    ),
  );
}

bool _contains(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
