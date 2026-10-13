// Compiled to JavaScript in CI: renders templates that use every kind of
// tag, printing a digest; the CI job compares it with the Dart VM's, as
// the results must be the same on both.
import 'dart:convert';

import 'package:plain_mustache/plain_mustache.dart';

const Map<String, String> _partials = {
  'page': r'''
<h1>{{$title}}Untitled{{/title}}</h1>
  {{$body}}
  nothing
  {{/body}}
''',
  'item': '- {{name}} ({{price}})\n',
};

const String _template = r'''
{{<page}}{{$title}}{{shop}} & co{{/title}}{{$body}}
{{#items}}
{{>item}}
{{/items}}
{{^items}}none{{/items}}
{{! a comment }}
{{=<% %>=}}
<%#lambda%>Straße ΣΟΦΟΣ 日本語 👩‍👩‍👧<%/lambda%>
<%={{ }}=%>
{{>*dynamic}}|{{list}}|{{map}}
{{/body}}{{/page}}
''';

void main() {
  final template = MustacheTemplate(_template, partials: (n) => _partials[n]);
  final rendered = template.render(
    MustacheMap({
      'shop': const MustacheText('<Shop>'),
      'items': MustacheList([
        for (var i = 0; i < 3; i++)
          MustacheMap({
            'name': MustacheText('item "$i"'),
            'price': MustacheText('${i * 15} p'),
          }),
      ]),
      'lambda': MustacheLambda(
        (context) => context.source.split('').reversed.join(),
      ),
      'dynamic': const MustacheText('item'),
      'name': const MustacheText("it's"),
      'list': const MustacheList([MustacheBoolean(true), null]),
      'map': const MustacheMap({'k': MustacheText('v')}),
    }),
  );
  // An Adler-32 style checksum: its sums stay small enough for
  // JavaScript's numbers.
  var a = 1;
  var b = 0;
  for (final byte in utf8.encode(rendered)) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  // The digest is the program's output.
  // ignore: avoid_print
  print('${rendered.length} $b-$a');
}
