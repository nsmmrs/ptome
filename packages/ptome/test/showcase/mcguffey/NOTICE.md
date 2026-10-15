---
title: "McGuffey's Second Eclectic Reader"
source: mcguffey.adoc
looks: [mcguffey]
compare:
  - page: 7
    scan: https://archive.org/download/mcguffeysseconde0000unse/page/n14.jpg
    note: "Lesson I: its woodcut and its words with their marks (1879)"
  - page: 12
    scan: https://archive.org/download/mcguffeysseconde0000unse/page/n18.jpg
    note: "Lesson III: Willie's letter in script (1879)"
  - page: 14
    scan: https://archive.org/download/mcguffeysseconde0000unse/page/n20.jpg
    note: "Lesson V: the words in four columns, the woodcut, the paragraphs numbered (1879)"
---

# McGuffey's Second Eclectic Reader

The preface, the introductory matter and the first twenty of the
seventy-one lessons of McGuffey's Second Eclectic Reader, in a look
after its revised edition (1879). What the work shows: a schoolbook's
structure — numbered lessons, each its new words at its head in
columns, its woodcut, its title, its paragraphs or stanzas numbered —
and the marks of pronunciation over and under the letters (macrons,
breves, dots and diaereses above and below, the barred c and g, the
underlined n, the long and short double o), some of them combining
marks set by the font's mark positioning; the key to the marks as the
reader prints it; the lessons printed in script, set in a copybook hand
(FEAT-zgygsw).

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| McGuffey's Second Eclectic Reader, Project Gutenberg eBook #14668 (HTML, its scans) | https://www.gutenberg.org/cache/epub/14668/pg14668-h.zip | `7ad465684a98bc6d0301258a04612e2220c53a2142587b798148ded381ab0475` (its `pg14668-images.html`: `c33b2b1122e4c2789707b0bc453bbc080402057e18189a76ee31d2935b04d30f`) |
| The woodcuts, the same edition's scans | in `fetch.yml` with their SHA-256 | in `fetch.yml` |
| `words.txt`, `script.txt`, `key.adoc` | transcribed for the work from the facsimile of the 1879 printing, https://archive.org/details/mcguffeysseconde0000unse (pages 11–48), and from Project Gutenberg's scans of the key and the script lessons | |

Project Gutenberg's transcription leaves out the words at the head of
each lesson (it keeps some as scans, the others in comments without
their marks), the key to the marks and the script lessons, which it
keeps as scans. The work transcribes them: each lesson's words with
their marks as the 1879 printing has them, in Unicode — ā ă ä â ȧ a̤ ạ,
ē ĕ ẽ e̱, ī ĭ ĩ ï, ō ŏ ô ȯ õ o̤ ọ, ū ŭ û ụ ṳ, ȳ y̆, o͞o and o͝o (a long or
short mark over both letters, U+035E and U+035D), ȼ (a hard c), ç (a
soft c), ḡ (a hard g), ġ (a soft g), n̲ (as ng, U+0332), s̱ and x̱ (as z
and gz, U+0331), t͟h (the voiced th) — and the accent marks as primes.

Imported by `tool/showcase_gutenberg.dart mcguffey`, which writes
`text/reader.adoc`:

- Project Gutenberg's header, licence and transcriber's notes are left
  out, and the later printings' copyright and trademark notices, and the
  contents.
- The lessons after the twentieth are left out.
- Each lesson's words are a table at its head, in the rows the printing
  sets them in, from `words.txt`; where it sets them around the woodcut,
  they are set above it.
- The woodcuts are the edition's scans. Eight of them hold the lesson's
  words printed beside or around the picture: those words are painted
  white and the picture cut from the rest (`blank` and `crop` in
  `fetch.yml`, written as PNG by `tool/showcase.dart`). Lesson V's
  woodcut, which Project Gutenberg sets again in Lesson VI, is set once.
- The script lessons (Willie's letter, the slate work of Lesson VI,
  Lesson XV's poem) are text in the `script` role, from `script.txt`.
- The straight quotation marks and apostrophes are curled.

## Licence

The reader is in the public domain in the United States (the revised
edition published 1879; the printing Project Gutenberg follows 1920).
Project Gutenberg's edition is a public-domain text in the United
States; its header, licence and trademark are not reproduced, and its
name is used only in this credit. The transcriptions are the work's own
(MIT, as the repository).

## Fonts

Charis SIL (the text and its marks), Noto Sans (the lesson heads),
Noto Serif, and Petit Formal Script (the script), all SIL Open Font
License 1.1, from Google Fonts: `ptome doctor --look mcguffey --looksdir
test/showcase/mcguffey` installs them. Not committed.

## The printing the look follows

The revised edition, Cincinnati and New York, Van Antwerp, Bragg & Co.,
1879, scanned by the Internet Archive,
https://archive.org/details/mcguffeysseconde0000unse.

Where the look departs from it:

- Charis SIL stands in for the printing's modern roman, for its marks;
  Petit Formal Script for its Spencerian hand, which it resembles less.
- The words the printing sets around a woodcut are set above it.
- In the excerpt test, Lesson III's words and the key are left out:
  their combining marks are in none of the fonts the tests commit.
