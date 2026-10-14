/// The generated text in the document's language (Ptome; not under
/// `asciidoctor-compat`): Asciidoctor's translations of its labels
/// (`data/locale/attributes-<lang>.adoc`, which Asciidoctor has the author
/// include) read from the document's `lang` once its header is parsed, an
/// attribute the author set (in the header, or from the API or the command
/// line) kept; and the words an index's cross-references use.
library;

import 'package:ptome/src/compat.dart';
import 'package:ptome/src/data.g.dart';
import 'package:ptome/src/document.dart';

/// The locale file (`attributes-<name>.adoc`) for the BCP 47 tag [lang],
/// or null when there is none (English's labels are the defaults).
String? localeFileFor(String lang) {
  final subtags = lang.trim().toLowerCase().replaceAll('_', '-').split('-');
  final language = subtags.first;
  final rest = subtags.skip(1).toSet();
  final name = switch (language) {
    'en' || '' => null,
    'zh' when rest.intersection({'hant', 'tw', 'hk', 'mo'}).isNotEmpty =>
      'zh_TW',
    'zh' => 'zh_CN',
    'sr' when rest.contains('latn') => 'sr_Latn',
    'pt' when rest.contains('br') => 'pt_BR',
    'no' => 'nb',
    _ => language,
  };
  if (name == null) return null;
  final path = 'locale/attributes-$name.adoc';
  return EmbeddedData.files.containsKey(path) ? path : null;
}

/// The words an index uses to refer to another term, by language: Ptome's
/// own (Asciidoctor's locale files have none), as each language's style
/// guides write them.
const Map<String, (String, String)> _indexReferences = {
  'ca': ('vegeu', 'vegeu també'),
  'cs': ('viz', 'viz též'),
  'da': ('se', 'se også'),
  'de': ('siehe', 'siehe auch'),
  'es': ('véase', 'véase también'),
  'fi': ('katso', 'katso myös'),
  'fr': ('voir', 'voir aussi'),
  'hu': ('lásd', 'lásd még'),
  'id': ('lihat', 'lihat juga'),
  'it': ('vedi', 'vedi anche'),
  'nb': ('se', 'se også'),
  'nl': ('zie', 'zie ook'),
  'nn': ('sjå', 'sjå også'),
  'pl': ('zob.', 'zob. też'),
  'pt': ('ver', 'ver também'),
  'pt_BR': ('ver', 'ver também'),
  'ro': ('vezi', 'vezi și'),
  'ru': ('см.', 'см. также'),
  'sv': ('se', 'se även'),
  'tr': ('bkz.', 'ayrıca bkz.'),
  'uk': ('див.', 'див. також'),
  'zh_CN': ('见', '参见'),
  'zh_TW': ('見', '參見'),
};

/// The English labels Asciidoctor's locale files set only when the author
/// turns them on (`ifdef::listing-caption[...]`).
const Map<String, String> _english = {
  'listing-caption': 'Listing',
  'manname-title': 'Name',
  'preface-title': 'Preface',
};

/// Whether the labels follow [document]'s language: `locale-labels`
/// `true` or `false` says so; unset, they do unless `asciidoctor-compat`
/// names a format (the parse is one for every format).
bool _localized(Document document) =>
    switch (document.attr('locale-labels')?.trim().toLowerCase()) {
      'false' || 'none' => false,
      null => !anyAsciidoctorCompat(document),
      _ => true,
    };

/// Sets [document]'s labels from its language's locale file: each entry of
/// the file (`:name: value`, or `ifdef::other[:name: value]` when `other`
/// is set) whose attribute the author didn't set (or turned on, empty or
/// in English, for `ifdef::name[:name: value]`), its references to other
/// attributes (`{appendix-caption}`) replaced; then the index's words.
/// A nested document (an AsciiDoc table cell's) keeps its parent's.
void applyLocaleLabels(Document document) {
  if (document.parentDocument != null) return;
  final lang = document.attr('lang');
  if (lang == null || !_localized(document)) return;
  final path = localeFileFor(lang);
  if (path == null) return;
  final attributes = document.attributes;
  final authored = {
    for (final entry
        in document.headerAttributeEntries ?? const <DocumentAttributeEntry>[])
      entry.name,
  };
  bool free(String name) =>
      !authored.contains(name) && !document.attributeLocked(name);
  final entry = RegExp(
    r'^(?:ifdef::([\w-]+)\[:([\w-]+):\s*(.*)\]|:([\w-]+):\s*(.*))$',
  );
  for (final line in EmbeddedData.files[path]!.split('\n')) {
    if (line.startsWith('//')) continue;
    final match = entry.firstMatch(line.trim());
    if (match == null) continue;
    final condition = match[1];
    final name = match[2] ?? match[4]!;
    final value = match[3] ?? match[5]!;
    if (condition != null && !attributes.containsKey(condition)) continue;
    // (A label the author turns on, `:listing-caption:`, empty or in
    // English, is translated.)
    final enabled =
        condition == name &&
        (attributes[name]!.isEmpty || attributes[name] == _english[name]);
    if (!enabled && !free(name)) continue;
    attributes[name] = value.trimRight().replaceAllMapped(
      RegExp(r'\{([\w-]+)\}'),
      (m) => attributes[m[1]!] ?? m[0]!,
    );
  }
  final key = path.substring('locale/attributes-'.length, path.length - 5);
  if (_indexReferences[key] case (final see, final also)) {
    if (free('index-see-label')) attributes['index-see-label'] = see;
    if (free('index-see-also-label')) {
      attributes['index-see-also-label'] = also;
    }
  }
}
