# Looks

A look is a document's design, written once for every output
([ADR-0023](../../../adr/0023-looks.md)): one YAML file whose values
each output compiles into its own terms. Ptome's house style is the
built-in look `ptome` (`data/looks/ptome-look.yml`, `doc/style.md`); a
document chooses another with an attribute:

```asciidoc
:look: magazine
:looksdir: {docdir}/looks
```

`look` names a file `<name>-look.yml` in `looksdir`, or a built-in look; a
path ending in `.yml` names a file. A look that can't be read is reported,
with its line and column, and the house look is used. A project names its
look once in its `ptome.yml` (or a user in `~/.config/ptome/config.yml`),
found beside that file or in its `looksdir:`; the command line uses it
unless `-a look` says otherwise:

```yaml
look: book
looksdir: design      # relative to ptome.yml; beside it if left out
```

What each output does with a look:

- **PDF:** the look becomes the theme (its keys, over asciidoctor-pdf's
  `default` theme). A theme the document names (`pdf-theme`) replaces the
  look, as naming a theme always has (`pdf-theme=default` is
  asciidoctor-pdf's theme); a theme that wants the look under it says
  `extends: look` (the document's) or `extends: ptome` (the house look).
- **HTML and the website:** the default stylesheet is Asciidoctor's, then
  the look's CSS (its tokens as custom properties, `--ptome-color-link`,
  `--ptome-font-text`, `--ptome-rule-hairline`; its styles as rules over
  Asciidoctor's markup that read them; the print values in
  `@media print`, the page in `@page`), then the device rules
  (`data/stylesheets/ptome-device.css`), which hold no values, then the
  look's own `css:`. A `stylesheet` the document names replaces it.
- **EPUB:** asciidoctor-epub3's stylesheet, then the look's rules with
  the `ebook` values written out (e-readers such as Kindle's don't read
  custom properties), then the device rules, then the look's own
  `epub-css:`. Unless the look sets an
  `ebook` line spacing or alignment, asciidoctor-epub3's justified,
  1.6-spaced paragraphs are undone, so the reader's settings apply.
- **`asciidoctor-compat`:** no look applies; the classic theme and
  stylesheets do.

## Built-in looks

| Look | What it is |
| --- | --- |
| `ptome` | The house style (`doc/style.md`), the default. |
| `troff` | The troff-era manual: the Bell Labs books set with troff and ms (*The C Programming Language*, *The UNIX Programming Environment*, *The AWK Programming Language*), measured from them: Times 11 on 12 on a 4.8 in measure, code in Courier indented half an inch, headings in Times Bold, the running head 32 pt above the first line, a 6.25 × 9.25 in trim. Set in TeX Gyre Termes and Cursor (`ptome doctor --look troff`); without them in the PDF's own Times and Courier. |
| `tech-book` | The tech book: the O'Reilly animal books, measured from one of 2018: a 7 × 9.1875 in trim, a 30 pc text block, body 10.5 on 12.6, headings in a semibold condensed sans, code 8.5 on 10.2 indented 17 pt, a running foot and no head, notes as an uppercase label between 0.5 pt rules, a title page with a copyright verso. Set in Crimson Pro, Fira Sans Condensed and Ubuntu Mono (`ptome doctor --look tech-book`; on the web from Google Fonts). |

## The file

```yaml
extends: ptome            # the look it changes (a built-in, or a file)
tokens:                   # 1. the design's values
  font:
    text: { family: Noto Serif }
    display: { family: Noto Sans, weight: bold }
  size: { text: { print: 10.5pt, screen: 17px } }
  color: { ink: '#1F1F1F', link: '#2156A5' }
styles:                   # 2. elements and roles, in token terms
  heading: { font: display, color: ink }
  .dek: { size: 1.25, style: italic }
templates:                # 3. generated text (ADR-0010)
  footnote-reference: '{{number}}'
pdf:                      # what tokens can't say, in the theme's own keys
  font:
    catalog: { merge: true, Noto Sans: { normal: notosans.ttf } }
webfonts:                 # Google Fonts families HTML pages load
  - Crimson Pro:400,400italic,700,700italic
css: ''                   # rules after the device stylesheet (HTML)
epub-css: ''              # rules after it in an EPUB
```

`webfonts` lists the Google Fonts families an HTML page loads for the
look's faces (after those of Asciidoctor's stylesheet, when the
`webfonts` attribute is set but empty, its default); the latest look of
a chain that gives any. A look sets only what it means to. Merged over the looks it extends, a
later value wins and `null` removes one (`link: ~`). The `pdf:`, `css:`
and `epub-css:` parts apply look by look, the one extended first.

