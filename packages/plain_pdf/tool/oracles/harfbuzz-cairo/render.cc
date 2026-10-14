// The color glyph tests' rendering oracle: HarfBuzz's own painting through
// cairo (hb-cairo, from HarfBuzz's source at the tag the shaper follows).
// Usage: hb-render FONT EM DIR < GLYPHS. Each line of standard input is a
// glyph id, rendered at EM pixels to the em on a white square 2 EM wide,
// its origin EM / 2 from the left and the bottom, to DIR/GLYPH.ppm (a
// binary PPM, as pdftoppm writes them).
#include <hb.h>
#include <hb-cairo.h>
#include <cairo.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <string>

int main (int argc, char **argv) {
  if (argc != 4) {
    fprintf (stderr, "usage: hb-render FONT EM DIR < GLYPHS\n");
    return 2;
  }
  hb_blob_t *blob = hb_blob_create_from_file_or_fail (argv[1]);
  if (!blob) { fprintf (stderr, "cannot read %s\n", argv[1]); return 1; }
  hb_face_t *face = hb_face_create (blob, 0);
  hb_font_t *font = hb_font_create (face);
  double em = atof (argv[2]);
  int size = (int) (2 * em);
  // (As hb-view sets it up: the font scaled to the size in 64ths.)
  hb_font_set_scale (font, (int) (em * 64), (int) (em * 64));
  cairo_font_face_t *cairo_face = hb_cairo_font_face_create_for_font (font);
  hb_cairo_font_face_set_scale_factor (cairo_face, 64);
  std::string line;
  while (std::getline (std::cin, line)) {
    unsigned glyph = (unsigned) std::stoul (line);
    cairo_surface_t *surface =
        cairo_image_surface_create (CAIRO_FORMAT_RGB24, size, size);
    cairo_t *cr = cairo_create (surface);
    cairo_set_source_rgb (cr, 1, 1, 1);
    cairo_paint (cr);
    cairo_set_font_face (cr, cairo_face);
    cairo_set_font_size (cr, em);
    cairo_set_source_rgb (cr, 0, 0, 0);
    cairo_glyph_t g = {glyph, em / 2, size - em / 2};
    cairo_show_glyphs (cr, &g, 1);
    if (cairo_status (cr)) fprintf (stderr, "%s\n", cairo_status_to_string (cairo_status (cr)));
    std::string out = std::string (argv[3]) + "/" + line + ".ppm";
    cairo_surface_flush (surface);
    FILE *f = fopen (out.c_str (), "wb");
    if (!f) { fprintf (stderr, "cannot write %s\n", out.c_str ()); return 1; }
    fprintf (f, "P6\n%d %d\n255\n", size, size);
    unsigned char *data = cairo_image_surface_get_data (surface);
    int stride = cairo_image_surface_get_stride (surface);
    for (int y = 0; y < size; y++)
      for (int x = 0; x < size; x++) {
        uint32_t px = *(uint32_t *) (data + y * stride + 4 * x);
        unsigned char rgb[3] = {(unsigned char) (px >> 16),
                                (unsigned char) (px >> 8), (unsigned char) px};
        fwrite (rgb, 1, 3, f);
      }
    fclose (f);
    cairo_destroy (cr);
    cairo_surface_destroy (surface);
  }
  cairo_font_face_destroy (cairo_face);
  hb_font_destroy (font);
  hb_face_destroy (face);
  hb_blob_destroy (blob);
  return 0;
}
