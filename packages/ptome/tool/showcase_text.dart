/// What the showcase's importers (tool/showcase_import.dart,
/// tool/showcase_gutenberg.dart) share: text written as AsciiDoc that
/// reads as the text.
library;

/// [text] in an unconstrained mark pair (`__x__`), which holds wherever
/// it stands, its spaces outside it.
String markPair(String mark, String text, {String attributes = ''}) {
  if (text.trim().isEmpty) return text;
  final lead = text.substring(0, text.length - text.trimLeft().length);
  final trail = text.substring(text.trimRight().length);
  final inner = text.trim();
  return '$lead$attributes$mark$mark$inner$mark$mark$trail';
}

/// [text] with what AsciiDoc would read as markup written as character
/// references.
String escapeText(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    out.write(switch (rune) {
      0x26 => '&amp;',
      0x3C => '&lt;',
      0x3E => '&gt;',
      0x2A => '&#42;',
      0x5F => '&#95;',
      0x23 => '&#35;',
      0x60 => '&#96;',
      0x5E => '&#94;',
      0x7E => '&#126;',
      0x2B => '&#43;',
      0x7B => '&#123;',
      0x5B => '&#91;',
      0x5D => '&#93;',
      0x7C => '&#124;',
      _ => String.fromCharCode(rune),
    });
  }
  return '$out'
      .replaceAll('--', '-&#45;')
      .replaceAll('...', '..&#46;')
      .replaceAll('::', ':&#58;')
      .replaceAll(';;', ';&#59;')
      .replaceAll('(C)', '(&#67;)')
      .replaceAll('(R)', '(&#82;)')
      .replaceAll('(TM)', '(&#84;M)');
}

/// [text] with its first letter a capital.
String capitalized(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// [text] as a quotation's attribution: single-quoted, so that its
/// markup (a title's italics) is converted, as a double-quoted value's
/// isn't.
String citation(String text) => "'${text.replaceAll("'", r"\'")}'";

/// [text] as an attribute value: quoted.
String attributeValue(String text) => '"${text.replaceAll('"', r'\"')}"';

/// [line] safe to start a paragraph: `{empty}` before what would start a
/// list, a heading, a block title or an attribute entry.
String lineStart(String line) =>
    RegExp(r'^(\*+ |-+ |\.+\S|\.+ |\d+\. |[a-zA-Z]\. |=+ |:\w[\w-]*:|/{2})')
        .hasMatch(line)
    ? '{empty}$line'
    : line;
