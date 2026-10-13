/// plain_images: raster image files read in pure Dart.
///
/// - `ImageFile.read` tells a file's format by its signature and reads
///   its header: `PngFile`, `JpegFile`, `GifFile`, `BmpFile`,
///   `WebPFile`. Formats it
///   recognizes but doesn't read (AVIF, HEIC, ...) are named in the
///   `ImageFormatException` it throws.
/// - `ImageFile.decode` gives a `Raster`: packed samples (gray, RGB, CMYK
///   or palette indices, 1 to 16 bits), with what is transparent kept
///   apart (an `AlphaChannel` or a `ColorKey`), the ICC profile and the
///   EXIF orientation.
library;

export 'src/exception.dart' show ImageFormatException;
export 'src/image.dart'
    show
        AlphaChannel,
        BmpCompression,
        BmpFile,
        ColorKey,
        ColorModel,
        GifFile,
        ImageFile,
        ImageFormat,
        JpegFile,
        PngColorType,
        PngFile,
        Raster,
        Transparency,
        WebPFile;
