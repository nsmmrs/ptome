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

## The scans transcribed

The pages of https://archive.org/details/mcguffeysseconde0000unse the transcription was
made from, each the Internet Archive's JPEG
(`https://archive.org/download/mcguffeysseconde0000unse/page/<page>.jpg`) with its
SHA-256:

```
90ad8b9153ed6419b1164234ea073526802f705fe998e152af077583ad580508  n14.jpg
92b1dd75a60230271d84faa5b2ae60813a7de6aac87bee4c874a19bcfd8e4856  n15.jpg
12cd7d7009fe490d34c8d3552f5744af8f97971bc53203662677e2259150e518  n16.jpg
d9986b6e7e8ac5dd03238317dec95429f10d5c7505b7a6d5a74986ffea685e4e  n17.jpg
a9ebf0d77203deda07c642469c2669ec547a7506c3893542b488c47180705772  n18.jpg
a72d4f467968e540ff6b7fce7629213132a5db3bc32cc8ce486da5fd76fdd7e2  n19.jpg
8c88dfd16ab5028ccc949d0eb9b4d6f870ee9b636643a333e18c518a13678231  n20.jpg
78c208038d8734ab06f31e5be21795a679f47e444e76981ae6d411cca4104c70  n21.jpg
be1b9f95e111abe466dd6dac1de06b737f114c0d34a1dce20d6e7260e26b4751  n22.jpg
f2ba72d7bae50f27d7d1f721b3e4de57c69e56b980e25404766c01dbffaa02a9  n23.jpg
0f99403a6e94ebcafefe9d8836bf92fee7365e857c8b71b1b4b528ca112626ff  n24.jpg
827d4abea952107134d4dfc7653d04992a3f2d3ba070b95bb3aeb1100ce7fe55  n25.jpg
9fb1d3e4ad3a97c5bde2dc51755edabc7460a55e6427b8462ba8455ec404f0ee  n26.jpg
8b7a27a05f9afa80f02c5003799e0de7c9901dfdb0a253a6c01eeac44fd43443  n27.jpg
55ff200b3cbaa29904170883316ebd9390470dd35d138361bb94ecd3bfd80665  n28.jpg
57411ddeae563f575360a31ec087758dbeac32dec1ec686cde5e5aa2849dfce4  n29.jpg
e8c54c1e6e349725046152397215bb28308dfc36743e8386281d36557427639b  n30.jpg
e9ee9e0520a44b3ebddaac0c0c2f4747f01855339843cf2e681350f1ea2ea806  n31.jpg
e53fb9ad0784745ac667ca6441260d993b3ab064626643a9bf378608605c1215  n32.jpg
38c5c3d65267fb1d6476990c3929666756146496c1e9c34269e6cbffecaa2321  n33.jpg
4bdbe782c8537183ce692da4b271e4cd585ce64d6f24fc7a0f62573d4b0c6e7d  n34.jpg
586baa1ccba2bbf83239f3bde054cf2acf5536e7cf00c893b6149a7164596e03  n35.jpg
cfaea42e37c23ff63b28065939940b3c5caf015e48e5636c0352837db5031bf7  n36.jpg
0101771b30ffcc90abed85df6806e8102569e99b00968a2713f757f1915aba89  n37.jpg
33e1508c515b71461c4b7ee7d9b40910abebcc37605252c718bcc5f6e5cc5755  n38.jpg
c9bb99fe189ff2d114dc53022f23d44f4fdf8f2c056d64ebe3a9eac641cd9c88  n39.jpg
47b1494dd288fee6a35b1710f88d783259f99212277c1805660b9bb86b7c4594  n40.jpg
7888da525d34e308c5189c7f580a03b750bbc0e70ae5c965f6ffc5826c505612  n41.jpg
ff76772dc08a1eb6e6b76dfd6f4105d6a2de181af16779f6efed4d4f29fad0ee  n42.jpg
e499a0406c79311deb4ed5077bd324363635b79245e6628789cdc5e43d7a7cef  n43.jpg
5b0fa139295baa2c4136bb5b414a2abfa25b36ed3f854439a1892d8024752619  n44.jpg
e30c8af266c42e201877fbc7a71edd96f34b2f18a08f9d6ce1ba7eb985f47794  n45.jpg
9c81a3a67333886096cf847cd7be0f0dbff60f599346b5a05ac8c0f459e8fa5e  n46.jpg
8ef93cb217f3a8fd26e70eb80c08bfd1c1a8eeac39641e4b3c45eb203fe046ea  n47.jpg
2a4d63078a3f3f7f339f509fffef430e1cef52c4be53e114da01940cd38f20fe  n48.jpg
8bf9ff119a56dca2dfd8e2055847bced6be07a75937bf11c73e5606c26409567  n49.jpg
51737d1630b863c7f6bf8f8c52697045729e5cb7119b5548bc71f066e9817900  n50.jpg
79c4d6be128aac4cf891fda88af3b262bf599bfaeb4e92d5d3e5197cd7049ffa  n51.jpg
```

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
