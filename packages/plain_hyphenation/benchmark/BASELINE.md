# Performance

The word cache answers most calls (ptome hyphenates each block once, and a
book's words repeat), so what is measured here is where it doesn't help: a
language's startup (its patterns' family decompressed and its trie
decoded) and its cache misses (every word of
`test/fixtures/words/<tag>.txt` once, on a hyphenator of its own).

```sh
dart compile exe benchmark/hyphenation.dart -o /tmp/hyph && /tmp/hyph
```

## 2026-10-14

Linux x64, Dart 3.13 AOT, nothing else running, the median of 41 runs
after 3 warmups, over the 19 languages with word lists (10,637 words):
startup 10.0 ms in all (German 4.5 ms, Norwegian 1.9 ms, the others under
1 ms), misses 5.2 ms in all (0.33–0.78 µs a word).

Two changes from TASK-pfmyzk were measured and not kept:

- A case table for words outside ASCII (each code unit's lower case as
  `String.toLowerCase` has it, built from it a page at a time; U+0130,
  U+03A3, surrogates and longer mappings left to `toLowerCase` on the
  whole word), in place of `toLowerCase` on the word: no faster, a little
  slower (misses in all 5.48 → 5.65 ms, Russian 0.46 → 0.52 ms, the means
  of four interleaved runs each): the VM's `toLowerCase` already costs
  little.
- The trie as a double array (a node's child by letter in one step):
  misses 5.31 → 4.69 ms (×1.13; German ×1.29), the same results for every
  word. But shipped (bases kept unique, so each slot holds its letter
  rather than its parent), the ten largest languages' patterns compress to
  300.1 KB against 196.6 KB, and decode in 7.31 ms against 6.32 ms
  (German 2.68 against 2.22 ms): German recovers its startup only after
  some 2,700 misses, and every document pays the bigger package.
