---
title: "The Temple"
source: herbert.adoc
looks: [herbert]
compare:
  - page: 4
    scan: https://archive.org/download/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633/page/n25.jpg
    note: "The Altar, its lines making an altar between bands of ornament (1633)"
  - page: 7
    scan: https://archive.org/download/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633/page/n41.jpg
    note: "Easter-wings, its first stanza printed sideways (1633)"
  - page: 8
    scan: https://archive.org/download/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633/page/n42.jpg
    note: "Easter-wings, its second stanza on the facing page (1633)"
---

# The Temple

The Dedication and eight poems of The Church from George Herbert's The
Temple, in a look after its first edition (1633). What the work shows:
shaped verse — The Altar's lines set in to draw an altar, the two
stanzas of Easter-wings each turned sideways on a page of its own (the
`sideways` role, FEAT-wlw5wq), their lines centred into a pair of
wings, as the first edition prints them; the stanzas' indents, as
spaces at the lines' starts; the long s of the Fell types, with its
ligatures (ſt, ſh, ſl, ſſ), and their ct, not typed in the text but set
by the font's own rules
(`base_font_variant_alternates: historical-forms`,
`base_font_variant_ligatures: discretionary-ligatures`, FEAT-h9smyr);
words in spaced small capitals (FEAT-7nyr0t).

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| `text/dedication.adoc`, `text/church.adoc` | transcribed for the work from the facsimile of the first edition, https://archive.org/details/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633 (pages 6, 24–25, 38–43, 50 and 59–60 of the scan) | |

The poems: Superliminare, The Altar, Redemption, Easter, Easter-wings,
H. Baptisme (II), Prayer (I) and Grace, with the Dedication. The
transcription keeps the edition's spelling, its capitals and its
punctuation, and its u, v, i and j; it writes the round s for every s,
the long s coming from the font.

## Licence

The Temple is in the public domain (published 1633; George Herbert died
in 1633). The transcription is the work's own (MIT, as the
repository). The scans are not committed: `tool/showcase.dart` fetches
the pages it compares into its cache.

## Fonts

IM Fell DW Pica, roman and italic (SIL Open Font License 1.1; Igino
Marini's revival of the Fell types, cut in the 1670s), from Google
Fonts: `ptome doctor --look herbert --looksdir test/showcase/herbert`
installs it. Not committed.

## The printing the look follows

The first edition, Cambridge, Thomas Buck and Roger Daniel, 1633, in the
facsimile of Early English Books scanned by the Internet Archive,
https://archive.org/details/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633.

Where the look departs from it:

- IM Fell DW Pica, a type of the 1670s, stands in for the edition's
  roman and italic.
- The bands of type ornament over each page's first poem are a rule;
  the drop capitals and the catchwords are left out, and a line too
  long for the measure turns over to a line of its own, where the
  edition turns it up or down into the line beside, after a bracket.
- In HTML and EPUB, Easter-wings is set upright, centred: an e-book's
  page can't be turned. The long s and the ligatures come from the
  font's features where the reader's browser applies them
  (`font-feature-settings`).
- In the excerpt test, the long s and the ligatures are left out: they
  are in none of the fonts the tests commit.
