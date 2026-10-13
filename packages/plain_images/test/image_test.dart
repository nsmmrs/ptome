/// Formats told by their signatures, and what the headers say.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:plain_images/plain_images.dart';
import 'package:test/test.dart';

Uint8List _file(String path) => File('test/images/$path').readAsBytesSync();

void main() {
  test('formats are told by their signatures', () {
    expect(ImageFormat.of(_file('pngsuite/basn2c08.png')), ImageFormat.png);
    expect(ImageFormat.of(_file('jpeg/gray.jpg')), ImageFormat.jpeg);
    expect(ImageFormat.of(_file('gif/few.gif')), ImageFormat.gif);
    expect(ImageFormat.of(_file('bmp/rgb24.bmp')), ImageFormat.bmp);
    expect(ImageFormat.of(Uint8List.fromList('hello'.codeUnits)), isNull);
  });

  test('formats it recognizes but does not read are named', () {
    Uint8List bytes(String text) => Uint8List.fromList(text.codeUnits);
    for (final (signature, name) in [
      ('\u0000\u0000\u0000\u001cftypavif', 'AVIF'),
      ('\u0000\u0000\u0000\u0018ftypheic', 'HEIC'),
      ('ÿ\u000a', 'JPEG XL'),
      ('II*\u0000\u0008\u0000\u0000\u0000', 'TIFF'),
      ('RIFF\u0000\u0000\u0000\u0000WEBPVP8 ', 'WebP'),
    ]) {
      expect(
        () => ImageFile.read(bytes(signature)),
        throwsA(
          isA<ImageFormatException>()
              .having((e) => e.unsupportedFormat, 'format', name)
              .having(
                (e) => e.message,
                'message',
                '$name images are not supported',
              ),
        ),
      );
    }
    expect(
      () => ImageFile.read(bytes('plain text')),
      throwsA(
        isA<ImageFormatException>().having(
          (e) => e.unsupportedFormat,
          'format',
          isNull,
        ),
      ),
    );
  });

  test('PNG chunks are read', () {
    PngFile png(String name) =>
        ImageFile.read(_file('pngsuite/$name.png')) as PngFile;
    final palette = png('basn3p04');
    expect(palette.colorType, PngColorType.palette);
    expect(palette.colorModel, ColorModel.indexed);
    expect(palette.bitDepth, 4);
    expect(png('basi6a16').interlaced, isTrue);
    expect(png('tbrn2c08').transparency, isNotNull);
    expect(png('tbrn2c08').colorKey, isNotNull);
    expect(png('exif2c08').orientation, 1);
  });

  test('JPEG frame header, Adobe segment and orientation are read', () {
    JpegFile jpeg(String name) =>
        ImageFile.read(_file('jpeg/$name.jpg')) as JpegFile;
    final gray = jpeg('gray');
    expect((gray.width, gray.height, gray.components), (48, 32, 1));
    expect(gray.colorModel, ColorModel.gray);
    expect(jpeg('rgb-baseline').progressive, isFalse);
    expect(jpeg('rgb-progressive').progressive, isTrue);
    expect(jpeg('cmyk').components, 4);
    expect(jpeg('cmyk').adobe, isTrue);
    expect(jpeg('rgb-baseline').orientation, 1);
    expect(jpeg('exif-orientation-6').orientation, 6);
  });

  test('GIF and BMP headers', () {
    final animated =
        ImageFile.read(_file('gif/animated-offset.gif')) as GifFile;
    expect((animated.width, animated.height), (40, 30));
    expect((animated.frameLeft, animated.frameTop), (7, 5));
    expect(animated.frames, 2);
    expect(
      (ImageFile.read(_file('gif/interlaced.gif')) as GifFile).interlaced,
      isTrue,
    );
    final rle = ImageFile.read(_file('bmp/rle8.bmp')) as BmpFile;
    expect(rle.compression, BmpCompression.rle8);
    expect(rle.colorModel, ColorModel.indexed);
    final os2 = ImageFile.read(_file('bmp/os2-pal4.bmp')) as BmpFile;
    expect((os2.width, os2.height, os2.bitsPerPixel), (23, 17, 4));
    expect(
      (ImageFile.read(_file('bmp/rgba32-v5.bmp')) as BmpFile).masks,
      isNotNull,
    );
  });

  test('the raster of a 16-bit image rounds to 8 bits', () {
    final raster = ImageFile.read(_file('pngsuite/basn0g16.png')).decode();
    expect(raster.bitDepth, 16);
    final value = raster.sample(0, 0);
    expect(raster.toRgba8()[0], (value * 255 + 32767) ~/ 65535);
  });
}
