# ADR-0023: Looks: One Design File, Every Output

**Status:** Proposed on 2026-10-11 (lane TASK-t24g6w, EPIC-x68zbv).
Builds on [ADR-0010](0010-output-templates.md),
[ADR-0011](0011-house-style.md) and
[ADR-0013](0013-typst-derived-options.md); leaves
[ADR-0015](0015-asciidoctor-compat.md) as it is.

## Context

ADR-0011 gave every format one house style. Today it is written three
times, by hand: as the PDF theme `data/pdf-themes/ptome-theme.yml` (92
lines of asciidoctor-pdf keys), as the HTML overlay
`data/stylesheets/ptome-house.css` and as the EPUB overlay
`ptome-epub3-house.css`, with `doc/style.md` as the table that says they
agree. Nothing checks that they do, and a change to one is a change to
remember in the others. A new look (the troff-era manual, the tech book,
a statute, a magazine era: TASK-jbw2vx, TASK-b2qvkf, TASK-d0359h,
EPIC-kzdb6h) would be written three times again.

Prior art agrees on the shape:

- **DocBook XSL** splits a look into scalar parameters, attribute sets
  and template overrides, and its title pages are data: recto and verso
  slot lists per element (`fo/titlepage.templates.xml`).
- **Quarto's `_brand.yml`** is one YAML file of colors (a palette, then
  roles such as `foreground` and `primary`) and typography (`fonts`,
  `base`, `headings`, `monospace`) that its HTML, Typst and dashboard
  formats all read. It is, in its own words, "by design incomplete for
  any given output format": each format uses what applies to it.
- **asciidoctor-pdf** overlays YAML theme files in `extends` order, with
  variables and arithmetic, and styles roles by key (`role_<name>_*`).
- **Pandoc** feeds the same template variables (`mainfont`, `fontsize`,
  `linestretch`, `linkcolor`) to its LaTeX and HTML templates.
- **The W3C Design Tokens format** (Community Group report 2025.10,
  the first stable version) exchanges tokens between tools as JSON
  (`$value`, `$type`): colors, dimensions, font families and weights,
  composites such as typography.

The research behind ADR-0021 ("Named looks are parameter files over three
theme levels") draws the conclusion for ptome: a format-neutral token
file, compiled into PDF theme keys, CSS custom properties and man-page
style maps, each output dropping what it cannot render.

## Decision

1. **A look is one YAML file in three levels.** `<name>-look.yml`:

   ```yaml
   # The house look, data/looks/ptome-look.yml, in part. A look that
   # changes another starts with `extends: <look>` (a built-in or a file).
   tokens:                       # 1. design values, in no format's terms
     font:
       text: { family: Noto Serif }
       display: { family: Noto Sans, weight: bold }
       code: { family: M+ 1mn, size: 0.9 }      # a ratio of the text
     size:
       text: { print: 10.5pt, screen: 17px }
       headings: [26pt, 20pt, 14pt, 12pt, 11pt, 10.5pt]
       small: 0.9
     leading: { print: 1.4, screen: 1.6 }
     measure: 75ch
     paragraph: { signal: space, space: 6pt }
     align: { print: justify, screen: start }
     color:
       ink: '#1F1F1F'
       ink-strong: '#191919'
       muted: '#555555'
       link: '#2156A5'
       tint: '#F7F7F8'
       rule: '#DDDDDD'
     rule: { hairline: 0.5pt, heavy: 1pt }
     page: { size: A4, margin: [0.75in, 1.5in, 0.875in, 1.5in] }
   styles:                       # 2. elements and roles, in token terms
     heading: { font: display, color: ink-strong, space-before: 1.5em }
     caption: { font: display, size: small, color: muted }
     code-block: { background: tint, border: none }
     table: { rows: hairline, head-rule: heavy, columns: none }
     .small-caps: { variant: small-caps }
     .dek: { font: text, size: 1.25, style: italic }
   templates:                    # 3. generated text and structure
     footnote-reference: '{{number}}'
     node-templates: templates/  # the -T folder, relative to the look
   ```

   - **Tokens** are the design's values: faces by role (`text`,
     `display`, `code`, `utility`), sizes, leading, measure, paragraph
     signal, alignment and hyphenation, colors by role, rules, spacing,
     the page. A value may differ by medium: `print` (the PDF, and CSS
     print media), `screen` (HTML) and `ebook` (EPUB); a plain value is
     every medium's. Lengths take `pt`, `px`, `in`, `mm`, `em`, `ch` and
     `lines` (multiples of the line spacing); `1px` is `0.75pt`, CSS's
     reference pixel; a bare number is a ratio of what it scales.
   - **Styles** are AsciiDoc's elements (`heading`, `h2`, `paragraph`,
     `code-block`, `caption`, `admonition`, `sidebar`, `table`,
     `footnote`, `link`, ...) and roles (a leading dot: `.dek`), styled
     with a closed set of properties (`font`, `size`, `weight`, `style`,
     `variant`, `color`, `background`, `align`, `space-before`,
     `space-after`, `indent`, `border`, `rows`, `columns`, ...) whose
     values name tokens or give values.
   - **Templates** are ADR-0010's Mustache templates, by name, and the
     folder of `-T` node templates; title pages become DocBook-style slot
     lists (`title-page: { recto: [...], verso: [...] }`).

   YAML, like the PDF themes, because looks are written by hand. The
   token groups map one to one onto the Design Tokens format's types
   (color, dimension, font family and weight, number, typography), so an
   importer and exporter can come later without changing the file.

