// The magazine looks on the web, as browsers draw them: the sample piece
// (test/look/magazine/feature.adoc) in each look, screenshot in headless
// Chromium (initial-letter, shape-outside) and Firefox (the fallbacks;
// driven through Marionette, so the shot waits for its fonts and images),
// compared with the reference screenshots in test/look/magazine/shots.
// A change on purpose is a change to those files:
//
//   MAGAZINE_SHOTS_UPDATE=1 dart test test/look/magazine_shots_test.dart
//
// The faces are the ones `ptome doctor --look <look>` installs, given to
// the browsers by @font-face (no network); a fresh Chromium profile gets
// the hyphenation dictionaries of this user's (it has none of its own).
// Skipped without the browsers (CHROMIUM_PATH, FIREFOX_PATH) or the faces.
@TestOn('vm')
@Tags(['slow'])
library;

import 'dart:io';

import 'package:ptome/src/cli/doctor.dart';
import 'package:ptome/src/font_index.dart';
import 'package:ptome/src/internal.dart';
import 'package:ptome/src/look/loader.dart';
import 'package:test/test.dart';

import '../support/marionette.dart';

const String _sample = 'test/look/magazine';

const List<String> _looks = [
  'magazine',
  'magazine-1950s',
  'magazine-1960s',
  'magazine-1970s',
  'magazine-1980s',
  'broadsheet',
  'compact',
];

/// The width of the window, in CSS pixels.
const int _width = 1280;

final bool _update = Platform.environment['MAGAZINE_SHOTS_UPDATE'] == '1';

