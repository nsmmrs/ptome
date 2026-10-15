/// An OpenStax textbook chapter (CNXML, CC BY 4.0) as AsciiDoc, for the
/// showcase corpus (test/showcase/openstax): the chapter's modules its
/// sections, their learning objectives, notes, worked examples and
/// checks of understanding as blocks, their equations AsciiMath (from
/// MathML, so that the EPUB has MathML too), their figures drawn for the
/// book (a third party's photographs, under other licences, left out
/// but public-domain ones); the modules' summaries, conceptual questions
/// and problems collected at the chapter's end as the printed book sets
/// them, the problems numbered through the chapter, their answers in an
/// answer key at the back; the glossary of the chapter's terms.
///
///     dart run tool/showcase_openstax.dart --checkout DIR --commit SHA
///
/// DIR is github.com/openstax/osbooks-college-physics-bundle at SHA (the
/// `codeload.github.com` tarball, unpacked), the commit before the book
/// was relicensed (College Physics 2e is CC BY 4.0 there; later commits
/// say CC BY-NC-SA). The chapter is Chapter 2, Kinematics.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
// (The workspace's XML reader, plain_svg's.)
import 'package:plain_svg/src/xml.dart';

import 'showcase_text.dart';

const String _repository =
    'https://raw.githubusercontent.com/openstax/osbooks-college-physics-bundle';

/// The chapter's modules: its introduction, then its sections.
const List<String> _modules = [
  'm42122', 'm42033', 'm42124', 'm42096', 'm42100', //
  'm42099', 'm42125', 'm42102', 'm42103',
];

const String _dir = 'test/showcase/openstax';

void main(List<String> arguments) {
  String? checkout;
  String? commit;
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--checkout':
        checkout = arguments[++i];
      case '--commit':
        commit = arguments[++i];
    }
  }
  if (checkout == null || commit == null) {
    stderr.writeln(
      'usage: dart run tool/showcase_openstax.dart --checkout DIR '
      '--commit SHA',
    );
    exit(64);
  }
  _Chapter(checkout, commit).write();
}

/// The text of [node] and its descendants.
String _text(XmlElement node) => node.innerText;

/// The chapter being read.
final class _Chapter {
  new(this.checkout, this.commit);

  final String checkout;
  final String commit;

  /// The figures' images the work fetches: name, the file in the
  /// repository.
  final Map<String, String> images = {};

  /// The ids the text links to that the work keeps.
  final Set<String> ids = {};

  /// The modules' section numbers (`2.1`), by their ids.
  final Map<String, String> numbers = {};

  /// The examples' numbers (`2.3`), by their ids.
  final Map<String, String> examples = {};

  /// The figures left out, by their ids.
  final Set<String> omitted = {};

  /// Whether a caption is being converted: its links are text.
  bool _inCaption = false;

  /// Whether [figure] is kept: the book's own drawing, or a photograph in
  /// the public domain; a third party's photograph (its caption's credit
  /// names a person, Flickr, Wikimedia Commons) is left out.
  static bool _kept(XmlElement figure) {
    final caption = figure.childElements
        .where((e) => e.localName == 'caption')
        .firstOrNull;
    final credit = RegExp(r'\(credit:([^)]*)\)')
        .firstMatch(caption == null ? '' : _text(caption))?[1];
    return credit == null ||
        RegExp(
          r'PD Photo|U\.S\. Army|NASA|public domain',
          caseSensitive: false,
        ).hasMatch(credit);
  }

  /// The glossary's terms and their meanings.
  final List<(String, String)> glossary = [];

  /// Each module's summary, conceptual questions and problems, by its
  /// number and title.
  final List<(String, String, String, String, String)> ends = [];

  /// The answers to the problems: the problem's anchor, its number, the
  /// answer.
  final List<(String, int, String)> answers = [];

  int _problem = 0;

