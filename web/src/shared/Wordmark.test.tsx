import { render, screen } from "@testing-library/react";
import { Wordmark, WORDMARK_NAME } from "./Wordmark";
import { WORDMARK_FACES, WORDMARK_LETTERS } from "./wordmarkPaths";
import { DEFAULT_FACE_ID, FACES } from "./faces";

// The wordmark draws with no font: seven letters as outlines, the blob, and
// one face, with every colour and the size the caller's.

describe("the wordmark", () => {
  test("every face the app knows has an outline for both themes", () => {
    expect(WORDMARK_FACES.map((f) => f.id)).toEqual(FACES.map((f) => f.id));
    for (const f of WORDMARK_FACES) {
      expect(f.light.d).toMatch(/^M/);
      expect(f.dark.d).toMatch(/^M/);
    }
    expect(WORDMARK_LETTERS.map((l) => l.char).join("")).toBe(WORDMARK_NAME);
  });

  test("named for a screen reader, sized and coloured by its arguments", () => {
    render(<Wordmark size={120} ink="#111" blob="#abc" face="cat" theme="light" />);
    const svg = screen.getByRole("img", { name: WORDMARK_NAME });
    expect(svg.getAttribute("style")).toContain("width: 120px");
    const paths = svg.querySelectorAll("path");
    expect(paths).toHaveLength(WORDMARK_LETTERS.length + 1);
    expect(paths[0].getAttribute("fill")).toBe("#111");
    expect(svg.querySelector("circle")?.getAttribute("fill")).toBe("#abc");
    const cat = WORDMARK_FACES.find((f) => f.id === "cat")!;
    expect(paths[paths.length - 1].getAttribute("d")).toBe(cat.light.d);
  });

  test("an unknown face draws the default, and an empty title hides the mark", () => {
    render(<Wordmark face="nope" title="" />);
    const svg = document.querySelector("svg")!;
    expect(svg.getAttribute("aria-hidden")).toBe("true");
    const d = svg.querySelectorAll("path");
    const smile = WORDMARK_FACES.find((f) => f.id === DEFAULT_FACE_ID)!;
    expect(d[d.length - 1].getAttribute("d")).toBe(smile.dark.d);
  });
});
