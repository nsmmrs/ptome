// Reads {font, runs: [{text, features}], detail?} as JSON on standard
// input (font: a path; features: HarfBuzz feature strings such as "-liga"
// or "onum") and writes, as a JSON array, HarfBuzz's glyphs for each run:
// [glyph id, x advance in font units] pairs, kerning included in the
// advance; with detail, [glyph id, cluster, x advance, x offset, y
// offset] in visual order (the runs' direction and script guessed from
// their text, as HarfBuzz guesses them).
import { readFileSync } from 'node:fs';
import * as hb from 'harfbuzzjs';

let input = '';
for await (const chunk of process.stdin) input += chunk;
const { font: path, runs, detail } = JSON.parse(input);
const font = new hb.Font(new hb.Face(new hb.Blob(readFileSync(path))));
const out = runs.map(({ text, features }) => {
  const buffer = new hb.Buffer();
  buffer.addText(text);
  buffer.guessSegmentProperties();
  // (Clusters by character: a mark its own.)
  if (detail) buffer.setClusterLevel(2);
  hb.shape(font, buffer, features.map((f) => hb.Feature.fromString(f)));
  const positions = buffer.getGlyphPositions();
  return buffer.getGlyphInfos().map((g, i) =>
    detail
      ? [g.codepoint, g.cluster, positions[i].xAdvance, positions[i].xOffset, positions[i].yOffset]
      : [g.codepoint, positions[i].xAdvance],
  );
});
process.stdout.write(JSON.stringify(out));
