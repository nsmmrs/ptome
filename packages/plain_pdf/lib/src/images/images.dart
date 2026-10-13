/// Raster images as PDF image XObjects (ISO 32000-2, 8.9.5), from the
/// image files plain_images reads: JPEG files pass through as DCTDecode
/// streams (but 12-bit, arithmetic-coded and lossless ones, which
/// DCTDecode doesn't read, are decoded); PNG files pass through as
/// FlateDecode streams with a PNG predictor when PDF can show them as
/// they are; anything else is decoded, its samples written with a PNG
/// predictor (alpha as a soft mask, a transparent color as a color-key
/// mask, a palette as an indexed color space).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:plain_images/plain_images.dart';
import 'package:plain_pdf/src/drawing/canvas.dart';
import 'package:plain_pdf/src/images/png_filter.dart';
import 'package:plain_pdf/src/objects.dart';
import 'package:plain_pdf/src/writer.dart';
import 'package:plain_typesetting/plain_typesetting.dart';

/// An image's samples encoded for writing (see [PdfImage.encode]): the
/// compression they were encoded with, how the color samples are laid
/// out, and the stream data of the color and of the alpha.
@immutable
final class ImagePayload {
  /// A payload of the given parts.
  const new({
    required this.compress,
    required this.level,
    required this.colorModel,
    required this.bitDepth,
    required this.color,
    this.palette,
    this.colorKey,
    this.alpha,
    this.alphaDepth = 8,
  });

  /// Whether the streams are compressed.
  final bool compress;

  /// The compression level they were compressed at.
  final int level;

  /// How the color samples give a color.
  final ColorModel colorModel;

  /// The bits per color sample.
  final int bitDepth;

  /// The color's stream data.
  final Uint8List color;

  /// The palette of indexed samples: RGB triples.
  final Uint8List? palette;

  /// The transparent color's samples, if any.
  final List<int>? colorKey;

  /// The alpha's stream data, or null when the image is opaque.
  final Uint8List? alpha;

  /// The bits per alpha sample.
  final int alphaDepth;
}

/// A raster image, drawn as an image XObject.
final class PdfImage implements Graphic {
  /// The image of [file].
  new(this.file);

  /// The image file in [bytes] (any format plain_images reads); throws an
  /// [ImageFormatException] when it isn't one.
  factory parse(Uint8List bytes) => PdfImage(ImageFile.read(bytes));

  /// The image file.
  final ImageFile file;

  /// The width, in pixels.
  int get width => file.width;

  /// The height, in pixels.
  int get height => file.height;

  /// The EXIF orientation (1–8; 1 is upright). It is reported, not
  /// applied: placing the image is up to the caller.
  int get orientation => file.orientation;

  /// The bits per color component the XObject has.
  int get bitsPerComponent => switch (file) {
    JpegFile(:final precision) when _passThrough => precision,
    final other => other.bitDepth,
  };

  /// A pixel to a point.
  @override
  double get intrinsicWidth => width.toDouble();

  @override
  double get intrinsicHeight => height.toDouble();

  @override
  void paint(Canvas canvas, Rect rect) =>
      pdfCanvasOf(canvas, 'a PDF image').image(this, rect);

  /// The reference the image is written under, reserved from [writer].
  PdfRef reference(PdfWriter writer) =>
      _references[writer] ??= writer.reserve();

  final Expando<PdfRef> _references = Expando<PdfRef>();

  /// Whether PDF shows the file's data as it is: a JPEG file that
  /// DCTDecode reads (8-bit, Huffman-coded, DCT-based; of 1, 3 or 4
  /// components), or a PNG file that isn't interlaced and has no alpha to
  /// split out.
  bool get _passThrough => switch (file) {
    JpegFile(
      :final precision,
      :final lossless,
      :final arithmetic,
      :final components,
    ) =>
      precision == 8 &&
          !lossless &&
          !arithmetic &&
          (components == 1 || components == 3 || components == 4),
    PngFile(:final interlaced, :final colorType, :final transparency) =>
      !interlaced &&
          !colorType.hasAlpha &&
          !(colorType == PngColorType.palette && transparency != null),
    _ => false,
  };

  /// Whether writing the image decodes and encodes its samples: the work
  /// [encode] does.
  bool get reencodes => !_passThrough;

  /// The samples as writing the image with [options] encodes them, when
  /// it [reencodes]. Plain data, computed anywhere (another isolate, say)
  /// and handed back as [payload]; throws an [ImageFormatException] when
  /// the image data is damaged.
  ImagePayload encode(PdfWriterOptions options) {
    final raster = switch (file) {
      final PngFile png => png.decode(inflate: options.decodeZlib),
      final other => other.decode(),
    };
    final (alpha, alphaDepth) = switch (raster.transparency) {
      AlphaChannel(:final samples, :final bitDepth) => (samples, bitDepth),
      _ => (null, 8),
    };
    final rows = raster.height;
    Uint8List encoded(Uint8List samples, int depth, int channels) {
      if (!options.compress) return samples;
      final stride = (raster.width * channels * depth + 7) >> 3;
      return options.encodeZlib(
        filterImage(
          samples.length == stride * rows
              ? samples
              : Uint8List.sublistView(samples, 0, stride * rows),
          stride,
          (channels * depth + 7) >> 3,
        ),
      );
    }

    return ImagePayload(
      compress: options.compress,
      level: options.compressionLevel,
      colorModel: raster.colorModel,
      bitDepth: raster.bitDepth,
      color: encoded(
        raster.samples,
        raster.bitDepth,
        raster.colorModel.channels,
      ),
      palette: raster.palette,
      colorKey: switch (raster.transparency) {
        ColorKey(:final values) => values,
        _ => null,
      },
      alpha: alpha == null ? null : encoded(alpha, alphaDepth, 1),
      alphaDepth: alphaDepth,
    );
  }

