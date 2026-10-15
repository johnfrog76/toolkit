import fs from "node:fs";
import path from "node:path";

import { tokens } from "@fluentui/react-components";

import { thinScrollbar } from "./thinScrollbar";

// The themed scrollbar is written once. It was three identical copies and a
// fourth surface with none; this holds it to one.

const SRC_DIR = path.resolve(__dirname, "..");
const HOME = path.join("shared", "thinScrollbar.ts");

function walk(dir: string, out: string[] = []): string[] {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (/\.tsx?$/.test(entry.name) && !/\.test\.tsx?$/.test(entry.name)) out.push(full);
  }
  return out;
}

describe("thinScrollbar", () => {
  it("draws the webkit bar from the neutral strokes, 6px", () => {
    expect(thinScrollbar["&::-webkit-scrollbar"]).toMatchObject({ width: "6px" });
    expect(thinScrollbar["&::-webkit-scrollbar-thumb"]).toMatchObject({
      backgroundColor: tokens.colorNeutralStroke2,
    });
    expect(thinScrollbar["&::-webkit-scrollbar-thumb:hover"]).toMatchObject({
      backgroundColor: tokens.colorNeutralStroke1,
    });
  });

  it("gives an engine without the pseudo-elements the standard pair, from the same token", () => {
    expect(thinScrollbar["@supports not selector(::-webkit-scrollbar)"]).toEqual({
      scrollbarWidth: "thin",
      scrollbarColor: `${tokens.colorNeutralStroke2} transparent`,
    });
  });

  it("is the only place in src/ that styles a scrollbar", () => {
    const offenders = walk(SRC_DIR)
      .filter((f) => path.relative(SRC_DIR, f) !== HOME)
      .filter((f) =>
        /::-webkit-scrollbar|scrollbarColor|scrollbarWidth/.test(fs.readFileSync(f, "utf8")),
      )
      .map((f) => path.relative(SRC_DIR, f));
    expect(offenders).toEqual([]);
  });
});
