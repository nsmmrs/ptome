// The least-recently-used cache that bounds the process-wide caches.
import 'package:ptome/src/lru.dart';
import 'package:test/test.dart';

void main() {
  test('at most its capacity, the least recently used left out', () {
    final cache = LruCache<String, int>(2)
      ..['a'] = 1
      ..['b'] = 2;
    // (Reading a counts as a use: b is the least recently used.)
    expect(cache['a'], 1);
    cache['c'] = 3;
    expect(cache.length, 2);
    expect(cache.containsKey('b'), isFalse);
    expect(cache['a'], 1);
    expect(cache['c'], 3);
  });

  test('putIfAbsent makes a value once', () {
    final cache = LruCache<String, int>(4);
    var made = 0;
    expect(cache.putIfAbsent('x', () => ++made), 1);
    expect(cache.putIfAbsent('x', () => ++made), 1);
    expect(made, 1);
  });

  test('a null value is kept as one', () {
    final cache = LruCache<String, int?>(4)..['gone'] = null;
    expect(cache.containsKey('gone'), isTrue);
    expect(cache['gone'], isNull);
  });
}
