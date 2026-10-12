/// A cache of at most a number of entries, the least recently used left
/// out first: for caches that live as long as the process (a server's, a
/// watch mode's), which would otherwise grow with every document.
library;

import 'dart:collection';

/// Values by key, at most [capacity] of them.
final class LruCache<K, V> {
  /// A cache of at most [capacity] entries.
  new(this.capacity) : assert(capacity > 0, 'a cache keeps something');

  /// The most entries kept.
  final int capacity;

  final LinkedHashMap<K, V> _entries = LinkedHashMap();

  /// How many entries are kept.
  int get length => _entries.length;

  /// Whether [key] has an entry (counts as a use).
  bool containsKey(K key) => _touch(key);

  /// The value of [key], if kept (counts as a use).
  V? operator [](K key) => _touch(key) ? _entries[key] : null;

  /// Keeps [value] for [key], leaving out the least recently used entry
  /// when there are too many.
  void operator []=(K key, V value) {
    _entries
      ..remove(key)
      ..[key] = value;
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
  }

  /// The value of [key], made by [make] when not kept.
  V putIfAbsent(K key, V Function() make) {
    if (_touch(key)) return _entries[key] as V;
    final value = make();
    this[key] = value;
    return value;
  }

  /// Moves [key]'s entry to the most recently used end; whether it has one.
  bool _touch(K key) {
    if (!_entries.containsKey(key)) return false;
    final value = _entries.remove(key) as V;
    _entries[key] = value;
    return true;
  }
}
