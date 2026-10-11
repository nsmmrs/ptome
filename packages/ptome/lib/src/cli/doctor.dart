/// `ptome doctor`: checks that the fonts the built-in PDF themes use
/// are installed, and offers to download the missing ones from their
/// official sources into this user's font folder.
///
/// Ptome compiles no fonts in: the backends use the fonts installed
/// on the machine (see `font_index.dart`), and a theme can name any of
/// them. The built-in themes name Noto, M+ (M PLUS) and the icon fonts of
/// prawn-icon; `doctor` finds them as the PDF backend does (by the gem's
/// file names, then by family) and fetches what is missing: the Noto and
/// M PLUS families from Google Fonts (each file checked to be the family
/// asked for), the icon fonts from their projects' repositories at pinned
/// commits (each file checked against its SHA-256 digest). Each font's
/// license is saved beside it. With a look (`--look`, or the look
/// `ptome.yml` names), the fonts its PDF theme names too, from
/// [lookFonts]: TeX Gyre from CTAN (pinned), Google Fonts families.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ptome/src/cli/compat_config.dart';
import 'package:ptome/src/font_index.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/look/loader.dart';
import 'package:ptome/src/look/model.dart';
import 'package:ptome/src/pdf/look_theme.dart';
import 'package:ptome/src/remote.dart';

/// Usage text for `doctor` (printed by `--help` and on misuse).
const String doctorUsage = '''
Usage: ptome doctor [options]

Checks that the fonts of ptome's built-in PDF themes are installed
(Noto Serif, Noto Sans, M+ 1mn for code, the fallback fonts, Noto Sans
Math and the icon fonts), and offers to download the missing ones from
their official sources (Google Fonts, the projects' repositories) into
this user's font folder, in a folder of its own named ptome.

With a look (--look, or the look ptome.yml names), the fonts that look
names too: the built-in looks' are TeX Gyre (from CTAN) and Google
Fonts families.

Options:
  -y, --yes             install the missing fonts without asking
  -c, --check           only check: exit with status 1 when fonts are
                        missing
      --look=LOOK       the fonts of LOOK too (troff, tech-book, ...)
      --looksdir=DIR    the folder of the looks
  -h, --help            show this help
''';

/// A face of a family.
enum FontStyle {
  /// Regular.
  normal('regular'),

  /// Bold.
  bold('bold'),

  /// Italic.
  italic('italic'),

  /// Bold italic.
  boldItalic('bold italic');

  new(this.label);

  /// The style's name in messages.
  final String label;

  /// Whether the style is bold.
  bool get isBold => this == bold || this == boldItalic;

  /// Whether the style is italic.
  bool get isItalic => this == italic || this == boldItalic;
}

/// A file to download, pinned to its digest.
typedef PinnedFile = ({String url, String sha256, String name});

/// Where a font comes from.
sealed class FontSource {
  const new();

  /// The source, as `doctor` names it.
  String get description;
}

/// A family of Google Fonts: the files of each style in its download
/// (`static/NotoSerif-Bold.ttf`), and its license file.
final class GoogleFonts extends FontSource {
  /// [family]'s [files] by style.
  const new(this.family, this.files, {this.license = 'OFL.txt'});

  /// The family's name on Google Fonts.
  final String family;

  /// The file of each style in the family's download.
  final Map<FontStyle, String> files;

  /// The license file in the download.
  final String license;

  @override
  String get description => '$family from Google Fonts';
}

/// Files from a project's repository, pinned to their digests.
final class PinnedFiles extends FontSource {
  /// The [files] of each style, and the [license] file (with
  /// [licenseInHeader], a file whose first comment states it).
  const new(
    this.project,
    this.files,
    this.license, {
    this.licenseInHeader = false,
  });

  /// The project, as `doctor` names it.
  final String project;

  /// The file of each style.
  final Map<FontStyle, PinnedFile> files;

  /// The license file.
  final PinnedFile license;

  /// Whether the license is the first comment of [license] (a stylesheet
  /// stating it).
  final bool licenseInHeader;

  @override
  String get description => project;
}

/// A font the built-in themes use.
final class NeededFont {
  /// A font named [name] (in messages), used by [usedBy], found by
  /// [fileNames] or [families] in [styles], from [source] under
  /// [license].
  const new({
    required this.name,
    required this.usedBy,
    required this.families,
    required this.styles,
    required this.fileNames,
    required this.source,
    required this.license,
  });

