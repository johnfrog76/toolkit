import { act, fireEvent, render, screen, within } from "@testing-library/react";
import type { SpaceChoice } from "./AvatarMenu";
import type * as AvatarMenuModule from "./AvatarMenu";
import type * as QuickMenuModule from "./SpaceQuickMenu";

// The theme hook reads matchMedia when its module loads, so the stub goes in
// before the menu is required.
(globalThis as unknown as { matchMedia: unknown }).matchMedia = (query: string) => ({
  matches: false,
  media: query,
  addEventListener: () => {},
  removeEventListener: () => {},
  addListener: () => {},
  removeListener: () => {},
});
/* eslint-disable @typescript-eslint/no-require-imports */
const { AvatarMenu } = require("./AvatarMenu") as typeof AvatarMenuModule;
const { SPACE_QUICK_MENU_THRESHOLD } = require("./SpaceQuickMenu") as typeof QuickMenuModule;
/* eslint-enable @typescript-eslint/no-require-imports */

// The avatar menu's Space entry: up to the threshold, the plain
// submenu it always was; past it, a quick menu -- a box that narrows the list,
// Enter chooses, View all at the foot -- switching through the same call.

const NAMES = [
  "Toolkit",
  "Demo",
  "Bowling",
  "Recipes",
  "Wasteland",
  "Azure Demo",
  "GitHub Demo",
  "Client A",
  "Juggler",
  "Seals",
  "Lounge",
  "Orbit",
];

function spaces(n: number): SpaceChoice[] {
  return NAMES.slice(0, n).map((name) => ({ name, slug: name.toLowerCase().replace(/ /g, "-") }));
}

function draw(list: SpaceChoice[], activeSpace = list[0].slug) {
  const onSwitchSpace = jest.fn();
  render(
    <AvatarMenu
      displayName="Pat"
      unsaved={0}
      spaces={list}
      activeSpace={activeSpace}
      onSwitchSpace={onSwitchSpace}
      links={[]}
      onOpenSettings={() => {}}
      restoreFocusTarget={{}}
    />,
  );
  return onSwitchSpace;
}

async function openSpaceEntry() {
  fireEvent.click(screen.getByRole("button", { name: "You and your settings" }));
  const entry = await screen.findByRole("menuitem", { name: /^Space/ });
  fireEvent.click(entry);
  return entry;
}

const optionNames = () =>
  screen.getAllByRole("option").map((o) => o.querySelector("span:nth-child(2)")?.textContent);

describe("the avatar menu's Space entry", () => {
  it("is today's submenu at the threshold", async () => {
    expect(SPACE_QUICK_MENU_THRESHOLD).toBe(8);
    const onSwitch = draw(spaces(SPACE_QUICK_MENU_THRESHOLD));
    await openSpaceEntry();
    const radios = await screen.findAllByRole("menuitemradio");
    expect(radios.map((r) => r.textContent)).toEqual(NAMES.slice(0, 8));
    expect(screen.queryByRole("combobox")).toBeNull();
    fireEvent.click(radios[2]);
    expect(onSwitch).toHaveBeenCalledWith("bowling");
  });

  it("is a quick menu past it, the box focused, the active Space first and checked", async () => {
    draw(spaces(SPACE_QUICK_MENU_THRESHOLD + 1), "recipes");
    await openSpaceEntry();
    const box = await screen.findByRole("combobox", { name: "Find a Space" });
    expect(document.activeElement).toBe(box);
    expect(screen.queryByRole("menuitemradio")).toBeNull();
    const options = screen.getAllByRole("option");
    expect(options).toHaveLength(SPACE_QUICK_MENU_THRESHOLD);
    expect(optionNames()).toEqual([
      "Recipes",
      "Toolkit",
      "Demo",
      "Bowling",
      "Wasteland",
      "Azure Demo",
      "GitHub Demo",
      "Client A",
    ]);
    expect(options[0].getAttribute("aria-selected")).toBe("true");
    expect(options.slice(1).every((o) => o.getAttribute("aria-selected") === "false")).toBe(true);
    expect(box.getAttribute("aria-activedescendant")).toBe(options[0].id);
  });

  it("narrows as you type, and Enter switches through the same call", async () => {
    const onSwitch = draw(spaces(12));
    await openSpaceEntry();
    const box = await screen.findByRole("combobox");
    fireEvent.change(box, { target: { value: "jug" } });
    expect(optionNames()).toEqual(["Juggler"]);
    fireEvent.keyDown(box, { key: "Enter" });
    expect(onSwitch).toHaveBeenCalledWith("juggler");
    expect(screen.queryByRole("combobox")).toBeNull();
  });

  it("matches the slug as well as the name, ignoring case", async () => {
    draw([...spaces(9), { name: "The Big Client", slug: "acme-corp" }]);
    await openSpaceEntry();
    const box = await screen.findByRole("combobox");
    fireEvent.change(box, { target: { value: "ACME" } });
    expect(optionNames()).toEqual(["The Big Client"]);
  });

  it("moves the highlight with the arrows, and a click chooses", async () => {
    const onSwitch = draw(spaces(10));
    await openSpaceEntry();
    const box = await screen.findByRole("combobox");
    fireEvent.keyDown(box, { key: "ArrowDown" });
    fireEvent.keyDown(box, { key: "ArrowDown" });
    expect(box.getAttribute("aria-activedescendant")).toBe(screen.getAllByRole("option")[2].id);
    fireEvent.keyDown(box, { key: "ArrowUp" });
    fireEvent.keyDown(box, { key: "Enter" });
    expect(onSwitch).toHaveBeenCalledWith("demo");
    onSwitch.mockClear();
    await openSpaceEntry();
    fireEvent.click(within(await screen.findByRole("listbox")).getByText("Wasteland"));
    expect(onSwitch).toHaveBeenCalledWith("wasteland");
  });

  it("shows View all only when the short list leaves some out, and it lists every Space", async () => {
    draw(spaces(12));
    await openSpaceEntry();
    const box = await screen.findByRole("combobox");
    fireEvent.click(screen.getByRole("button", { name: "View all" }));
    expect(optionNames()).toEqual(NAMES);
    expect(screen.queryByRole("button", { name: "View all" })).toBeNull();
    expect(document.activeElement).toBe(box);
    // Typing lists every match already: no View all while there is text.
    fireEvent.change(box, { target: { value: "demo" } });
    expect(screen.queryByRole("button", { name: "View all" })).toBeNull();
  });

  it("says so when nothing matches", async () => {
    draw(spaces(9));
    await openSpaceEntry();
    const box = await screen.findByRole("combobox");
    fireEvent.change(box, { target: { value: "zzz" } });
    expect(screen.queryAllByRole("option")).toHaveLength(0);
    expect(within(screen.getByRole("listbox")).getByText("No Space matches 'zzz'")).toBeTruthy();
  });

  it("closes on Escape and gives the focus back to the Space entry", async () => {
    draw(spaces(9));
    const entry = await openSpaceEntry();
    const box = await screen.findByRole("combobox");
    await act(async () => {
      fireEvent.keyDown(box, { key: "Escape" });
    });
    expect(screen.queryByRole("combobox")).toBeNull();
    expect(document.activeElement).toBe(entry);
  });
});
