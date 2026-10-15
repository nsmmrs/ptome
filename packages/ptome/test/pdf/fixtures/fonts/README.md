# Test fonts

`yrsa-regular-latin.ttf` and `yrsa-italic-latin.ttf` are Yrsa Regular and
Italic (Rosetta Type, https://github.com/rosettatype/yrsa-rasa), under the
SIL Open Font License 1.1 (`OFL.txt`), subset to Basic Latin with their
`liga` and `kern` features:

```sh
pyftsubset Yrsa-Regular.ttf --unicodes=U+0020-007E \
  --layout-features=liga,kern --name-IDs='*' \
  --output-file=yrsa-regular-latin.ttf
```

The modern PDF engine's tests set text in them (ligatures, GPOS kerning).

`notoserif-features.ttf` is Noto Serif 2.015 (© 2022 The Noto Project
Authors, SIL Open Font License 1.1), subset to Basic Latin with its
`onum`, `smcp`, `liga` and `kern` features (as in plain_pdf's test fonts).

`libertinus-scripts.otf` is Libertinus Serif Regular 7.051 (© 2012-2024
The Libertinus Project Authors, SIL Open Font License 1.1, from
typst/typst-assets), subset to Basic Latin with its `sups` and `subs`
features, for typographic superscripts:

```sh
pyftsubset LibertinusSerif-Regular.otf --unicodes=U+0020-007E \
  --layout-features=sups,subs --name-IDs='*' \
  --output-file=libertinus-scripts.otf
```

`notoserifhebrew-subset.ttf` is Noto Serif Hebrew 2.004 (© 2022 The Noto
Project Authors, SIL Open Font License 1.1), subset to the Hebrew block
with its layout tables (as in plain_typesetting's test fonts), for
right-to-left documents.

`notonaskharabic-subset.ttf` is Noto Naskh Arabic 2.021 (© 2022 The Noto
Project Authors, SIL Open Font License 1.1), subset to the Arabic blocks
with its layout tables (as in plain_typesetting's test fonts), for text
taken from shaped Arabic.

`notonaskharabic-mushaf.ttf` is Noto Naskh Arabic Regular 2.021 (© 2022
The Noto Project Authors, SIL Open Font License 1.1), subset to the
characters of the pages test/pdf/mushaf_test.dart sets (al-Fatiha and the
last three surahs of the units corpus's Tanzil text, the surahs' titles
and the page numbers) with every layout feature:

```sh
pyftsubset NotoNaskhArabic-Regular.ttf --text-file=CHARS \
  --layout-features='*' --name-IDs='*' \
  --output-file=notonaskharabic-mushaf.ttf
```

`cjk/` holds Noto Serif CJK Regular's five regional faces (SC, TC, JP,
KR, HK) and Noto Sans CJK SC Bold (© 2017 Adobe, SIL Open Font License
1.1), each subset to the characters of test/pdf/cjk_fonts_test.dart's
regions document, the fonts it installs:

```sh
pyftsubset NotoSerifCJK-Regular.ttc --font-number=2 --text='直骨今한국어字体' \
  --layout-features='*' --name-IDs='*' \
  --output-file=cjk/notoserifcjksc-regular-subset.otf
```

(faces 0 to 4: jp, kr, sc, tc, hk; NotoSansCJK-Bold.ttc's face 2 for
`notosanscjksc-bold-subset.otf`).
