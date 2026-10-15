/// Jump lines: a piece that goes on later in the document says where
/// ("Continued on page 7"), and where it goes on says where it came from
/// ("Continued from page 1"). A paragraph with the role `jump` whose
/// content is a cross reference alone is one: the PDF words it with the
/// target's page, HTML with the target's title (a website's page). The
/// `jump-template` attribute words it (ADR-0010).
library;

import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/document.dart';
import 'package:ptome/src/output_template.dart';

/// The default wording: with a page, "Continued on page 7" ("from" when
/// the target comes before); without, "Continued in The Science".
const String defaultJumpTemplate =
    '{{#page}}Continued {{#back}}from{{/back}}{{^back}}on{{/back}} '
    'page {{page}}{{/page}}{{^page}}Continued '
    '{{#back}}from{{/back}}{{^back}}in{{/back}} {{title}}{{/page}}';

/// The jump line of [doc] to a target titled [title] on [page] (none in
/// HTML), [back] when the target comes before it.
String jumpText(
  Document doc, {
  required String title,
  required bool back,
  String? page,
}) => renderTemplate(doc.attr('jump-template') ?? defaultJumpTemplate, {
  'title': title,
  'page': page,
  'back': back ? 'back' : null,
});

/// Whether [block] is a jump line: a paragraph with the role `jump`.
bool isJump(AbstractBlock block) => block.includesRole('jump');

/// Whether the block [id] names comes before [block] in [doc] (the
/// AsciiDoc table cells' documents in their places among its blocks, a
/// newspaper's stories set in a table).
bool jumpsBack(Document doc, AbstractBlock block, String id) {
  var root = doc;
  for (var parent = doc.parentDocument; parent != null;) {
    root = parent;
    parent = parent.parentDocument;
  }
  for (final other in root.findBy(traverseDocuments: true)) {
    if (identical(other, block)) return false;
    if (other.id == id) return true;
  }
  return false;
}
