# ADR-0024: Compressed Bytes from plain_compression on Every Platform

**Status:** Accepted on 2026-10-12. Closes TASK-fs3rdd.

## Context

On the Dart VM, ptome compressed PDF streams (`/FlateDecode`) and the
entries of an EPUB with `dart:io`'s zlib. That zlib is Chromium's fork:
its output "will differ from canonical zlib output", and it can depend on
the CPU's features (SSE4.2, CRC32 instructions) and on the SDK's zlib
revision. On JavaScript, ptome compressed PDF streams with
plain_compression (pure Dart) and EPUB entries with Node.js's zlib.

So the same document made different bytes on the VM and on Node.js, and
could make different bytes on another CPU or after an SDK roll, with no
change to ptome. Nothing compares ptome's compressed bytes to a fixed
file: the corpus compares PDFs by their rendered pages and EPUBs by their
files (ADR-0022), keeping the hash of the last file found equal only to
skip that comparison. A shift costs a full comparison of every PDF and
EPUB case and rewrites every `ptome.yml`; it fails nothing. But a
document's bytes moving with the machine it is made on is wrong for a
tool that makes reproducible output (`:reproducible:`), for caches keyed
on the output, and for anyone diffing two builds.

The options (the card's): accept it and document it; compress with
plain_compression everywhere; or port zlib's own deflate, faithfully, as
an SDK-independent oracle (FEAT-wc1ftf, opt-in levels).

Measured on the Hypermedia Systems book (313 pages; its PDF's 34 MB of
uncompressed objects, level 6, on this machine): `dart:io` 199 ms,
plain_compression 348 ms, and plain_compression's output 0.2% smaller.

## Decision

1. **ptome compresses with plain_compression on every platform**: PDF
   streams (`zlibEncode`) and EPUB entries (`deflateRaw`), on the VM, on
   Node.js and in a browser. The same document makes the same bytes
   everywhere, whatever the CPU or the SDK.
2. **Decompression stays the platform's own** where it is faster
   (`dart:io` on the VM, for PNG data and imported PDFs): inflating is
   deterministic, any correct inflater gives the same bytes.
3. **The cost is accepted**: about 0.15 s on a 313-page book whose
   conversion takes seconds; making plain_compression faster is its own
   work, not a reason to take another encoder's bytes.
4. **A faithful zlib port stays opt-in work** (FEAT-wc1ftf): useful as an
   oracle and for byte-equality with other tools' output, not needed for
   ptome's own reproducibility.

## Consequences

- PDF and EPUB bytes change once (this change): the corpus compares every
  PDF and EPUB case again by its pages and files and records the new
  hashes in the cases' `ptome.yml`; none may fail.
- The VM and Node.js make the same PDF and EPUB bytes for the same
  document and fonts.
- The JavaScript host no longer needs Node.js's `zlib` module
  (`globalThis.ptomeHost` is `{fs, process}`).
