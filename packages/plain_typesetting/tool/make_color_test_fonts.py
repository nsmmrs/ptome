# Makes the color glyph tests' own fonts (test/fonts), with fontTools:
#
# - colr-test.ttf, written for the tests: a few outlines (a square, a
#   circle, a triangle) and color glyphs over them in COLR version 0
#   (layers) and version 1 (every paint format, the extend modes, a
#   glyph painted from another, composites), two CPAL palettes;
# - sbix-test.ttf: some of notocoloremoji-subset.ttf's images (Noto Color
#   Emoji, OFL) as an sbix strike, one glyph a 'dupe' of another.
#
#     uv run --with fonttools python tool/make_color_test_fonts.py
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.colorLib.builder import buildCOLR, buildCPAL
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables import otTables as ot
from fontTools.ttLib.tables.sbixGlyph import Glyph as SbixGlyph
from fontTools.ttLib.tables.sbixStrike import Strike


def square(pen):
    pen.moveTo((100, 0))
    pen.lineTo((100, 800))
    pen.lineTo((900, 800))
    pen.lineTo((900, 0))
    pen.closePath()


def circle(pen):
    k = 0.5523 * 400
    cx, cy, r = 500, 400, 400
    pen.moveTo((cx, cy - r))
    pen.curveTo((cx - k, cy - r), (cx - r, cy - k), (cx - r, cy))
    pen.curveTo((cx - r, cy + k), (cx - k, cy + r), (cx, cy + r))
    pen.curveTo((cx + k, cy + r), (cx + r, cy + k), (cx + r, cy))
    pen.curveTo((cx + r, cy - k), (cx + k, cy - r), (cx, cy - r))
    pen.closePath()


def triangle(pen):
    pen.moveTo((100, 0))
    pen.lineTo((500, 800))
    pen.lineTo((900, 0))
    pen.closePath()


