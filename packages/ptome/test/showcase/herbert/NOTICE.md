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

## The scans transcribed

The pages of https://archive.org/details/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633 the transcription was
made from, each the Internet Archive's JPEG
(`https://archive.org/download/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633/page/<page>.jpg`) with its
SHA-256:

```
135abeeab775b085108d7565a76110f4388fcbdd9eae6c2a837a5cb254e69bb3  n6.jpg
2c2d751a5c8e311c6555aab5df1f094d7516d15fa890c7dce2a5c9f692f577e8  n24.jpg
1fba9e29b54955c5af65488b160b54aa92670d3196cb77a96a98fc1a81072336  n25.jpg
f148738e4f13436efe8641a8f3b13cbfc14f12fd05883ec250203e7b571a0b95  n38.jpg
bdf42a0bb36a5ccd2d450771d6b01a7b81421cbe96a5d43e7dc5a7c758df801b  n39.jpg
7fd85f04a2ac8e05e3ab5982bbfeb648a02273094ec11912e619048591b5fc36  n40.jpg
d37e12d229d0358d3579290791b67da4db0d5d5b6d0e1e33654be5e90fdfeca4  n41.jpg
a8922e1de746be76bb274c96254eefb3f608b8fb1dc70b9ec6d7cf06ebc7aa17  n42.jpg
81e9246e03cf0ca70fcf9ff86db40b97110e8d7b7580a7bf1b4644f1473fe8dd  n43.jpg
cf65059bc3782639a56baeb237a0b3c9b42a17ddf58a2d955297c506efec385e  n50.jpg
5ce415ab863a16bdc7656d28dc4a248e31b0c56be3c501a768da434f203b60c5  n59.jpg
2e6fd299320a5e89d4a6ec6908beacf69cd0f826caad9d77c75cb07e65014c31  n60.jpg
```

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
