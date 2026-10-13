# plain_mustache

[Mustache](https://mustache.github.io/) templates in pure Dart, with typed
values: the context is a sealed `MustacheValue` (text, booleans, lists,
maps, lambdas) rather than untyped maps, so a template's data is checked
by the compiler like any other.

It passes every case of the
[Mustache specification](https://github.com/mustache/spec), the optional
modules included: inheritance (parents and blocks), dynamic names
(`{{>*name}}`) and lambdas.

```dart
import 'package:plain_mustache/plain_mustache.dart';

final template = MustacheTemplate(
  '{{#people}}- {{name}}\n{{/people}}{{^people}}No one.\n{{/people}}',
);
template.render(MustacheMap({
  'people': MustacheList([
    MustacheMap({'name': MustacheText('Ada')}),
    MustacheMap({'name': MustacheText('Grace & co')}),
  ]),
}));
// '- Ada\n- Grace &amp; co\n'
```

- A template is read once (`MustacheTemplate(source)`, which throws a
  `MustacheException` with the line and column of a tag left open or a
  section closed by another name) and rendered as often as needed.
- `partials` gives a partial's (or parent's) source by name; each is read
  once. A missing one renders as nothing.
- `escape` escapes what `{{name}}` writes: HTML by default (`&`, `<`, `>`,
  `"`, `'`), or any function, such as `(text) => text`.
- A `MustacheLambda` gets a `MustacheLambdaContext`: a section's
  unrendered `source`, `render()` for its content, `renderSource(text)` to
  render text as a template with the section's delimiters, and `lookup`.
  Its result is written as it is; return `context.renderSource(result)`
  to have it rendered, as the specification's lambdas are.

Where the specification is silent: any text is true in a section, the
empty one too; a name made of digits looks up a list's item by index
(`{{items.0.title}}`); a list or a map writes as Dart writes it
(`[a, b]`, `{k: v}`).

The library lives in the [ptome](https://github.com/nsmmrs/ptome)
workspace, where it renders custom converter templates and the text
templates documents and themes set.

Status: in development; not published to pub.dev.

## License

MIT; see [LICENSE](LICENSE). The specification's test files in
`test/spec/` are under the MIT license of the Mustache contributors
(`test/spec/LICENSE`).
