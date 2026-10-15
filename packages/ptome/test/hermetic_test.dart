@TestOn('vm')
library;

import 'package:ptome/src/font_index.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:test/test.dart';

/// The tests' output depends on what they give it alone, so that it is
/// the same on every machine and every run, and the outside tools'
/// answers recorded for it (test/support/oracles.dart) still hold: no
/// font installed on the machine is found (nor PTOME_FONT_PATH's), and
/// the date and the time zone are fixed (tool/gate.sh and CI set them
/// so).
void main() {
  const reason =
      'run the tests with PTOME_SYSTEM_FONTS=off '
      'SOURCE_DATE_EPOCH=1767225600 TZ=UTC (tool/gate.sh and CI set them)';

  test("the tests search none of the machine's font folders", () {
    expect(Fonts.systemFonts, isFalse, reason: reason);
    // (Nor a folder of this shell's: the fonts are the tests' own.)
    expect(Fonts.fontPath, isEmpty, reason: 'PTOME_FONT_PATH is set');
    final machine = io.fontDirectories;
    expect(Fonts.machine().directories, isNot(anyElement(isIn(machine))));
    for (final font in Fonts.machine().fonts) {
      expect(machine.where(font.path.startsWith), isEmpty, reason: font.path);
    }
  });

  test('the date and the time zone are fixed', () {
    expect(io.environment['SOURCE_DATE_EPOCH'], '1767225600', reason: reason);
    expect(DateTime.now().timeZoneOffset, Duration.zero, reason: reason);
  });
}
