# Changelog

## 0.1.0 (unreleased)

First release of Ptome (called asciidart until 2026-10-08, ADR-0018), a
processor for AsciiDoc® documents written in Dart, compatible with
Asciidoctor's development version (upstream `main` at `30fb8cd5`, which
reports **2.1.0.alpha.0**), fixing bugs Asciidoctor still has. The tag
`asciidoctor-2.0.26-parity` marks the last commit that matched the 2.0.26
release byte for byte (ADR-0017). Not affiliated with or endorsed by the
Asciidoctor project.

- PDF: `footnotes_columns` sets the footnotes in balanced columns at the
  foot of the page (Gibbon's notes; FEAT-6nsldy), and a page of notes in
  columns is laid out many times faster.
- PDF: a two- or three-em dash that the text's faces lack is set as two
  or three em dashes run together (Tristram Shandy in Caslon); a tagged
  table's cell that spans rows or columns carries its `RowSpan` or
  `ColSpan` (PDF/UA-1 7.2; BUG-85ldy8).
- A footnote in a discrete heading's title is numbered where the heading
  is set, once and in reading order; Asciidoctor numbers it while
  parsing, so it shares number 1 with the text's first note, and an EPUB
  sets it among the first chapter's notes
  (`test/upstream_fixes/discrete-heading-footnote-*`); not under
  `asciidoctor-compat`.
- EPUB: a chapter's title element holds the title's text alone; with
  emphasis in a chapter's title (`== The _Albatross_`) asciidoctor-epub3
  writes the tags there too, which EPUBCheck rejects
  (`test/upstream_fixes/epub-output-3`); not under `asciidoctor-compat`.
- PDF, for plays (FEAT-d1sdfw): `role_<role>_text_indent: continue`
  steps a verse line shared between speakers to where the line before it
  ended, counted once by logical line numbers;
  `line_numbers_restart_level` counts a play's lines from each scene;
  `line_numbers_skip_headings`, `_skip_terms` and `_skip_roles` leave its
  heads, speakers' names and stage directions out of the count;
  `description_list_term_indent` sets a run-in term in from the lines
  after it (the First Folio's speech prefixes). `ptome doctor` installs
  IM Fell DW Pica, UnifrakturMaguntia and Noto Serif Hebrew for a look
  that names them, and the fonts a look falls back to (`font:
  fallbacks:`).
- PDF: Ptome's `mirror` role sets a block mirrored, left to right
  (`[verse.mirror]`, Jabberwocky as Through the Looking-Glass prints it;
  FEAT-yq6kff), kept whole on a page; not under `asciidoctor-compat`.
- The showcase corpus (`doc/showcase.md`, EPIC-phf3n2): public-domain
  works that show what Ptome's output can do, built whole by
  `tool/showcase.dart` (HTML, EPUB and PDF, EPUBCheck and veraPDF, pages
  beside scans of the printing their looks follow), each with an
  excerpt test; Standard Ebooks productions imported by
  `tool/showcase_import.dart`.
- `PTOME_SYSTEM_FONTS=off` keeps fonts to `PTOME_FONT_PATH` and the
  folders a theme or document names: no font installed on the machine is
  found, so the output depends on none (a reproducible build; the tests
  run so).
- The substitutions restructured (CHORE-fthx89), output the same: each
  pass declares what it needs in the text and the pipeline skips it in
  one place; a substitution run holds the passthroughs and their lock, the
  mask of the characters a text holds and the inline elements' tracking,
  in place of two `Expando`s and statics. A little faster on the
  throughput corpus (html5 −7%).
- Faster units documents (TASK-frytn1): the inline scanner looks for each
  token's literal (`@`, `note:`, `<<`, `[.dfn]#`, the range brackets)
  before running its regex, markers tried only at the first `@` of a run:
  Ethics in Greek to HTML 87 → 58 ms, the KJV 4.4 → 3.7 s, output the
  same byte for byte.
- PDF: jukugo ruby with three or more reading characters to a character
  is set as JLREQ Appendix F has it (readings hanging over the compound's
  next character, then the kana beside it, then space opened around the
  long ones) and a line may break between its characters, each part set
  as one of its own (FEAT-7gyqtj); it used to be one unbreakable group.
- PDF: a warichu note longer than the rest of its line fills it and goes
  on at the next line's start, each part balanced in two lines spaced to
  the same length (JLREQ 3.4.2, FEAT-cjd1nv); it used to be cut into
  line-sized pieces, the first moved to the next line whole.
- Dates in other calendars (FEAT-gtxzgh, FEAT-5639x7): `:calendar:`
  (`japanese`, `buddhist`, `roc`, `hebrew`, `persian`, the Islamic
  calendar's forms, `coptic`, `ethiopic`, `indian`, `chinese`, `dangi`),
  or `lang`'s `-u-ca-`, shows the "Last updated" date and an ISO
  `revdate` in it (`令和8年10月14日`, `ג׳ בחשוון תשפ״ז`), long by default.
  Not under `asciidoctor-compat`.
- Warichu (FEAT-csvpsb): `warichu:[...]`, an inline cutting note in two
  half-size lines within its line in the PDF (JLREQ 3.4), balanced, in
  columns in vertical text; a `<span class="warichu">` in HTML and EPUB,
  parentheses elsewhere. And the kihon-hanmen (JLREQ 2.3): the theme's
  `page_hanmen_characters` and `page_hanmen_lines` (`page_hanmen_line_gap`)
  size the text area, center it on the page and keep the body's lines to
  its grid. Not under `asciidoctor-compat`.
- PDF: ruby in vertical text stands upright, shaped with the font's
  vertical forms, rather than lying on its side (BUG-tt4d5k).
- Direction per block and per span (FEAT-nyf5rz): a block's `dir`, or a
  `lang` written the other way from the document, sets it from its own
  side in the PDF (alignments, list markers, table columns; the pages keep
  the document's direction) and writes `lang` and `dir` on its HTML and
  EPUB element; a span's `dir` (`[dir=rtl]#…#`) is a bidirectional isolate
  in the PDF and an attribute in HTML, as is a span's `lang`. An isolate,
  a joiner or another invisible control no font has is set unwarned of.
  None of it under `asciidoctor-compat`, which warns as Asciidoctor PDF
  does.
- Line-breaking strictness (FEAT-cr864h): `line-break` (`strict`,
  `normal`, `loose`, `anywhere`), CSS Text 3's, in every format (HTML and
  EPUB as CSS's `line-break`, the PDF's theme key `base_line_break`); not
  under `asciidoctor-compat`.
- PDF: ruby as JLREQ 3.3 and CLREQ set it (FEAT-8xyny8): a shorter
  reading spread 1:2:1 over its base (JIS X 4051), a longer one hanging
  over the kana and punctuation blanks beside it but never a Han
  character, the rest made up between its base's characters, no further
  than a line's start or end; mono ruby breakable between its
  characters; jukugo ruby (`ruby:鬼門[き もん,jukugo]`); zhuyin in a column
  at its character's right with its tone marks (HTML: `ruby-position:
  inter-character`).
- Dates in the language's format (FEAT-f7cn49): the "Last updated" date
  and time and an ISO `revdate` (HTML header, title pages, the PDF's) in
  CLDR's patterns for `lang` (`2026年10月14日`, `14. Oktober 2026`),
  `date-format` (`short`, `medium`, `long`, `full`, `iso`) choosing the
  length, `long` by default outside English; the attributes stay ISO.
  Not under `asciidoctor-compat`.
- Numbers in the language's numerals (FEAT-ndn74f): section, caption,
  footnote and list numbers (and the PDF's page numbers) in the digits of
  the numbering system CLDR gives `lang` (Arabic-Indic in `ar-EG`,
  Persian in `fa`, Devanagari in `mr`), or `numbering-system`'s; ordered
  lists in any of CSS's 203 counter styles (`[hiragana]`,
  `[cjk-ideographic]`, `[hebrew]`, `[lower-russian]`), HTML and EPUB with
  `list-style-type` and the `@counter-style` rules browsers lack;
  `sectnums-style`; the PDF theme's `page_numbering_style`. A list marker
  is as wide as its text in the fallback fonts. A language whose locale
  file has no word for "Chapter" or "Part" drops the English one. Not
  under `asciidoctor-compat`.
- PDF/UA: a block's own `lang` reaches its structure elements and a
  span's marks its text, as PDF/UA-1 7.2 asks (FEAT-r90rkz).
- Generated text in the document's language (FEAT-rss0h8): Asciidoctor's
  locale file for `lang` (table of contents, captions, admonitions,
  appendix and chapter labels) read without an include, the author's
  labels kept, in every format; the index's "see" and "see also" in the
  language (`index-see-label`, `index-see-also-label`). `:locale-labels:
  false` keeps the English; not under `asciidoctor-compat`.
- PDF: on a vertical page, a table too wide for the page is turned to lie
  along the column, as the official gazette turns them, instead of
  squeezed with its cells wrapping (BUG-38zmwk).
- PDF: color emoji (FEAT-rr13pg): emoji sequences set whole in a font
  with color glyphs (the text's, a color fallback of the theme's, else the
  installed Noto Color Emoji; `base_color_emoji: false` leaves it out) and
  drawn as the font paints them (COLR v0/v1 with CPAL, CBDT, sbix), their
  text read back as written; U+FE0E and U+FE0F kept after an emoji. Not
  under `asciidoctor-compat`.
- Index order by language (FEAT-5ttjh1): a document whose `lang` isn't
  English has its index (HTML, EPUB, PDF) in the language's collation,
  UCA with CLDR 48.2's tailoring (plain_unicode's `Collator`), headed by
  its index characters: Chinese by pinyin or stroke count, Japanese by
  kana row and by reading (a term's ruby, or `sort-as`). `index-sort:
  collation` or `asciidoctor` chooses either way; nothing changes under
  `asciidoctor-compat`.
- PDF: script-specific justification (FEAT-z8hxn0): Nastaliq (and any
  font with `jalt`) takes wider letterforms before its spaces widen (W3C
  alreq 7.2.3; `base_justify_alternates`); Tibetan spreads the room
  between all its characters, or with `base_tsheg_padding` fills a line
  ending with a tsheg out with tshegs, as pecha do.
- PDF: Tai Tham, New Tai Lue, Tai Viet and Ahom lines break between
  their orthographic syllables (FEAT-d2xh7l): no dictionary exists for
  them under a permissive licence.
- PDF: Japanese and Chinese lines adjusted in JLREQ 3.8's order
  (FEAT-vfmrnj): spaces, then the quarter em beside Latin, then between
  characters when stretching; spaces, then marks' blank halves, then the
  quarter em when shrinking. A line-end closing bracket or comma and a
  line-start opening bracket set solid (JIS X 4051, JLREQ 3.1.5);
  `base_hanging_punctuation` (burasagari) and `base_line_start_bracket`
  (`solid`, `full-width`, `novel`).
- HTML and EPUB: the document's direction and writing mode
  (FEAT-5gt09c): `:dir: rtl` writes `dir="rtl"` and turns an EPUB's
  pages to the left (`page-progression-direction`); `:writing-mode:
  vertical-rl` (or `vertical-lr`) sets the text vertical with CSS's
  `writing-mode`, tables and listings across, one- and two-digit numbers
  combined (`tcy` spans); the `vertical-rl`, `vertical-lr`,
  `horizontal-tb` and `tcy` roles; epubcheck-clean. The PDF reads
  `:writing-mode:` too. Not under `asciidoctor-compat`.
- PDF: with `reproducible`, no creation or modification date in the
  document information or the XMP metadata, as asciidoctor-pdf leaves
  them out (BUG-d2dtqb); they had been the conversion's time, so two
  runs differed.
- PDF: a block's own writing mode (TASK-kj6r6q): `[.vertical-rl]` and
  `[.vertical-lr]` set a block in vertical lines on a horizontal page,
  `[.horizontal-tb]` any block across on a vertical one; text the box
  sets itself is measured by its vertical advances in vertical lines.
- PDF: on vertical pages, tables, listings and literal blocks stand
  upright, set across (JLREQ 4.4.2), as wide as their content needs;
  lying on their side, top to the page's right, only when too long for
  the page upright (FEAT-tc0ts6); `[.vertical]` or
  `table_writing_mode: vertical` sets a table down the columns.
- PDF: tate-chu-yoko (FEAT-zhqwr3): on vertical pages, numbers of up
  to two digits stand upright across the column, an em long (JLREQ
  3.2.5), a lone digit in its full-width form;
  `base_text_combine_upright` (`digits 2`, `digits 3`, `none`); the
  `tcy` role (`[.tcy]#!?#`) for any short text.
- PDF: decorations in vertical text on their languages' sides
  (BUG-dfkx3f): strike-throughs down the middle of the characters (in
  vertical-lr's Mongolian they had run beside the letters), underlines on
  the right in Japanese and Korean, the left in Chinese, the right in
  Mongolian (mlreq 6.2.1).
- Captions numbered by chapter (FEAT-nnnwwv): `<kind>-numbering: chapter`
  numbers figures, tables, listings and examples from 1 in each chapter
  after its number (`表 2.1`, an appendix's `表 A.1`), `{{chapter}}` and
  `{{index}}` in `<kind>-caption-template`; not under
  `asciidoctor-compat`. `doc/books.md` shows a three-rule (booktabs)
  table look.
- French spacing (FEAT-96hbqp): French text gets a narrow no-break space
  before `;`, `!` and `?` and a no-break space before `:` and inside
  guillemets (the Imprimerie nationale's *Lexique*); Canadian French
  before `:` and inside guillemets only (OQLF); every format, not under
  `asciidoctor-compat`.
- Typographic quotes in the text's language's marks, CLDR's, in HTML,
  EPUB, PDF and man pages (FEAT-tlp95q): `„…“` in German, `«…»` in
  French, `「…」` in Japanese; a block's `lang` or the document's; not
  under `asciidoctor-compat`.
- PDF: Korean wraps at spaces, its words whole (FEAT-87x2gw);
  `base_word_break` (`auto`, `keep-all`, `normal`) chooses.
- PDF: Chinese, Japanese and Korean text no theme font has is set in the
  installed Noto CJK face of its language's region (FEAT-stxzq9): Serif
  or Sans beside the text's font, SC, TC, HK, JP or KR by the document's,
  block's or span's `lang`; the missing-glyph warning suggests installing
  Noto CJK when none is.
- PDF: Chinese punctuation by region (FEAT-mcmc8f): mainland Chinese
  sets a line-ending closing mark half wide (GB/T 15834), Hong Kong
  squeezes brackets only, Taiwan none. Two full-width marks in a row are
  squeezed again in embedded fonts (the squeeze had only reached the
  engine's own fonts).
- PDF: `text_transform: uppercase` and `lowercase` follow the text's
  language: a Turkish or Azeri document's headings upper-case `i` to `İ`,
  Lithuanian keeps its dot above (FEAT-8b8z4k).
- PDF: the text's language chooses its fonts' forms (FEAT-7zjk4y): the
  document's `lang`, a block's own `lang` attribute (`[lang=zh-Hant]`)
  and, Ptome's syntax, a span's (`[lang=ja]#直#`, roles beside it) pick
  the font's OpenType language system as HarfBuzz does, so one Noto CJK
  font sets Japanese, Simplified or Traditional Chinese forms, Serbian
  Cyrillic its own б, Marathi its ल and श, Urdu its digits. Not under
  `asciidoctor-compat`.
- PDF: vertical writing, `page_writing_mode: vertical-rl` (Japanese,
  Chinese) or `vertical-lr` (Mongolian) (FEAT-pwq40f): the body's lines
  run down the page, columns following to the left (or right), Han,
  kana and full-width punctuation upright in their vertical forms, Latin
  and digits on their side, ruby at the right, images upright; a
  vertical-rl book is bound at the right; running heads stay across.
- Ruby: `ruby:漢字[かんじ]` (group) and `ruby:東京[とう きょう]` (mono), Ptome's
  syntax (FEAT-2q4rln): `<ruby>` in HTML and EPUB, the reading in
  parentheses in DocBook and man pages, set above its base in the PDF
  (half size, centered, the base copied); text under `asciidoctor-compat`.
  `Ruby` in the API. PDF: emphasis marks, a role's `text_emphasis`
  (`sesame`, `dot`, `circle`... over or `under`), as CSS's.
- PDF: Japanese and Chinese set as JLREQ and CLREQ have it
  (FEAT-x45qvj): full-width punctuation squeezed in pairs, a quarter em
  beside Latin letters and digits, justified lines stretched between
  characters (Thai, Lao, Khmer and Burmese between words), no line
  starting with a closing mark or small kana. Justified Thai was ragged.
- PDF: hyphenation in the newly shaped scripts (TASK-1wlzq5): Hindi,
  Marathi, Sanskrit, Bengali, Assamese, Punjabi, Gujarati, Odia, Tamil,
  Telugu, Kannada, Malayalam, Coptic, Georgian, Ethiopic, Thai and
  polytonic Greek words are hyphenated at their syllables, the hyphen
  drawn (it was hidden at the end of an Indic line; BUG-0rtx6p,
  BUG-9t3kgj), decomposed text as its composed form (BUG-5srx49).
- PDF: justified Arabic is lengthened by kashida inside its words
  before its spaces widen (`base_kashida`, half an em a word by
  default; FEAT-01jjv7); the Medina mushaf (`tool/mushaf.dart`) is set
  with it, its spaces even as the print's.
- PDF: Thai, Lao, Khmer and Burmese lines break between words, found
  as ICU finds them in its dictionaries (FEAT-hpr7b0); they broke only
  where a word was too long for the line.
- PDF: Sinhala, Tibetan, Mongolian, N'Ko, Javanese, Balinese and the
  Universal Shaping Engine's other scripts, Khmer, Myanmar, Thai, Lao and
  Hangul shape as HarfBuzz shapes them; Persian and Urdu (Naskh and
  Nastaliq) too (FEAT-d34wmb, FEAT-3765z4, TASK-68hs2g). A Nastaliq
  paragraph was measured as if left to right and crammed onto one line.
- PDF: the Indic scripts (Devanagari for Sanskrit, Pali, Hindi and
  Marathi; Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada,
  Malayalam) shape as HarfBuzz shapes them (FEAT-g4rmb9); Syriac too
  (FEAT-3765z4).
- PDF: text is shaped as HarfBuzz 14.6 shapes it, in plain_typesetting's
  port of its pipeline (EPIC-yz0yqt): Cyrillic, Greek (polytonic,
  decomposed accents composed or placed), Vietnamese, Armenian, Georgian,
  Coptic and Ge'ez shape glyph for glyph as HarfBuzz does (TASK-nqzrww;
  `doc/pdf.md`, "Scripts"). With `font_fallbacks`, a combining mark stays
  in its letter's font. New engine key `base_text_shaping` (`full`;
  `asciidoctor-compat` sets `right_to_left`, shaping right-to-left text
  alone, as before, since Prawn shapes no other script).
- npm: the package has a `THIRD_PARTY_NOTICES.md` (made by
  `tool/npm_notices.dart` in `tool/build-npm.sh`): the licences of the
  Dart SDK and of every Dart package the bundle compiles in, and the
  notices of the data and code those packages embed or follow (HarfBuzz,
  Unicode, the hyphenation patterns, highlight.js's styles, Brotli,
  RFC 6386, Adobe's font metrics and glyph list, asciidoctor-epub3's
  assets, Font Awesome's icon names).
- PDF: `base_text_align_last: justify` stretches a justified paragraph's
  last line, and each line before a hard break, to the measure. With it,
  `tool/mushaf.dart` sets the Medina mushaf line for line (FEAT-ytfd13):
  604 pages of 15 lines, each ending where the mushaf's does, in the
  KFGQPC Hafs font (see `doc/mushaf.md`).
- HTML and EPUB: a units document's notes beside its text
  (FEAT-bzmqzc). `:note-asides: sn` sets a note stream's footnotes at
  their calls: in a column on the right of the text on a wide screen, the
  entries (cross-references) in one on the left; on a phone, a note opens
  under its line when its call is followed, and the entries are a small
  line above their verse. In EPUB every stream's notes are footnote
  popups, with their `data-stream`. The study edition's cross-references
  are links (to the passages the excerpt holds), and an `:excerpt:` no
  longer warns about the addresses it leaves out. A unit's `label-after`
  is now inside its mark (`<sup>6</sup>&#160;</span>`).
- PDF: an image file drawn many times (a logo in the running content, an
  SVG's raster image on each page) is embedded once (BUG-h9yc30): the
  chronicles example drops from 296 to 187 KB.
- PDF, `asciidoctor-compat`: every PDF case of the corpus now matches
  Asciidoctor PDF pixel for pixel (the red list is empty). New engine
  key `page_layer_clip: page` (set by compat) clips the page's foreground
  image and the running content's background and border to the page, as
  asciidoctor-pdf's stamps are clipped by their bounding box; an SVG's
  viewport is clipped by a path under `svg_placement: page_origin`, as
  prawn-svg clips it; and an image inside an SVG is clipped to its
  viewport only when it reaches past it.
- PDF: GIF, BMP, WebP and TIFF images are embedded (FEAT-c16d1m,
  FEAT-z1rgx9, FEAT-3rvh14, FEAT-9fcj76), read by plain_images, the workspace's own
  image package, in the modern engine and with `compat` alike:
  Asciidoctor PDF warns that GIF is not supported (unless the
  prawn-gmagick gem is installed) and leaves the alt text, and ptome no
  longer imitates that. A GIF or animated WebP is its first frame on its
  canvas, transparent where it has no pixels; a WebP decodes as libwebp
  decodes it, a TIFF (its first page) as libtiff does. Images
  plain_images recognizes but doesn't read (AVIF, HEIC, JPEG XL) are
  reported by name ("could not embed image: x.avif; AVIF images are not
  supported"). Text runs around the opaque
  pixels of any image with transparency (a GIF's transparent color, a
  PNG's or WebP's alpha), not only a PNG with alpha. JPEG and PNG images
  are written byte for byte as before, but for 12-bit, arithmetic-coded
  and lossless JPEG files, which PDF readers can't show as JPEG data:
  they are decoded (FEAT-gzlt7l) and written as other images are.
- PDF: SVG images are drawn by plain_svg, the workspace's own SVG
  package with its own XML reader (FEAT-dqv18q), instead of plain_pdf's
  reader on package:xml: the same PDFs (checked on 1,110 SVG files and
  the 133 documents of the corpus and Hypermedia Systems that use them),
  but that entities an SVG declares are expanded (Illustrator's
  `style="&st0;"` is drawn, as browsers draw it), an SVG that isn't well
  formed is reported in other words (with its line and column), and
  path data with numbers after a close path, a clip path that clips
  itself and an image that shows itself no longer hang or crash the
  conversion.
- Templates (`-T` converter templates, the website's navigation and
  contents, and the text templates documents and themes set) render with
  plain_mustache, the workspace's own Mustache engine, instead of
  `mustache_template` (FEAT-dj39h0): its context is typed (a helper
  returns a `MustacheValue`), and the template code no longer needs
  `Object?`. Output is the same, checked on 200,000 random templates,
  but for `{{.}}` inside an inverted section, which wrote the section's
  name and now writes the enclosing value, as the Mustache specification
  has it.
- PDF: a right-to-left document's pages are mirrored (FEAT-49lks5), the
  theme's left read as the start: page margins, running content (its
  margins and columns: a recto's folio at its outer edge, the left), a
  book for print bound at the right (a recto's inner margin and gutter
  at its right), note stream columns and line numbers, lists marked at
  the right, tables from the right. And a right-to-left line no longer
  runs past its measure: shaped advances are the ones drawn. Left-to-
  right documents are unchanged.
- PDF, modern engine: lines are their text's font height and the
  leading apart whatever fonts they mix (TeX's interline glue,
  BUG-kd9h5p), in the engine's paragraphs and the text box alike, and
  both measure fonts the same way (their `OS/2` typographic metrics): a
  line with inline code or a kbd chip stays on its paragraph's pitch, a
  line of smaller text (a heading's subtitle) doesn't rise into the one
  above, and only text taller than the paragraph's own moves a line,
  by as much. Checked against the previous build: 30 of 1,079 documents
  move, each for one of these (fallback and icon fonts measured as the
  text box measures them, smaller second lines of headings, listings and
  cells mixing fonts) or a page break they move.
- PDF: text in a script no font of the theme has (Arabic in the default
  theme) converts as fast as with a font for it, and one warning lists
  the characters drawn as empty boxes, where no fallbacks were tried
  (BUG-z0xjdy): the units corpus's Arabic Qur'an in 5.8 s, where it ran
  for minutes.
- PDF: Arabic and Hebrew taken from the page (copied, searched, read
  aloud, extracted by pdftotext) read as written: letters drawn from
  shared dotless bases and their dots, and vowels and points moved onto
  their letters, no longer come out as U+FFFD or apart from their words
  (BUG-z5sf9v). The units corpus's Arabic Qur'an extracts verse for verse
  and passes veraPDF's PDF/UA-1 with `-a pdf-ua`.
- PDF: the last text the modern engine left to the text box is the
  engine's too (FEAT-1kwk5y): an abstract's first line in its own style
  (broken by the engine, then transformed and shrunk to fit as before),
  drops and first lines on paragraphs with notes numbered by page, table
  cells with lines from their cap heights, and spans of a fixed width.
  Checked against the previous build on 1,079 documents and 12 fixtures:
  all the same but two, where the text box was wrong. A span of a fixed
  width holding several words is one slot of that width, its text
  centered as its markup says (the box overprinted its words and lost
  some), and a note referred to in a transformed first line is set and
  numbered (the box left it out). A justified first line that a hard
  break ends is no longer stretched.
- PDF: a right-to-left document's contents and running content as before
  the engine set them: each entry's dots from the title to its page number
  at the left, and the running heads and feet on the page's own sides
  (`TextLayout.mirrored`), not mirrored. The units corpus's Arabic Qur'an
  (108 pages) is word for word what it was.
- PDF: a footnote whose reference follows Hebrew or Arabic text is set
  (it was lost), and the notes of a right-to-left line come in reading
  order. Checked on the Aramaic Talmud (Berakhot 2a-4a with Rashi's 114
  notes, a CC BY-NC text kept out of the repository).
- PDF: all the text the modern engine sets is set by plain_typesetting's
  paragraphs (FEAT-3jvkxk): list items, admonitions, table cells, the
  table of contents, headings, title pages, captions, footnotes, kbd
  chips, callouts, and source listings, wrapped with their indent and
  continuation arrows and their logical line numbers. The Prawn-shaped
  text box is left only to compat mode. Checked page by page against the
  previous build on 1,079 documents: 1,053 render the same; the 26 that
  differ break where UAX #14 does rather than at Prawn's characters (a
  thin space after "[", a URL after "/"), set overlong code tokens by
  the paragraph's emergency rule rather than Prawn's, or choose other
  Knuth-Plass breaks around floats.
- PDF: a look's line spacing is exact. `leading: 1.2` sets 10.5 point
  text on 12.6 whatever the face (a look's `leading` now compiles to
  `base_line_pitch` and `<category>_line_pitch` as well as the line
  height, which couldn't set lines closer than the face is tall).
  Visible change: the house look's body text was 10.5 on 18.5 (176%),
  against doc/style.md's 120-145%; it is now 10.5 on 14.7 (1.4), as the
  look says, and its headings and listings follow theirs.
- Oracle comparisons (TASK-s6bbsz, `doc/oracles.md`,
  `tool/oracle_compare.dart`): one fixture set in Ptome, WeasyPrint 70,
  Typst main and ConTeXt LMTX, measured for leaders, running heads,
  footnotes and column balancing. All four agree on leaders, heads and
  footnotes. Typst doesn't balance columns. Ptome's columns end two
  lines apart where its widow and orphan rules allow no closer split.
- Look studies (TASK-66c2mr, `test/look/studies_test.dart`): the
  publisher recipes the looks follow, re-measured from the publishers'
  PDFs (baselines from the glyphs' origins), rendered and checked within
  stated tolerances: the US bill, the EU Official Journal, the O'Reilly
  animal book, the Bell Labs troff books, the Supreme Court's booklet, a
  B-format paperback, a UK Act and a dictionary. The looks corrected to
  fit:
  - us-bill: GPO's grid, the first baseline 85 pt down and 25 lines to
    83 pt above the foot (pages held 22-24 lines); the text to 489.7 pt;
    the page number in 14 point, its baseline at 731.
  - eu-journal: the column from 67.4 to 529.8 pt, 9.6 on 10.55, the
    running head in 9.6 point at 784.4.
  - tech-book: the running foot in 9 point at 42.75.
  - troff: the running head 32 pt above the first line.
  - scotus-booklet: 12 on 14 exactly.
- PDF theme keys: `page_baseline_grid_offset` puts the baseline grid's
  first line that far below the top of the page's text, whatever the
  face (a fixed first-baseline offset). `base_word_spacing` sets the
  spaces between words in the engine's paragraphs as a share of the
  face's (a dictionary's 72%).
- PDF: right-to-left documents (`:dir: rtl`): paragraphs, headings,
  captions and cells set from the right, the theme's alignments
  mirrored, the table of contents mirrored; Arabic and Hebrew shaped by
  the fonts' layout tables, and every line's text in reading order by
  the Unicode Bidirectional Algorithm, in any document (text the old
  text box sets included). The units corpus's Qur'an, all 6,236 verses,
  converts in 13 seconds.
- Looks (ADR-0023, `doc/looks.md`): a document's design in one YAML
  file of tokens, styles of elements and roles, and templates, which
  each output compiles into its own terms (`:look:`, `:looksdir:`).
  The house style is the built-in look `ptome`; the PDF theme is
  compiled from it, byte for byte the PDFs its hand-written theme
  made. A theme a document names still replaces the look, and can
  extend it (`extends: look`). The HTML and EPUB stylesheets are
  compiled from it too (HTML as custom properties, pages rendering as
  before); the EPUB now leaves its body text's alignment and line
  spacing to the reader and hyphenates it.
  `ptome look explain` prints what each token and style became in each
  output (theme keys, custom properties, CSS) and what an output left
  out and why, from the compilers' own results, the ones conversion
  warns of. A look's own `css:` and `epub-css:` come after the device
  rules. A look's title page is a list of slots, recto and verso, after
  DocBook XSL's (`templates.title-page`): the PDF's title page and a
  verso page (`title_page_recto`, `title_page_verso`, also for themes),
  HTML's header in their order, and an EPUB title page.
  Named looks, measured from the books they follow: `troff`, the Bell
  Labs manuals set with troff (Times 11/12 on a 4.8 in measure, code in
  Courier indented half an inch, a 6.25 × 9.25 in trim). A page may be a
  trim (`page.size: [6.25in, 9.25in]`); an indented paragraph look
  indents a paragraph after another alone (`prose_text_indent_inner`).
  `ptome doctor --look LOOK` installs a look's fonts too (TeX Gyre from
  CTAN, pinned; Google Fonts families).
  `tech-book`, the O'Reilly animal books (a 7 × 9.1875 in trim, body
  10.5/12.6 on 30 pc, semibold condensed headings, code 8.5/10.2
  indented 17 pt, a running foot, notes between rules, a copyright
  verso). A look's `webfonts` are loaded by its HTML pages.
  Statutes: `us-code` (two columns of 8/9, catchlines in bold, sections
  in the running head), `eu-journal` (one column of 9.6/10.5, centred
  italic article headings) and `uk-act` (11/12, bold section headings,
  italic running heads). A heading's number (its title's `[.number]`
  span, from a unit scheme's title template) hangs in the margin or
  stands on a line of its own (`number: hang | line` in a look,
  `heading_number_placement` in a theme): the UK Acts' and the
  Journal's headings. A face's family may be a font stack.
- PDF: a section or open block with the role `columns` sets its content
  in balanced columns from where it starts (`columns_count`,
  `column-count`; modern engine). A paragraph's role may set its own
  first letter as an initial lines deep (`role_<role>_drop_lines`),
  opening punctuation hung, lead-in words in the role `lead-in`. A
  paragraph beside a block floating to a side (`role_<role>_float`: a
  pull quote, a sidebar) runs around it, its rest set again at the full
  width below it. A section whose role has page keys
  (`section_role_<role>_page_margin`, `_page_background_color`,
  `_page_background_image`, `_page_running_content`, `_page_columns`) is
  set on pages of its own, laid out by that page template.
- Text runs around an image's outline: a floated PNG with `shape=alpha`
  (or a role floated with `float_shape: alpha`) is a cutout, its opaque
  pixels' edge what the lines beside it follow, in the PDF line by line,
  on the web as a `shape-outside` polygon computed from the image.
- The website's navigation bar (`multipage_html5`) is laid out in the
  house style: a ruled row in the text's column, the link on at the right.
- Jump lines: a `[.jump]` paragraph that is a cross reference alone says
  where a piece goes on, or came from: "Continued on page 7" in a PDF
  (the page known once laid out), "Continued in The Science" on the web
  (`jump-template`).
- PDF thematic breaks as a mark (`thematic_break_content`: a dinkus, a
  fleuron, an image), or as space with the mark only where a break falls
  at the top or the bottom of a page (`content_display: boundary`).
- The `trade-novel` look: a B-format paperback of fiction, its chapters
  opened on a recto by an initial and a lead-in in small capitals
  (`heading_h<n>_initial_lines`), scene breaks one line on the baseline
  grid, running heads in letterspaced small capitals.
- The `scholarly-monograph` look: a university press's 6 × 9 in book,
  its margins the measured profile's, extracts and notes 9 on 11, and a
  run-on index in two columns (`index_layout: run-on`: a term's
  subterms after semicolons in its own paragraph, Chicago's run-in
  style).
- The `us-bill` and `uk-bill` looks: a bill of the US Congress (every
  line numbered on a 26 pt grid, each level 2 em in) and of the UK
  Parliament (every fifth line numbered at the right, the labels hung),
  measured from H.R. 2 and HL Bill 81. Units that are blocks take a
  level's indent and space above (`units_<level>_margin_left`,
  `_margin_top`), and `units_<level>_label_hang: true` hangs a level's
  labels in any block.
  The US bill's slug at the foot (`:bill-slug:`), and the UK bill's
  numbers flush right: `line_numbers_align` and `line_numbers_width`.
- PDF streams and EPUB entries are compressed by plain_compression on
  every platform (ADR-0024): the same document makes the same bytes on
  the VM, Node.js and the web, whatever the CPU or the SDK's zlib. The
  JavaScript host no longer needs Node.js's `zlib`.
- Man pages: `:man-semantic:` writes man(7)'s own macros, `.UR`/`.UE`,
  `.MT`/`.ME`, `.IP` and `.TP`: links that click in mandoc's HTML and
  groff's terminal output, list numbers apart from their text, terms
  with anchors. Off by default and under asciidoctor-compat.
- HTML: the house look's prose hyphenated in the document's `lang`
  unless the document unsets `hyphens` (`:hyphens!:`, its body then
  `nohyphens`), as the PDF's modern engine; its last lines balanced
  (`text-wrap: pretty`),
  old-style figures and hung punctuation where the browser and face can,
  headings balanced; the measure 75ch (the old 42em in the face's own
  characters). Browsers without a property ignore it; compat output is
  unchanged.
- The `docs-site` look: a documentation site, code first, its contents in
  a sidebar (`:toc:`), admonitions tinted by type, and a dark mode.
- `:quotation-lint:` (PDF): a quotation of a hundred words or more run
  in, or a block quotation shorter than five lines, is reported (Chicago
  13.9), for the scholarly-monograph look's books.
- `-a pdf-ua` (modern engine): a tagged PDF conforming to PDF/UA-1, its
  structure tree recording headings, paragraphs, lists, tables (header
  cells with their scope), figures with their alternate text and links,
  running content and backgrounds as artifacts, the language given
  (`en` by default) (FEAT-cs3j22). veraPDF finds the Hypermedia Systems
  book conforming. The text box no longer draws an anchor's placeholder
  (an invisible `.notdef` that took room on the page).
- The modern engine's paragraphs (plain_typesetting's) now also set
  paragraphs with protrusion (`base_overhang`), font expansion and
  `base_text_align_last`, and break each paragraph as the text box would
  (ragged, centered or justified, at its own size, `base_line_breaking`
  too), on a baseline grid as well, with labels hung beside their lines
  (units' `label_hang`, `heading_h<n>_display: margin`), with lines from
  their cap heights (`base_leading`) and justified to their widest line
  (`base_justify_width: widest`), running around a block floating to a
  side and an image's outline, with side notes beside their lines, with
  drop initials (a role's `drop_lines`, a section's
  `heading_h<n>_initial_lines`), an abstract's first line in its own
  style, inline images and formulas, text on a background or in a
  border, and small capitals made from capitals; and headings, captions
  and table cells' text are set by them too. Every word where the box
  puts it
  (test/pdf/engine_paragraphs_test.dart). The Hypermedia Systems book's
  paragraphs go through the engine (313 pages, the same words); its lines
  differ from the box's only where the engine is right and the box isn't:
  a paragraph split across pages keeps its own breaks (the box breaks its
  rest again), no line starts with a comma, and a code path may break
  after a slash before digits (Unicode 15.1's line breaking). A line
  mixing fonts (inline code) is as tall as its tallest ascender and
  deepest descender, where the box took its tallest font's height, and a
  formula taller than its text makes its line taller, where the box let
  it reach into the line above. A footnote's
  number on its page (`footnotes_numbering: page`) keeps its paragraph in
  the box for now.
- Units note streams: `entry-first-in` and `entry-heading` head the first
  entry under each unit of a level (`Chapter {{chapter}}` over each
  chapter's cross-references), so the entries can give the verse alone;
  the study Bible's scheme does.
- The `federal-register` look: a Federal Register document (measured
  from 89 FR 47855) in three columns, its agency block, run-in
  captions and footnotes at the foot of their column. New: the
  `folio-start` attribute (pages numbered within a volume),
  `footnotes_placement: column`, `<category>_line_pitch` (a heading's
  or the notes' lines a pitch apart, as `base_line_pitch` the body's),
  `role_<role>_hyphens: false`, `description_list_term_suffix`.
- PDF margins from a rule: the classical canon (`page_margin_canon`),
  KOMA-Script's DIV and binding allowance with whole lines
  (`page_margin_div`, `page_margin_bcor`), profiles measured from books
  (`page_margin_profile`), and a gutter that grows with the page count
  as KDP's minimums do (`page_margin_gutter: kdp`); with `media=prepress` a rule's
  inner and outer margins come before the theme's `page_margin_inner` and
  `_outer`.
- The modern engine's plain paragraphs are set by plain_typesetting's
  paragraphs (`base_text_engine: paragraph`, the default; `box` for the
  text box), their lines where the text box would set them; paragraphs
  with what the engine doesn't do yet stay in the text box.
- PDF headings in the margin (`heading_h<n>_display: margin`): a
  reader's edition's chapter numbers beside the first line, the
  `readers-bible` look's now. A run-in note stream's separator in a face
  without the em space is no-break spaces of its width, not a missing
  glyph.
- A study Bible's page from open data, set as the Reformation Study
  Bible's samples (`test/units/corpus/themes/rsb-study-theme.yml`), with
  its acceptance and verdict in `doc/study-bible.md`. The Bible looks set
  the divine name in small capitals by `font_variant` (the face's, or
  made from its capitals), not Unicode's small-capital letters, which few
  faces have.
- PDF unit labels bold (`units_<level>_label_font_style`) and hung left
  of their lines in blocks with given roles (`units_<level>_label_hang:
  [poetry]`: a poem's verse numbers in the gutter); side notes in the
  inner margin (`side_notes_column: inside`).
- PDF: a block with a role can float to the top or the bottom of the
  page, across its columns (`role_<role>_float: bottom`,
  `_float_scope: page`), and a sidebar's body can be set in columns
  (`sidebar_columns`): a study Bible's feature articles, tinted boxes
  between the text and the notes.
- The units corpus has a study edition (`bible/bsb-study`, Genesis 1–3
  and Mark 1): the Berean Standard Bible with its translators' notes,
  OpenBible.info's cross-references and Tyndale Open Study Notes, made by
  `tool/import_study_bible.dart`, and a study Bible's theme for it.
- The `reference-bible` and `readers-bible` looks: two columns with the
  cross-references between them, chapter numbers dropped into the
  first verse, light verse numbers and the page's verses in the running
  head; or one column without verse numbers or cross-references. New
  PDF keys: `units_<level>_label_font_color`, `_display: none`.
- The `scotus-booklet` and `pleading` looks: a Supreme Court brief by
  Rule 33.1, a California pleading by the Rules of Court (28 numbered
  lines, a double line beside them, the court's title on line 8). New
  PDF keys for them: `base_line_pitch` (the body's lines a length
  apart), `role_<role>_grid_line` (a paragraph on a line of the
  baseline grid), `line_numbers_rule`.
- The `critical-edition` look, after the Oxford Classical Texts: margin
  line numbers counted from each Stephanus section or Bekker column, the
  labels in the margin only (`role_<role>_display: none` leaves a role's
  phrases out of the PDF's text), and the apparatus run in at the foot
  without marks in the text (a note stream's `_reference_content`).
- PDF notes in step with their text (`footnotes_text_min_lines`,
  `footnotes_lag`): the least text a page with notes keeps, and how many
  pages after its reference's a note may start, for a study Bible's notes
  far longer than its verses.
- PDF note streams for a study Bible's foot: a note that opens with a
  `[.heading]#…#` has it as a heading above it (`footnotes_heading_*`,
  `note_stream_<name>_heading_*`); notes carried to the next page go on
  in their own stream and columns.
- Optimal pagination in the PDF (`pagination: optimal`): the pages' breaks
  chosen together, the unused room spread rather than one nearly empty
  page.
- `:index-sort:` orders the index by The Chicago Manual of Style's
  letter-by-letter or word-by-word system, in every format.
- The PDF's line breaker counts protrusion (with `base_overhang`) and
  avoids runts (`base_last_line_min_width`): a last line too short only
  when there's no other way.
- EPUB: `epub-font-families` embeds a document's own faces besides the
  stylesheet's (and, with embedded fonts, its look's), each with its
  `@font-face` rules.
- Note streams run in (`note_stream_<name>_arrangement: run_in`, one
  paragraph a page, as an apparatus) or in a margin column of their own
  (`note_stream_<name>_column`, each note beside its reference: a
  Talmud page's commentaries).
- Line numbers restart at units (`line_numbers_restart_units`), their
  labels in the margin (Stephanus sections, Bekker columns); a baseline
  grid may start at each page's first line
  (`page_baseline_grid_anchor: first_line`), as a US bill's page that
  opens with a heading holds a line more.
- A page frame in the PDF (`page_frame_*`): rules around the text area,
  an Oxford rule's thick and thin; the 1970s magazine look has one in
  print as on the web.
- Conversions in one process (batch, serve) share the machine's font
  index and each installed font parsed once (its shaper and kerning); a
  conversion's own fonts are layered over the index.
- Running content in units: `{page-first-<level>}` and
  `{page-last-<level>}`, each level's label at the page's first and last
  unit, for heads of a form of their own.
- Microtypography in the PDF: font expansion in the line breaker
  (`base_font_expansion`, microtype's 2%, the letters' share of a line's
  adjustment set by horizontal scaling), a limit on hyphenated lines in a
  row (`base_hyphenate_limit_lines`), and protrusion at the left of
  justified lines with `base_overhang`.
- Tracking in the PDF: `<category>_letter_spacing` (a heading, a role, a
  title page part), a look style's `tracking` (CSS `letter-spacing` on the
  web), and `caps_letter_spacing`, which letterspaces words in capitals
  and small capitals by themselves (microtype's 0.05 em), half the space
  outside the word, word spaces widened with it. The magazine looks'
  kickers are tracked in print.
- Note streams at the foot of the PDF's page apart from the footnotes
  (`note_streams`, `note_stream_<name>_*`): each units stream under its
  own separator, by its caller, in its own size and columns (a critical
  apparatus); the footnotes are numbered without them.
- Line numbers in the PDF's margin (`:line-numbers:` `typeset`,
  `logical` or `grid`; `line_numbers_*` theme keys): every line or every
  nth, restarting each page, section or never, the lines the text is set
  in (a bill's), the source's (a wrapped verse line counted once) or a
  fixed grid (pleading paper).
- A baseline grid (`page_baseline_grid`, a look's `page: { grid: true }`):
  the body text's lines keep to a grid a body line apart, in every
  column and on every page, each paragraph starting where its first
  baseline falls on it (the space before it rounded up), so lines match
  on the two sides of a leaf of thin paper.
- The magazine website (`doc/magazine.md`): a role vocabulary for a
  piece's parts (kicker, hed, dek, byline, dateline, lede, dropcap,
  pullquote, caption-lead, columns, end; aligned with IPTC NITF and
  Apple News Format) and looks that set them as a print magazine of an
  era (`magazine`, `-1950s`, `-1960s`, `-1970s`, `-1980s`, `broadsheet`,
  `compact`): a twelve-unit grid, the kicker, credit and issue lines
  from attributes (title page slots), runarounds, drop caps, pull
  quotes, bounded column sections, end marks, a thick-and-thin frame,
  each device with a fallback; one column on a phone. Looks' lengths
  may be `rem`. Each era is a print design too: its page size,
  columns (balanced where the piece ends, hairlines between them in
  some), faces (installed by `ptome doctor --look`, optical sizes
  included), the head, dek and byline across the top of the piece's
  first page (`title_page_inline`), pull quotes styled by
  `quote_role_<role>_*` keys, and a folio. In columns a block floats to
  a side within its column, and a soft hyphen ending a line is a hyphen
  in a font that has none. A theme's font family keeps a measurement in
  its name (`Bodoni Moda 28pt`).
- The ptome language: texts cited by numbered units (ADR-0019, ADR-0020,
  `doc/units.md`), read by ptome's own parser and rendered by every
  backend.
  - A document that names schemes (`:units: bible, kjv`, YAML files in the
    nearest `schemes/` directory) can write:
    - unit markers: `@`, `@@`, `@6`, `@(a)(1)`, bridges, `@^`, attributes;
    - ranges `[name}` … `{name]`;
    - note streams `note:x[…]`, placed as footnotes, entries or after the
      unit;
    - references by address (`<<Ps 86:15; 103:8–13>>`);
    - includes by ID and by address, with citations made from the work;
    - `[annotations]`, `[overlays]` and speeches;
    - defined terms, apparatus roles and term rules.
  - Ptome works out every unit's anchor, label and reftext. Labels out of
    sequence are warnings. How units look is in the scheme files, as text
    templates, styles and roles (scheme format 2).
  - `-a units-as-of=DATE` gives a statute as in force on that date, and
    `-a units!` reads a units document as plain AsciiDoc.
  - `ptome check FILE...` reads documents without converting them.
  - `include::text.adoc[parallel=translation.adoc]` sets two documents in
    one scheme side by side, unit by unit, matched by address.
  - `Document.units`, `Document.unit(idOrAddress)` and
    `Document.passage(address)` give the units in the Dart and JavaScript
    APIs: each `Unit` has its scheme, level, labels, ID, reftext, citation,
    source line, parent, children and notes; references by address and
    defined terms too. Units are nodes of their own in the tree
    (`UnitMark`, `NoteCall`, `NoteEntry`, `UnitBlock`) and in every
    backend (semantic HTML: `class="unit"`, `data-unit`).
  - `ptome check --format=json --list` reports units and problems (each
    with its kind, file, line and column) to tools.
  - The units corpus (`test/units/corpus`, from the loci experiment): 23
    real documents (the KJV, the Qur'an, suttas, Greek classics, liturgy,
    a hymnal, a catechism, US, EU and UK law, a specification) and a
    commonplace book quoting them, each with its units model frozen and
    tested (`test/units/corpus_model_test.dart`); it agreed with the first,
    preprocessing implementation's before that was removed.
  - Documents without `:units:` or `:works:` are unaffected.
- Follows Asciidoctor's development version (upstream `main` at
  `30fb8cd5`, 2.1.0.alpha.0) rather than the 2.0.26 release: the CLI's
  `--log-level` and `--sourcemap`; highlight.js `nohighlight`; `linenums` as
  a block option; ordered lists that start at their first marker; empty
  section IDs; the `~~~~` open block; a block style above the title keeping
  it in the body; block attributes overriding `imagesdir`; `cxx`; attribute
  lists in formatted text without `[`; dot-free attribute names; inline image
  IDs; `link=self`; Wistia videos; per-section `toclevels` and multipart
  outlines; table and column widths as attributes; page and thematic break
  classes; no generator meta with `reproducible`; DocBook quote roles; man
  page lists and table cells without spurious `.sp`; front matter with
  `+++`, skipped per include; a warning for URI includes without
  `allow-uri-read`; the main branch's stylesheet and locales. The corpus
  (17,900 conversions) is identical to the gem built from that commit.
- Fixes 25 bugs reported upstream that Asciidoctor (upstream `main` at
  `30fb8cd5`) still has, chosen by triaging
  all 610 open upstream issues (`doc/upstream-triage.md`). Each fix has a
  test in `test/upstream_fixes/` (what ptome's output must contain where
  the gem's shows the bug), and the output differences are listed in
  `benchmark/PARITY.md`: section IDs for punctuation-only titles and titles
  with footnotes; nested fonts in man pages; table cells after colspans and
  beside rowspans taking the right column spec, invalid column specs, tabs
  in literal cells and comments in AsciiDoc cells; `X//..` in paths;
  assigned author names; links in superscripts; icons in link text; `\]` in
  anchor reference text; anchors in section titles; em dashes next to
  formatted text and curved quotes; URLs ending in `>`; paragraphs that look
  like attribute lines; ancestor list continuations; headings beyond `<h6>`;
  quotes in image attributes.
- Documents that stop Asciidoctor convert, found by the corpus's fuzzer
  and pool: a table has at most 1000 columns and a cell spans at most 1000
  columns and 65534 rows (HTML's limits), where the gem builds as many as
  asked until memory runs out; a span of zero is no span; a man page table
  whose rows were all dropped, and AsciiMath with an unclosed `"`. An
  index term without words indexes nothing in DocBook.
- The test corpus (ADR-0022): about 1,700 documents with the files the
  Asciidoctor 2.0.26 command line writes for them (asciidoctor-pdf's PDFs
  and asciidoctor-epub3's EPUBs too); ptome with `asciidoctor-compat` must
  write the same files, PDFs compared by their pages pixel for pixel.
  Compatibility is settings of the engine, such as `base_glyph_widths:
  thousandths` (a glyph as wide as its advance in whole thousandths of the
  em).
- Converts AsciiDoc to HTML 5, DocBook 5 and man pages. Output is
  byte-identical to the Asciidoctor gem (built from upstream `main` at
  `30fb8cd5`) on every backend, apart from the bugs fixed, as the
  parity gate (`tool/parity.sh`, retired for the test corpus) found it on
  every backend; the end-to-end
  CLI suite (134 tests) passes against both Ptome and the gem.
- A small, typed public API designed from usage scenarios
  (`doc/api.md`): a `Ptome` configuration (safe mode, attributes,
  extensions, an HTML override, highlighters, Mustache templates) with
  `parse`, `parseHeader`, `convert` and asynchronous variants; the default
  configuration `asciidoc`; a sealed tree of typed nodes (`Section`,
  `Paragraph`, `Listing`, `Admonition`, lists, tables, inline elements)
  with `descendants<T>()` and `plainText`; inline content as a typed tree
  (`inlines`, `titleInlines`: text and formatted text, links, images...,
  nested; ADR-0008); typed attributes; source-preserving edits of header
  attributes (`withAttribute`, `withoutAttribute`: only the entry's lines
  change); an EPUB 3 backend in the native executable (`-b epub3`), the
  same EPUB as the asciidoctor-epub3 2.3.0 gem file by file (ADR-0009);
  diagnostics
  collected per document; callback-based extensions (`InlineMacro`,
  `BlockMacro`, `CustomBlock`, `IncludeResolver` (may be asynchronous),
  `TreeProcessor`, `Preprocessor`, `Postprocessor`, `Docinfo`).
  `package:ptome/ptome.dart` has no file system access and runs on
  the web; `package:ptome/io.dart` adds `parseFile`, `convertFile` and
  `convertTree`; `package:ptome/cli.dart` runs the command line with a
  configuration compiled in. Everything else is private;
  `tool/api_surface.txt` records the public API and CI checks it.
- A PDF backend (`-b pdf`, native executable) that converts as the
  asciidoctor-pdf 2.3.27 gem does and reads its YAML themes unchanged, drawn
  with plain_pdf (Ptome's own pure-Dart PDF library; no Prawn code). It
  covers:
  - title pages, covers and backgrounds (PDF pages included);
  - running content;
  - tables, images (raster and SVG), icons and admonitions;
  - the table of contents, the index, footnotes and outlines;
  - `media=prepress` books (recto starts and inner and outer margins) and
    man pages.

  By default the layout is Ptome's own: justified and left-aligned
  paragraphs are broken by Knuth and Plass's total fit with TeX's costs
  (even spacing, few hyphens, an emergency-stretch pass; ragged lines
  with even ends), other text one line at a time, never inside a word at
  a style change, and
  hyphenated in the document's language (hyph-utf8's patterns, 72
  languages; `:hyphens!:` turns it off; code spans stay whole; a word
  across formatting hyphenated whole), a compound's hyphen repeated at
  the next line's start in Portuguese, Spanish and the other languages
  whose orthography has it so, URLs broken where The Chicago Manual of
  Style breaks them (after `//` and colons, before slashes, periods and
  the other separators, around `=` and `&`), punctuation hung into the
  margin by microtype's protrusion amounts (`base_overhang`), and a
  paragraph leaves at least two lines on either side of a page break
  (`prose_orphans`, `prose_widows`). Text is kerned by the font's GPOS
  pairs and set with its standard ligatures (`base_font_ligatures: none`
  turns them off), emphasis inside italic text is upright
  (`base_emphasis_inversion`), and paragraph indents may be given in
  `em` or `rem`. Listings split only between lines, leaving at least two
  on either side of a page break (`code_orphans`, `code_widows`); a line
  too long for the block wraps with a return arrow past its end and a
  hanging indent (`code_wrap_marker`, `code_wrap_indent`); a caption
  stays with its block; and text in a column too narrow for a single
  character is set anyway rather than dropped. Callout markers are left out
  when code is copied (marked content with an empty ActualText) and link
  to their callout list items, which link back. Blank pages (before a
  recto start) carry no running content unless
  `running_content_on_blank_pages` is true. Tables with a role take the
  theme's `table_role_<role>_*` keys, and a cell whose text is a phrase
  with a role, `table_cell_role_<role>_*`. `base_line_breaking: optimal`
  optimizes ragged text too, `greedy` breaks any text one line at a time. `doc/pdf.md` lists every setting. With `asciidoctor-compat` (or
  `-a pdf-compat`) the settings default to asciidoctor-pdf's look: 792 of
  the 797 documents of the gem's spec suite look the same, page image
  against page image (`benchmark/PARITY.md`), 6 to 15 times faster than
  the gem (`benchmark/BASELINE.md`). `hyphens` and `base_hyphens`
  hyphenate as the gem does with text-hyphen.
- The index in HTML and EPUB: an `[index]` section lists the document's
  index terms by letter, with subterms, see and see-also references, and a
  link to each section a term is used in (Asciidoctor renders it empty;
  `index-html!` keeps its output). `Document.index` gives the same as typed
  `IndexLetter` and `IndexEntry` values.
- A `multipage_html5` backend (native executable): a book as a website,
  one page per part and chapter (`multipage-level` for deeper sections),
  a home page listing them, previous, up and next links, cross references,
  the TOC, the index and callout links rewritten across pages, footnotes
  on the page they are on.
- Valid DocBook and EPUB where Asciidoctor's output isn't (unbalanced
  emphasis around index terms, section styles DocBook has no element for,
  emphasis in literals, invalid image widths, an empty TOC title, links
  from a website's root): the Hypermedia Systems book validates against
  the DocBook 5.0 schema and passes EPUBCheck.
- `asciidoctor-compat` (ADR-0015) keeps Asciidoctor's look while
  migrating, for every format or a list (`html`, `epub`, `docbook`,
  `manpage`, `pdf`): an attribute, the `PTOME_COMPAT` environment
  variable, `compat:` in a project's `ptome.yml` or in
  `~/.config/ptome/config.yml`.
- Math in the PDF: AsciiMath and LaTeX math are typeset (ADR-0014), inline at the
  text's size and in display style in STEM blocks, by plain_pdf's math layout
  (the OpenType MATH table's rules) in the bundled Noto Sans Math or the
  theme's `math_font_family`; copied, a formula gives its source. The
  AsciiMath and LaTeX converters live in plain_math (ADR-0018), checked
  against the asciimath gem, Temml and KaTeX; LaTeX's `\text` reads TeX's text
  mode, including `$...$` math in it.
- Old-style numerals and small capitals from the font's OpenType
  features (`base_font_variant_numeric: oldstyle-nums`,
  `role_<role>_font_variant: small-caps`), in the modern PDF engine.
- Books in the modern PDF engine: footnotes at the bottom of the page
  (`footnotes_placement`), links' URIs as footnotes
  (`show-link-uri=footnote`), chapter and part openers without running
  content and with their label on a line of their own
  (`heading_h2_content`, a template), `noheader` and `nofooter` on a section,
  floating images (`image_placement: auto`), sections with a styled role
  in a box (`section_role_<role>_*`), an index with each page once and
  page numbers in a column
  (`index_pagenum_text_align`, `index_category_headings`, `index_font_*`),
  and source code highlighted by plain_highlighting in a highlight.js theme
  (`source-highlighter=highlight.js`, `highlightjs-theme`).
- What a reference Bible needs, from theme keys any book can use: a book
  in columns with its chapter headings across them and each chapter's
  columns balanced (`page_columns`), running content from the first and
  last marks on the page (`running_content_marks`, `{page-first-mark}`),
  headings set as drops beside the first lines (`heading_h<n>_drop_lines`),
  figures that span the columns (`image_scope`), and phrases with a role
  set beside their line in the center column or the outer margin
  (`role_<role>_display: side`, `side_notes_column`).
- Layouts no PDF library we know of makes: a sidebar that floats beside
  the text (`role_<role>_float`) and goes on at the top of the next page,
  through the repeated banner there (`heading_h<n>_repeat`), the blocks
  beside it narrowed or, where they don't fit beside it, set below it;
  banners (`heading_h<n>_background_color`, negative side margins), rules
  of rounded bars under headings (`heading_h<n>_rule_*`), shadows and
  background images on framed blocks, and role keys for example blocks
  and sidebars (`example_role_<role>_*`, links in them included).
- Generated text from templates (ADR-0010): caption numbers
  (`<kind>-caption-template`, `appendix-caption-template`) in every
  format, footnote markers (`footnote-reference-template`,
  `footnote-label-template`; the PDF's `footnotes_reference_content`,
  `footnotes_label_content`), callout markers, headings, running content
  and contents entries in the modern PDF engine (`{{number}}`,
  `{{title}}`, optional parts), and the website's navigation and list of
  pages (`multipage-nav-*-template`, `multipage_nav.mustache`,
  `multipage-toc-entry-template`). The website: a `toc::[]` macro takes
  the list of pages (a contents page), `multipage-page-toclevels` puts a
  page's own sections at its top (`multipage_toc.mustache`), the list's
  entries carry the section's kind and roles as classes. The `notoc`
  option leaves a section out of the contents; `epub-unique-identifier:
  isbn` makes the ISBN the EPUB's identifier. In the modern PDF engine,
  a styled section role can sit in the middle of its page
  (`section_role_<role>_vertical_align`), a paragraph role has its own
  indent and space below (`role_<role>_text_indent`, `_margin_bottom`),
  a sidebar's title its own space below (`sidebar_title_margin_bottom`).
- Print: `pdf-standard=PDF/X-4` with an output intent
  (`pdf-output-intent`, the printer's ICC profile), a bleed from the
  theme (`page_bleed`), and a layout report of the blocks that break
  across pages (`pdf-layout-report`), with preflight messages.
- `--progress` reports each phase of a conversion as it finishes; the
  modern PDF engine's layout warnings name the source line of the block.
- `callout-links`: callouts and their list items linked both ways in HTML
  and EPUB, markers kept out of copied code, and warnings for callouts no
  list item explains.
- Remote content (`allow-uri-read`): `parseAsync` and `convertAsync` fetch
  includes and data-URI images, honoring `cache-uri`.
- The `ptome` command takes the options of the gem's `asciidoctor`
  command, except the Ruby-specific `-r`, `-I`, `--eruby` and `-w`.
  Messages start with `ptome:` and read like a Dart tool's
  (`benchmark/PARITY.md`); `--version` names Ptome and the Asciidoctor
  release it is compatible with; `man/ptome.1` documents it.
  `init-config` generates a project for a custom command with Dart converter
  functions compiled in.
- Syntax highlighting with highlight.js at conversion (plain_highlighting, a Dart port
  of highlight.js 11.12.0); `highlightjs-mode=client` gives Asciidoctor's
  browser-side markup. Rouge, Pygments and CodeRay behave as when their gems
  are missing.
- Custom converters: Mustache templates (`-T`, `templateDirs`) and HTML
  overrides in Dart, in place of Ruby's Tilt templates (ADR-0002).
- `{asciidoctor-version}` (and `asciidoctorVersion` in the API) report
  2.1.0.alpha.0, so documents written for Asciidoctor keep working;
  `{ptome-version}` (`ptomeVersion`) reports Ptome's version,
  which also appears in the HTML generator meta tag and the man page
  header.
- The compiled command converts 5–10x faster than the gem end to end, and
  about 2x faster in process (`benchmark/BASELINE.md`).
- Text outside Latin-1 no longer falls off a cliff: each inline pass is
  tried only where it can match, and its guards are answered from the
  characters a paragraph holds. The KJV converts to HTML in 0.9 s instead
  of 10.5 s (Ruby: 2.2 s), Greek *Ethics* in 42 ms instead of 688 ms. Text
  boxes in the PDF keep their placements and line breaks across the
  layout's probes and passes: the whole KJV as a PDF takes 11.8 s instead
  of 27.4 s, in half the memory.
- Fonts are the machine's, not compiled in: the PDF backend finds a
  theme's fonts among the installed ones (by file name, then by family;
  `PTOME_FONT_PATH` adds folders), falls back to the built-in PDF
  fonts with a warning when one is missing, and `ptome doctor`
  checks the built-in themes' fonts and downloads the missing ones from
  Google Fonts and their projects into the user's font folder. An EPUB
  embeds fonts only with `-a epub-embed-fonts`. The executable is 14.9 MB
  instead of 31.5 (the highlighting languages are compressed data, not
  code; the npm bundle is 1.57 MB).
- PDFs and EPUBs through the API and on JavaScript: `convertToBytes`,
  `convertToBytesAsync` and `convertFile` with `Backend.pdf` or
  `Backend.epub3`. Fonts can be given as bytes (`fonts`). The npm package
  loads the PDF and EPUB code on demand, so pages that only make HTML
  don't download it, and its command makes PDFs and EPUBs as the native
  one does. On Node.js, installed fonts come from the font folders. In a
  browser, the page's web fonts are used (`pageFonts`), and so are the
  visitor's installed fonts of the families asked for (`localFonts`,
  through Local Font Access). In a browser, the images and the theme a
  conversion reads are fetched relative to the page (includes are not).
  WOFF and WOFF2 fonts work everywhere fonts do. EPUBs also work in a browser without a host zlib: they are
  compressed with plain_compression's deflate there (the Dart VM and
  Node.js keep their zlib), and ZIP reading and `.gz` man pages use
  plain_compression on every platform. Font reading and the installed-font
  index live in plain_fonts, compression and ZIP in plain_compression,
  both in this workspace (ADR-0018). The PDF converter lays out with
  plain_typesetting (shaping, paragraphs, pages, math), which draws on
  plain_pdf's canvas.
- PDFs are the same on every run when sections have no ids (`sectids`
  unset): their destinations were named after a hash code that changed
  from run to run; they are numbered in order (`__section-1`...).
- Speed on every core (ADR-0016): the work a PDF or EPUB doesn't need in
  order (PNG images, compression) runs on the physical cores (`-a
  jobs=N`, `1` for none), with the same bytes at any number of workers;
  the index and page-numbered footnotes lay out again only from the
  pages they change; line breaks are kept per paragraph. The Hypermedia
  Systems PDF takes 2.1 s, from 3.8 s; `-j` batches
  run on the same pool, each worker taking the next file as it finishes
  one, with every backend the executable has (PDF and EPUB included).
- The same core builds as the npm package `ptome` for Node.js and
  browsers (ADR-0005). Its API is generated from the Dart API, with the
  same names and shapes, plus TypeScript declarations
  (`tool/generate_js.dart`, ADR-0007).
