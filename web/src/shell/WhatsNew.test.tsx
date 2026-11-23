import fs from "node:fs";
import path from "node:path";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { parseChangelog } from "./changelogParse";
import type { ChangelogRelease } from "./changelogParse";
import consts from "../../../consts.json";
import { resetWhatsNewMemory, WHATS_NEW_SEEN_KEY } from "./releaseNotes";
import type * as MenuModule from "./AvatarMenu";
import type * as HookModule from "./WhatsNew";

// The avatar menu's theme hook reads matchMedia when its module loads.
(globalThis as unknown as { matchMedia: unknown }).matchMedia = (query: string) => ({
  matches: false,
  media: query,
  addEventListener: () => {},
  removeEventListener: () => {},
  addListener: () => {},
  removeListener: () => {},
});
/* eslint-disable @typescript-eslint/no-require-imports */
const { AvatarMenu } = require("./AvatarMenu") as typeof MenuModule;
const { WhatsNewDialog, useWhatsNew } = require("./WhatsNew") as typeof HookModule;
/* eslint-enable @typescript-eslint/no-require-imports */

// What's new: the dialog, once per version per browser, and the account menu's
// item. The harness is the App's own wiring -- the hook, the menu, the dialog --
// with every module off: the item is core, so nothing here names a module.

const section = (version: string, entry: string): ChangelogRelease => ({
  version,
  date: "2026-01-01",
  groups: [{ heading: "Added", entries: [entry] }],
});
const FILE = [section("1.7.0", "Seven."), section("1.6.0", "Six."), section("1.5.0", "Five.")];

function Harness({ source }: { source?: Parameters<typeof useWhatsNew>[0] }) {
  const whatsNew = useWhatsNew(source);
  return (
    <>
      <AvatarMenu
        unsaved={0}
        spaces={[]}
        activeSpace=""
        onSwitchSpace={() => {}}
        links={[]}
        onOpenSettings={() => {}}
        onOpenWhatsNew={whatsNew.open}
        restoreFocusTarget={{}}
      />
      {whatsNew.releases ? (
        <WhatsNewDialog releases={whatsNew.releases} onClose={whatsNew.close} />
      ) : null}
    </>
  );
}

const sourceOf = (version: string, releases = FILE) => ({
  version,
  load: () => Promise.resolve(releases),
});
const dialog = () => screen.queryByRole("dialog");

beforeEach(() => {
  resetWhatsNewMemory();
  window.localStorage.clear();
});
afterEach(() => jest.restoreAllMocks());

