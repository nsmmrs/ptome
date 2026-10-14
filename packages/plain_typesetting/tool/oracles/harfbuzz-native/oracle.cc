// The script shaping tests' native oracle: HarfBuzz (a full build, from
// its source), shaping each line of standard input in the font named by
// the first argument, the features named by the others ("-liga", "onum"),
// the direction and script guessed from the text as hb-shape guesses
// them, characters their own clusters. Each line's glyphs are written as
// a JSON array of [glyph id, cluster, x advance, x offset, y offset] in
// visual order, one line each. With --ttb, the lines are shaped top to
// bottom and the advance is the y advance; with --language=TAG, in that
// BCP 47 language.
#include <hb.h>
#include <hb-ot.h>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <iostream>

// With --language-tags, each line of standard input is a BCP 47 tag: its
// OpenType language system tags (hb_ot_tags_from_script_and_language),
// space-separated, one line each.
static int language_tags () {
  std::string line;
  while (std::getline (std::cin, line)) {
    hb_tag_t tags[HB_OT_MAX_TAGS_PER_LANGUAGE];
    unsigned count = HB_OT_MAX_TAGS_PER_LANGUAGE;
    hb_ot_tags_from_script_and_language (
        HB_SCRIPT_UNKNOWN, hb_language_from_string (line.c_str (), -1),
        nullptr, nullptr, &count, tags);
    for (unsigned i = 0; i < count; i++) {
      char buf[5] = {0};
      hb_tag_to_string (tags[i], buf);
      printf ("%s[%s]", i ? " " : "", buf);
    }
    printf ("\n");
  }
  return 0;
}

// --paint FONT: each line a glyph id; prints what hb_font_paint_glyph_or_fail
// paints for it (palette 0, foreground opaque black), one operation after
// another separated by " | " ("-" where it isn't a color glyph): T (a
// transform other than the identity) and t, CG (a clip to a glyph), CR (a
// clip to a rectangle) and c, F (a glyph filled), S (a color), L, R, W
// (gradients: extend, stops, points), G and g (groups and their modes),
// I (an image). Numbers to two decimals.
static std::string paint_out;
static std::vector<bool> transform_emitted;

static void out (const char *fmt, ...) {
  char buf[4096];
  va_list ap;
  va_start (ap, fmt);
  vsnprintf (buf, sizeof buf, fmt, ap);
  va_end (ap);
  if (!paint_out.empty ()) paint_out += " | ";
  paint_out += buf;
}

static std::string num (float v) {
  char buf[64];
  snprintf (buf, sizeof buf, "%.2f", v);
  std::string s = buf;
  if (s == "-0.00") s = "0.00";
  return s;
}

static std::string color (hb_bool_t fg, hb_color_t c) {
  char buf[64];
  snprintf (buf, sizeof buf, "%d:%02x%02x%02x%02x", fg ? 1 : 0,
            hb_color_get_red (c), hb_color_get_green (c),
            hb_color_get_blue (c), hb_color_get_alpha (c));
  return buf;
}

static std::string stops (hb_color_line_t *line) {
  unsigned count = hb_color_line_get_color_stops (line, 0, nullptr, nullptr);
  std::vector<hb_color_stop_t> s (count);
  hb_color_line_get_color_stops (line, 0, &count, s.data ());
  std::string r = std::to_string ((int) hb_color_line_get_extend (line)) + " [";
  for (unsigned i = 0; i < count; i++) {
    if (i) r += ",";
    r += num (s[i].offset) + "/" + color (s[i].is_foreground, s[i].color);
  }
  return r + "]";
}

