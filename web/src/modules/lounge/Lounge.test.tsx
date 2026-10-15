/**
 * The room asks nothing, and since M3 it is a page in the GUI's clothes:
 * one action (Skins), no scene, no input, no digit in its visible text. The
 * Skins dialog is where a skin is worn -- No skin and every scene as frozen
 * thumbs, one click wears one product-wide and STILL (D-L19: Animate off by
 * default), the switch runs the clocks live, and No skin takes it off in the
 * same place. What the dialog writes the shell wears (GrantedSkin).
 */
// jsdom has no matchMedia; the theme store asks it once for a browser that
// never chose (useCurrentTheme), and the dialog names the theme underneath.
// Installed before the imports below evaluate it.
(globalThis as unknown as { matchMedia: unknown }).matchMedia = (query: string) => ({
  matches: false,
  media: query,
  addEventListener: () => {},
  removeEventListener: () => {},
});

import { render, screen, fireEvent } from "@testing-library/react";
import { Lounge } from "./Lounge";
import { GrantedSkin } from "../../shared/GrantedSkin";
import { isAnimated, parseSkinGrant } from "../../shared/skinGrant";
import { TANK_SCENES, TEMPLE_SCENE } from "./skins";

beforeEach(() => {
  window.localStorage.clear();
});

function visibleText(container: HTMLElement): string {
  const clone = container.cloneNode(true) as HTMLElement;
  // Decorative text is a drawing, not a reading: a face drawn with a 3 for a
  // mouth is not a numeral in the room's sense.
  clone.querySelectorAll("style, svg, [aria-hidden='true']").forEach((el) => el.remove());
  return clone.textContent ?? "";
}

const LOUNGE_GAMES_NOTE = "The games are here for the mood. Ones that play back are on the way.";

const grantNow = () => parseSkinGrant(window.localStorage.getItem("toolkit-skin-grant"));

describe("the Lounge room", () => {
  it("is a page in the theme: one action, Skins; no scene, no input, no digit", () => {
    const { container } = render(<Lounge />);
    expect(screen.getByRole("button", { name: "Skins" })).toBeTruthy();
    expect(screen.getByText("Face")).toBeTruthy();
    expect(screen.getByRole("group", { name: "Go board" })).toBeTruthy();
    expect(screen.getByRole("group", { name: "Word ring" })).toBeTruthy();
    expect(screen.getByRole("group", { name: "Tic-tac-toe board" })).toBeTruthy();
    // Face first, then the games (document order).
    const face = screen.getByText("Face");
    const go = screen.getByText("Go");
    expect(face.compareDocumentPosition(go) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(container.querySelector("iframe")).toBeNull();
    expect(screen.queryByRole("combobox")).toBeNull();
    expect(container.querySelectorAll("input, textarea, a")).toHaveLength(0);
    expect(visibleText(container)).not.toMatch(/\d/);
  });

  it("says once what the games are: there for the mood, and ones that play back are on the way", () => {
    render(<Lounge />);
    expect(screen.getAllByText(LOUNGE_GAMES_NOTE)).toHaveLength(1);
  });

  it("the Skins dialog: No skin and every scene as frozen thumbs; a click wears one, still", () => {
    render(
      <>
        <Lounge />
        <GrantedSkin />
      </>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Skins" }));
    expect(screen.getAllByRole("button", { name: /^Wear / })).toHaveLength(1 + TANK_SCENES.length);
    expect(document.querySelectorAll('iframe[src$="#still"]')).toHaveLength(1 + TANK_SCENES.length);
    expect(screen.getByRole("button", { name: "No skin" }).getAttribute("aria-pressed")).toBe(
      "true",
    );
    expect((screen.getByRole("switch", { name: "Animate" }) as HTMLInputElement).checked).toBe(
      false,
    );

    const garden = TANK_SCENES.find((s) => s.id === "garden")!;
    fireEvent.click(screen.getByRole("button", { name: "Wear coral garden" }));
    expect(grantNow()).toEqual({
      skinId: "tank",
      src: garden.src,
      caption: garden.caption,
      animate: false,
    });
    expect(
      screen.getByRole("button", { name: "Wear coral garden" }).getAttribute("aria-pressed"),
    ).toBe("true");
    // The shell wears it FROZEN: its frame is src#still (the dialog's thumb is the other one).
    expect(document.querySelectorAll(`iframe[src="${garden.src}#still"]`)).toHaveLength(2);
    expect(document.querySelectorAll(`iframe[src="${garden.src}"]`)).toHaveLength(0);
  });

  it("Animate runs the worn skin's clocks live, and No skin takes it off in the same place", () => {
    render(
      <>
        <Lounge />
        <GrantedSkin />
      </>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Skins" }));
    const lagoon = TANK_SCENES.find((s) => s.id === "lagoon")!;
    fireEvent.click(screen.getByRole("button", { name: "Wear lagoon" }));
    fireEvent.click(screen.getByRole("switch", { name: "Animate" }));
    expect(grantNow()?.animate).toBe(true);
    expect(document.querySelectorAll(`iframe[src="${lagoon.src}"]`)).toHaveLength(1);
    fireEvent.click(screen.getByRole("switch", { name: "Animate" }));
    expect(grantNow()?.animate).toBe(false);
    expect(document.querySelectorAll(`iframe[src="${lagoon.src}"]`)).toHaveLength(0);

    fireEvent.click(screen.getByRole("button", { name: "No skin" }));
    expect(window.localStorage.getItem("toolkit-skin-grant")).toBeNull();
    expect(screen.getByRole("button", { name: "No skin" }).getAttribute("aria-pressed")).toBe(
      "true",
    );
    // The wearer renders nothing: only the dialog's frozen thumbs remain.
    expect(document.querySelectorAll('iframe:not([src$="#still"])')).toHaveLength(0);
  });

  it("the temple is a skin too, through its standalone twin", () => {
    render(<Lounge />);
    fireEvent.click(screen.getByRole("button", { name: "Skins" }));
    fireEvent.click(screen.getByRole("button", { name: "Wear offerings on the altar" }));
    expect(grantNow()).toEqual({
      skinId: "temple",
      src: TEMPLE_SCENE.src,
      caption: TEMPLE_SCENE.caption,
      animate: false,
    });
  });

  it("the switch remembers its resting answer, so the next skin wears it", () => {
    render(<Lounge />);
    fireEvent.click(screen.getByRole("button", { name: "Skins" }));
    fireEvent.click(screen.getByRole("switch", { name: "Animate" }));
    expect(grantNow()).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Wear iwagumi" }));
    expect(grantNow()?.animate).toBe(true);
  });

  it("an older grant that said still reads as its inverse; one that said nothing is off", () => {
    const base = { skinId: "tank" as const, src: "/x.html", caption: "c" };
    expect(isAnimated({ ...base, still: false })).toBe(true);
    expect(isAnimated({ ...base, still: true })).toBe(false);
    expect(isAnimated(base)).toBe(false);
    expect(isAnimated({ ...base, animate: true, still: true })).toBe(true);
  });
});