  /// The samples encoded elsewhere (see [encode]), used when the image is
  /// written with the same compression (and the same zlib codec, which
  /// the caller sees to).
  ImagePayload? payload;

  /// Writes the image's objects to [writer].
  void writeTo(PdfWriter writer) {
    switch (file) {
      case final JpegFile jpeg when _passThrough:
        _writeJpeg(writer, jpeg);
        return;
      case final PngFile png when _passThrough:
        final colorSpace = _colorSpace(
          writer,
          png.colorModel,
          png.palette,
          png.iccProfile,
        );
        writer.write(
          _image(
            png.data,
            colorSpace,
            png.bitDepth,
            predictor: (png.colorType.channels, png.bitDepth),
            mask: _mask(png.colorKey?.values),
          ),
          reference(writer),
        );
        return;
      default:
    }
    final options = writer.options;
    final encoded = switch (payload) {
      final payload?
          when payload.compress == options.compress &&
              payload.level == options.compressionLevel =>
        payload,
      _ => encode(options),
    };
    final channels = encoded.colorModel.channels;
    final colorSpace = _colorSpace(
      writer,
      encoded.colorModel,
      encoded.palette,
      file.iccProfile,
    );
    final softMask = switch (encoded.alpha) {
      final alpha? => writer.write(
        _image(
          alpha,
          const PdfName('DeviceGray'),
          encoded.alphaDepth,
          predictor: options.compress ? (1, encoded.alphaDepth) : null,
          compress: options.compress,
        ),
      ),
      null => null,
    };
    writer.write(
      _image(
        encoded.color,
        colorSpace,
        encoded.bitDepth,
        predictor: options.compress ? (channels, encoded.bitDepth) : null,
        mask: _mask(encoded.colorKey),
        softMask: softMask,
        compress: options.compress,
      ),
      reference(writer),
    );
  }

  void _writeJpeg(PdfWriter writer, JpegFile jpeg) {
    writer.write(
      PdfStream(
        jpeg.bytes,
        dict: PdfDict({
          'Type': const PdfName('XObject'),
          'Subtype': const PdfName('Image'),
          'Width': PdfInt(width),
          'Height': PdfInt(height),
          'ColorSpace': switch (jpeg.components) {
            1 => const PdfName('DeviceGray'),
            3 => const PdfName('DeviceRGB'),
            4 => const PdfName('DeviceCMYK'),
            _ => throw ImageFormatException(
              'JPEG images with ${jpeg.components} components are not '
              'supported',
            ),
          },
          'BitsPerComponent': PdfInt(jpeg.precision),
          'Filter': const PdfName('DCTDecode'),
          if (jpeg.components == 4 && jpeg.adobe)
            'Decode': PdfArray([
              for (var i = 0; i < 4; i++) ...[const PdfInt(1), const PdfInt(0)],
            ]),
        }),
        compress: false,
      ),
      reference(writer),
    );
  }

  /// The color space of samples of [model]: a device space (ICC-based
  /// with an embedded profile), or indexed over RGB with [palette].
  PdfObject _colorSpace(
    PdfWriter writer,
    ColorModel model,
    Uint8List? palette,
    Uint8List? iccProfile,
  ) {
    final device = PdfName(switch (model) {
      ColorModel.gray => 'DeviceGray',
      ColorModel.cmyk => 'DeviceCMYK',
      ColorModel.rgb || ColorModel.indexed => 'DeviceRGB',
    });
    final base = switch (iccProfile) {
      final profile? => PdfArray([
        const PdfName('ICCBased'),
        writer.write(
          PdfStream(
            profile,
            dict: PdfDict({
              'N': PdfInt(switch (model) {
                ColorModel.gray => 1,
                ColorModel.cmyk => 4,
                _ => 3,
              }),
              'Alternate': device,
            }),
          ),
        ),
      ]),
      null => device,
    };
    if (model != ColorModel.indexed || palette == null) return base;
    final entries = palette.length ~/ 3;
    return PdfArray([
      const PdfName('Indexed'),
      base,
      PdfInt(entries - 1),
      PdfString(palette.sublist(0, entries * 3), hex: true),
    ]);
  }

  /// The color-key mask of transparent [samples].
  PdfArray? _mask(List<int>? samples) => samples == null
      ? null
      : PdfArray([
          for (final sample in samples) ...[PdfInt(sample), PdfInt(sample)],
        ]);

  /// An image XObject of [data] (Flate-compressed with a PNG predictor
  /// for samples of [predictor]'s channels and depth, if given).
  PdfStream _image(
    Uint8List data,
    PdfObject colorSpace,
    int depth, {
    (int channels, int depth)? predictor,
    PdfArray? mask,
    PdfRef? softMask,
    bool compress = true,
  }) => PdfStream(
    data,
    dict: PdfDict({
      'Type': const PdfName('XObject'),
      'Subtype': const PdfName('Image'),
      'Width': PdfInt(width),
      'Height': PdfInt(height),
      'ColorSpace': colorSpace,
      'BitsPerComponent': PdfInt(depth),
      if (predictor case (final channels, final depth)) ...{
        'Filter': const PdfName('FlateDecode'),
        'DecodeParms': PdfDict({
          'Predictor': const PdfInt(15),
          'Colors': PdfInt(channels),
          'BitsPerComponent': PdfInt(depth),
          'Columns': PdfInt(width),
        }),
      },
      'Mask': ?mask,
      'SMask': ?softMask,
    }),
    compress: compress && predictor == null,
  );
}
