/// A title page's slots (ADR-0023) as HTML: the header's in HTML, the
/// title page's in an EPUB.
library;

import 'package:ptome/src/document.dart';
import 'package:ptome/src/look/model.dart';
import 'package:ptome/src/text_case.dart';

/// The header's [slots] in their order, each an element of the class
/// `title-page-<part>` (or `<attribute>`) and its role's.
List<String> titleSlotsHtml(
  Document node,
  List<Slot> slots, {
  required String br,
  String voidSlash = '',
}) {
  final title = node.partitionedTitle(separator: node.attr('title-separator'));
  // (The whole title, when no slot shows the subtitle.)
  final subtitled = slots.any(
    (slot) => switch (slot.content) {
      PartContent(part: TitlePart.subtitle) => true,
      _ => false,
    },
  );
  final result = <String>[];
  for (final slot in slots) {
    final name = switch (slot.content) {
      PartContent(:final part) => part.name,
      AttributeContent(:final name) => name,
    };
    final classes = ['title-page-$name', ?slot.role].join(' ');
    final before = switch (slot.before) {
      final before? => _spaces(node.subSpecialchars(before)),
      null => '',
    };
    switch (slot.content) {
      case PartContent(part: TitlePart.title) when !node.notitle:
        if (title != null) {
          result.add(
            '<h1 class="$classes">$before'
            '${subtitled ? title.main : node.header!.title ?? ''}</h1>',
          );
        }
      case PartContent(part: TitlePart.subtitle):
        if (title?.subtitle case final subtitle?) {
          result.add('<div class="subtitle $classes">$before$subtitle</div>');
        }
      case PartContent(part: TitlePart.authors):
        String author(int i, DocumentAuthor author) {
          final n = i > 0 ? '${i + 1}' : '';
          final name =
              '<span id="author$n" class="author">'
              '${node.subReplacements(author.name!)}</span>';
          return switch (author.email) {
            final email? =>
              '$name <span id="email$n" class="email">'
                  '${node.subMacros(email)}</span>',
            null => name,
          };
        }

        final authors = [
          for (final (i, a) in node.authors.indexed) author(i, a),
        ];
        if (authors.isNotEmpty) {
          final separator = switch (slot.separator) {
            final separator? => _spaces(node.subSpecialchars(separator)),
            null => br,
          };
          result.add(
            '<div class="details $classes">$before'
            '${authors.join(separator)}</div>',
          );
        }
      case PartContent(part: TitlePart.revision):
        final label = downcase(node.attr('version-label') ?? '');
        final comma = node.hasAttr('revdate') ? ',' : '';
        final revision = [
          if (node.attr('revnumber') case final number?)
            '<span id="revnumber">$label $number$comma</span>',
          if (node.attr('revdate') case final date?)
            '<span id="revdate">$date</span>',
        ];
        var text = revision.join(' ');
        if (node.attr('revremark') case final remark?) {
          final line = text.isEmpty ? '' : br;
          text = '$text$line<span id="revremark">$remark</span>';
        }
        if (text.isNotEmpty) {
          result.add('<div class="details $classes">$before$text</div>');
        }
      case PartContent(part: TitlePart.logo):
        final logo = node.attr('title-logo-image');
        final target = switch (logo) {
          null => null,
          final value => switch (RegExp(r'^image::?(.+?)\[')
              .firstMatch(value)) {
            final match? => match[1],
            null => value,
          },
        };
        if (target != null) {
          result.add(
            '<div class="$classes"><img src="${node.imageUri(target)}" '
            'alt="${node.attr('title-logo-image-alt', 'Logo') ?? 'Logo'}"'
            '$voidSlash></div>',
          );
        }
      case AttributeContent(:final name):
        if (node.attr(name) case final value? when value.isNotEmpty) {
          result.add('<div class="$classes">$before$value</div>');
        }
      case _:
    }
  }
  return result;
}

/// [text]'s spaces kept: Asciidoctor's stylesheet sets the header's
/// details as a flex row, which drops the spaces at the ends of the text
/// between its spans.
String _spaces(String text) => text.replaceAll(' ', '&#160;');