  /// The font, as `doctor` names it.
  final String name;

  /// What uses it.
  final String usedBy;

  /// The families it may be installed as (the first is the theme's).
  final List<String> families;

  /// The styles needed.
  final List<FontStyle> styles;

  /// The file names it may be installed under, by style (the gem's
  /// subsets, the project's own files).
  final Map<FontStyle, List<String>> fileNames;

  /// Where it comes from.
  final FontSource source;

  /// Its license, as `doctor` names it.
  final String license;
}

const List<FontStyle> _all = FontStyle.values;

GoogleFonts _google(String family, String prefix, List<FontStyle> styles) =>
    GoogleFonts(family, {
      for (final style in styles)
        style:
            'static/$prefix-${switch (style) {
              FontStyle.normal => 'Regular',
              FontStyle.bold => 'Bold',
              FontStyle.italic => 'Italic',
              FontStyle.boldItalic => 'BoldItalic',
            }}.ttf',
    });

Map<FontStyle, List<String>> _gemSubsets(String prefix) => {
  for (final style in _all)
    style: [
      '$prefix-${switch (style) {
        FontStyle.normal => 'regular',
        FontStyle.bold => 'bold',
        FontStyle.italic => 'italic',
        FontStyle.boldItalic => 'bold_italic',
      }}-subset.ttf',
    ],
};

const String _fontAwesome =
    'https://raw.githubusercontent.com/FortAwesome/Font-Awesome/5.15.1';
const String _foundation =
    'https://raw.githubusercontent.com/zurb/foundation-icon-fonts/'
    'afed003521ff971bc614de68bba2676e16ce39f4';
const String _paymentFont =
    'https://raw.githubusercontent.com/AlexanderPoellmann/PaymentFont/'
    'c9dcb62cc507d778c2aa92ecf4f7b1c5a63cd4c9';

const String _foundationDigest =
    '7e1dd03dd4ce90b658052554cd7459df16716717389a552fa4c6d56a5f8933e6';
const String _paymentFontDigest =
    '03eb1d6b2b330ea611766452bdc66c9236ab695e80e43af1e6609250b8cc09e9';

const PinnedFile _fontAwesomeLicense = (
  url: '$_fontAwesome/LICENSE.txt',
  sha256: 'e779748dfe75e84f974df3c7bc07f842011a100159158b0f1f49b2f2a5a515cb',
  name: 'FontAwesome-LICENSE.txt',
);

const String _ctanTexGyre = 'https://mirrors.ctan.org/fonts/tex-gyre';

const PinnedFile _gustLicense = (
  url: '$_ctanTexGyre/doc/GUST-FONT-LICENSE.txt',
  sha256: '2bd69affc3da00715116f713f57eab9707e96daf3562ad0215987b15b9c16f73',
  name: 'GUST-FONT-LICENSE.txt',
);

/// A TeX Gyre family from CTAN: its files ([name] lower-cased, `termes`)
/// pinned to their digests, by style.
NeededFont _texGyre(
  String name,
  String usedBy,
  Map<FontStyle, String> digests,
) {
  final family = 'TeX Gyre ${name[0].toUpperCase()}${name.substring(1)}';
  String file(FontStyle style) =>
      'texgyre$name-${switch (style) {
        FontStyle.normal => 'regular',
        FontStyle.bold => 'bold',
        FontStyle.italic => 'italic',
        FontStyle.boldItalic => 'bolditalic',
      }}.otf';
  return NeededFont(
    name: family,
    usedBy: usedBy,
    families: [family],
    styles: [...digests.keys],
    fileNames: {
      for (final style in digests.keys) style: [file(style)],
    },
    source: PinnedFiles('$family from CTAN', {
      for (final MapEntry(key: style, value: digest) in digests.entries)
        style: (
          url: '$_ctanTexGyre/opentype/${file(style)}',
          sha256: digest,
          name: file(style),
        ),
    }, _gustLicense),
    license: 'GUST Font License',
  );
}

