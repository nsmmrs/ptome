@TestOn('vm')
library;

import 'package:ptome/src/font_index.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:test/test.dart';

/// The tests' output depends on the fonts they name alone, so that it is
/// the same on every machine: no font installed on this one is found.
void main() {
  test("the tests search none of the machine's font folders", () {
    expect(
      Fonts.systemFonts,
      isFalse,
      reason:
          'run the tests with PTOME_SYSTEM_FONTS=off '
          '(tool/gate.sh and CI set it)',
    );
    final machine = io.fontDirectories;
    expect(Fonts.machine().directories, isNot(anyElement(isIn(machine))));
    for (final font in Fonts.machine().fonts) {
      expect(machine.where(font.path.startsWith), isEmpty, reason: font.path);
    }
  });
}
