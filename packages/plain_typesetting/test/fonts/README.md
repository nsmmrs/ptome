# Test fonts

The same fonts as plain_pdf's tests use (`packages/plain_pdf/test/fonts`,
whose README says how each was made):

- `notoserif-regular-latin.ttf`: Noto Serif, Latin subset, distributed with
  asciidoctor-epub3 2.3.0 (Apache License 2.0,
  https://www.apache.org/licenses/LICENSE-2.0; © Google).
- `notoserif-kern-subtables.ttf`: `notoserif-regular-latin.ttf` with a
  `kern` table of two subtables (A V −80; then T o −60 and A V −40).
- `notoserif-features.ttf`: Noto Serif 2.015, Basic Latin, with the
  `onum`, `smcp`, `liga` and `kern` features (SIL Open Font License 1.1,
  https://openfontlicense.org; © 2022 The Noto Project Authors).
- `libertinus-smcp.otf`: Libertinus Serif 7.051, "Abc", whose `smcp` is a
  multiple substitution (SIL Open Font License 1.1; © the Libertinus
  Project Authors).
- `notosansmath-subset.ttf`: Noto Sans Math 3.000, subset to ASCII, the
  Greek letters, the math italic letters and the operators the math tests
  use, its `MATH` table kept (SIL Open Font License 1.1; © 2022 The Noto
  Project Authors).
- `notonaskharabic-subset.ttf`: Noto Naskh Arabic 2.021, subset to the
  Arabic blocks (letters, vowels, Qur'anic marks, Arabic-Indic digits)
  with its `GDEF`, `GSUB` and `GPOS` tables kept, for the right-to-left
  shaping tests (SIL Open Font License 1.1; © 2022 The Noto Project
  Authors).
- `notoserifhebrew-subset.ttf`: Noto Serif Hebrew 2.004, subset to the
  Hebrew block with its layout tables kept (SIL Open Font License 1.1;
  © 2022 The Noto Project Authors).
- `notoserif-scripts.ttf`, `notosansarmenian-subset.ttf`,
  `notosansgeorgian-subset.ttf`, `notosanscoptic-subset.ttf`,
  `notosansethiopic-subset.ttf`: Noto Serif and Noto Sans Armenian,
  Georgian, Coptic and Ethiopic, each subset to the characters of its
  sample lines in `test/fixtures/scripts` with its layout tables kept
  (`tool/subset_test_fonts.dart`, from the installed fonts), for the
  script shaping tests (SIL Open Font License 1.1; © 2022 The Noto
  Project Authors).
- `notosanssyriac-subset.ttf`, `notosanssyriaceastern-subset.ttf`,
  `notosanssyriacwestern-subset.ttf`: Noto Sans Syriac (Estrangela),
  Syriac Eastern and Syriac Western, subset the same way (SIL Open Font
  License 1.1; © 2022 The Noto Project Authors).
- `notosansdevanagari-subset.ttf`, `notoserifdevanagari-subset.ttf`,
  `notosansbengali-subset.ttf`, `notosansgurmukhi-subset.ttf`,
  `notosansgujarati-subset.ttf`, `notosansoriya-subset.ttf`,
  `notosanstamil-subset.ttf`, `notosanstelugu-subset.ttf`,
  `notosanskannada-subset.ttf`, `notosansmalayalam-subset.ttf`: the Noto
  Sans (and Serif) fonts of the Indic scripts, subset the same way; the
  `-oldspec` ones the same fonts with their script tag renamed to the old
  specification's (`dev2` to `deva`, `bng2` to `beng`, `mlm2` to `mlym`),
  for the shaper's old-specification rules (SIL Open Font License 1.1;
  © 2022 The Noto Project Authors).
- `notosanssinhala-subset.ttf`, `notosansmongolian-subset.ttf`,
  `notosansnko-subset.ttf`, `notosansjavanese-subset.ttf`,
  `notosansbalinese-subset.ttf`, `notosanskhmer-subset.ttf`,
  `notosansmyanmar-subset.ttf`, `notosansthai-subset.ttf`,
  `notosanslao-subset.ttf`, `notosanscjk-hangul-subset.otf` (Noto Sans
  CJK's first face), `notoseriftibetan-subset.ttf`,
  `notonaskharabic-persian-urdu.ttf`, `notonastaliqurdu-subset.ttf`
  (Noto Serif Tibetan, Naskh Arabic and Nastaliq Urdu from google/fonts'
  `ofl/`, their variable fonts pinned at the default instance): subset
  the same way (SIL Open Font License 1.1; © 2022 The Noto Project
  Authors).
