/// A document's logical structure: what each piece of its content is
/// (a paragraph, a heading, a list item, a table cell, a figure), as
/// Tagged PDF's structure tree records it (ISO 32000-2, 14.7–14.8) for
/// assistive technology, reflow and extraction.
library;

import 'package:plain_typesetting/src/canvas.dart';

/// A node of the logical structure: a box's content, by one of the
/// standard structure types (ISO 32000-2, 14.8.4: `P`, `H1`–`H6`, `L`,
/// `LI`, `Lbl`, `LBody`, `Table`, `TR`, `TH`, `TD`, `Figure`, `Caption`,
/// `BlockQuote`, `Code`, `Note`, `Sect`, `Div`, `Span`). One element is
/// one node however many pieces its content is split into: the same
/// object for each.
final class StructureElement {
  /// An element of [role], with [alt] (a figure's alternate description,
  /// which assistive technology reads instead of its content), its own
  /// [language], [actualText] (what its content reads as) and the
  /// [attributes] of its role's owner (a table header cell's `Scope`).
  new(
    this.role, {
    this.alt,
    this.language,
    this.actualText,
    this.attributes = const {},
  });

  /// The standard structure type.
  final String role;

  /// The alternate description.
  final String? alt;

  /// The natural language of its content, where not the document's.
  final String? language;

  /// The text its content reads as.
  final String? actualText;

  /// Attributes of the owner of [role]'s standard attributes (`Table` for
  /// `Scope`, `Layout` for `Placement`): names and values (a name's value
  /// starting with `/`, a number's all digits).
  final Map<String, String> attributes;
}

/// A canvas that records the logical structure of what is painted on it:
/// the content painted between [beginStructure] and [endStructure] is
/// that element's (and an element begun inside another is its child);
/// the content painted between [beginArtifact] and [endArtifact], or
/// outside any element, is no part of the document's content (running
/// heads, page numbers, backgrounds, rules).
abstract interface class StructureCanvas implements Canvas {
  /// Begins [element]'s content.
  void beginStructure(StructureElement element);

  /// Ends the element [beginStructure] began last.
  void endStructure();

  /// Begins content that is no part of the structure.
  void beginArtifact();

  /// Ends what [beginArtifact] began.
  void endArtifact();
}
