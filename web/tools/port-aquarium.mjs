// Port the aquarium-saver scapes into the Lounge as self-contained documents.
//
// The tank skin's scenes are PORTED, never imported across repos
// (spec/toolkit-lounge.spec.md, "what ported means"): this tool reads the
// sibling checkout's index.html -- the engine CSS, the shared symbol library,
// and each scape's stage SVG -- and emits one full-bleed, zero-JavaScript
// HTML document per scape under web/public/lounge/aquarium/. Assets, not
// bundle: the Lounge mounts them in a sandboxed iframe, so a machine with the
// module off ships and fetches nothing, and the saver runs exactly as built
// -- "on its own slow clocks", reduced-motion resting pose included, because
// the engine's own @media rule travels with it.
//
// Run from web/:  node tools/port-aquarium.mjs [path-to-aquarium-saver]
// Re-run to re-port after the studio changes; the outputs are committed.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const source = process.argv[2] ?? join(here, "..", "..", "..", "aquarium-saver");
const outDir = join(here, "..", "public", "lounge", "aquarium");
const html = readFileSync(join(source, "index.html"), "utf8");

function block(startMark, endMark, from = 0) {
  const a = html.indexOf(startMark, from);
  if (a < 0) throw new Error(`not found: ${startMark}`);
  const b = html.indexOf(endMark, a);
  if (b < 0) throw new Error(`unterminated: ${startMark}`);
  return { text: html.slice(a, b + endMark.length), end: b };
}

// The engine's stylesheet is the <style> block that declares the room tokens.
const styleBlocks = [...html.matchAll(/<style>([\s\S]*?)<\/style>/g)].map((m) => m[1]);
const engineCss = styleBlocks.find((s) => s.includes("--room:"));
if (!engineCss) throw new Error("engine css (--room:) not found");
if (!engineCss.includes("prefers-reduced-motion")) {
  throw new Error("the engine css lost its reduced-motion rule -- refusing to port without it");
}

// The shared symbol library -- every plant, fish, stone, light and room.
const lib = block('<svg class="lib"', "</svg>").text;

const scapes = [
  { id: "nature", title: "nature style", world: "fresh water · nordic room" },
  { id: "iwagumi", title: "iwagumi", world: "fresh water · nordic room" },
  { id: "dutch", title: "dutch street", world: "fresh water · vienna room" },
  { id: "jungle", title: "moss jungle", world: "fresh water · paris room" },
  { id: "reef", title: "reef range", world: "salt water · vienna room" },
  { id: "lagoon", title: "lagoon", world: "salt water · nordic room" },
  { id: "garden", title: "coral garden", world: "salt water · paris room" },
];

mkdirSync(outDir, { recursive: true });
for (const { id, title, world } of scapes) {
  const section = block(`<section class="scene" id="${id}">`, "</section>");
  const stageStart = section.text.indexOf('<svg class="stage"');
  const stageEnd = section.text.lastIndexOf("</svg>");
  if (stageStart < 0 || stageEnd < 0) throw new Error(`no stage svg in #${id}`);
  const stage = section.text.slice(stageStart, stageEnd + "</svg>".length);
  const doc = `<!doctype html>
<!-- Ported from aquarium-saver (MIT) by web/tools/port-aquarium.mjs.
     ${title} — ${world}. Zero JavaScript; the saver's own clocks and its own
     reduced-motion resting pose. Do not edit by hand: re-port instead. -->
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${title}</title>
    <style>
      html, body { margin: 0; height: 100%; background: #0d0b16; overflow: hidden; color-scheme: dark; }
      .lib { position: absolute; width: 0; height: 0; overflow: hidden; }
      svg.stage { position: fixed; inset: 0; width: 100%; height: 100%; display: block; }
      /* STILL, with zero JavaScript: load this document as <src>#still and
         the body matches :target, freezing every clock at the saver's own
         resting pose -- the same pose its reduced-motion rule holds. The
         Lounge's Still control and a frozen grant both ride this fragment. */
      body:target, body:target * { animation: none !important; }
    </style>
    <style>${engineCss}</style>
  </head>
  <body id="still">
    ${lib}
    ${stage}
  </body>
</html>
`;
  writeFileSync(join(outDir, `${id}.html`), doc);
  console.log(`${id}.html  ${(doc.length / 1024).toFixed(0)}kb  (${title} — ${world})`);
}
console.log(`\n${scapes.length} scapes ported to ${outDir}`);
