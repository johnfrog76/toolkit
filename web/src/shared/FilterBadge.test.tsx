import { render, screen } from "@testing-library/react";
import { CHIP_APPEARANCES, THEMES, chipToken, themeById } from "../shell/themeList";
import { fluentThemeFor } from "../shell/theme";
import { FilterBadge } from "./FilterBadge";

function chip(appearance: (typeof CHIP_APPEARANCES)[number], active = true) {
  const { unmount } = render(
    <FilterBadge label="x" count={3} active={active} appearance={appearance} onClick={() => {}} />,
  );
  const cls = screen.getByRole("radio").className;
  unmount();
  return cls;
}

/** The CSS the page holds for a class: Griffel inserts its rules through the CSSOM. */
function ruleFor(cls: string): string {
  const rules = Array.from(document.styleSheets).flatMap((sheet) =>
    Array.from(sheet.cssRules).map((r) => r.cssText),
  );
  const names = cls.split(" ");
  return rules.filter((r) => names.some((c) => r.includes(`.${c}`))).join("\n");
}

describe("FilterBadge", () => {
  it("the Fluent theme carries each appearance's colour, per theme", () => {
    for (const t of THEMES) {
      const f = fluentThemeFor(t) as unknown as Record<string, string>;
      for (const a of CHIP_APPEARANCES) expect(f[chipToken(a)]).toBe(t.chips[a]);
    }
  });

  it("a selected chip's colour changes with the theme: dark and light differ", () => {
    const dark = fluentThemeFor(themeById("atlantis")!) as unknown as Record<string, string>;
    const light = fluentThemeFor(themeById("seaglass")!) as unknown as Record<string, string>;
    for (const a of CHIP_APPEARANCES) expect(dark[chipToken(a)]).not.toBe(light[chipToken(a)]);
  });

  it("a selected chip reads the theme's token for its appearance, and no other", () => {
    for (const a of CHIP_APPEARANCES) {
      const rule = ruleFor(chip(a));
      expect(rule).toContain(`var(--${chipToken(a)})`);
      for (const other of CHIP_APPEARANCES.filter((o) => o !== a)) {
        expect(rule).not.toContain(`var(--${chipToken(other)})`);
      }
    }
  });

  it("rows of different appearances differ: four classes, four colours in one theme", () => {
    expect(new Set(CHIP_APPEARANCES.map((a) => chip(a))).size).toBe(CHIP_APPEARANCES.length);
    const t = fluentThemeFor(themeById("office")!) as unknown as Record<string, string>;
    expect(new Set(CHIP_APPEARANCES.map((a) => t[chipToken(a)])).size).toBe(4);
  });

  it("an unselected chip draws no appearance colour", () => {
    expect(ruleFor(chip("pink", false))).not.toContain(chipToken("pink"));
  });

  it("draws its count, a zero included, and null draws none", () => {
    const { rerender } = render(
      <FilterBadge label="a" count={0} active={false} onClick={() => {}} />,
    );
    expect(screen.getByRole("radio").textContent).toBe("a0");
    rerender(<FilterBadge label="a" count={null} active={false} onClick={() => {}} />);
    expect(screen.getByRole("radio").textContent).toBe("a");
  });
});