static void p_push_transform (hb_paint_funcs_t *, void *, float xx, float yx,
                              float xy, float yy, float dx, float dy, void *) {
  bool identity = xx == 1 && yx == 0 && xy == 0 && yy == 1 && dx == 0 && dy == 0;
  transform_emitted.push_back (!identity);
  if (!identity)
    out ("T %s %s %s %s %s %s", num (xx).c_str (), num (yx).c_str (),
         num (xy).c_str (), num (yy).c_str (), num (dx).c_str (),
         num (dy).c_str ());
}
static void p_pop_transform (hb_paint_funcs_t *, void *, void *) {
  bool emitted = transform_emitted.back ();
  transform_emitted.pop_back ();
  if (emitted) out ("t");
}
static void p_fill_glyph (hb_paint_funcs_t *, void *, hb_codepoint_t glyph,
                          hb_font_t *, hb_bool_t fg, hb_color_t c, void *) {
  out ("F %u %s", glyph, color (fg, c).c_str ());
}
static void p_push_clip_glyph (hb_paint_funcs_t *, void *, hb_codepoint_t glyph,
                               hb_font_t *, void *) {
  out ("CG %u", glyph);
}
static void p_push_clip_rectangle (hb_paint_funcs_t *, void *, float x0,
                                   float y0, float x1, float y1, void *) {
  out ("CR %s %s %s %s", num (x0).c_str (), num (y0).c_str (),
       num (x1).c_str (), num (y1).c_str ());
}
static void p_pop_clip (hb_paint_funcs_t *, void *, void *) { out ("c"); }
static void p_color (hb_paint_funcs_t *, void *, hb_bool_t fg, hb_color_t c,
                     void *) {
  out ("S %s", color (fg, c).c_str ());
}
static hb_bool_t p_image (hb_paint_funcs_t *, void *, hb_blob_t *blob,
                          unsigned width, unsigned height, hb_tag_t format,
                          float, hb_glyph_extents_t *e, void *) {
  char tag[5] = {0};
  hb_tag_to_string (format, tag);
  out ("I %u %u %s %d %d %d %d %u", width, height, tag, e->x_bearing,
       e->y_bearing, e->width, e->height, hb_blob_get_length (blob));
  return true;
}
static void p_linear (hb_paint_funcs_t *, void *, hb_color_line_t *line,
                      float x0, float y0, float x1, float y1, float x2,
                      float y2, void *) {
  out ("L %s %s %s %s %s %s %s", stops (line).c_str (), num (x0).c_str (),
       num (y0).c_str (), num (x1).c_str (), num (y1).c_str (),
       num (x2).c_str (), num (y2).c_str ());
}
static void p_radial (hb_paint_funcs_t *, void *, hb_color_line_t *line,
                      float x0, float y0, float r0, float x1, float y1,
                      float r1, void *) {
  out ("R %s %s %s %s %s %s %s", stops (line).c_str (), num (x0).c_str (),
       num (y0).c_str (), num (r0).c_str (), num (x1).c_str (),
       num (y1).c_str (), num (r1).c_str ());
}
static void p_sweep (hb_paint_funcs_t *, void *, hb_color_line_t *line,
                     float x, float y, float a0, float a1, void *) {
  out ("W %s %s %s %s %s", stops (line).c_str (), num (x).c_str (),
       num (y).c_str (), num (a0).c_str (), num (a1).c_str ());
}
static void p_push_group (hb_paint_funcs_t *, void *, void *) { out ("G"); }
static void p_pop_group (hb_paint_funcs_t *, void *,
                         hb_paint_composite_mode_t mode, void *) {
  out ("g %d", (int) mode);
}