/// The fonts the built-in looks name beyond the themes' (ADR-0023):
/// checked and installed for a look that names them (`--look`).
final List<NeededFont> lookFonts = [
  _texGyre('termes', 'the troff look (Times)', {
    FontStyle.normal:
        'cc3fe7c707b81428d23d54df3eadd9228a2bf6a4d43125d94df56f5f63134659',
    FontStyle.bold:
        '2fb3e952065fa153c7e4e64e04b98b9d79225739b6025aa3f0f0782d299ff61e',
    FontStyle.italic:
        '6dd103a1672e50568cd2f8a706ccd48443d44d7d073a59d2286f4e6f746575d6',
    FontStyle.boldItalic:
        '1bf6af99cb0e26c12951317032d79b96ae009551e59ccf02a5b24f325ecfec87',
  }),
  _texGyre('cursor', 'the troff look (Courier)', {
    FontStyle.normal:
        '0667deb48aa0e88be8f499c4d308e8b9116f290e7f969b0f5a34ee15c9644272',
    FontStyle.bold:
        '95e9755bfa05759e8d1f8fba21a919ba46091e1275aeb5bf831dffd9c93b041e',
    FontStyle.italic:
        '545f24a2a9e5dd5ace865fe5e80134f55a37794b36e26abae5424aebff600056',
    FontStyle.boldItalic:
        '6aa5c41f489b898aa890c543e7dcd5e732c63894babc65569e01ee7e46533d82',
  }),
  _texGyre('schola', 'the us-code look (Century Schoolbook)', {
    FontStyle.normal:
        '935b82e25f56b1d1276ca82793205e8ce254fbb37ebd38bedf7388cef21fbf44',
    FontStyle.bold:
        '988c7b2a0ff0eae77d1df3338751b3c47a5e759117734a375b8e7f9de80e698b',
    FontStyle.italic:
        '2f45b8c394037951aaec73d947f0b0c3af715950f8f207c9f4290ba37a53a4d2',
    FontStyle.boldItalic:
        '95f085da44c04817771f2a3a754b6eeb442b9a79e79f51dc3b0612e3cc0d75cc',
  }),
  _texGyre('pagella', 'the uk-act look (Palatino)', {
    FontStyle.normal:
        '44e64260716d8f2bbe412baa1ee99b7c995190ac4573177c24def0b9200438c7',
    FontStyle.bold:
        'dd4f9b69f0b24f1fb9be8634abf1fce2009e5c68a30842a3e9f5d6e535900abd',
    FontStyle.italic:
        '069bb27f48eb98a741715227fc6e4b7baf3639c29fc13925f70d1ed8884ac29a',
    FontStyle.boldItalic:
        '556fd64655a92bd9f5485ae2c03f7b9cdaf745a27a91d7edb3c3abde997206d2',
  }),
  NeededFont(
    name: 'Crimson Pro',
    usedBy: 'the tech-book and eu-journal looks (Minion, Albertina)',
    families: const ['Crimson Pro'],
    styles: _all,
    fileNames: const {},
    source: _google('Crimson Pro', 'CrimsonPro', _all),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'Fira Sans Condensed',
    usedBy: 'the tech-book look (Myriad Condensed)',
    families: ['Fira Sans Condensed'],
    // (Its semibold as the bold: Myriad's semibold condensed.)
    styles: [FontStyle.normal, FontStyle.bold],
    fileNames: {},
    source: GoogleFonts('Fira Sans Condensed', {
      FontStyle.normal: 'FiraSansCondensed-Regular.ttf',
      FontStyle.bold: 'FiraSansCondensed-SemiBold.ttf',
    }),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'Ubuntu Mono',
    usedBy: 'the tech-book look (code)',
    families: ['Ubuntu Mono'],
    styles: _all,
    fileNames: {},
    source: GoogleFonts('Ubuntu Mono', {
      FontStyle.normal: 'UbuntuMono-Regular.ttf',
      FontStyle.bold: 'UbuntuMono-Bold.ttf',
      FontStyle.italic: 'UbuntuMono-Italic.ttf',
      FontStyle.boldItalic: 'UbuntuMono-BoldItalic.ttf',
    }),
    license: 'Ubuntu Font Licence 1.0',
  ),
];

/// The families [look]'s PDF theme names (its `*_font_family` keys).
Set<String> lookFamilies(Look look) {
  final theme = lookTheme(look);
  return {
    for (final key in theme.keys)
      if (key.endsWith('_font_family')) ?theme.string(key),
  };
}