### Values

- **Lengths** carry their unit: `pt`, `px` (0.75pt), `in`, `mm`, `em`
  (the font size), `ch` (a `0`'s width), `lines` (the line spacing). `0`
  needs none.
- **Ratios** are bare numbers: `size: 1.25` is 1.25 times the text around
  it, `leading: 1.4` is 1.4 times the size.
- **Colors** are `'#RRGGBB'` or `'#RGB'`, quoted (YAML reads `#` as a
  comment, and `191919` as a number); a style may name a color token
  instead, or say `none`.
- **By medium:** any value, a token's or a style's, may differ by where
  it is shown, `print` (the PDF, and CSS print media), `screen` (HTML)
  and `ebook` (EPUB): `leading: { print: 1.4, screen: 1.6 }`,
  `weight: { print: bold, screen: 600 }`. A plain value is every
  medium's; a value with media applies in those alone, and elsewhere the
  output's base stylesheet or theme decides. An e-book's reading system
  owns the body text: the house look sets no size, line spacing or
  alignment for `ebook`.
- **Weights** are `normal` (400), `bold` (700) or 100 to 900; the PDF
  sets 600 and up in the bold face.

## Tokens

| Token | What it is | PDF (HTML and EPUB: the same values, as CSS) |
| --- | --- | --- |
| `font.<role>` | A face: `family`, `weight` (`normal`, `bold`), `style` (`normal`, `italic`), `size` (a ratio, for `code`). Roles: `text`, `display`, `code`, `utility`, or any a style names | `text`: `base_font_family`; `code`: `code_font_family`, `codespan_font_family`, `codespan_font_size` |
| `size.text` | The text's size | `base_font_size` (print) |
| `size.headings` | Levels 1 to 6 | `heading_h<n>_font_size` |
| `size.small` | Small text, a ratio (`size: small` in a style) | |
| `leading` | Line spacing, a ratio | `base_line_height` (print) |
| `measure` | The line length | `page_measure` (the side margins), when `page.margin` isn't set |
| `paragraph` | `signal` (`space`, `indent`), `space`, `indent` (after another paragraph) | `prose_margin_bottom`; `prose_margin_inner: 0`, `prose_text_indent_inner` |
| `align` | `start`, `center`, `end`, `justify` | `base_text_align` (print) |
| `hyphenate` | `true` or `false` | `base_hyphens` (print) |
| `color.<name>` | Colors by role; `ink` is the text's, `paper` the page's | `base_font_color`, `page_background_color` |
| `rule.<name>` | Rule widths by name (`hairline`, `heavy`) | |
| `page` | `size` (a name, `A4`, or a trim, `[6.25in, 9.25in]`), `margin` (1, 2 or 4 lengths), `inner`, `outer` | `page_size`, `page_margin`, `page_margin_inner`, `page_margin_outer` |

## Styles

Elements: `heading`, `h1` to `h6`, `title`, `subtitle`, `paragraph`,
`link`, `code` (in a line), `code-block`, `caption`, `quote`,
`admonition`, `admonition-label`, `sidebar`, `sidebar-title`, `table`,
`table-head`, `footnote`. A role starts with a dot: `.dek` styles
`[.dek]`. In CSS each element is its selectors in the output's markup
(`heading` is Asciidoctor's `h1,h2,h3,#toctitle,...`, an EPUB's
`h1,...,h6`); an output without the element (HTML has no separate
subtitle) leaves its style out.

| Property | Value | PDF (the element's category) | CSS |
| --- | --- | --- | --- |
| `font` | a font token | `_font_family`, and `_font_style` from its weight and style | `font-family`, `font-weight`, `font-style` |
| `weight`, `style`, `variant` | a weight; `italic`; `small-caps` | `_font_style`, `_font_variant` | `font-weight`, `font-style`, `font-variant` (and `smcp`) |
| `size` | a length, a ratio, or `small` | `_font_size` | `font-size` (a ratio in `em`) |
| `color`, `background` | a color token, a color, or `none` | `_font_color`, `_background_color` | `color`, `background-color` |
| `leading` | a ratio | `_line_height` | `line-height` |
| `space-before`, `space-after` | lengths | `_margin_top`, `_margin_bottom` | `margin-top`, `margin-bottom` |
| `padding`, `radius` | lengths | `_padding`, `_border_radius` | `padding`, `border-radius` |
| `border`, `rule` | `none`, or `{ width, color }` (a width may name a rule token) | `_border_width`, `_border_color`; `_column_rule_*` (an admonition's rule) | `border`; `border-left` |
| `keep-with-next` | `true` | `_min_height_after: auto` (headings) | `break-after: avoid` |
| `frame`, `frame-sides`, `rows`, `columns`, `head-rule`, `stripes` | a table's rules, and its alternate rows' background | `table_border_*`, `table_grid_*`, `table_head_border_bottom_*`, `table_body_stripe_background_color` | the table's, its cells' and its head's borders |

## Title pages

A look's title page is a list of slots, as DocBook XSL's title page
templates are: the parts of the header on the front (`recto`), in
order, and on its back (`verso`, a book's copyright page).

```yaml
templates:
  title-page:
    recto:
      - { slot: authors, separator: ' & ', space-before: { print: 1in } }
      - { slot: title, space-before: { print: 2in, screen: 1em } }
      - subtitle
      - { attribute: publisher, style: .publisher }
    verso:
      - { attribute: copyright, style: .legal }
      - { slot: revision, before: 'Edition: ' }
```

A slot is a part's name (`title`, `subtitle`, `authors`, `revision`,
`logo`), or a mapping of what it shows (`slot:` a part, or `attribute:`
the value of a document attribute, where the document sets it) and how:
`style` (a role the look's `styles` give, with its dot), `space-before`
and `space-after` (lengths, by medium), `before` (text before it) and
`separator` (between the authors). The title is the whole title unless
the subtitle has a slot of its own (`title-separator` divides them).

- **PDF:** `title_page_recto` and `title_page_verso` (`doc/pdf.md`); the
  slots placed by their space alone, the verso on the next page. A
  theme without them keeps asciidoctor-pdf's order.
- **HTML:** the header's parts in the slots' order, each of the class
  `title-page-<part>` (or `title-page-<attribute>`) and its role's, the
  verso's in a `div.verso` (a page of its own in print).
- **EPUB:** a title page after the cover (`titlepage.xhtml`, a landmark),
  its verso a page of its own (`epub:type="copyright-page"`).

A look without `title-page` leaves each output's own; `asciidoctor-compat`
the classic ones.

## What an output can't render

Each output applies what it can and leaves out, quietly, what it doesn't
by design (an e-book's alignment and line spacing, HTML's subtitle).
Anything else a look sets that an output can't render is a warning
naming the look, the item and the output (`look magazine:
styles.paragraph.keep-with-next has no effect in the PDF`); an unknown
token, element or property is an error with its line and column.

## Explaining a look

`ptome look explain` prints what each item of a look became in each
output, and what an output left out and why:

```console
$ ptome look explain magazine --looksdir design
look magazine (design): what each item became, by output

tokens.size.text
  PDF   base_font_size: 10.5
  HTML  body{font-size:17px}
        body{font-size:10.5pt}  (print)
  EPUB  — set for print and screen only
styles.paragraph.keep-with-next
  PDF   left out: has no effect in the PDF (a warning)
  HTML  .paragraph>p{break-after:avoid}
        .paragraph>p{page-break-after:avoid}
  EPUB  body p{break-after:avoid}
        body p{page-break-after:avoid}
...
```

The PDF's lines are theme keys, as a theme file writes them; HTML's and
an EPUB's are custom properties and declarations with their selectors
(a long list of selectors shortened to its first), HTML's print-only
ones marked `(print)`. A token that only styles read (a color, a rule
width) says so where the output doesn't declare it. The results and the
drops are the compilers' own, the ones conversion warns of, so the two
can't disagree. `--format pdf` (or `html`, `epub3`, or a list) explains
those outputs alone; without a look it explains the one `ptome.yml`
names, else `ptome`.
