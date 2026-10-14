/// French spacing (Ptome; not under `asciidoctor-compat`): the no-break
/// spaces French typography puts before high punctuation and inside
/// guillemets, after the Imprimerie nationale's *Lexique des règles
/// typographiques* (France, Belgium, Switzerland) and the Office québécois
/// de la langue française's *Banque de dépannage linguistique* (Canada).
library;

import 'package:ptome/src/abstract_node.dart';
import 'package:ptome/src/compat.dart';
import 'package:ptome/src/document.dart';
import 'package:ptome/src/inline_tree.dart';

/// How [node]'s text is spaced, by its language (its block's `lang`, the
/// document's): null where it isn't French, or where `asciidoctor-compat`
/// names the document's format.
FrenchSpacing? frenchSpacingOf(AbstractNode node) {
  final document = switch (node) {
    final Document d => d,
    _ => node.document,
  };
  if (document is! Document) return null;
  final format = CompatFormat.named(document.attr('backend') ?? 'html5');
  if (format == null || asciidoctorCompat(document, format)) return null;
  String? language;
  for (AbstractNode? n = node; n != null; n = n.parent) {
    if (n.attributes['lang'] case final lang? when lang.isNotEmpty) {
      language = lang;
      break;
    }
  }
  language ??= document.attr('lang');
  final subtags = (language ?? '').toLowerCase().split(RegExp('[-_]'));
  if (subtags.first != 'fr') return null;
  return subtags.contains('ca') ? FrenchSpacing.canada : FrenchSpacing.france;
}

/// The spacing conventions of French.
enum FrenchSpacing {
  /// France, Belgium, Switzerland (the *Lexique*): a narrow no-break space
  /// before `;`, `!` and `?`, a no-break space before `:` and inside
  /// guillemets.
  france,

  /// Canada (the OQLF): a no-break space before `:` and inside guillemets,
  /// none before `;`, `!` and `?`.
  canada;

  /// [text] (substituted text: markup and character references in it)
  /// with its spaces put in.
  String apply(String text) {
    if (!_candidate.hasMatch(text)) return text;
    return InlineRun.replace(text, _scan, (m) {
      final s = m[0]!;
      final input = m.input;
      // Markup and character references stay as they are.
      if (s.startsWith('<') || s.startsWith('&')) return s;
      final mark = s.trim();
      // (What comes before the match, and after it.)
      final before = input.substring(0, m.start);
      final after = input.substring(m.end);
      if (_nbspEnd.hasMatch(before)) return s;
      switch (mark) {
        case '«' || '‹':
          // An opening guillemet before a word.
          if (after.isEmpty ||
              _spaceStart.hasMatch(after) ||
              _nbspStart.hasMatch(after)) {
            return s;
          }
          return '$mark$_nbsp';
        case '»' || '›':
          if (!_wordEnd.hasMatch(before)) return s;
          return '$_nbsp$mark';
        default:
          // `;`, `!`, `?` (France alone) and `:` ending a word, followed by
          // a space, the end, markup or closing punctuation.
          if (mark != ':' && this == canada) return s;
          if (!_wordEnd.hasMatch(before) || !_follows.hasMatch(after)) {
            return s;
          }
          return '${mark == ':' ? _nbsp : _narrowNbsp}$mark';
      }
    });
  }
}

const String _nbsp = '&#160;';
const String _narrowNbsp = '&#8239;';

/// What may be spaced: a quick test before the scan.
final RegExp _candidate = RegExp('[;!?:«»‹›]');

/// Markup and character references (kept whole), the marks (a space
/// before the closing ones, or after the opening ones, taken with them).
final RegExp _scan = RegExp('<[^>]*>|&#?[A-Za-z0-9]+;| ?[;!?:»›]|[«‹] ?');

/// Text ending a word: a letter, a digit, closing punctuation, the end of
/// markup or of a character reference.
final RegExp _wordEnd = RegExp(
  r'[\p{L}\p{N}\p{M})\]}»›”’…%*>;]$',
  unicode: true,
);

/// What may follow high punctuation: a space, the end, markup, a
/// character reference, closing punctuation, more punctuation.
final RegExp _follows = RegExp(r'^($|[\s<&)\]}»›”’.,;!?…])');

final RegExp _spaceStart = RegExp(r'^\s');
final RegExp _nbspStart = RegExp('^(&#160;|&#8239;|\u00a0|\u202f)');
final RegExp _nbspEnd = RegExp('(&#160;|&#8239;|\u00a0|\u202f)\$');
