/// The look a document names (ADR-0023): `look`, found in `looksdir`
/// before the built-in looks, else the house look `ptome`.
library;

import 'package:ptome/src/document.dart';
import 'package:ptome/src/logging.dart';
import 'package:ptome/src/look/loader.dart';
import 'package:ptome/src/look/model.dart';

/// The look [doc] names, or the house look ([house], or no `look`
/// attribute); a look that can't be read is reported and the house look
/// used.
Look documentLook(Document doc, {bool house = false}) {
  if (house) return _load(doc, 'ptome');
  // (Read once a document: its stylesheet, header and theme ask.)
  return _looks[doc] ??= _load(doc, doc.attr('look') ?? 'ptome');
}

final Expando<Look> _looks = Expando('documentLook');

/// [doc]'s look's named templates (ADR-0010's, ADR-0023 decision 1) as
/// the defaults of their attributes: the look's `templates.<name>` is the
/// `<name>-template` attribute where the document (or the command line)
/// sets none. Only a look the document names (the house look has none).
void applyLookTemplates(Document doc) {
  if (doc.attr('look') == null) return;
  for (final MapEntry(:key, :value) in documentLook(
    doc,
  ).templates.named.entries) {
    doc.attributes.putIfAbsent('$key-template', () => value);
  }
}

Look _load(Document doc, String name) {
  final dir = doc
      .attr('looksdir')
      ?.replaceAll('{docdir}', doc.attr('docdir') ?? '');
  try {
    return LookLoader(looksDir: dir).load(name);
  } on LookException catch (error) {
    LoggerManager.logger.error('$error');
    return LookLoader().load('ptome');
  }
}