  void write() {
    final docs = [
      for (final id in _modules)
        parseXml(File('$checkout/modules/$id/index.cnxml').readAsStringSync()),
    ];
    // (The ids the text has, so that links to them are kept.)
    for (final doc in docs) {
      for (final e in doc.descendantElements) {
        if (e.getAttribute('id') case final id?) ids.add(id);
      }
    }
    for (final (i, id) in _modules.indexed) {
      if (i > 0) numbers[id] = '2.$i';
    }
    // (The examples' numbers, for the captions that name them, and the
    // figures left out, which the text can't link to.)
    var example = 0;
    for (final doc in docs) {
      for (final e in doc.descendantElements) {
        if (e.localName == 'example') {
          example++;
          if (e.getAttribute('id') case final id?) examples[id] = '2.$example';
        }
        if (e.localName == 'figure' && !_kept(e)) {
          if (e.getAttribute('id') case final id?) {
            ids.remove(id);
            omitted.add(id);
          }
        }
      }
    }
    final text = Directory('$_dir/text')..createSync(recursive: true);
    for (final old in text.listSync().whereType<File>()) {
      old.deleteSync();
    }
    final files = <String>[];
    for (final (i, doc) in docs.indexed) {
      final out = StringBuffer();
      _module(_modules[i], doc, out, introduction: i == 0);
      final name = i == 0 ? 'introduction' : 'section-2-$i';
      File('$_dir/text/$name.adoc').writeAsStringSync(_tidy(out));
      files.add(name);
    }
    File('$_dir/text/end.adoc').writeAsStringSync(_tidy(_end()));
    File('$_dir/text/answers.adoc').writeAsStringSync(_tidy(_answerKey()));
    _fetch();
    stdout.writeln(
      '${files.length} modules; ${glossary.length} terms; $_problem problems, '
      '${answers.length} answers; ${images.length} figures',
    );
  }