/// The fonts of the built-in PDF themes, their fallbacks, math and icons.
final List<NeededFont> neededFonts = [
  NeededFont(
    name: 'Noto Serif',
    usedBy: 'the default theme',
    families: const ['Noto Serif'],
    styles: _all,
    fileNames: _gemSubsets('notoserif'),
    source: _google('Noto Serif', 'NotoSerif', _all),
    license: 'SIL Open Font License 1.1',
  ),
  NeededFont(
    name: 'Noto Sans',
    usedBy: "ptome's theme, default-sans",
    families: const ['Noto Sans'],
    styles: _all,
    fileNames: _gemSubsets('notosans'),
    source: _google('Noto Sans', 'NotoSans', _all),
    license: 'SIL Open Font License 1.1',
  ),
  NeededFont(
    name: 'M+ 1mn',
    usedBy: 'code in the default themes',
    families: const ['M+ 1mn', 'M PLUS 1 Code'],
    // (Italics are slanted from these: M PLUS 1 Code has none.)
    styles: const [FontStyle.normal, FontStyle.bold],
    fileNames: _gemSubsets('mplus1mn'),
    source: _google('M PLUS 1 Code', 'MPLUS1Code', const [
      FontStyle.normal,
      FontStyle.bold,
    ]),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'M+ 1p',
    usedBy: 'the fallback font of the *-with-font-fallbacks themes',
    families: ['M+ 1p', 'M PLUS 1p'],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['mplus1p-regular-fallback.ttf'],
    },
    source: GoogleFonts('M PLUS 1p', {FontStyle.normal: 'MPLUS1p-Regular.ttf'}),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'Noto Emoji',
    usedBy: 'the emoji fallback of the *-with-font-fallbacks themes',
    families: ['Noto Emoji'],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['notoemoji-subset.ttf'],
    },
    source: GoogleFonts('Noto Emoji', {
      FontStyle.normal: 'static/NotoEmoji-Regular.ttf',
    }),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'Noto Sans Math',
    usedBy: 'math (stem) in PDFs',
    families: ['Noto Sans Math'],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['notosansmath-regular.ttf'],
    },
    source: GoogleFonts('Noto Sans Math', {
      FontStyle.normal: 'NotoSansMath-Regular.ttf',
    }),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'Font Awesome 5 Free Solid',
    usedBy: 'icons (fas), admonition icons',
    families: ['Font Awesome 5 Free Solid'],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['fa-solid.ttf', 'fa-solid-900.ttf'],
    },
    source: PinnedFiles('Font Awesome Free 5.15.1', {
      FontStyle.normal: (
        url: '$_fontAwesome/webfonts/fa-solid-900.ttf',
        sha256:
            'e3b4ee7d2dc2641317d00347cb27f06120dcda110d85af9a47f5ba29e6747e76',
        name: 'fa-solid-900.ttf',
      ),
    }, _fontAwesomeLicense),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'Font Awesome 5 Free Regular',
    usedBy: 'icons (far), admonition icons',
    families: ['Font Awesome 5 Free Regular'],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['fa-regular.ttf', 'fa-regular-400.ttf'],
    },
    source: PinnedFiles('Font Awesome Free 5.15.1', {
      FontStyle.normal: (
        url: '$_fontAwesome/webfonts/fa-regular-400.ttf',
        sha256:
            '5a6a7730b932700ce3bb607e6bf933ff0e9a62208ebeaa71a584151ab213151b',
        name: 'fa-regular-400.ttf',
      ),
    }, _fontAwesomeLicense),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'Font Awesome 5 Brands',
    usedBy: 'icons (fab)',
    families: ['Font Awesome 5 Brands'],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['fa-brands.ttf', 'fa-brands-400.ttf'],
    },
    source: PinnedFiles('Font Awesome Free 5.15.1', {
      FontStyle.normal: (
        url: '$_fontAwesome/webfonts/fa-brands-400.ttf',
        sha256:
            '0097aaf99df2ae041aeccda155c791b155c01039e0942d1ca36ec737982f67f7',
        name: 'fa-brands-400.ttf',
      ),
    }, _fontAwesomeLicense),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'Foundation Icons',
    usedBy: 'icons (fi)',
    families: [],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['foundation-icons.ttf'],
    },
    source: PinnedFiles(
      'Foundation Icons 3 (ZURB)',
      {
        FontStyle.normal: (
          url: '$_foundation/foundation-icons.ttf',
          sha256: _foundationDigest,
          name: 'foundation-icons.ttf',
        ),
      },
      (
        url: '$_foundation/foundation-icons.css',
        sha256:
            '09696d0bf5be7a592450a862b5cced3e249f137004a7302fae4984a81ebc2f1d',
        name: 'FoundationIcons-LICENSE.txt',
      ),
      licenseInHeader: true,
    ),
    license: 'MIT',
  ),
  const NeededFont(
    name: 'PaymentFont',
    usedBy: 'icons (pf)',
    families: [],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['paymentfont-webfont.ttf'],
    },
    source: PinnedFiles(
      'PaymentFont',
      {
        FontStyle.normal: (
          url: '$_paymentFont/fonts/paymentfont-webfont.ttf',
          sha256: _paymentFontDigest,
          name: 'paymentfont-webfont.ttf',
        ),
      },
      (
        url: '$_paymentFont/LICENSE',
        sha256:
            'a81002fa8cd21d4b4a21101bde70a1fb9b7803608f23012e04248b770a1b2dd1',
        name: 'PaymentFont-LICENSE.txt',
      ),
    ),
    license: 'MIT',
  ),
];