/// A browser's executable: [variable]'s value, else [fallbacks]'
/// first that exists.
String? _browser(String variable, List<String> fallbacks) {
  final path = Platform.environment[variable];
  if (path != null) return File(path).existsSync() ? path : null;
  for (final candidate in fallbacks) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

final String? _chromium = _browser('CHROMIUM_PATH', ['/usr/bin/chromium']);
final String? _firefox = _browser('FIREFOX_PATH', [
  '/usr/bin/firefox',
  '${Platform.environment['HOME']}/.cache/asciidart-work/firefox/firefox',
]);

bool _has(String tool) => Process.runSync('which', [tool]).exitCode == 0;

/// The @font-face rules giving the browsers the looks' faces from their
/// installed files (a family set in an optical size, `Bodoni Moda 28pt`,
/// under its screen name, `Bodoni Moda`); null when one is missing.
String? _fontFaces() {
  final fonts = Fonts.machine();
  final rules = StringBuffer();
  final families = {
    for (final look in _looks) ...lookFamilies(LookLoader().load(look)),
  };
  for (final font in lookFonts) {
    if (!font.families.any(families.contains)) continue;
    final family = font.name.replaceFirst(RegExp(r' \d+pt$'), '');
    for (final style in font.styles) {
      final path = installedPath(fonts, font, style);
      if (path == null) return null;
      rules.write(
        '@font-face{font-family:"$family";src:url("file://$path");'
        'font-weight:${style.isBold ? 700 : 400};'
        'font-style:${style.isItalic ? 'italic' : 'normal'}}\n',
      );
    }
  }
  return '$rules';
}

late Directory _dir;

void main() {
  final faces = _fontFaces();
  final missing = [
    if (faces == null) "the looks' faces (ptome doctor --look …)",
    if (_chromium == null && _firefox == null) 'Chromium or Firefox',
    if (!_has('magick')) 'ImageMagick',
  ];

  setUpAll(() {
    _dir = Directory.systemTemp.createTempSync('magazine-shots');
    for (final image in ['coast.jpg', 'lighthouse.png']) {
      File('$_sample/$image').copySync('${_dir.path}/$image');
    }
  });
  tearDownAll(() async {
    await _marionette?.close();
    _dir.deleteSync(recursive: true);
  });

  for (final look in _looks) {
    for (final (name, browser) in [
      ('chromium', _chromium),
      ('firefox', _firefox),
    ]) {
      test(
        '$look in $name',
        () async {
          final page = _page(look, faces!);
          final shot = '${_dir.path}/$look-$name.png';
          final golden = File('$_sample/shots/$look-$name.png');
          Future<void> take() async {
            name == 'chromium'
                ? _chromiumShot(browser!, page, shot)
                : await _firefoxShot(browser!, page, shot);
            // (In 64 colors: the references stay small.)
            Process.runSync('magick', [
              shot,
              '+dither',
              '-colors',
              '64',
              'PNG8:$shot',
            ]);
          }

          await take();
          if (_update) {
            golden.parent.createSync(recursive: true);
            File(shot).copySync(golden.path);
            return;
          }
          expect(
            golden.existsSync(),
            isTrue,
            reason: 'no reference: run with MAGAZINE_SHOTS_UPDATE=1',
          );
          // (Taken again when it differs: Chromium under load may take it
          // before the faces are loaded; Firefox waits for them.)
          var (differing, total) = _difference(golden.path, shot);
          for (
            var retry = 0;
            retry < 2 && differing / total >= 0.002;
            retry++
          ) {
            await take();
            (differing, total) = _difference(golden.path, shot);
          }
          expect(
            differing / total,
            lessThan(0.002),
            reason:
                '$differing of $total pixels differ from ${golden.path} '
                '(now $shot); a change on purpose: MAGAZINE_SHOTS_UPDATE=1',
          );
        },
        skip: missing.isNotEmpty
            ? 'needs ${missing.join(', ')}'
            : browser == null
            ? 'needs $name'
            : false,
      );
    }
  }
}

/// The sample in [look] as a page in the temporary folder, its faces
/// given by [faces]; its path.
String _page(String look, String faces) {
  final out = '${_dir.path}/$look.html';
  convertFile(
    '$_sample/feature.adoc',
    AsciidoctorOptions(
      safe: SafeMode.unsafe,
      toFile: out,
      attributes: {'look': look, 'webfonts!': '', 'reproducible': ''},
    ),
  );
  final html = File(out).readAsStringSync();
  File(out).writeAsStringSync(
    // (Chromium's window is taller than the page: the page's own height,
    // not the window's, for a frame around the body.)
    html.replaceFirst(
      '</head>',
      '<style>\n${faces}body{min-height:0!important}</style>\n</head>',
    ),
  );
  return out;
}

/// Screenshots [page] in Chromium at [_width] into [shot]: a window
/// taller than the page, cut to the page's height.
void _chromiumShot(String chromium, String page, String shot) {
  final profile = Directory('${_dir.path}/chromium-profile');
  if (!profile.existsSync()) {
    profile.createSync();
    // (Hyphenation dictionaries, which only a used profile has.)
    final hyphens = Directory(
      '${Platform.environment['HOME']}/.config/chromium/hyphen-data',
    );
    if (hyphens.existsSync()) {
      Process.runSync('cp', ['-r', hyphens.path, profile.path]);
    }
  }
  final tall = '$shot.tall.png';
  final result = Process.runSync(chromium, [
    '--headless',
    '--disable-gpu',
    '--no-sandbox',
    '--hide-scrollbars',
    '--allow-file-access-from-files',
    '--force-device-scale-factor=1',
    '--user-data-dir=${profile.path}',
    '--window-size=$_width,8000',
    '--screenshot=$tall',
    'file://$page',
  ]);
  if (!File(tall).existsSync()) {
    fail('Chromium made no screenshot: ${result.stderr}');
  }
  // The page's height: down to its last mark that isn't the background.
  final box = Process.runSync('magick', [
    tall,
    '-trim',
    '-format',
    '%h %y',
    'info:',
  ]).stdout.toString().trim().split(' ');
  final height = int.parse(box[0]) + int.parse(box[1]) + 48;
  Process.runSync('magick', [
    tall,
    '-crop',
    '${_width}x$height+0+0',
    '+repage',
    shot,
  ]);
}

/// The Firefox the shots are taken in, started for the first one.
Marionette? _marionette;

/// Screenshots [page] in Firefox (the whole page) at [_width] into [shot],
/// once its fonts have loaded.
Future<void> _firefoxShot(String firefox, String page, String shot) async {
  final marionette = _marionette ??= await Marionette.start(
    firefox,
    Directory('${_dir.path}/firefox-profile'),
    width: _width,
  );
  File(shot).writeAsBytesSync(await marionette.screenshot('file://$page'));
}

/// How many pixels of [a] and [b] differ (beyond a little anti-aliasing),
/// and how many there are (of the larger, when their sizes differ).
(int, int) _difference(String a, String b) {
  String size(String path) => Process.runSync('magick', [
    'identify',
    '-format',
    '%w %h',
    path,
  ]).stdout.toString().trim();
  final (sa, sb) = (size(a), size(b));
  int area(String s) => s.split(' ').map(int.parse).reduce((x, y) => x * y);
  if (sa != sb) {
    final most = area(sa) > area(sb) ? area(sa) : area(sb);
    return (most, most);
  }
  final compared = Process.runSync('magick', [
    'compare',
    '-metric',
    'AE',
    '-fuzz',
    '10%',
    a,
    b,
    'null:',
  ]);
  final count = double.tryParse('${compared.stderr}'.trim().split(' ').first);
  return ((count ?? area(sa).toDouble()).round(), area(sa));
}
