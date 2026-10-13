/// plain_mustache: Mustache templates in pure Dart, with typed values.
///
/// - `MustacheTemplate` reads a template once and renders it against a
///   context, as the Mustache specification says: variables, sections,
///   inverted sections, comments, partials, delimiter changes, and the
///   optional inheritance (parents and blocks), dynamic names and lambdas.
/// - The context is a `MustacheValue`: text, booleans, lists, maps and
///   lambdas, a sealed type rather than untyped maps.
library;

export 'src/exception.dart' show MustacheException;
export 'src/renderer.dart' show MustacheLambdaContext;
export 'src/template.dart' show MustacheTemplate, escapeHtml;
export 'src/value.dart'
    show
        MustacheBoolean,
        MustacheLambda,
        MustacheList,
        MustacheMap,
        MustacheText,
        MustacheValue;
