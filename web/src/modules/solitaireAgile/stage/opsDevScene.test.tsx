import fs from "node:fs";
import path from "node:path";
import { render, screen } from "@testing-library/react";
import { CastScene, OPS_TERMINAL_BEAT, OPS_TERMINAL_GREEN, REDUCED_MOTION_RULE } from "./cast";

const SOURCE = fs.readFileSync(path.join(__dirname, "cast.tsx"), "utf8");

/** The keyframes a named animation runs, as the stage's stylesheet writes them. */
function keyframes(name: string): string {
  const m = new RegExp(`@keyframes ${name}\\s*\\{((?:[^{}]*\\{[^{}]*\\})*)\\s*\\}`).exec(SOURCE);
  if (!m) throw new Error(`no @keyframes ${name}`);
  return m[1];
}

describe("the ops window: the terminal is his background, never over his face", () => {
  it("draws the terminal before the figure, so the head is in front on every frame", () => {
    render(<CastScene id="ops-dev" />);
    const terminal = screen.getByTestId("ops-dev-terminal");
    const figure = screen.getByTestId("ops-dev-figure");
    // Siblings in one stacking context, neither with a z-index: the later one paints on top.
    expect(terminal.parentElement).toBe(figure.parentElement);
    expect(
      terminal.compareDocumentPosition(figure) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    expect(terminal.style.zIndex).toBe("");
    expect(figure.style.zIndex).toBe("");
    expect(figure.querySelector("svg")).not.toBeNull();
  });

  it("the panel itself never animates: no fade, no blink, no movement", () => {
    render(<CastScene id="ops-dev" />);
    const terminal = screen.getByTestId("ops-dev-terminal");
    expect(terminal.style.animation).toBe("");
    expect(terminal.style.opacity).toBe("");
    expect(terminal.style.color).not.toBe("");
  });

  it("the beat is the text's colour only, between green and white, slow", () => {
    render(<CastScene id="ops-dev" />);
    const text = screen.getByTestId("ops-dev-terminal-text");
    expect(text.style.animation).toBe(OPS_TERMINAL_BEAT);
    const [name, duration] = OPS_TERMINAL_BEAT.split(" ");
    expect(parseFloat(duration)).toBeGreaterThanOrEqual(2);
    const frames = keyframes(name);
    // Every declaration in the beat is a colour: nothing that could hide or move anything.
    const props = [...frames.matchAll(/([a-z-]+)\s*:/g)].map((m) => m[1]);
    expect(props.length).toBeGreaterThan(0);
    expect(new Set(props)).toEqual(new Set(["color"]));
    expect(frames).toContain(OPS_TERMINAL_GREEN);
  });

  it("no keyframes in the cast fade a whole panel on a loop any more", () => {
    expect(SOURCE).not.toContain("rs-flicker");
  });

  it("reduced motion stops the beat with every other animation", () => {
    expect(REDUCED_MOTION_RULE).toContain("prefers-reduced-motion: reduce");
    expect(REDUCED_MOTION_RULE).toContain("animation: none !important");
  });
});