static int paint (const char *path) {
  hb_blob_t *blob = hb_blob_create_from_file_or_fail (path);
  if (!blob) { fprintf (stderr, "cannot read %s\n", path); return 1; }
  hb_face_t *face = hb_face_create (blob, 0);
  hb_font_t *font = hb_font_create (face);
  hb_paint_funcs_t *funcs = hb_paint_funcs_create ();
  hb_paint_funcs_set_push_transform_func (funcs, p_push_transform, nullptr, nullptr);
  hb_paint_funcs_set_pop_transform_func (funcs, p_pop_transform, nullptr, nullptr);
  hb_paint_funcs_set_fill_glyph_func (funcs, p_fill_glyph, nullptr, nullptr);
  hb_paint_funcs_set_push_clip_glyph_func (funcs, p_push_clip_glyph, nullptr, nullptr);
  hb_paint_funcs_set_push_clip_rectangle_func (funcs, p_push_clip_rectangle, nullptr, nullptr);
  hb_paint_funcs_set_pop_clip_func (funcs, p_pop_clip, nullptr, nullptr);
  hb_paint_funcs_set_color_func (funcs, p_color, nullptr, nullptr);
  hb_paint_funcs_set_image_func (funcs, p_image, nullptr, nullptr);
  hb_paint_funcs_set_linear_gradient_func (funcs, p_linear, nullptr, nullptr);
  hb_paint_funcs_set_radial_gradient_func (funcs, p_radial, nullptr, nullptr);
  hb_paint_funcs_set_sweep_gradient_func (funcs, p_sweep, nullptr, nullptr);
  hb_paint_funcs_set_push_group_func (funcs, p_push_group, nullptr, nullptr);
  hb_paint_funcs_set_pop_group_func (funcs, p_pop_group, nullptr, nullptr);
  std::string line;
  while (std::getline (std::cin, line)) {
    paint_out.clear ();
    transform_emitted.clear ();
    bool painted = hb_font_paint_glyph_or_fail (
        font, (hb_codepoint_t) std::stoul (line), funcs, nullptr, 0,
        HB_COLOR (0, 0, 0, 255));
    printf ("%s\n", painted ? paint_out.c_str () : "-");
  }
  hb_paint_funcs_destroy (funcs);
  hb_font_destroy (font);
  hb_face_destroy (face);
  hb_blob_destroy (blob);
  return 0;
}

int main (int argc, char **argv) {
  if (argc == 2 && strcmp (argv[1], "--language-tags") == 0)
    return language_tags ();
  if (argc == 3 && strcmp (argv[1], "--paint") == 0)
    return paint (argv[2]);
  if (argc < 2) {
    fprintf (stderr, "usage: hb-oracle FONT [FEATURE...] < LINES\n");
    return 2;
  }
  hb_blob_t *blob = hb_blob_create_from_file_or_fail (argv[1]);
  if (!blob) { fprintf (stderr, "cannot read %s\n", argv[1]); return 1; }
  hb_face_t *face = hb_face_create (blob, 0);
  hb_font_t *font = hb_font_create (face);
  std::vector<hb_feature_t> features;
  bool ttb = false;
  const char *language = nullptr;
  for (int i = 2; i < argc; i++) {
    if (strcmp (argv[i], "--ttb") == 0) { ttb = true; continue; }
    if (strncmp (argv[i], "--language=", 11) == 0) {
      language = argv[i] + 11;
      continue;
    }
    hb_feature_t f;
    if (hb_feature_from_string (argv[i], -1, &f)) features.push_back (f);
  }
  std::string line;
  while (std::getline (std::cin, line)) {
    hb_buffer_t *buffer = hb_buffer_create ();
    hb_buffer_add_utf8 (buffer, line.c_str (), (int) line.size (), 0, -1);
    if (ttb) hb_buffer_set_direction (buffer, HB_DIRECTION_TTB);
    if (language)
      hb_buffer_set_language (buffer, hb_language_from_string (language, -1));
    hb_buffer_guess_segment_properties (buffer);
    hb_buffer_set_cluster_level (buffer, HB_BUFFER_CLUSTER_LEVEL_CHARACTERS);
    hb_shape (font, buffer, features.data (), (unsigned) features.size ());
    unsigned count;
    hb_glyph_info_t *info = hb_buffer_get_glyph_infos (buffer, &count);
    hb_glyph_position_t *pos = hb_buffer_get_glyph_positions (buffer, &count);
    printf ("[");
    for (unsigned i = 0; i < count; i++)
      printf ("%s[%u,%u,%d,%d,%d]", i ? "," : "", info[i].codepoint,
              info[i].cluster, ttb ? pos[i].y_advance : pos[i].x_advance,
              pos[i].x_offset,
              pos[i].y_offset);
    printf ("]\n");
    hb_buffer_destroy (buffer);
  }
  hb_font_destroy (font);
  hb_face_destroy (face);
  hb_blob_destroy (blob);
  return 0;
}