def colr_font(path):
    outlines = {'square': square, 'circle': circle, 'triangle': triangle}
    # Each color glyph, the character it is for.
    colored = {
        'layers': 0x1F600, 'solid': 0x1F601, 'linear': 0x1F602,
        'radial': 0x1F603, 'sweep': 0x1F604, 'transform': 0x1F605,
        'translate': 0x1F606, 'scale': 0x1F607, 'rotate': 0x1F608,
        'skew': 0x1F609, 'colrglyph': 0x1F60A, 'composite': 0x1F60B,
        'repeat': 0x1F60C, 'reflect': 0x1F60D, 'foreground': 0x1F60E,
        'blend': 0x1F60F,
    }
    order = ['.notdef', 'space', *outlines, *colored]
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap({0x20: 'space', **{c: g for g, c in colored.items()}})
    glyphs = {}
    for name in order:
        pen = TTGlyphPen(None)
        draw = outlines.get(name, square if name == '.notdef' else None)
        if draw:
            # (The circle's curves as TrueType's quadratic ones.)
            draw(Cu2QuPen(pen, 1, reverse_direction=True))
        glyphs[name] = pen.glyph()
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics({name: (1000, 0) for name in order})
    fb.setupHorizontalHeader(ascent=900, descent=-100)
    fb.setupNameTable({'familyName': 'Color Test', 'styleName': 'Regular'})
    fb.setupOS2(sTypoAscender=900, sTypoDescender=-100, usWinAscent=900,
                usWinDescent=100)
    fb.setupPost()

    def line(extend, *stops):
        return {'Extend': extend, 'ColorStop': [
            {'StopOffset': o, 'PaletteIndex': i, 'Alpha': a}
            for o, i, a in stops]}

    def glyph(name, paint):
        return {'Format': ot.PaintFormat.PaintGlyph, 'Paint': paint,
                'Glyph': name}

    def solid(index, alpha=1.0):
        return {'Format': ot.PaintFormat.PaintSolid, 'PaletteIndex': index,
                'Alpha': alpha}

    linear = {'Format': ot.PaintFormat.PaintLinearGradient,
              'ColorLine': line('pad', (0, 0, 1), (0.5, 1, 0.5), (1, 2, 1)),
              'x0': 100, 'y0': 0, 'x1': 900, 'y1': 800, 'x2': 100,
              'y2': 800}
    radial = {'Format': ot.PaintFormat.PaintRadialGradient,
              'ColorLine': line('pad', (0, 1, 1), (1, 3, 1)),
              'x0': 500, 'y0': 400, 'r0': 0, 'x1': 500, 'y1': 400,
              'r1': 400}
    sweep = {'Format': ot.PaintFormat.PaintSweepGradient,
             'ColorLine': line('pad', (0, 0, 1), (0.5, 2, 1), (1, 0, 1)),
             'centerX': 500, 'centerY': 400, 'startAngle': 0,
             'endAngle': 360}
    v1 = {
        'solid': glyph('circle', solid(1, 0.75)),
        'linear': glyph('square', linear),
        'radial': glyph('circle', radial),
        'sweep': glyph('circle', sweep),
        'transform': {'Format': ot.PaintFormat.PaintTransform,
                      'Paint': glyph('triangle', solid(0)),
                      'Transform': {'xx': 0.5, 'yx': 0.25, 'xy': -0.25,
                                    'yy': 0.5, 'dx': 250, 'dy': 100}},
        'translate': {'Format': ot.PaintFormat.PaintTranslate,
                      'Paint': glyph('circle', linear), 'dx': 50,
                      'dy': -25},
        'scale': {'Format': ot.PaintFormat.PaintColrLayers, 'Layers': [
                      {'Format': ot.PaintFormat.PaintScale,
                       'Paint': glyph('square', solid(0)), 'scaleX': 0.5,
                       'scaleY': 0.75},
                      {'Format': ot.PaintFormat.PaintScaleAroundCenter,
                       'Paint': glyph('circle', solid(1)), 'scaleX': 0.5,
                       'scaleY': 0.5, 'centerX': 500, 'centerY': 400},
                      {'Format': ot.PaintFormat.PaintScaleUniform,
                       'Paint': glyph('triangle', solid(2)), 'scale': 0.25},
                      {'Format': ot.PaintFormat.PaintScaleUniformAroundCenter,
                       'Paint': glyph('triangle', solid(3)), 'scale': 0.5,
                       'centerX': 500, 'centerY': 400},
                  ]},
        'rotate': {'Format': ot.PaintFormat.PaintColrLayers, 'Layers': [
            {'Format': ot.PaintFormat.PaintRotate,
             'Paint': glyph('square', solid(0)), 'angle': 15},
            {'Format': ot.PaintFormat.PaintRotateAroundCenter,
             'Paint': glyph('triangle', solid(2)), 'angle': -30,
             'centerX': 500, 'centerY': 400},
        ]},
        'skew': {'Format': ot.PaintFormat.PaintColrLayers, 'Layers': [
            {'Format': ot.PaintFormat.PaintSkew,
             'Paint': glyph('square', solid(1)), 'xSkewAngle': 10,
             'ySkewAngle': 0},
            {'Format': ot.PaintFormat.PaintSkewAroundCenter,
             'Paint': glyph('triangle', solid(3)), 'xSkewAngle': -15,
             'ySkewAngle': 5, 'centerX': 500, 'centerY': 400},
        ]},
        'colrglyph': {'Format': ot.PaintFormat.PaintColrLayers, 'Layers': [
            glyph('square', solid(3)),
            {'Format': ot.PaintFormat.PaintColrGlyph, 'Glyph': 'radial'},
        ]},
        'composite': {'Format': ot.PaintFormat.PaintComposite,
                      'SourcePaint': glyph('circle', solid(1)),
                      'CompositeMode': 'src_in',
                      'BackdropPaint': glyph('square', linear)},
        'blend': {'Format': ot.PaintFormat.PaintComposite,
                  'SourcePaint': glyph('triangle', solid(2, 0.5)),
                  'CompositeMode': 'multiply',
                  'BackdropPaint': glyph('circle', radial)},
        'repeat': glyph('square', {
            'Format': ot.PaintFormat.PaintLinearGradient,
            'ColorLine': line('repeat', (0, 0, 1), (1, 1, 1)),
            'x0': 300, 'y0': 0, 'x1': 500, 'y1': 0, 'x2': 300, 'y2': 100}),
        'reflect': glyph('circle', {
            'Format': ot.PaintFormat.PaintRadialGradient,
            'ColorLine': line('reflect', (0, 2, 1), (1, 3, 1)),
            'x0': 450, 'y0': 350, 'r0': 50, 'x1': 500, 'y1': 400,
            'r1': 150}),
        'foreground': glyph('circle', {
            'Format': ot.PaintFormat.PaintLinearGradient,
            'ColorLine': line('pad', (0, 0xFFFF, 1), (1, 0xFFFF, 0.25)),
            'x0': 100, 'y0': 0, 'x1': 900, 'y1': 0, 'x2': 100, 'y2': 800}),
    }
    v0 = {'layers': [('square', 0), ('circle', 1), ('triangle', 0xFFFF)]}
    clips = {name: (0, -100, 1000, 900) for name in v1 if name != 'scale'}
    fb.font['COLR'] = buildCOLR({**v0, **v1}, clipBoxes=clips)
    fb.font['CPAL'] = buildCPAL([
        [(0.8, 0.1, 0.1, 1), (0.1, 0.6, 0.2, 1), (0.1, 0.2, 0.8, 1),
         (0.9, 0.8, 0.1, 0.5)],
        [(0.2, 0.2, 0.2, 1), (0.5, 0.5, 0.5, 1), (0.8, 0.8, 0.8, 1),
         (0, 0, 0, 0.5)],
    ])
    fb.save(path)


def sbix_font(source, path):
    font = TTFont(source)
    order = font.getGlyphOrder()
    cmap = font.getBestCmap()
    keep = {cmap[c] for c in (0x1F600, 0x1F602, 0x1F44D)}
    strike = Strike(ppem=109, resolution=72)
    cbdt = font['CBDT'].strikeData[0]
    for name in order:
        if name in keep and name in cbdt:
            data = cbdt[name]
            data.decompile()
            png = data.imageData
            strike.glyphs[name] = SbixGlyph(
                glyphName=name, graphicType='png ', originOffsetX=0,
                originOffsetY=-20, imageData=png)
        else:
            strike.glyphs[name] = SbixGlyph(glyphName=name)
    # (U+1F642's glyph shows U+1F600's image: a 'dupe'.)
    dupe = cmap[0x1F642]
    strike.glyphs[dupe] = SbixGlyph(
        glyphName=dupe, graphicType='dupe',
        referenceGlyphName=cmap[0x1F600])
    sbix = newTable('sbix')
    sbix.version = 1
    sbix.flags = 1
    sbix.strikes = {109: strike}
    font['sbix'] = sbix
    del font['CBDT']
    del font['CBLC']
    font.save(path)


if __name__ == '__main__':
    colr_font('test/fonts/colr-test.ttf')
    sbix_font('test/fonts/notocoloremoji-subset.ttf', 'test/fonts/sbix-test.ttf')
    sys.stdout.write('test/fonts/colr-test.ttf, test/fonts/sbix-test.ttf\n')
