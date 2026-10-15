# Makes the historical forms test's own font (test/fonts), with fontTools:
#
# - historical-test.ttf, written for the tests: bars for a, c, s, t, the
#   long s and a c_t ligature, a `hist` feature that sets s as the long s
#   before a letter (a contextual substitution, as the Fell types' do) and
#   a `dlig` feature that joins c and t.
#
#     uv run --with fonttools python tool/make_historical_test_font.py
import sys

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen


def bar(width):
    pen = TTGlyphPen(None)
    pen.moveTo((50, 0))
    pen.lineTo((50, 700))
    pen.lineTo((width - 50, 700))
    pen.lineTo((width - 50, 0))
    pen.closePath()
    return pen.glyph()


names = ['.notdef', 'space', 'a', 'c', 's', 't', 'longs', 'c_t']
widths = {'.notdef': 500, 'space': 250, 'a': 500, 'c': 450, 's': 400,
          't': 300, 'longs': 250, 'c_t': 700}
builder = FontBuilder(1000, isTTF=True)
builder.setupGlyphOrder(names)
builder.setupCharacterMap(
    {0x20: 'space', 0x61: 'a', 0x63: 'c', 0x73: 's', 0x74: 't',
     0x17F: 'longs'})
builder.setupGlyf({name: bar(widths[name]) for name in names})
builder.setupHorizontalMetrics({name: (widths[name], 50) for name in names})
builder.setupHorizontalHeader(ascent=800, descent=-200)
builder.setupNameTable(
    {'familyName': 'Historical Test', 'styleName': 'Regular'})
builder.setupOS2()
builder.setupPost()
addOpenTypeFeaturesFromString(builder.font, """
languagesystem DFLT dflt;
languagesystem latn dflt;
feature hist { sub s' [a c s t] by longs; } hist;
feature dlig { sub c t by c_t; } dlig;
""")
builder.save(sys.argv[1] if len(sys.argv) > 1 else
             'test/fonts/historical-test.ttf')