/// Where [font] in [style] is installed in [index], if it is: under one of
/// its file names, else as one of its families in that very style.
String? installedPath(FontIndex index, NeededFont font, FontStyle style) {
  for (final name in font.fileNames[style] ?? const <String>[]) {
    if (index.fileNamed(name) case final path?) return path;
  }
  for (final family in font.families) {
    final found = index.find(
      family,
      bold: style.isBold,
      italic: style.isItalic,
    );
    if (found != null &&
        found.bold == style.isBold &&
        found.italic == style.isItalic) {
      return found.path;
    }
  }
  return null;
}

/// Runs `ptome doctor` with [args]; its exit status (0 when every font
/// is installed, 1 when some are missing or couldn't be installed, 64 on
/// misuse). The fonts are looked up in [index] (the installed fonts) and
/// installed into [installDirectory] (this user's font folder's
/// `ptome`), fetched with [fetch]; a question is asked when
/// [interactive] (standard input is a terminal) and answered by
/// [readLine]. Without `--look`, the look a configuration file names
/// (found with [environment]) adds its fonts.
Future<int> runDoctor(
  List<String> args, {
  StringSink? out,
  StringSink? err,
  FontIndex Function()? index,
  String? installDirectory,
  Future<RemoteResource> Function(Uri uri)? fetch,
  bool? interactive,
  String? Function()? readLine,
  Map<String, String>? environment,
}) async {
  final output = out ?? io.standardOutput;
  final errors = err ?? io.standardError;
  var yes = false;
  var check = false;
  String? lookName;
  String? looksDir;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '-y' || '--yes':
        yes = true;
      case '-c' || '--check':
        check = true;
      case '-h' || '--help':
        output.write(doctorUsage);
        return 0;
      case '--look' when i + 1 < args.length:
        lookName = args[++i];
      case '--looksdir' when i + 1 < args.length:
        looksDir = args[++i];
      case _ when arg.startsWith('--look='):
        lookName = arg.substring('--look='.length);
      case _ when arg.startsWith('--looksdir='):
        looksDir = arg.substring('--looksdir='.length);
      default:
        errors
          ..writeln('ptome doctor: unknown option $arg')
          ..write(doctorUsage);
        return 64;
    }
  }
  if (lookName == null) {
    final configured = resolveLook(
      env: environment ?? io.environment,
      startDir: io.currentDirectory,
      warn: (message) => errors.writeln('ptome: WARNING: $message'),
    );
    lookName = configured?.look;
    looksDir ??= configured?.looksDir;
  }
  final List<NeededFont> needed;
  try {
    needed = switch (lookName) {
      null || 'ptome' => neededFonts,
      final name => () {
        final families = lookFamilies(
          LookLoader(looksDir: looksDir ?? io.currentDirectory).load(name),
        );
        return [
          ...neededFonts,
          for (final font in lookFonts)
            if (font.families.any(families.contains)) font,
        ];
      }(),
    };
  } on LookException catch (error) {
    errors.writeln('ptome doctor: $error');
    return 1;
  }
  final fonts = (index ?? Fonts.machine)();
  final missing = <(NeededFont, List<FontStyle>)>[];
  output.writeln(
    lookName == null || lookName == 'ptome'
        ? "The fonts of ptome's built-in PDF themes:"
        : "The fonts of ptome's built-in PDF themes and the look $lookName:",
  );
  for (final font in needed) {
    final absent = <FontStyle>[];
    final found = <String>{};
    for (final style in font.styles) {
      final path = installedPath(fonts, font, style);
      if (path == null) {
        absent.add(style);
      } else {
        found.add(_folderOf(path));
      }
    }
    final status = absent.isEmpty
        ? 'installed'
        : absent.length == font.styles.length
        ? 'missing'
        : 'missing ${absent.map((s) => s.label).join(', ')}';
    output.writeln(
      '  ${font.name.padRight(28)} ${status.padRight(10)} ${font.usedBy}'
      '${found.isEmpty ? '' : ' (${found.join(', ')})'}',
    );
    if (absent.isNotEmpty) missing.add((font, absent));
  }
  if (missing.isEmpty) {
    output.writeln('Every font is installed.');
    return 0;
  }
  output
    ..writeln()
    ..writeln(
      '${missing.length} of ${needed.length} fonts are missing; in their '
      'place PDFs use the built-in PDF fonts (Times, Helvetica, Courier) and '
      'show icons as text.',
    );
  if (check) return 1;
  final String target;
  try {
    target = installDirectory ?? _join(io.userFontDirectory, 'ptome');
  } on Exception {
    errors.writeln('ptome doctor: no font folder on this platform');
    return 1;
  }
  output
    ..writeln('They can be downloaded and installed into $target:')
    ..writeln();
  for (final (font, styles) in missing) {
    output.writeln(
      '  ${font.name.padRight(28)} ${font.source.description}, '
      '${font.license} (${styles.map((s) => s.label).join(', ')})',
    );
  }
  output.writeln();
  if (!yes) {
    if (!(interactive ?? io.hasTerminal)) {
      output.writeln('Run `ptome doctor --yes` to install them.');
      return 1;
    }
    output.write('Download and install them? [y/N] ');
    final answer = (readLine ?? io.readLine)()?.trim().toLowerCase() ?? '';
    if (answer != 'y' && answer != 'yes') {
      output.writeln('Nothing installed.');
      return 1;
    }
  }
  final download = fetch ?? io.fetchUri;
  final installed = <String>[];
  var failed = 0;
  final licenses = <String>{};
  for (final (font, styles) in missing) {
    try {
      final files = await _fetchFont(font, styles, download, licenses);
      io.createDirectories(target);
      for (final (name, bytes) in files) {
        final path = _join(target, name);
        io.writeBytes(path, bytes);
        if (name.endsWith('.ttf') || name.endsWith('.otf')) {
          installed.add(path);
        }
      }
      output.writeln('  installed ${font.name}');
    } on Exception catch (error) {
      failed++;
      errors.writeln('ptome doctor: ${font.name}: $error');
    }
  }
  if (installed.isNotEmpty) _register(installed);
  output.writeln(
    failed == 0
        ? 'Installed ${installed.length} font files into $target.'
        : 'Installed ${installed.length} font files into $target; '
              '$failed fonts could not be installed.',
  );
  return failed == 0 ? 0 : 1;
}

