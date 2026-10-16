---
title: "McGuffey's Second Eclectic Reader"
source: mcguffey.adoc
looks: [mcguffey]
compare:
  - page: 1
    scan: https://archive.org/download/mcguffeysseconde0000unse/page/n4.jpg
    note: "The title page, its woodcut and its lines (American Book Company, 1920)"
  - page: 7
    scan: https://archive.org/download/mcguffeysseconde0000unse/page/n10.jpg
    note: "Articulation: the key's table of vocals, a rule between its halves (1920)"
  - page: 11
    scan: https://archive.org/download/mcguffeysseconde0000unse/page/n14.jpg
    note: "Lesson I: its woodcut, its words below it, its numbered paragraphs line for line (1920)"
  - page: 13
    scan: https://archive.org/download/mcguffeysseconde0000unse/page/n16.jpg
    note: "Lesson II: its words in the room its woodcut leaves them (1920)"
  - page: 15
    scan: https://archive.org/download/mcguffeysseconde0000unse/page/n18.jpg
    note: "Lesson III: Willie's letter in script, line for line (1920)"
  - page: 22
    scan: https://archive.org/download/mcguffeysseconde0000unse/page/n25.jpg
    note: "Lesson VII: its words either side of the vignette, the poem's lines set in (1920)"
  - page: 24
    scan: https://archive.org/download/mcguffeysseconde0000unse/page/n27.jpg
    note: "Lesson VIII: three groups of words around the stairs (1920)"
---

# McGuffey's Second Eclectic Reader

The first forty-eight pages of McGuffey's Second Eclectic Reader, the
revised edition (1879), as the American Book Company printed them in
1920: the title page and its verso, the preface, the contents, the
introductory matter (the key to the marks of pronunciation, the marks of
punctuation) and Lessons I–XXI, page for page and line for line. What
the work shows: a schoolbook's structure — numbered lessons, each its new
words at its head in columns (around its woodcut where the printing sets
them there), its woodcut, its title, its paragraphs numbered in their
first lines or its stanzas' numbers hung — and the marks of pronunciation
over and under the letters (macrons, breves, dots and diaereses above and
below, the barred c and g, the underlined n, the long and short double o),
some of them combining marks set by the font's mark positioning; the key
to the marks in its tables; the lessons printed in script, set in a
copybook hand (FEAT-zgygsw); a contents with its numerals in a column and
its dots to the pages.

In the PDF each page is the printing's page of its number: it starts and
ends with the printing's words, each line breaks and each word divides
where the printing's does (`:source-lines:`), and each block — a lesson's
heading, its words, its woodcut, its title, its first paragraph — sits
where the scan shows it, within half a point (its own `margin-top`,
fitted to the scan: `tool/mcguffey_1920`). The folios are the printing's
(roman to vi, then from 7), the running heads "ECLECTIC SERIES." and
"SECOND READER.", the opening pages' folios in brackets at the foot, the
gatherings' numbers at the foot of their first pages ("2, 2.").

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| The text | transcribed for the work from the printing (below), Project Gutenberg's text (eBook #14668, `pg14668-images.html`, which follows the same printing) aligned with the scan's OCR and checked against the scan | `c33b2b1122e4c2789707b0bc453bbc080402057e18189a76ee31d2935b04d30f` (`pg14668-images.html`) |
| The scan and its OCR | https://archive.org/details/mcguffeysseconde0000unse: `mcguffeysseconde0000unse_jp2.zip` (the pages, 360 ppi), `_hocr.html` | `27be307f09e40da805db7e650d3e742e4255bef8d8f83629373ef7c63290997a`, `dab7698b9a7be818decf0ca1cdccf9e5598781dfd75bf57f2a3da9ef59ba14d4` |
| The woodcuts | Project Gutenberg's scans of the same printing, in `fetch.yml` with their SHA-256 | in `fetch.yml` |

The transcription follows the printing where Project Gutenberg's text
departs from it ("Every one" for its "Everyone", "needlebook", "going by,
and", "belong to him", "quite well.”", "mine,” said James"); it adds what
Project Gutenberg leaves out or keeps as scans: each lesson's words with
their marks as the printing has them, in Unicode — ā ă ä â ȧ a̤ ạ, ē ĕ ẽ e̱,
ī ĭ ĩ ï, ō ŏ ô ȯ õ o̤ ọ, ū ŭ û ụ ṳ, ȳ y̆, o͞o and o͝o (a long or short mark
over both letters, U+035E and U+035D), ȼ (a hard c), ç (a soft c), ḡ (a
hard g), ġ (a soft g), n̲ (as ng, U+0332), s̱ and x̱ (as z and gz, U+0331),
t͟h (the voiced th) and the accent marks as primes —, the key to the marks,
the lessons in script (Willie's letter, the slate work of Lessons VI and
XXI, Lesson XV's poem), the title page, its verso and the contents, which
list the whole book (the first twenty-one lessons linked). The straight
quotation marks and apostrophes are curled. Each woodcut's words printed
beside or around it are painted out of Project Gutenberg's scan
(`fetch.yml`'s `blank`, found as the ink apart from the picture) and set
as text over the room they leave.

## Licence

The reader is in the public domain in the United States (the revised
edition published 1879; this printing 1920). Project Gutenberg's edition
is a public-domain text in the United States; its header, licence and
trademark are not reproduced, and its name is used only in this credit.
The transcription is the work's own (MIT, as the repository). The scans
are not committed: `tool/showcase.dart` fetches the woodcuts and the pages
it compares into its cache.

## Fonts

Charis SIL (the text and its marks), Noto Sans (the lesson heads), Noto
Serif, Noto Sans Symbols 2 (the title page's fleurons) and Petit Formal
Script (the script), all SIL Open Font License 1.1, from Google Fonts:
`ptome doctor --look mcguffey --looksdir test/showcase/mcguffey` installs
them. Not committed.

## The printing the look follows

The revised edition (1879), New York, Cincinnati and Chicago, American
Book Company, in its printing of 1920 (copyright 1879, 1896, 1907 and
1920; the Nashville Public Library's copy), scanned by the Internet
Archive, https://archive.org/details/mcguffeysseconde0000unse.

Where the look departs from it:

- Charis SIL stands in for the printing's modern roman, for its marks;
  Petit Formal Script for its Spencerian hand, which it resembles less;
  Noto Sans Bold for the lesson heads' gothic.
- Charis is wider than the printing's face: one stanza line is set a
  little tighter to keep its line, as are four of the words beside the
  woodcuts.
- The preface's and the contents' engraved headings are set in type.
- The woodcuts are Project Gutenberg's scans, a few per cent off the
  printing's size here and there.
- In HTML and EPUB the text runs as prose, the words before each woodcut;
  the title page, its verso and the contents are the PDF's alone (HTML
  and EPUB have the woodcut of the title page as a frontispiece, and
  their own contents).
- In the excerpt test, Lesson III's words are left out: their combining
  marks are in none of the fonts the tests commit.