2. **One file compiles into each output's own terms.**
   - **PDF:** tokens and styles become theme keys (`base_font_size`,
     `heading_h2_font_size`, `heading_font_family`, `role_dek_*`) laid
     over the theme the look's chain starts from; the page tokens become
     `page_size` and `page_margin`. A `measure` without page margins sets
     the side margins that give it.
   - **HTML and the website:** tokens become custom properties on `:root`
     (`--ptome-font-text`, `--ptome-size-text`, `--ptome-leading`,
     `--ptome-color-link`, ...), the `print` values in `@media print` and
     an `@page` rule; styles become rules over Asciidoctor's markup (`h2`,
     `.listingblock pre`, `.dek`) that read those properties. The house
     overlay becomes one **device stylesheet** that reads tokens and holds
     no values of its own, written after Asciidoctor's stylesheet, so a
     look changes values without new CSS.
   - **EPUB:** the same stylesheet with the `ebook` values. The reading
     system owns the body text (Kindle asks for its default size and line
     height, Apple Books applies the reader's justification): a look sets
     no text size, line spacing or alignment for `ebook` unless it says
     so, and the house look sets none and turns hyphenation on, as
     Standard Ebooks' core stylesheet does (decided with the user,
     2026-10-11).
   - **Man pages:** styles map roles onto bold, italic and indentation;
     nothing else applies.
   - **DocBook:** nothing applies; it records structure.

   The markup never changes (ADR-0011 decision 2); only themes and
   stylesheets do.

3. **Precedence, from lowest to highest.**
   1. Each output's base: asciidoctor-pdf's `default` theme,
      Asciidoctor's stylesheet, asciidoctor-epub3's.
   2. The looks of the `extends` chain, then the look itself, merged as
      asciidoctor-pdf merges themes (a later value wins, `null` removes
      one), and compiled per item 2.
   3. The look's own format sections, for what tokens can't say: `pdf:`
      (theme keys, any the engine has), `css:` (rules appended to the
      device stylesheet), `epub-css:`. Explicit keys beat compiled ones.
   4. A `pdf-theme` or `stylesheet` the document names replaces that
      format's compiled look, as naming one does today (`pdf-theme=default`
      is asciidoctor-pdf's theme, ADR-0011 decision 4), so every existing
      theme and stylesheet keeps meaning what it means; a PDF theme that
      wants the look under it says `extends: look`.
   5. Document attributes that set single values (`pdf-page-size`,
      `pdf-page-margin`, `hyphens`), as today.

   The look comes from `-a look=<name>` (a file `<name>-look.yml` in
   `looksdir`, else a built-in), `look:` in `ptome.yml`, else the house
   look `ptome`. `asciidoctor-compat` applies no look at all: the classic
   theme and stylesheets, as ADR-0015 freezes them.

4. **What an output can't render is dropped by rule, never silently by
   accident.** Each compiler declares the tokens and style properties it
   maps and those it doesn't apply by design (an EPUB's text size, a man
   page's colors, DocBook's everything); a design drop is quiet. Anything
   else a look sets that an output can't render is a warning naming the
   look, the item and the output, once per conversion ("look magazine:
   tokens.grid.columns has no effect in man pages"); an unknown token,
   style or property is an error with its line and column. `ptome look
   explain <look> [--format pdf|html|epub3|manpage]` prints what each
   token and style became in each output (theme keys, CSS declarations)
   and what was dropped, and why.

5. **The house style is the first look.** `data/looks/ptome-look.yml`
   holds the values `doc/style.md` lists; the PDF theme
   `ptome-theme.yml` and the two overlays become what it compiles to
   (generated, then removed as sources), and `doc/style.md`'s table is
   generated from it. Named looks are parameter files over it, never
   modes (ADR-0013 decision 1): the troff-era manual, the tech book and
   the statute join it in `data/looks/` as their tasks land.

6. **The model is typed.** The loader parses a look into sealed Dart
   types (lengths with units, ratios, colors, face references, per-medium
   values, style properties), never maps of `Object?`, with source
   positions for its diagnostics; each compiler is a function from that
   model to its output's terms.

## Consequences

- One edit changes every output; the three hand-kept files go, and with
  them the chance of their disagreeing.
- The house look's first version must change nothing: the PDF theme it
  compiles to gives byte for byte the PDFs `ptome-theme.yml` gives today
  (checked over the corpus's documents converted without compat, and by
  `modern_test`), and the HTML and EPUB pages it styles render as they do
  now (their page images compared), the stylesheets changing only by the
  custom properties they read.
- The house EPUB stops imposing asciidoctor-epub3's justified
  paragraphs and 1.6 line height: reading systems set them from their
  defaults and the reader's settings, and the text is hyphenated.
- Existing PDF themes and stylesheets keep working unchanged
  (precedence 4); a look is optional for anyone who has one, and can be
  adopted one format at a time.
- Implementation, in order: the model, loader and diagnostics; the PDF
  compiler and the house look (TASK-rwg74t); the CSS compiler and the
  device stylesheet (TASK-sq53bn); `ptome look explain`; title-page slot
  lists; then the named looks. The magazine website (EPIC-kzdb6h)
  writes its era files as looks.