/// The files of [font] in [styles] (and its license, once per source),
/// fetched with [fetch]: their names and contents.
Future<List<(String, List<int>)>> _fetchFont(
  NeededFont font,
  List<FontStyle> styles,
  Future<RemoteResource> Function(Uri uri) fetch,
  Set<String> licenses,
) async {
  final files = <(String, List<int>)>[];
  switch (font.source) {
    case GoogleFonts(:final family, files: final wanted, :final license):
      final manifest = await _manifest(family, fetch);
      for (final style in styles) {
        final name = wanted[style];
        final url = name == null ? null : manifest.urls[name];
        if (name == null || url == null) {
          throw DoctorException('Google Fonts has no $name for $family');
        }
        final bytes = (await fetch(Uri.parse(url))).body;
        final actual = _familyOf(bytes);
        if (actual == null ||
            !actual.toLowerCase().startsWith(family.toLowerCase())) {
          throw DoctorException(
            '$name is not a font of $family (${actual ?? 'not a font'})',
          );
        }
        files.add((_baseName(name), bytes));
      }
      final licenseName = '${family.replaceAll(' ', '')}-$license';
      if (manifest.license case final text? when licenses.add(licenseName)) {
        files.add((licenseName, utf8.encode(text)));
      }
    case PinnedFiles(
      files: final wanted,
      :final license,
      :final licenseInHeader,
    ):
      for (final style in styles) {
        if (wanted[style] case final file?) {
          files.add((file.name, await _pinned(file, fetch)));
        }
      }
      if (licenses.add(license.name)) {
        var text = await _pinned(license, fetch);
        if (licenseInHeader) {
          final source = utf8.decode(text, allowMalformed: true);
          final end = source.indexOf('*/');
          text = utf8.encode(
            '${end < 0 ? source : source.substring(0, end + 2)}\n',
          );
        }
        files.add((license.name, text));
      }
  }
  return files;
}