  String _tidy(StringBuffer out) =>
      '${'$out'.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n')}\n';

  void _module(
    String id,
    XmlElement doc,
    StringBuffer out, {
    required bool introduction,
  }) {
    final title = _text(
      doc.childElements.firstWhere((e) => e.localName == 'title'),
    );
    // (The sections numbered as the book numbers them, the introduction
    // not.)
    out
      ..writeln('[#$id]')
      ..writeln(introduction ? '=== $title' : '=== ${numbers[id]} $title')
      ..writeln();
    final content = doc.childElements.firstWhere(
      (e) => e.localName == 'content',
    );
    final summary = StringBuffer();
    final questions = StringBuffer();
    final problems = StringBuffer();
    for (final node in content.childElements) {
      final type =
          node.getAttribute('class') ?? node.getAttribute('type') ?? '';
      if (node.localName == 'section') {
        switch (type) {
          case 'section-summary':
            _blocks(node, summary, level: 5, skipTitle: true);
            continue;
          case 'conceptual-questions':
            _exercises(node, questions, answered: false);
            continue;
          case 'problems-exercises':
            _exercises(node, problems, answered: true);
            continue;
          case 'ap-test-prep':
            // (The AP® edition's test preparation: not in the book.)
            continue;
        }
      }
      _block(node, out, level: 4);
    }
    if (!introduction) {
      ends.add((numbers[id]!, title, '$summary', '$questions', '$problems'));
    }
    for (final glossary in doc.childElements.where(
      (e) => e.localName == 'glossary',
    )) {
      for (final definition in glossary.childElements) {
        final term = definition.childElements
            .where((e) => e.localName == 'term')
            .firstOrNull;
        final meaning = definition.childElements
            .where((e) => e.localName == 'meaning')
            .firstOrNull;
        if (term != null && meaning != null) {
          this.glossary.add((_inline(term).trim(), _inline(meaning).trim()));
        }
      }
    }
  }

  /// The blocks of [parent] (a section's, a note's).
  void _blocks(
    XmlElement parent,
    StringBuffer out, {
    required int level,
    bool skipTitle = false,
  }) {
    for (final node in parent.childElements) {
      if (node.localName == 'title' || node.localName == 'label') {
        if (skipTitle || node.localName == 'label') continue;
      }
      _block(node, out, level: level);
    }
  }

  void _block(XmlElement node, StringBuffer out, {required int level}) {
    final id = node.getAttribute('id');
    final type = node.getAttribute('class') ?? node.getAttribute('type') ?? '';
    switch (node.localName) {
      case 'title':
        out
          ..writeln()
          ..writeln('${'=' * level} ${_inline(node).trim()}')
          ..writeln();
      case 'para':
        final title = node.childElements
            .where((e) => e.localName == 'title')
            .firstOrNull;
        // (A paragraph that is only a title: a step of a worked example,
        // "Strategy", "Solution", "Discussion".)
        if (title != null && _text(node).trim() == _text(title).trim()) {
          out
            ..writeln()
            ..writeln('[.step]')
            ..writeln(_inline(title).trim())
            ..writeln();
          return;
        }
        // (Blocks inside the paragraph, a figure, an equation or a list,
        // set between its text's parts.)
        if (node.childElements.any(
          (e) => const {
            'figure',
            'equation',
            'list',
            'table',
          }.contains(e.localName),
        )) {
          final text = StringBuffer();
          void flush() {
            final part = '$text'.trim();
            text.clear();
            if (part.isEmpty) return;
            out
              ..writeln()
              ..writeln(lineStart(part))
              ..writeln();
          }

          for (final child in node.children) {
            switch (child) {
              case XmlText(text: final t):
                text.write(escapeText(t.replaceAll(RegExp(r'\s+'), ' ')));
              case final XmlElement e
                  when const {
                    'figure',
                    'equation',
                    'list',
                    'table',
                  }.contains(e.localName):
                flush();
                _block(e, out, level: level);
              case final XmlElement e:
                text.write(_inlineNode(e));
            }
          }
          flush();
          return;
        }
        out
          ..writeln()
          ..writeln(lineStart(_inline(node).trim()))
          ..writeln();
      case 'section' when type == 'learning-objectives':
        out
          ..writeln()
          ..writeln('[.learning-objectives]')
          ..writeln('.Learning Objectives')
          ..writeln('****');
        _blocks(node, out, level: level + 1, skipTitle: true);
        out
          ..writeln('****')
          ..writeln();
      case 'section':
        out.writeln();
        if (id != null) out.writeln('[#$id]');
        final title = node.childElements
            .where((e) => e.localName == 'title')
            .firstOrNull;
        if (title != null) {
          out
            ..writeln('${'=' * level} ${_inline(title).trim()}')
            ..writeln();
        }
        _blocks(node, out, level: level + 1, skipTitle: true);
      case 'list':
        _list(node, out);
      case 'figure':
        _figure(node, out);
      case 'equation':
        out
          ..writeln()
          ..writeln(id == null ? '[stem]' : '[stem#$id]')
          ..writeln('++++')
          ..writeln(_math(node))
          ..writeln('++++')
          ..writeln();
      case 'table':
        _table(node, out);
      case 'note' when type == 'interactive':
        // (A simulation to run, in the online book: not here.)
        break;
      case 'note':
        final title = node.childElements
            .where((e) => e.localName == 'title')
            .firstOrNull;
        out
          ..writeln()
          ..writeln(id == null ? '[.note]' : '[#$id.note]');
        if (title != null) out.writeln('.${_inline(title).trim()}');
        out.writeln('****');
        _blocks(node, out, level: level + 1, skipTitle: true);
        out
          ..writeln('****')
          ..writeln();
      case 'example':
        final title = node.childElements
            .where((e) => e.localName == 'title')
            .firstOrNull;
        out.writeln();
        if (id != null) out.writeln('[#$id]');
        if (title != null) out.writeln('.${_inline(title).trim()}');
        out.writeln('====');
        _blocks(node, out, level: level + 1, skipTitle: true);
        out
          ..writeln('====')
          ..writeln();
      case 'exercise' when type == 'check-understanding':
        out
          ..writeln()
          ..writeln(id == null ? '[.check]' : '[#$id.check]')
          ..writeln('.Check Your Understanding')
          ..writeln('****');
        for (final part in node.childElements) {
          if (part.localName == 'problem') {
            _blocks(part, out, level: level + 1);
          } else if (part.localName == 'solution') {
            out
              ..writeln()
              ..writeln('[.step]')
              ..writeln('Solution')
              ..writeln();
            _blocks(part, out, level: level + 1);
          }
        }
        out
          ..writeln('****')
          ..writeln();
      case 'iframe' || 'media':
        break;
      default:
        _blocks(node, out, level: level);
    }
  }

  /// A section's exercises: each a numbered item (the problems numbered
  /// through the chapter), its anchor; a problem's solution an answer in
  /// the answer key.
  void _exercises(
    XmlElement section,
    StringBuffer out, {
    required bool answered,
  }) {
    // (The figures the problems refer to, set before them.)
    for (final figure in section.childElements.where(
      (e) => e.localName == 'figure',
    )) {
      _figure(figure, out);
    }
    final items = <String>[];
    for (final exercise in section.childElements.where(
      (e) => e.localName == 'exercise',
    )) {
      final problem = exercise.childElements
          .where((e) => e.localName == 'problem')
          .firstOrNull;
      if (problem == null) continue;
      final body = StringBuffer();
      _blocks(problem, body, level: 6);
      final anchor = exercise.getAttribute('id')!;
      final solution = exercise.childElements
          .where((e) => e.localName == 'solution')
          .firstOrNull;
      var text = _listItem('$body');
      if (answered) {
        _problem++;
        if (solution != null) {
          final answer = StringBuffer();
          _blocks(solution, answer, level: 6);
          // (A solution that is only a photograph left out: none.)
          final text = _listItem('$answer').trim();
          if (text.isNotEmpty) answers.add((anchor, _problem, text));
        }
      }
      text = '[[$anchor]]$text';
      items.add(text);
    }
    if (items.isEmpty) return;
    out.writeln();
    if (answered) out.writeln('[start=${_problem - items.length + 1}]');
    for (final item in items) {
      out.writeln('. $item');
    }
    out.writeln();
  }

  /// Blocks as one list item's content: the first paragraph its text, the
  /// others attached by list continuations.
  String _listItem(String blocks) {
    final parts = blocks.trim().split(RegExp(r'\n{2,}'));
    if (parts.isEmpty) return '';
    // (A block that isn't a paragraph first: after an empty text.)
    final first = parts.first;
    final startsBlock = RegExp(r'^(\[|\.\S|\*|=|\+\+\+\+|\. )').hasMatch(first);
    return [
      if (startsBlock) '{empty}',
      for (final (i, part) in parts.indexed)
        if (i == 0 && !startsBlock) part else '+\n$part',
    ].join('\n');
  }

  void _list(XmlElement list, StringBuffer out) {
    final ordered = list.getAttribute('list-type') == 'enumerated';
    final style = switch (list.getAttribute('number-style')) {
      'lower-alpha' => 'loweralpha',
      'upper-alpha' => 'upperalpha',
      'lower-roman' => 'lowerroman',
      _ => null,
    };
    out.writeln();
    if (style != null) out.writeln('[$style]');
    for (final item in list.childElements.where((e) => e.localName == 'item')) {
      out.writeln('${ordered ? '.' : '*'} ${_inline(item).trim()}');
    }
    out.writeln();
  }

  /// A figure: its image the book's own drawing, or a photograph in the
  /// public domain; a third party's photograph (its caption's credit
  /// names a person, Flickr, Wikimedia Commons) is left out, its caption
  /// with it.
  void _figure(XmlElement figure, StringBuffer out) {
    final caption = figure.childElements
        .where((e) => e.localName == 'caption')
        .firstOrNull;
    if (!_kept(figure)) return;
    final id = figure.getAttribute('id');
    out.writeln();
    if (id != null) out.writeln('[#$id]');
    if (caption != null) {
      _inCaption = true;
      out.writeln('.${_inline(caption).trim()}');
      _inCaption = false;
    }
    for (final media in figure.descendantElements.where(
      (e) => e.localName == 'media',
    )) {
      final image = media.childElements
          .where((e) => e.localName == 'image')
          .firstOrNull;
      if (image == null) continue;
      final src = image.getAttribute('src')!.split('/').last;
      final name = src.replaceAll(' ', '_');
      images[name] = src;
      final alt = attributeValue(media.getAttribute('alt') ?? '');
      out.writeln('image::$name[$alt,align=center]');
    }
    out.writeln();
  }

  void _table(XmlElement table, StringBuffer out) {
    final rows = [
      for (final row in table.descendantElements.where(
        (e) => e.localName == 'row',
      ))
        [
          for (final entry in row.childElements.where(
            (e) => e.localName == 'entry',
          ))
            _inline(entry).trim().replaceAll('|', r'\|'),
        ],
    ];
    if (rows.isEmpty) return;
    final columns = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final header = table.descendantElements.any((e) => e.localName == 'thead');
    final id = table.getAttribute('id');
    final title = table.childElements
        .where((e) => e.localName == 'title')
        .firstOrNull;
    out.writeln();
    if (title != null) out.writeln('.${_inline(title).trim()}');
    out
      ..writeln(
        '[${id == null ? '' : '#$id'}'
        '${header ? '%header' : '%noheader'},cols="$columns*"]',
      )
      ..writeln('|===');
    for (final row in rows) {
      out.writeln(
        [for (var i = 0; i < columns; i++) '|${i < row.length ? row[i] : ''}']
            .join(' '),
      );
    }
    out
      ..writeln('|===')
      ..writeln();
  }

  /// [element]'s content as inline AsciiDoc.
  String _inline(XmlElement element) {
    final out = StringBuffer();
    for (final node in element.children) {
      switch (node) {
        case XmlText(:final text):
          out.write(escapeText(text.replaceAll(RegExp(r'\s+'), ' ')));
        case final XmlElement e:
          out.write(_inlineNode(e));
      }
    }
    return '$out';
  }

  String _inlineNode(XmlElement e) {
    switch (e.localName) {
      case 'emphasis':
        final text = _inline(e);
        return switch (e.getAttribute('effect')) {
          'bold' => markPair('*', text),
          'underline' => '[.underline]#$text#',
          _ => markPair('_', text),
        };
      case 'term':
        return markPair('*', _inline(e));
      case 'sub':
        return '~${_inline(e).trim()}~';
      case 'sup':
        return '^${_inline(e).trim()}^';
      case 'math':
        final math = _stemText(_asciiMath(e));
        return math.trim().isEmpty ? '' : 'stem:[$math]';
      case 'link':
        final target = e.getAttribute('target-id');
        final url = e.getAttribute('url');
        final document = e.getAttribute('document');
        final text = _inline(e).trim();
        if (url != null) return text.isEmpty ? url : '$url[$text]';
        if (document != null && numbers.containsKey(document)) {
          return text.isEmpty ? '<<$document>>' : '<<$document,$text>>';
        }
        // (In a caption, a reference is its text: a caption's xref is
        // resolved before its target is known, when the caption is
        // numbered.)
        if (_inCaption && text.isEmpty && examples[target] != null) {
          return 'Example ${examples[target]}';
        }
        if (!_inCaption && target != null && ids.contains(target)) {
          return text.isEmpty ? '<<$target>>' : '<<$target,$text>>';
        }
        if (text.isEmpty && omitted.contains(target)) {
          return 'a photograph in the printed book';
        }
        return text;
      case 'label' || 'title':
        return '';
      case 'newline':
        return ' +\n';
      default:
        return _inline(e);
    }
  }

  /// An equation's math, AsciiMath.
  String _math(XmlElement equation) => [
    for (final math in equation.descendantElements.where(
      (e) => e.localName == 'math',
    ))
      _asciiMath(math),
  ].join(' ').trim();

  /// [math] safe in a `stem:[]` macro: its closing brackets escaped, and
  /// a space after each plus sign, which AsciiDoc would otherwise pair
  /// with another as a passthrough (`+g ... [+`).
  static String _stemText(String math) =>
      math.replaceAll(']', r'\]').replaceAll(RegExp(r'\+(?=\S)'), '+ ');

  void _fetch() {
    final entries = [
      for (final MapEntry(key: name, value: src)
          in images.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        (
          name,
          '$_repository/$commit/media/${Uri.encodeComponent(src)}',
          '${sha256.convert(File('$checkout/media/$src').readAsBytesSync())}',
        ),
    ];
    File('$_dir/fetch.yml').writeAsStringSync(
      [
        '# The figures the work uses, fetched by tool/showcase.dart into the',
        "# work cache and checked by their SHA-256: the book's own drawings",
        '# (and its public-domain photographs) in its repository, at the',
        '# commit before the book was relicensed (CC BY 4.0).',
        for (final (name, url, sha) in entries) ...[
          '- name: $name',
          '  url: $url',
          '  sha256: $sha',
        ],
        '',
      ].join('\n'),
    );
  }

  /// The chapter's end, as the book sets it: its glossary, the sections'
  /// summaries, the conceptual questions, the problems and exercises.
  StringBuffer _end() {
    final out = StringBuffer()
      ..writeln('[#glossary%unnumbered]')
      ..writeln('=== Glossary')
      ..writeln()
      ..writeln('[.glossary]');
    final sorted = [...glossary]
      ..sort((a, b) => a.$1.toLowerCase().compareTo(b.$1.toLowerCase()));
    for (final (term, meaning) in sorted) {
      out.writeln('${term.replaceAll('::', r'\::')}:: $meaning');
    }
    for (final (title, part) in const [
      ('Section Summary', 3),
      ('Conceptual Questions', 4),
      ('Problems & Exercises', 5),
    ]) {
      out
        ..writeln()
        ..writeln('[%unnumbered]')
        ..writeln('=== ${escapeText(title)}')
        ..writeln();
      for (final end in ends) {
        final (number, sectionTitle, summary, questions, problems) = end;
        final text = switch (part) {
          3 => summary,
          4 => questions,
          _ => problems,
        };
        if (text.trim().isEmpty) continue;
        out
          ..writeln()
          ..writeln('[discrete]')
          ..writeln('==== $number $sectionTitle')
          ..writeln()
          ..writeln(text);
      }
    }
    return out;
  }

  /// The answer key: each problem's answer under its number, linked to
  /// it.
  StringBuffer _answerKey() {
    final out = StringBuffer()
      ..writeln('[appendix#answer-key]')
      ..writeln('== Answer Key')
      ..writeln()
      ..writeln('[discrete]')
      ..writeln('=== Chapter 2')
      ..writeln();
    for (final (anchor, number, answer) in answers) {
      out
        ..writeln('[start=$number]')
        ..writeln('. <<$anchor,Problem $number>>: $answer')
        ..writeln();
    }
    return out;
  }
}

