// Twenty covers for the out-of-box cards: one visual system, drawn as SVG,
// sliced to 800x500 WebP through Chromium, and -- with --sheet=<dir> -- laid out on
// a contact sheet over a light and a dark ground for a look.
//
//   cd web && node ../samples/covers/make-covers.mjs [--sheet=/tmp/covers-sheet]
//
// System: a 1600x1000 canvas (16:10), a self-contained ground so the picture reads
// the same on either theme, a small palette, big geometric shapes, 6px strokes
// (3px at output), no text.

import { chromium } from "../../web/node_modules/playwright/index.mjs";
import { mkdirSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const sheetDir = (process.argv.find((a) => a.startsWith("--sheet=")) ?? "").slice(8) || null;
const out = { svg: resolve(here, "svg"), webp: here, sheet: sheetDir };
mkdirSync(out.svg, { recursive: true });
if (out.sheet) mkdirSync(resolve(out.sheet, "png"), { recursive: true });

const W = 1600, H = 1000;
const P = {
  teal: "#3ec7bb", amber: "#f2b84b", coral: "#ef7d6a", lavender: "#a99bf0",
  mint: "#8fd3a7", paper: "#f3ead8", sky: "#7cc4f5", rose: "#f0a3c0",
  ink: "rgba(255,255,255,0.78)", inkSoft: "rgba(255,255,255,0.42)", inkFaint: "rgba(255,255,255,0.14)",
};
// Four grounds, each a soft radial from a lit centre to a darker rim.
const GROUNDS = {
  slate: ["#2a3443", "#171c26"],
  teal: ["#1d4a4a", "#0f2a2c"],
  plum: ["#372a52", "#1e1730"],
  ember: ["#3d2f2a", "#211915"],
};
const SW = 6;

function svg(ground, body) {
  const [c, e] = GROUNDS[ground];
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">
<defs>
  <radialGradient id="g" cx="50%" cy="42%" r="75%"><stop offset="0" stop-color="${c}"/><stop offset="1" stop-color="${e}"/></radialGradient>
  <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="18"/></filter>
</defs>
<rect width="${W}" height="${H}" fill="url(#g)"/>
<rect x="28" y="28" width="${W - 56}" height="${H - 56}" rx="26" fill="none" stroke="${P.inkFaint}" stroke-width="2"/>
${body}
</svg>`;
}

// ---- small vocabulary -------------------------------------------------------
const stroke = (c = P.ink, w = SW) => `fill="none" stroke="${c}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"`;
const glow = (x, y, r, c) => `<circle cx="${x}" cy="${y}" r="${r}" fill="${c}" opacity="0.18" filter="url(#soft)"/>`;
/** A paper card: rounded rect with a title bar and n text lines. */
function card(x, y, w, h, { fill = P.paper, lines = 3, accent = P.teal, tilt = 0 } = {}) {
  const pad = 36, lineGap = (h - pad * 2 - 40) / Math.max(lines, 1);
  let s = `<g transform="rotate(${tilt} ${x + w / 2} ${y + h / 2})">`;
  s += `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="22" fill="${fill}"/>`;
  s += `<rect x="${x + pad}" y="${y + pad}" width="${w * 0.42}" height="22" rx="11" fill="${accent}"/>`;
  for (let i = 0; i < lines; i++) {
    const ly = y + pad + 70 + i * lineGap, lw = w - pad * 2 - (i % 2 ? w * 0.28 : w * 0.1);
    s += `<rect x="${x + pad}" y="${ly}" width="${lw}" height="14" rx="7" fill="#1b2230" opacity="0.28"/>`;
  }
  return s + `</g>`;
}
/** A row of lane columns, each with cards. */
function lanes(x, y, w, h, counts, dragged) {
  const gap = 40, cw = (w - gap * (counts.length - 1)) / counts.length;
  let s = "";
  counts.forEach((n, i) => {
    const cx = x + i * (cw + gap);
    s += `<rect x="${cx}" y="${y}" width="${cw}" height="${h}" rx="24" fill="${P.inkFaint}"/>`;
    s += `<rect x="${cx + 28}" y="${y + 26}" width="${cw * 0.45}" height="16" rx="8" fill="${P.inkSoft}"/>`;
    for (let k = 0; k < n; k++) {
      const cy = y + 76 + k * 118;
      s += card(cx + 24, cy, cw - 48, 96, { lines: 1, accent: [P.teal, P.amber, P.lavender][(i + k) % 3] });
    }
  });
  if (dragged) {
    const [dx, dy] = dragged;
    s += `<rect x="${dx + 10}" y="${dy + 16}" width="${cw - 48}" height="96" rx="22" fill="#000" opacity="0.28" filter="url(#soft)"/>`;
    s += card(dx, dy, cw - 48, 96, { lines: 1, accent: P.coral, tilt: -4 });
  }
  return s;
}
const tag = (x, y, c) => `<circle cx="${x}" cy="${y}" r="110" ${stroke(c, 8)} fill="${c}" fill-opacity="0.22"/>`;

// ---- the twenty ------------------------------------------------------------
const scenes = [
  // -- the recipe app's cards ----------------------------------------------------
  { id: "search-duplicates", title: "Search returns duplicates when tags overlap", ground: "slate", body: () => `
    ${glow(800, 430, 340, P.teal)}
    <circle cx="690" cy="430" r="190" fill="${P.teal}" fill-opacity="0.28" ${stroke(P.teal, 12)}/>
    <circle cx="910" cy="430" r="190" fill="${P.amber}" fill-opacity="0.28" ${stroke(P.amber, 12)}/>
    <path d="M800 266 a190 190 0 0 1 0 328 a190 190 0 0 1 0 -328 z" fill="${P.coral}" opacity="0.9"/>
    ${card(560, 720, 220, 110, { lines: 1, accent: P.coral })}
    ${card(820, 720, 220, 110, { lines: 1, accent: P.coral })}
    <path d="M790 720 l20 0" ${stroke(P.coral, 10)}/>` },
  { id: "shopping-list-double", title: "The shopping list double counts an ingredient", ground: "ember", body: () => `
    ${glow(800, 500, 320, P.amber)}
    <rect x="470" y="150" width="660" height="700" rx="28" fill="${P.paper}"/>
    ${[0, 1, 2, 3, 4].map((i) => {
      const y = 230 + i * 125, dup = i === 1 || i === 3;
      return `<rect x="530" y="${y}" width="56" height="56" rx="12" ${stroke(dup ? P.coral : "#1b2230", 6)} fill="${dup ? P.coral : "none"}" fill-opacity="0.25"/>
      ${dup ? `<path d="M544 ${y + 30} l14 14 l26 -30" ${stroke(P.coral, 8)}/>` : ""}
      <rect x="620" y="${y + 16}" width="${dup ? 300 : 230 + i * 30}" height="24" rx="12" fill="#1b2230" opacity="${dup ? 0.6 : 0.28}"/>`;
    }).join("")}
    <path d="M960 383 q130 0 130 125 q0 125 -130 125" ${stroke(P.coral, 10)} stroke-dasharray="18 18"/>
    <circle cx="960" cy="383" r="16" fill="${P.coral}"/><circle cx="960" cy="633" r="16" fill="${P.coral}"/>` },
  { id: "scale-by-servings", title: "Scale a recipe by servings", ground: "teal", body: () => `
    ${glow(560, 600, 240, P.mint)}${glow(1120, 560, 320, P.amber)}
    <path d="M360 560 l320 0 l-40 150 q-10 40 -50 40 l-140 0 q-40 0 -50 -40 z" fill="${P.paper}"/>
    <rect x="470" y="750" width="100" height="26" rx="8" fill="${P.paper}" opacity="0.8"/>
    <ellipse cx="520" cy="560" rx="160" ry="34" fill="${P.mint}"/>
    <path d="M820 470 l560 0 l-70 250 q-14 50 -64 50 l-292 0 q-50 0 -64 -50 z" fill="${P.paper}"/>
    <rect x="1030" y="770" width="140" height="30" rx="8" fill="${P.paper}" opacity="0.8"/>
    <ellipse cx="1100" cy="470" rx="280" ry="56" fill="${P.amber}"/>
    <path d="M700 420 l80 0 m-30 -30 l30 30 l-30 30" ${stroke(P.ink, 10)}/>
    <path d="M740 260 l0 80 m-40 -40 l80 0" ${stroke(P.amber, 12)}/>` },
  { id: "paginate", title: "Paginate the recipe list", ground: "plum", body: () => `
    ${glow(800, 420, 360, P.lavender)}
    ${card(430, 150, 740, 110, { lines: 1, accent: P.lavender })}
    ${card(430, 290, 740, 110, { lines: 1, accent: P.teal })}
    ${card(430, 430, 740, 110, { lines: 1, accent: P.amber })}
    ${card(430, 570, 740, 110, { lines: 1, accent: P.lavender })}
    <rect x="560" y="760" width="480" height="90" rx="45" fill="${P.inkFaint}"/>
    <path d="M630 805 l-24 0 m8 -16 l-16 16 l16 16" ${stroke(P.ink, 8)}/>
    <circle cx="730" cy="805" r="14" fill="${P.ink}"/><circle cx="800" cy="805" r="22" fill="${P.lavender}"/><circle cx="870" cy="805" r="14" fill="${P.ink}"/>
    <path d="M970 805 l24 0 m-8 -16 l16 16 l-16 16" ${stroke(P.ink, 8)}/>` },
  { id: "unit-conversion", title: "Extract unit conversion into a pure module", ground: "slate", body: () => `
    ${glow(520, 560, 260, P.sky)}${glow(1080, 560, 260, P.sky)}
    <path d="M380 300 l0 430 q0 40 40 40 l200 0 q40 0 40 -40 l0 -430 z" fill="${P.paper}"/>
    <rect x="380" y="520" width="280" height="250" rx="0" fill="${P.sky}" opacity="0.85"/>
    ${[0, 1, 2, 3].map((i) => `<line x1="600" y1="${360 + i * 100}" x2="650" y2="${360 + i * 100}" ${stroke("#1b2230", 6)}/>`).join("")}
    <path d="M940 300 l0 430 q0 40 40 40 l200 0 q40 0 40 -40 l0 -430 z" fill="${P.paper}"/>
    <rect x="940" y="640" width="280" height="130" fill="${P.sky}" opacity="0.85"/>
    ${[0, 1, 2, 3, 4, 5, 6].map((i) => `<line x1="1160" y1="${340 + i * 62}" x2="1210" y2="${340 + i * 62}" ${stroke("#1b2230", 6)}/>`).join("")}
    <line x1="740" y1="500" x2="860" y2="500" ${stroke(P.ink, 12)}/><line x1="740" y1="560" x2="860" y2="560" ${stroke(P.ink, 12)}/>` },
  { id: "import-from-photo", title: "Can we import a recipe from a photo?", ground: "ember", body: () => `
    ${glow(520, 480, 300, P.rose)}
    <rect x="260" y="230" width="520" height="520" rx="26" fill="${P.paper}"/>
    <rect x="300" y="270" width="440" height="380" rx="14" fill="#1b2230" opacity="0.85"/>
    <circle cx="520" cy="470" r="120" fill="${P.rose}" opacity="0.9"/><circle cx="520" cy="470" r="70" fill="${P.coral}"/>
    <circle cx="660" cy="330" r="22" fill="${P.amber}"/>
    <path d="M820 480 l180 0" ${stroke(P.ink, 10)} stroke-dasharray="20 22"/>
    <path d="M1000 480 l-30 -30 m30 30 l-30 30" ${stroke(P.ink, 10)}/>
    ${card(1060, 290, 300, 400, { lines: 5, accent: P.rose })}` },
  { id: "sprint-review", title: "Sprint review with the client", ground: "plum", body: () => `
    ${glow(700, 520, 340, P.lavender)}
    <rect x="330" y="200" width="740" height="620" rx="28" fill="${P.paper}"/>
    <rect x="330" y="200" width="740" height="110" rx="28" fill="${P.lavender}"/>
    ${Array.from({ length: 21 }, (_, i) => {
      const cx = 400 + (i % 7) * 100, cy = 380 + Math.floor(i / 7) * 130, mark = i === 10;
      return mark ? `<circle cx="${cx}" cy="${cy}" r="42" fill="${P.coral}"/>` : `<circle cx="${cx}" cy="${cy}" r="16" fill="#1b2230" opacity="0.25"/>`;
    }).join("")}
    <path d="M1090 420 q0 -70 70 -70 l180 0 q70 0 70 70 l0 130 q0 70 -70 70 l-120 0 l-70 70 l0 -70 q-60 0 -60 -70 z" fill="${P.teal}"/>
    <rect x="1190" y="420" width="130" height="16" rx="8" fill="#1b2230" opacity="0.35"/><rect x="1190" y="470" width="90" height="16" rx="8" fill="#1b2230" opacity="0.35"/>` },
  { id: "welcome", title: "Welcome to the Toolkit", ground: "teal", body: () => `
    ${glow(800, 470, 420, P.amber)}
    <rect x="620" y="200" width="360" height="620" rx="30" fill="${P.paper}"/>
    <rect x="660" y="240" width="280" height="540" rx="18" fill="${P.amber}" opacity="0.95"/>
    <circle cx="900" cy="520" r="18" fill="#1b2230" opacity="0.6"/>
    <path d="M980 520 q100 0 150 -150" ${stroke(P.ink, 10)} stroke-dasharray="18 20"/>
    <path d="M980 520 q100 0 150 150" ${stroke(P.ink, 10)} stroke-dasharray="18 20"/>
    ${card(1130, 240, 240, 130, { lines: 1, accent: P.teal, tilt: 6 })}
    ${card(1130, 640, 240, 130, { lines: 1, accent: P.lavender, tilt: -5 })}
    <path d="M260 560 l220 0 m-50 -50 l50 50 l-50 50" ${stroke(P.amber, 14)}/>` },
  { id: "recipe-card", title: "A recipe", ground: "ember", body: () => `
    ${glow(800, 500, 360, P.coral)}
    ${card(420, 170, 760, 660, { lines: 6, accent: P.coral })}
    <circle cx="1070" cy="690" r="86" fill="${P.coral}"/><path d="M1070 604 q30 -60 70 -50" ${stroke(P.mint, 10)}/>
    <circle cx="1030" cy="660" r="22" fill="${P.paper}" opacity="0.5"/>` },
  { id: "kitchen-timer", title: "A timer", ground: "slate", body: () => `
    ${glow(800, 520, 360, P.teal)}
    <circle cx="800" cy="540" r="300" fill="${P.paper}"/>
    <circle cx="800" cy="540" r="250" ${stroke("#1b2230", 10)} opacity="0.35"/>
    <path d="M800 540 L800 290 A250 250 0 0 1 1017 415 Z" fill="${P.teal}" opacity="0.85"/>
    <circle cx="800" cy="540" r="26" fill="#1b2230"/>
    <rect x="740" y="190" width="120" height="50" rx="16" fill="${P.paper}"/>
    ${Array.from({ length: 12 }, (_, i) => { const a = (i / 12) * Math.PI * 2; return `<circle cx="${800 + Math.sin(a) * 215}" cy="${540 - Math.cos(a) * 215}" r="9" fill="#1b2230" opacity="0.5"/>`; }).join("")}` },
  // -- the Toolkit itself -----------------------------------------------------------
  { id: "the-board", title: "The board", ground: "slate", body: () => `
    ${glow(800, 480, 420, P.teal)}
    ${lanes(220, 170, 1160, 660, [3, 2, 1], [560, 420])}` },
  { id: "the-card-file", title: "A card is a file", ground: "plum", body: () => `
    ${glow(800, 500, 360, P.lavender)}
    <rect x="520" y="150" width="560" height="700" rx="28" fill="${P.paper}"/>
    <rect x="580" y="220" width="300" height="26" rx="13" fill="${P.lavender}"/>
    ${[0, 1, 2].map((i) => `<circle cx="604" cy="${330 + i * 70}" r="14" fill="${P.teal}"/><rect x="640" y="${320 + i * 70}" width="${300 - i * 60}" height="20" rx="10" fill="#1b2230" opacity="0.3"/>`).join("")}
    <rect x="580" y="580" width="440" height="20" rx="10" fill="#1b2230" opacity="0.3"/>
    <rect x="580" y="630" width="380" height="20" rx="10" fill="#1b2230" opacity="0.3"/>
    <path d="M590 740 l40 40 l80 -80" ${stroke(P.mint, 14)}/>` },
  { id: "pull-request", title: "A pull request", ground: "teal", body: () => `
    ${glow(800, 500, 380, P.mint)}
    <path d="M520 220 l0 560" ${stroke(P.ink, 26)}/>
    <path d="M520 400 q0 180 360 180 l200 0" ${stroke(P.mint, 26)}/>
    <path d="M1080 260 l0 320" ${stroke(P.mint, 26)}/>
    <circle cx="520" cy="220" r="54" fill="${P.ink}"/><circle cx="520" cy="780" r="54" fill="${P.ink}"/>
    <circle cx="1080" cy="260" r="54" fill="${P.mint}"/><circle cx="1080" cy="580" r="66" fill="${P.amber}"/>
    <path d="M1240 440 l0 290 m-50 -50 l50 50 l50 -50" ${stroke(P.amber, 18)}/>` },
  { id: "archive-one-way", title: "A card travels one way", ground: "ember", body: () => `
    ${glow(1000, 600, 360, P.amber)}
    <path d="M740 660 l520 0 l0 180 q0 30 -30 30 l-460 0 q-30 0 -30 -30 z" fill="${P.paper}"/>
    <rect x="700" y="600" width="600" height="70" rx="18" fill="${P.amber}"/>
    <rect x="960" y="620" width="80" height="30" rx="15" fill="#1b2230" opacity="0.4"/>
    ${card(300, 300, 300, 160, { lines: 2, accent: P.teal, tilt: -8 })}
    <path d="M640 440 q140 60 260 170" ${stroke(P.ink, 10)} stroke-dasharray="18 20"/>
    <path d="M900 610 l-40 -8 m40 8 l-10 -40" ${stroke(P.ink, 10)}/>` },
  { id: "hub-cabinet", title: "The hub", ground: "slate", body: () => `
    ${glow(800, 520, 380, P.amber)}
    <rect x="480" y="160" width="640" height="700" rx="26" fill="${P.paper}"/>
    ${[0, 1, 2].map((i) => `<rect x="520" y="${200 + i * 215}" width="560" height="190" rx="18" fill="#1b2230" opacity="0.14"/><rect x="740" y="${282 + i * 215}" width="120" height="26" rx="13" fill="#1b2230" opacity="0.45"/>`).join("")}
    <path d="M560 300 l110 -60 l110 60 l-110 50 z" fill="${P.amber}"/><path d="M560 300 l110 50 l110 -50" ${stroke("#1b2230", 6)} opacity="0.4"/>
    <path d="M900 515 l110 -60 l110 60 l-110 50 z" fill="${P.teal}"/><path d="M900 515 l110 50 l110 -50" ${stroke("#1b2230", 6)} opacity="0.4"/>` },
  { id: "two-windows", title: "Connect a tracker", ground: "plum", body: () => `
    ${glow(560, 440, 300, P.sky)}${glow(1120, 440, 300, P.lavender)}
    <rect x="330" y="220" width="420" height="480" rx="26" fill="${P.paper}"/>
    <rect x="370" y="260" width="340" height="400" rx="16" fill="${P.sky}" opacity="0.9"/>
    <line x1="540" y1="260" x2="540" y2="660" ${stroke(P.paper, 10)}/><line x1="370" y1="460" x2="710" y2="460" ${stroke(P.paper, 10)}/>
    <rect x="850" y="220" width="420" height="480" rx="26" fill="${P.paper}"/>
    <rect x="890" y="260" width="340" height="400" rx="16" fill="${P.lavender}" opacity="0.9"/>
    <line x1="1060" y1="260" x2="1060" y2="660" ${stroke(P.paper, 10)}/><line x1="890" y1="460" x2="1230" y2="460" ${stroke(P.paper, 10)}/>
    <path d="M750 760 q50 60 100 0 t100 0" ${stroke(P.amber, 16)}/>
    <rect x="690" y="730" width="60" height="60" rx="14" fill="${P.amber}"/><rect x="850" y="730" width="60" height="60" rx="14" fill="${P.amber}"/>
    <path d="M750 760 l100 0" ${stroke(P.amber, 16)}/>` },
  { id: "the-studio", title: "The Studio", ground: "teal", body: () => `
    ${glow(800, 500, 400, P.teal)}
    ${[0, 1, 2, 3].map((i) => `<rect x="${290 + i * 265}" y="300" width="225" height="300" rx="24" fill="${P.paper}"/>
      <rect x="${320 + i * 265}" y="330" width="165" height="120" rx="14" fill="${[P.teal, P.amber, P.lavender, P.coral][i]}" opacity="0.9"/>
      <rect x="${320 + i * 265}" y="480" width="120" height="18" rx="9" fill="#1b2230" opacity="0.3"/><rect x="${320 + i * 265}" y="520" width="80" height="18" rx="9" fill="#1b2230" opacity="0.3"/>`).join("")}
    <rect x="290" y="680" width="1020" height="8" rx="4" fill="${P.inkSoft}"/>` },
  { id: "the-lounge", title: "The Lounge", ground: "plum", body: () => `
    ${glow(1100, 300, 260, P.paper)}
    <circle cx="1100" cy="300" r="90" fill="${P.paper}" opacity="0.95"/>
    <path d="M380 340 q420 -70 840 0 l0 70 l-840 0 z" fill="${P.coral}"/>
    <rect x="470" y="410" width="660" height="50" rx="12" fill="${P.coral}"/>
    <rect x="520" y="340" width="60" height="420" fill="${P.coral}"/><rect x="1020" y="340" width="60" height="420" fill="${P.coral}"/>
    <rect x="300" y="790" width="1000" height="70" rx="35" fill="${P.sky}" opacity="0.55"/>
    <path d="M330 825 q80 -24 160 0 t160 0 t160 0 t160 0 t160 0 t160 0" ${stroke(P.paper, 10)} opacity="0.7"/>` },
  { id: "a-bug", title: "A bug", ground: "ember", body: () => `
    ${glow(800, 520, 360, P.coral)}
    <ellipse cx="800" cy="560" rx="200" ry="250" fill="${P.coral}"/>
    <circle cx="800" cy="330" r="110" fill="${P.coral}"/>
    <line x1="800" y1="330" x2="800" y2="810" ${stroke("#1b2230", 10)} opacity="0.45"/>
    <circle cx="720" cy="500" r="30" fill="#1b2230" opacity="0.45"/><circle cx="880" cy="500" r="30" fill="#1b2230" opacity="0.45"/><circle cx="760" cy="650" r="30" fill="#1b2230" opacity="0.45"/><circle cx="840" cy="650" r="30" fill="#1b2230" opacity="0.45"/>
    ${[[-1,420],[-1,540],[-1,660],[1,420],[1,540],[1,660]].map(([d,y]) => `<path d="M${800 + d*190} ${y} l${d*90} ${y < 500 ? -60 : 40} l${d*60} ${y < 500 ? -10 : 60}" ${stroke(P.coral, 22)}/>`).join("")}
    <path d="M740 250 l-70 -90 M860 250 l70 -90" ${stroke(P.coral, 18)}/>` },
  { id: "a-spike", title: "A spike", ground: "slate", body: () => `
    ${glow(800, 560, 360, P.lavender)}
    <path d="M300 700 l1000 0" ${stroke(P.inkSoft, 10)}/>
    <path d="M800 160 l170 540 l-340 0 z" fill="${P.lavender}" opacity="0.95"/>
    <path d="M800 160 l60 190 l-120 0 z" fill="${P.paper}"/>
    <path d="M620 760 q0 70 70 70 l220 0 q70 0 70 -70" ${stroke(P.inkSoft, 10)} stroke-dasharray="16 20"/>
    <circle cx="1140" cy="300" r="60" ${stroke(P.amber, 12)}/><path d="M1120 285 q20 -30 45 -5 q15 20 -15 35 l-5 20 M1145 360 l0 8" ${stroke(P.amber, 12)}/>` },
];

// ---- render ---------------------------------------------------------------------
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 800, height: 500 }, deviceScaleFactor: 1 });
await page.setContent("<canvas id=c width=800 height=500></canvas>");
const shot = await browser.newPage({ viewport: { width: 800, height: 500 }, deviceScaleFactor: 1 });
for (const s of scenes) {
  const text = svg(s.ground, s.body());
  writeFileSync(resolve(out.svg, `${s.id}.svg`), text);
  // Chromium draws the SVG as a page and hands back PNG bytes; the canvas page then
  // re-encodes them as WebP at quality 0.82 -- 6-11 KB a cover.
  await shot.setContent(`<!doctype html><html><body style="margin:0">${text.replace(`width="${W}" height="${H}"`, 'width="800" height="500"')}</body></html>`);
  const png = await shot.screenshot({ type: "png" });
  if (out.sheet) writeFileSync(resolve(out.sheet, "png", `${s.id}.png`), png);
  const dataUrl = await page.evaluate(async (b64) => {
    const img = new Image(); img.src = "data:image/png;base64," + b64; await img.decode();
    const c = document.getElementById("c"); c.getContext("2d").drawImage(img, 0, 0, 800, 500);
    return c.toDataURL("image/webp", 0.82);
  }, png.toString("base64"));
  writeFileSync(resolve(out.webp, `${s.id}.webp`), Buffer.from(dataUrl.split(",")[1], "base64"));
}

if (out.sheet) {
  // The contact sheet: the twenty on a light ground, then on a dark one, each tile the
  // way the board draws a card face (16:10 top, a title line under).
  const tile = (s) => `<div class="card"><img src="png/${s.id}.png" alt=""><div class="t">${s.title}</div><div class="k">${s.id}</div></div>`;
  const half = (dark) => `<section class="${dark ? "dark" : "light"}"><h2>${dark ? "Dark theme" : "Light theme"}</h2><div class="grid">${scenes.map(tile).join("")}</div></section>`;
  const sheet = `<!doctype html><html><head><meta charset="utf-8"><style>
  body{margin:0;font-family:-apple-system,Segoe UI,sans-serif}
  section{padding:28px 32px 40px}
  .light{background:#f5f5f5;color:#242424}.dark{background:#292929;color:#f0f0f0}
  h2{font-size:14px;letter-spacing:.08em;text-transform:uppercase;opacity:.7;margin:0 0 18px}
  .grid{display:grid;grid-template-columns:repeat(5,1fr);gap:18px}
  .card{border-radius:8px;overflow:hidden;border:1px solid rgba(128,128,128,.35)}
  .light .card{background:#fff}.dark .card{background:#333}
  img{display:block;width:100%;aspect-ratio:16/10}
  .t{font-size:13px;font-weight:600;padding:10px 12px 2px}
  .k{font-size:11px;opacity:.6;padding:0 12px 12px;font-family:ui-monospace,monospace}
</style></head><body>${half(false)}${half(true)}</body></html>`;
  writeFileSync(resolve(out.sheet, "contact-sheet.html"), sheet);
  const sheetPage = await browser.newPage({ viewport: { width: 1600, height: 1200 } });
  await sheetPage.goto(`file://${resolve(out.sheet, "contact-sheet.html")}`);
  await sheetPage.screenshot({ path: resolve(out.sheet, "contact-sheet.png"), fullPage: true });
}
await browser.close();
console.log(`wrote ${scenes.length} svg + webp${out.sheet ? ", and the contact sheet" : ""}`);
