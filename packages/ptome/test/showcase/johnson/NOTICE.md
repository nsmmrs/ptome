---
title: "Johnson's Dictionary"
source: johnson.adoc
looks: [johnson]
compare:
  - page: 2
    scan: https://archive.org/download/b30451541_0002/page/n45.jpg
    note: "LEWDLY to LIBERAL in two columns, headed LIB LIB; the catchword “2. One” (1755)"
  - page: 3
    scan: https://archive.org/download/b30451541_0002/page/n46.jpg
    note: "LIBERTINE going on, “2. One who pays no regard…” (1755)"
---

# Johnson's Dictionary

The entries from LEWD to LIBERTINE of Samuel Johnson's A Dictionary of
the English Language, in a look after its first edition (1755). What the
work shows: a dictionary's page — two columns; each entry hung, its
headword in capitals and small capitals with its stress marked, its part
of speech in italic and its etymology in brackets (Greek and Saxon among
it); its senses numbered at the edge; its quotations set in, the word in
italic, each author in italic flush right at the end of the quotation's
last line or, when there is no room, on a line of its own (FEAT-tc5vgk);
the paragraphs hung and set in by the theme (FEAT-43wrgt); each column
headed by the first three letters of its last word, spaced, as the folio
heads its columns (`{column-1-last-mark}`, FEAT-0ks2ly); the next page's
first word, the catchword, at the foot of each page (`{page-catchword}`,
FEAT-mm205k); small capitals made from the lowercase letters alone where
the face has none (BUG-mpp8wr) (FEAT-bpcdr5).

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| `text/l.adoc` | transcribed for the work from the facsimile of the first edition, volume II, https://archive.org/details/b30451541_0002 (scans n44–n46) | |

The transcription keeps the edition's words, spelling, capitals,
punctuation and its misprints (LI´ABLE and LI´BELLOUS as nouns, a second
sense 2 of LIBERTINE, the stress of LIBERA´LLY); it writes the round s
for the edition's long s. LEWD begins at the foot of the page before
(n44) and LIBERTINE ends on the page after (n46); the page's entries run
from LE´WDLY to LIBERTINE. The Saxon of LEWD is written in Unicode, its
wynn as ƿ, the yogh of LEY as ȝ.

## The scans transcribed

The pages of https://archive.org/details/b30451541_0002 the transcription was
made from, each the Internet Archive's JPEG
(`https://archive.org/download/b30451541_0002/page/<page>.jpg`) with its
SHA-256:

```
eef884c7a9d96bb2a164b23de4d340322d2f03f31d5b994592de5e8e4dcbe3ff  n44.jpg
a9e3a3015802b5160e72a9f01440a82a923a5f5011e8bed649a6a99bcff3356a  n45.jpg
c2a9ed97f263cd79d02df7cce30b3d3d3c95d0d94d756004182d92690cd47047  n46.jpg
```

## Licence

The Dictionary is in the public domain (published 1755; Samuel Johnson
died in 1784); the Wellcome Collection's scans carry the Public Domain
Mark. The transcription is the work's own (MIT, as the repository). The
scans are not committed: `tool/showcase.dart` fetches the pages it
compares into its cache.

## Fonts

Libre Caslon Text, roman and italic, and Noto Serif for the Greek and
the Saxon letters (both SIL Open Font License 1.1), from Google Fonts:
`ptome doctor --look johnson --looksdir test/showcase/johnson` installs
them. Not committed.

## The printing the look follows

The first edition, London, W. Strahan for J. and P. Knapton and others,
1755, volume II: the Wellcome Collection's copy, scanned by the Internet
Archive, https://archive.org/details/b30451541_0002.

Where the look departs from it:

- Libre Caslon Text stands in for the edition's Caslon; the page is
  smaller than the folio's (8 × 12.4 in, where the folio is about
  17 in tall), its type smaller with it.
- The pages break where the text falls on them, not where the edition's
  do; the guide letters and catchwords follow the pages as they fall.
- The signatures and the page numbers at the foot are left out, and the
  title page is the work's own.
- In HTML and EPUB, the text is in one column and the authors stand on
  lines of their own, flush right: CSS has no flush right at the end of a
  line, and floats run across columns.