// MathML as AsciiMath.

/// The Greek letters and the symbols AsciiMath names.
const Map<String, String> _names = {
  'α': 'alpha', 'β': 'beta', 'γ': 'gamma', 'δ': 'delta', 'ε': 'epsilon', //
  'θ': 'theta', 'λ': 'lambda', 'μ': 'mu', 'π': 'pi', 'ρ': 'rho',
  'σ': 'sigma', 'τ': 'tau', 'φ': 'phi', 'ω': 'omega', 'Δ': 'Delta',
  'Σ': 'Sigma', 'Ω': 'Omega', 'Φ': 'Phi', 'Θ': 'Theta', 'Γ': 'Gamma',
  '−': '-', '×': 'xx', '·': '*', '⋅': '*', '÷': '-:', '±': '+-',
  '≈': '~~', '≤': '<=', '≥': '>=', '≠': '!=', '→': 'rarr', '∞': 'oo',
  '∝': 'prop', '∑': 'sum', '√': 'sqrt', '°': '^@', 'º': '^@', '′': "'",
  '∼': '~', '–': '-',
  ' ': ' ', ' ': ' ', ' ': ' ',
};

/// The words AsciiMath reads as functions or symbols, which a multi-letter
/// identifier may be.
const Set<String> _functions = {
  'sin', 'cos', 'tan', 'log', 'ln', 'exp', 'min', 'max', 'lim', //
};

