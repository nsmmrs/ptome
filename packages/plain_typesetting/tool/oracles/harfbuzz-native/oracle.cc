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

int main (int argc, char **argv) {
  if (argc == 2 && strcmp (argv[1], "--language-tags") == 0)
    return language_tags ();
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
