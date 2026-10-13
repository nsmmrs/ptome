# Changelog

## 0.1.0-dev (unreleased)

- Mustache templates with typed values (`MustacheTemplate`,
  `MustacheValue`: `MustacheText`, `MustacheBoolean`, `MustacheList`,
  `MustacheMap`, `MustacheLambda`). Every case of the Mustache
  specification passes (github.com/mustache/spec at e8ec001), the
  optional inheritance, dynamic names and lambdas modules included.
- Partials by name, read once; escaping as given (HTML by default);
  errors with their line and column (`MustacheException`).
- The same output compiled to JavaScript as on the Dart VM.