String _asciiMath(XmlElement e) {
  String inner(XmlElement el) =>
      [for (final child in el.childElements) _asciiMath(child)]
          .where((s) => s.trim().isNotEmpty)
          .join(' ');
  String group(XmlElement el) {
    final text = _asciiMath(el).trim();
    return text.contains(' ') ? '{:$text:}' : text;
  }

  String arg(XmlElement el) => '(${_asciiMath(el).trim()})';
  String script(String mark, XmlElement el) {
    final text = _asciiMath(el).trim();
    return text.isEmpty ? '' : '$mark($text)';
  }

  final kids = e.childElements.toList();
  String token(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    if (_names[t] case final name?) return name;
    if (RegExp(r'^[0-9.,]+$').hasMatch(t)) return t;
    if (t.length == 1) return t;
    if (_functions.contains(t)) return t;
    // (A number with its unit or a word: as text, its Greek named.)
    final parts = <String>[];
    for (final m in RegExp('([0-9.,]+)|([^0-9.,]+)').allMatches(t)) {
      if (m[1] != null) {
        parts.add(m[1]!);
      } else {
        final word = m[2]!;
        parts.add(
          word.runes.length == 1 && _names.containsKey(word)
              ? _names[word]!
              : '"${word.replaceAll('"', "'")}"',
        );
      }
    }
    return parts.join(' ');
  }

  switch (e.localName) {
    case 'math' || 'mrow' || 'mstyle' || 'mpadded' || 'semantics' || 'mphantom':
      return inner(e);
    case 'annotation' || 'annotation-xml' || 'none' || 'mprescripts':
      return '';
    case 'mi' || 'mn':
      return token(e.innerText);
    case 'mo':
      final t = e.innerText.trim();
      if (t.isEmpty) return '';
      return _names[t] ??
          (t == '(' || t == ')' || t == '[' || t == ']' ? t : token(t));
    case 'mtext':
      final t = e.innerText;
      if (t.trim().isEmpty) return '" "';
      if (_names[t.trim()] case final name? when t.trim().length == 1) {
        return name;
      }
      // (The masculine ordinal written for a degree, the en dash for a
      // minus: the signs themselves.)
      final text = t
          .replaceAll('"', "'")
          .replaceAll('\u00a0', ' ')
          .replaceAll('º', '°')
          .replaceAll('–', '−');
      return '"$text"';
    case 'mspace':
      return '" "';
    // (A script that is empty left out: MathML wants one there.)
    case 'msub' when kids.length == 2:
      return '${group(kids[0])}${script('_', kids[1])}';
    case 'msup' when kids.length == 2:
      return '${group(kids[0])}${script('^', kids[1])}';
    case 'msubsup' when kids.length == 3:
      return '${group(kids[0])}${script('_', kids[1])}${script('^', kids[2])}';
    case 'mfrac' when kids.length == 2:
      return '${arg(kids[0])}/${arg(kids[1])}';
    case 'msqrt':
      return 'sqrt(${inner(e)})';
    case 'mroot' when kids.length == 2:
      return 'root${arg(kids[1])}${arg(kids[0])}';
    case 'mover' when kids.length == 2:
      final over = kids[1].innerText.trim();
      return switch (over) {
        '-' || '¯' || '‾' || '_' || '―' => 'bar${arg(kids[0])}',
        '→' || '⇀' => 'vec${arg(kids[0])}',
        '^' || 'ˆ' => 'hat${arg(kids[0])}',
        '˙' || '.' => 'dot${arg(kids[0])}',
        _ => 'overset${arg(kids[1])}${arg(kids[0])}',
      };
    case 'munder' when kids.length == 2:
      final under = kids[1].innerText.trim();
      return switch (under) {
        '¯' || '_' || '‾' || '-' => 'ul${arg(kids[0])}',
        _ => 'underset${arg(kids[1])}${arg(kids[0])}',
      };
    case 'munderover' when kids.length == 3:
      return 'underset${arg(kids[1])}(overset${arg(kids[2])}${arg(kids[0])})';
    case 'mfenced':
      final open = e.getAttribute('open') ?? '(';
      final close = e.getAttribute('close') ?? ')';
      final separator = e.getAttribute('separators') ?? ',';
      final body = [for (final child in kids) _asciiMath(child)]
          .join(separator.isEmpty ? ' ' : ' ${separator[0]} ');
      String fence(String f, {required bool left}) => switch (f) {
        '' => left ? '{:' : ':}',
        '|' => '|',
        '{' => '{',
        '}' => '}',
        _ => f,
      };
      return '${fence(open, left: true)}$body${fence(close, left: false)}';
    case 'mtable':
      final rows = [
        for (final tr in kids.where((k) => k.localName == 'mtr'))
          '(${tr.childElements.map((td) => _asciiMath(td).trim()).join(',')})',
      ];
      return '{:${rows.join(',')}:}';
    case 'mtd':
      return inner(e);
    case 'mmultiscripts':
      // (Scripts after the base, then, after `mprescripts`, before it, as
      // an isotope's; `none` for one missing.)
      if (kids.isEmpty) return '';
      final split = kids.indexWhere((k) => k.localName == 'mprescripts');
      final post = kids.sublist(1, split < 0 ? kids.length : split);
      final pre = split < 0 ? <XmlElement>[] : kids.sublist(split + 1);
      String scripts(List<XmlElement> pair) => [
        if (pair.isNotEmpty) script('_', pair[0]),
        if (pair.length > 1) script('^', pair[1]),
      ].join();
      final before = scripts(pre);
      return '${before.isEmpty ? '' : '""$before'}'
          '${group(kids.first)}${scripts(post)}';
    default:
      return inner(e);
  }
}