/// The family name of the font in [bytes], or null when it isn't one.
String? _familyOf(List<int> bytes) => FontIndex.familyOf(bytes);

/// [file]'s contents, checked against its digest.
Future<List<int>> _pinned(
  PinnedFile file,
  Future<RemoteResource> Function(Uri uri) fetch,
) async {
  // (A mirror, CTAN's, may fail: each try may reach another.)
  late List<int> bytes;
  for (var attempt = 1; ; attempt++) {
    try {
      bytes = (await fetch(Uri.parse(file.url))).body;
      break;
    } on Exception {
      if (attempt == 3) rethrow;
    }
  }
  if ('${sha256.convert(bytes)}' != file.sha256) {
    throw DoctorException(
      '${file.url} is not the file expected (its SHA-256 differs)',
    );
  }
  return bytes;
}

/// The files of [family]'s download from Google Fonts, by name, and its
/// license's text.
Future<({Map<String, String> urls, String? license})> _manifest(
  String family,
  Future<RemoteResource> Function(Uri uri) fetch,
) async {
  final response = await fetch(
    Uri.https('fonts.google.com', '/download/list', {'family': family}),
  );
  final text = utf8.decode(response.body, allowMalformed: true);
  final start = text.indexOf('{');
  if (start < 0) throw DoctorException('Google Fonts has no $family');
  final urls = <String, String>{};
  String? license;
  if (jsonDecode(text.substring(start)) case {
    'manifest': {'fileRefs': [...final refs], 'files': [...final files]},
  }) {
    for (final ref in refs) {
      if (ref case {'filename': final String name, 'url': final String url}) {
        urls[name] = url;
      }
    }
    for (final file in files) {
      if (file
          case {
            'filename': final String name,
            'contents': final String contents,
          }
          when name.endsWith('.txt')) {
        license ??= contents;
      }
    }
  } else {
    throw DoctorException('Google Fonts sent no list of files for $family');
  }
  return (urls: urls, license: license);
}

/// Makes the fonts at [paths] known to the system: fontconfig's cache on
/// Linux, the user's font registry on Windows (macOS finds them).
void _register(List<String> paths) {
  if (io.isWindows) {
    for (final path in paths) {
      final name =
          '${_baseName(path).replaceAll(RegExp(r'\.[^.]+$'), '')} '
          '(TrueType)';
      io.commandOutput('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts',
        '/v',
        name,
        '/t',
        'REG_SZ',
        '/d',
        path,
        '/f',
      ]);
    }
    return;
  }
  final folder = _folderOf(paths.first);
  io.commandOutput('fc-cache', ['-f', folder]);
}

/// A failure to download or check a font.
final class DoctorException implements Exception {
  /// A failure with [message].
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

String _join(String dir, String name) => dir.endsWith('/') || dir.endsWith(r'\')
    ? '$dir$name'
    : '$dir${io.isWindows ? r'\' : '/'}$name';

String _folderOf(String path) {
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  return slash < 0 ? '.' : path.substring(0, slash);
}

String _baseName(String path) {
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  return slash < 0 ? path : path.substring(slash + 1);
}
