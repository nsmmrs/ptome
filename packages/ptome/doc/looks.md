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
with its line and column, and the house look is used.

What each output does with a look today:

- **PDF:** the look becomes the theme (its keys, over asciidoctor-pdf's
  `default` theme). A theme the document names (`pdf-theme`) replaces the
  look, as naming a theme always has (`pdf-theme=default` is
  asciidoctor-pdf's theme); a theme that wants the look under it says
  `extends: look` (the document's) or `extends: ptome` (the house look).
- **HTML, the website, EPUB:** the house stylesheets still apply as
  written; compiling looks into them is the next step (lane TASK-sq53bn).
- **`asciidoctor-compat`:** no look applies; the classic theme and
  stylesheets do.

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
css: ''                   # rules after the device stylesheet (HTML)
epub-css: ''              # rules after it in an EPUB
```

A look sets only what it means to. Merged over the looks it extends, a
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
- **By medium:** a token may differ by where it is shown, `print` (the
  PDF, and CSS print media), `screen` (HTML) and `ebook` (EPUB):
  `leading: { print: 1.4, screen: 1.6 }`. A plain value is every
  medium's. An e-book's reading system owns the body text: the house
  look sets no size, line spacing or alignment for `ebook`.

## Tokens

| Token | What it is | PDF |
| --- | --- | --- |
| `font.<role>` | A face: `family`, `weight` (`normal`, `bold`), `style` (`normal`, `italic`), `size` (a ratio, for `code`). Roles: `text`, `display`, `code`, `utility`, or any a style names | `text`: `base_font_family`; `code`: `code_font_family`, `codespan_font_family`, `codespan_font_size` |
| `size.text` | The text's size | `base_font_size` (print) |
| `size.headings` | Levels 1 to 6 | `heading_h<n>_font_size` |
| `size.small` | Small text, a ratio (`size: small` in a style) | |
| `leading` | Line spacing, a ratio | `base_line_height` (print) |
| `measure` | The line length | (the PDF takes it from `page.margin`) |
| `paragraph` | `signal` (`space`, `indent`), `space`, `indent` | `prose_margin_bottom`, `prose_text_indent` |
| `align` | `start`, `center`, `end`, `justify` | `base_text_align` (print) |
| `hyphenate` | `true` or `false` | `base_hyphens` (print) |
| `color.<name>` | Colors by role; `ink` is the text's, `paper` the page's | `base_font_color`, `page_background_color` |
| `rule.<name>` | Rule widths by name (`hairline`, `heavy`) | |
| `page` | `size`, `margin` (1, 2 or 4 lengths), `inner`, `outer` | `page_size`, `page_margin`, `page_margin_inner`, `page_margin_outer` |

## Styles

Elements: `heading`, `h1` to `h6`, `title`, `subtitle`, `paragraph`,
`link`, `code` (in a line), `code-block`, `caption`, `quote`,
`admonition`, `admonition-label`, `sidebar`, `sidebar-title`, `table`,
`table-head`, `footnote`. A role starts with a dot: `.dek` styles
`[.dek]`.

| Property | Value | PDF (the element's category) |
| --- | --- | --- |
| `font` | a font token | `_font_family`, and `_font_style` from its weight and style |
| `weight`, `style`, `variant` | `bold`; `italic`; `small-caps` | `_font_style`, `_font_variant` |
| `size` | a length, a ratio, or `small` | `_font_size` |
| `color`, `background` | a color token, a color, or `none` | `_font_color`, `_background_color` |
| `leading` | a ratio | `_line_height` |
| `space-before`, `space-after` | lengths | `_margin_top`, `_margin_bottom` |
| `padding`, `radius` | lengths | `_padding`, `_border_radius` |
| `border`, `rule` | `none`, or `{ width, color }` (a width may name a rule token) | `_border_width`, `_border_color`; `_column_rule_*` (an admonition's rule) |
| `keep-with-next` | `true` | `_min_height_after: auto` (headings) |
| `frame`, `frame-sides`, `rows`, `columns`, `head-rule`, `stripes` | a table's rules, and its alternate rows' background | `table_border_*`, `table_grid_*`, `table_head_border_bottom_*`, `table_body_stripe_background_color` |

## What an output can't render

Each output applies what it can and leaves out, quietly, what it doesn't
by design (an e-book's text size). Anything else a look sets that an
output can't render is a warning naming the look, the item and the
output (`look magazine: styles.paragraph.keep-with-next has no effect in
the PDF`); an unknown token, element or property is an error with its
line and column.
