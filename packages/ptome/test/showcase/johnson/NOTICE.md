---
title: "Johnson's Dictionary"
source: johnson.adoc
looks: [johnson]
compare:
  - page: 1
    scan: https://archive.org/download/b30451541_0002/page/n44.jpg
    note: "LEVEL going on to LEWD, headed LEV LEW; the catchword “Before” (1755)"
  - page: 2
    scan: https://archive.org/download/b30451541_0002/page/n45.jpg
    note: "LEWD going on to LIBERTINE, headed LIB LIB; the folio 4, the catchword “2. One” (1755)"
  - page: 3
    scan: https://archive.org/download/b30451541_0002/page/n46.jpg
    note: "LIBERTINE going on to LICENTIOUSLY, headed LIB LIC; the folio 5, the signature 15 K, the catchword “The” (1755)"
---

# Johnson's Dictionary

Three pages of Samuel Johnson's A Dictionary of the English Language,
LEVEL to LICENTIOUSLY, as its first edition sets them (1755), page for
page and line for line: each line the printing's, transcribed from the
scan, its first and last words, its divided words and its hyphens the
printing's (`:source-lines:`); each column ending where the printing's
ends; each line set in as far as the printing sets it and each block
where the printing sets it (tool/johnson_1755). What the work shows: a
dictionary's page — two columns; each entry hung, its headword in
capitals and small capitals with its stress marked, its part of speech
in italic and its etymology in brackets (Greek, Saxon and Hebrew among
it); its senses numbered at the edge; its quotations set in, the word in
italic, each author in italic flush right at the end of the quotation's
last line or, when the printing sets it so, on a line of its own
(FEAT-tc5vgk); the paragraphs hung and set in by the theme
(FEAT-43wrgt); each column headed by the first three letters of its last
word, spaced, as the folio heads its columns (`{column-1-last-mark}`,
FEAT-0ks2ly); the folio, the signature and the catchword at the foot;
small capitals made from the lowercase letters alone where the face has
none (BUG-mpp8wr) (FEAT-bpcdr5).

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| `text/pages.adoc` | transcribed for the work from the facsimile of the first edition, volume II, https://archive.org/details/b30451541_0002 (leaves n44–n46), line by line; made from `tool/johnson_1755/johnson.spec` by `gen.py` | |

The transcription keeps the edition's words, spelling, capitals,
punctuation and its misprints (LI´ABLE, LI´BELLOUS, LIBI´DINOUS and
LICE´NTIOUS as nouns, a second sense 2 of LIBERTINE and of LIBERTY, the
stress of LIBERA´LLY); it writes the round s for the edition's long s.
The page before (n43) and the page after (n47) are left out: the first
page starts within LEVEL, with a quotation from Addison under its third
sense, and the last ends with LICENTIOUSLY's definition, its quotation
on the page after (the catchword “The”). The Saxon of LEWD and LEVEROOK is written in Unicode, its
wynn as ƿ, the yogh of LEY as ȝ; LEVIATHAN's Hebrew unpointed.

## The scans transcribed

The leaves of https://archive.org/details/b30451541_0002 the
transcription was made from and the work is set after: the Internet
Archive's JPEG 2000 files (`b30451541_0002_jp2.zip`) with their SHA-256,
and its JPEG of each page
(`https://archive.org/download/b30451541_0002/page/<page>.jpg`) that
`tool/showcase.dart` compares:

```
27a04d0e7fafebc2c1285ca6ffb277a659f052b1226a433ba3670fbf6e8634a1  b30451541_0002_0046.jp2 (n44)
e5f6affe9aacd5f7121883f3921b1eb46578bd5b7378bc5d6c1f6fae69cd15b5  b30451541_0002_0047.jp2 (n45)
ff5d703e47f3cc4f529fa794b91017408cf5d7c9942cc099f7b0da05250bac7f  b30451541_0002_0048.jp2 (n46)
eef884c7a9d96bb2a164b23de4d340322d2f03f31d5b994592de5e8e4dcbe3ff  n44.jpg
a9e3a3015802b5160e72a9f01440a82a923a5f5011e8bed649a6a99bcff3356a  n45.jpg
c2a9ed97f263cd79d02df7cce30b3d3d3c95d0d94d756004182d92690cd47047  n46.jpg
```

## Licence

The Dictionary is in the public domain (published 1755; Samuel Johnson
died in 1784); the Wellcome Collection's scans carry the Public Domain
Mark. The transcription is the work's own (MIT, as the repository). The
scans are not committed: `tool/showcase.dart` fetches the pages it
compares into its cache, `tool/johnson_1755/fetch.sh` the leaves the
work was fitted to.

## Fonts

Libre Caslon Text, roman and italic, Noto Serif for the Greek and the
Saxon letters and Noto Serif Hebrew for the Hebrew (all SIL Open Font
License 1.1), from Google Fonts: `ptome doctor --look johnson --looksdir
test/showcase/johnson` installs them. Not committed.

## The printing the look follows

The first edition, London, W. Strahan for J. and P. Knapton and others,
1755, volume II: the Wellcome Collection's copy, scanned by the Internet
Archive, https://archive.org/details/b30451541_0002. The page is the
folio's as the scan has it, 785 × 1428 pt; its two columns, their lines
13.2 pt apart, as wide and as far apart as the printing's; the type as
wide as the printing's word for word, its spaces as wide as its
unjustified lines' (tool/johnson_1755/README.md).

Where the look departs from it:

- Libre Caslon Text stands in for the edition's Caslon: its words as
  wide, its letters' shapes its own; the headwords' small capitals,
  made from the lowercase, are a little smaller and narrower than the
  printing's, and a line with a headword ends a little short of the
  printing's.
- The heads over the columns sit where the printing's sit on the three
  pages taken together: the printing places each page's by hand, a few
  points from the next page's.
- In HTML and EPUB, the text is in one column, its lines run together
  but a verse quotation's, the authors on lines of their own, flush
  right, and the foot left out: CSS has no flush right at the end of a
  line, and floats run across columns.