describe("what's new, once per version per browser", () => {
  it("opens on first load, titled with the version, and not on the second load", async () => {
    const src = sourceOf("1.7.0");
    const first = render(<Harness source={src} />);
    const open = await screen.findByRole("dialog", { name: "What's new in 1.7.0" });
    expect(within(open).getByText("Seven.")).toBeTruthy();
    expect(window.localStorage.getItem(WHATS_NEW_SEEN_KEY)).toBe("1.7.0");
    first.unmount();

    render(<Harness source={src} />);
    await Promise.resolve();
    expect(dialog()).toBeNull();
  });

  it("opens again after the version changes", async () => {
    window.localStorage.setItem(WHATS_NEW_SEEN_KEY, "1.6.0");
    render(<Harness source={sourceOf("1.7.0")} />);
    expect(await screen.findByRole("dialog", { name: "What's new in 1.7.0" })).toBeTruthy();
  });

  it("shows each skipped version, newest first, titled with the running one", async () => {
    window.localStorage.setItem(WHATS_NEW_SEEN_KEY, "1.5.0");
    render(<Harness source={sourceOf("1.7.0")} />);
    const open = await screen.findByRole("dialog", { name: "What's new in 1.7.0" });
    const versions = within(open)
      .getAllByRole("heading", { level: 3 })
      .map((h) => h.textContent);
    expect(versions).toEqual(["1.7.0 - 2026-01-01", "1.6.0 - 2026-01-01"]);
  });

  it("shows only the running version on a browser with no mark", async () => {
    render(<Harness source={sourceOf("1.7.0")} />);
    const open = await screen.findByRole("dialog");
    expect(within(open).queryByText("Six.")).toBeNull();
  });

  it("does not open on its own for an unreleased build, and writes no mark", async () => {
    render(<Harness source={sourceOf("1.8.0")} />);
    await Promise.resolve();
    await Promise.resolve();
    expect(dialog()).toBeNull();
    expect(window.localStorage.getItem(WHATS_NEW_SEEN_KEY)).toBeNull();
  });

  it("does not load the changelog at all once the version is shown", () => {
    window.localStorage.setItem(WHATS_NEW_SEEN_KEY, "1.7.0");
    const load = jest.fn(() => Promise.resolve(FILE));
    render(<Harness source={{ version: "1.7.0", load }} />);
    expect(load).not.toHaveBeenCalled();
  });

  it("survives storage that throws, and does not reopen within the session", async () => {
    jest.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("denied");
    });
    jest.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("denied");
    });
    const src = sourceOf("1.7.0");
    const first = render(<Harness source={src} />);
    expect(await screen.findByRole("dialog")).toBeTruthy();
    first.unmount();
    render(<Harness source={src} />);
    await Promise.resolve();
    await Promise.resolve();
    expect(dialog()).toBeNull();
  });

  it.each([
    ["the plain Close button at the foot", true],
    ["the X beside the title", false],
  ])("closes with %s", async (_label, last) => {
    render(<Harness source={sourceOf("1.7.0")} />);
    const open = await screen.findByRole("dialog");
    const buttons = within(open).getAllByRole("button", { name: "Close" });
    fireEvent.click(last ? buttons[buttons.length - 1] : buttons[0]);
    await waitFor(() => expect(dialog()).toBeNull());
  });
});

describe("the account menu's What's new item", () => {
  const openMenu = () =>
    fireEvent.click(screen.getByRole("button", { name: "You and your settings" }));

  it("is present with every module off, after All settings, and reopens the dialog", async () => {
    window.localStorage.setItem(WHATS_NEW_SEEN_KEY, "1.7.0");
    render(<Harness source={sourceOf("1.7.0")} />);
    expect(dialog()).toBeNull();
    openMenu();
    const items = (await screen.findAllByRole("menuitem")).map((i) => i.textContent);
    const all = items.findIndex((t) => t?.startsWith("All settings"));
    expect(items[all + 1]).toBe("What's new");
    fireEvent.click(await screen.findByRole("menuitem", { name: "What's new" }));
    expect(await screen.findByRole("dialog", { name: "What's new in 1.7.0" })).toBeTruthy();
  });

  it("shows the newest released section, under its own version, on an unreleased build", async () => {
    render(<Harness source={sourceOf("1.8.0")} />);
    openMenu();
    fireEvent.click(await screen.findByRole("menuitem", { name: "What's new" }));
    expect(await screen.findByRole("dialog", { name: "What's new in 1.7.0" })).toBeTruthy();
  });
});

// The issue's "done when": the dialog shows the packaged changelog's section
// for the running version -- the real file, the real version, the real chunks.
describe("the packaged changelog", () => {
  const plain = (md: string) =>
    md
      .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
      .replace(/[`*]/g, "")
      .replace(/\s+/g, " ")
      .trim();

  it("is what the dialog shows for the running version", async () => {
    const text = fs.readFileSync(path.join(__dirname, "..", "..", "..", "CHANGELOG.md"), "utf8");
    const mine = parseChangelog(text).find((r) => r.version === consts.version);
    expect(mine).toBeDefined();
    expect(mine!.groups.length).toBeGreaterThan(0);

    // No mark, the default source: the shipped wiring end to end.
    render(<Harness />);
    const open = await screen.findByRole("dialog", { name: `What's new in ${consts.version}` });
    const headings = within(open)
      .getAllByRole("heading", { level: 4 })
      .map((h) => h.textContent);
    expect(headings).toEqual(mine!.groups.map((g) => g.heading));
    const shown = within(open)
      .getAllByRole("listitem")
      .map((li) => plain(li.textContent ?? ""));
    expect(shown).toEqual(mine!.groups.flatMap((g) => g.entries.map(plain)));
  });
});
