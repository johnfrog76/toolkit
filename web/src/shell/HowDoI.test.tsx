/**
 * The drawer's "How do I…" section (D-W1, D-W4, D-W11): one row per entry with
 * the CLI's state word, a door that opens the drawer at the right anchor with
 * the active Space filled in, folded when the drawer arrived at an anchor.
 */
import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { FluentProvider } from "@fluentui/react-components";
import { HowDoI, doorLabel } from "./HowDoI";
import { WORKFLOW_ENTRIES } from "./settingsWorkflows";
import type { SurfaceInventory } from "./api";
import { fluentThemeFor } from "./theme";
import { FIRST_LIGHT, themeById } from "./themeList";

/** A selector's specificity as [ids, classes, types]; `:not(x)` counts as x. */
function specificity(selector: string): number[] {
  const s = selector
    .replace(/::[\w-]+/g, "")
    .replace(/:not\(/g, " ")
    .replace(/\)/g, "");
  const ids = (s.match(/#[\w-]+/g) ?? []).length;
  const classes = (s.match(/\.[\w-]+|\[[^\]]+\]|:[\w-]+/g) ?? []).length;
  const types = (s.match(/(^|[\s>+~])[a-zA-Z][\w-]*/g) ?? []).length;
  return [ids, classes, types];
}

/** a outranks b, compared left to right. */
function outranks(a: number[], b: number[]): boolean {
  const i = a.findIndex((x, k) => x !== b[k]);
  return i >= 0 && a[i] > b[i];
}

/** The colour an element's own rules give it (with ` !important` when the
 *  winner carries it), cascaded as a browser does:
 *  !important first, then specificity, then source order. jsdom's
 *  getComputedStyle goes by source order alone, so it reports the rule a
 *  browser overrules. */
function cascadedColor(el: Element): string {
  let best: { rank: number[]; value: string } | null = null;
  let order = 0;
  for (const sheet of Array.from(document.styleSheets))
    for (const rule of Array.from(sheet.cssRules)) {
      if (!(rule instanceof CSSStyleRule)) continue;
      order++;
      const value = rule.style.getPropertyValue("color");
      if (!value) continue;
      for (const part of rule.selectorText.split(",")) {
        let hit = false;
        try {
          hit = el.matches(part);
        } catch {
          hit = false;
        }
        if (!hit) continue;
        const important = rule.style.getPropertyPriority("color") === "important" ? 1 : 0;
        const rank = [important, ...specificity(part), order];
        if (!best || outranks(rank, best.rank))
          best = { rank, value: important ? `${value} !important` : value };
      }
    }
  return best?.value ?? "";
}

function luminance(hex: string): number {
  const n = parseInt(hex.slice(1, 7), 16);
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

const inventory: SurfaceInventory = {
  activeSpace: "toolkit",
  prefix: "tk",
  entries: WORKFLOW_ENTRIES,
  surfaces: [
    {
      key: "promptsRoot",
      title: "Your hub",
      state: "on",
      config: "tkConfig -Set promptsRoot=<folder>",
      note: "",
      question: "q",
    },
    {
      key: "features.ado",
      title: "Azure DevOps",
      state: "off",
      config: "tkConfig -Set features.ado=true",
      note: "",
      question: "q",
    },
    {
      key: "features.lounge",
      title: "Lounge module",
      state: "not configured",
      config: "tkConfig -Set features.lounge=true",
      note: "",
      question: "q",
    },
  ],
};

// Team Agile's row ("How do you want to work in {space}?").
const teamAgile: SurfaceInventory["surfaces"][number] = {
  key: "features.solitaireAgile",
  title: "Team Agile module",
  state: "off",
  config: "tkConfig -Set spaces.toolkit.howIWork=agents -Hub",
  note: "",
  question: "How do you want to work in Toolkit?",
};
inventory.surfaces.push(teamAgile);

// The one config writer, PUT /api/config -> Config -Set. A reply is a
// promise the case may hold open, so the Saving state can be seen.
const writeSpy = jest.fn();
const SUCCESS = { result: { status: "success", error: null, output: "" }, config: {} };
let writeReply: () => Promise<unknown> = () => Promise.resolve(SUCCESS);
// The orchestrating answer's follow-up (registry.ts useWriteHowWeWork): what it
// decides is modules/studio/howWeWork.test.ts's; here, when the answer calls it
// and what the row shows of its outcome.
const howWeWorkSpy = jest.fn();
let howWeWorkReply: unknown = { kind: "listed" };
jest.mock("./registry", () => ({
  useWriteHowWeWork: () => (slug: string) => {
    howWeWorkSpy(slug);
    return Promise.resolve(howWeWorkReply);
  },
  useWriteConfigMutation: () => [
    (body: unknown) => {
      writeSpy(body);
      return { unwrap: () => writeReply() };
    },
    { isLoading: false },
  ],
}));

let declaredSpaces: { slug: string; name: string; status: string }[] = [];
// /env's howIWork for the Space you are in -- the agent's answer, per case.
let howIWork: Record<string, unknown> | undefined;
jest.mock("./api", () => ({
  useGetSurfacesQuery: () => ({ data: inventory, isError: false }),
  useGetEnvQuery: () => ({ data: { config: { spaces: declaredSpaces }, howIWork } }),
}));
const openSpy = jest.fn();
const navigateSpy = jest.fn();
jest.mock("./cards", () => ({
  useOpenSettings: () => openSpy,
}));
jest.mock("react-router", () => ({
  useNavigate: () => navigateSpy,
}));

function renderWith(anchor?: string) {
  openSpy.mockClear();
  render(<HowDoI anchor={anchor} />);
  return openSpy;
}

describe("HowDoI", () => {
  it("draws every question with the CLI's state word", () => {
    renderWith();
    expect(screen.getByText("Where do my cards live, and can I move them?")).toBeTruthy();
    const hub = screen
      .getByText("Where do my cards live, and can I move them?")
      .closest("[data-workflow-entry]")!;
    expect(hub.textContent).toContain("on");
    const lounge = screen
      .getByText("Is there somewhere to look up from the work?")
      .closest("[data-workflow-entry]")!;
    expect(lounge.textContent).toContain("not configured");
  });

  it("Change opens the drawer at the anchor, with the active Space filled in", () => {
    const open = renderWith();
    const lounge = screen
      .getByText("Is there somewhere to look up from the work?")
      .closest("[data-workflow-entry]")!;
    fireEvent.click(lounge.querySelector("button")!);
    expect(open).toHaveBeenCalledWith("features.lounge");
  });

  it("Set it up on the connect journey goes to the wizard's page, with the active Space filled in (D-W12)", () => {
    navigateSpy.mockClear();
    renderWith();
    declaredSpaces = [];
    const connect = screen
      .getByText(/How do I connect an Azure DevOps organisation/)
      .closest("[data-workflow-entry]")!;
    fireEvent.click(connect.querySelector("button")!);
    expect(navigateSpy).toHaveBeenCalledWith("/connect/toolkit");
  });

  it("the GitHub question walks the GitHub demo when it is declared, and your own Space when it is not", () => {
    navigateSpy.mockClear();
    declaredSpaces = [{ slug: "github-demo", name: "GitHub demo", status: "local" }];
    renderWith();
    const gh = screen
      .getByText("How do I connect a GitHub repo?")
      .closest("[data-workflow-entry]")!;
    fireEvent.click(gh.querySelector("button")!);
    expect(navigateSpy).toHaveBeenCalledWith("/connect/github-demo");
    cleanup();
    navigateSpy.mockClear();
    declaredSpaces = [];
    renderWith();
    const mine = screen
      .getByText("How do I connect a GitHub repo?")
      .closest("[data-workflow-entry]")!;
    fireEvent.click(mine.querySelector("button")!);
    expect(navigateSpy).toHaveBeenCalledWith("/connect/toolkit");
  });

  it("a sentence has no door; a walk with no key has none either", () => {
    renderWith();
    const review = screen
      .getByText("Can it review my pull request?")
      .closest("[data-workflow-entry]")!;
    expect(review.querySelector("button")).toBeNull();
    const teams = screen
      .getByText("Can it post to Teams for me?")
      .closest("[data-workflow-entry]")!;
    expect(teams.querySelector("button")).toBeNull();
    expect(doorLabel(WORKFLOW_ENTRIES.find((e) => e.id === "review")!)).toBeNull();
    expect(doorLabel(WORKFLOW_ENTRIES.find((e) => e.id === "connect-azure")!)).toBe("Set it up");
    expect(doorLabel(WORKFLOW_ENTRIES.find((e) => e.id === "connect-github")!)).toBe("Set it up");
  });

  describe("How do you want to work in {space}?", () => {
    const row = () =>
      screen
        .getByText("How do you want to work in Toolkit?")
        .closest("[data-workflow-entry]") as HTMLElement;
    const radio = (label: string) => within(row()).getByLabelText(label) as HTMLInputElement;
    const labels = () => Array.from(row().querySelectorAll("label")).map((l) => l.textContent);
    const group = () => within(row()).getByRole("radiogroup");
    const github = (answer = "alone", source = "default", sw: boolean | null = true) => ({
      answer,
      source,
      tracker: "github",
      locked: false,
      switch: sw,
    });

    beforeEach(() => {
      declaredSpaces = [{ slug: "toolkit", name: "Toolkit", status: "active" }];
      howIWork = github();
    });
    afterEach(() => {
      declaredSpaces = [];
      howIWork = undefined;
      writeSpy.mockClear();
      writeReply = () => Promise.resolve(SUCCESS);
      howWeWorkSpy.mockClear();
      howWeWorkReply = { kind: "listed" };
    });

    it("With agents, once set, asks for the Space's how-we-work note; a note already listed shows nothing", async () => {
      renderWith();
      await act(async () => {
        fireEvent.click(radio("With agents"));
      });
      expect(howWeWorkSpy).toHaveBeenCalledWith("toolkit");
      expect(row().querySelector("[data-how-we-work]")).toBeNull();
    });

    it("the note written: the verb's AGENTS.md line under the radios", async () => {
      howWeWorkReply = {
        kind: "written",
        line: "How we work here: /hub/toolkit/agentic/how-we-work.md",
      };
      renderWith();
      await act(async () => {
        fireEvent.click(radio("With agents"));
      });
      expect(
        await within(row()).findByText("How we work here: /hub/toolkit/agentic/how-we-work.md"),
      ).toBeTruthy();
    });

    it("the verb refused: its own sentence, and the answer stays set", async () => {
      howWeWorkReply = {
        kind: "refused",
        sentence:
          "/hub/toolkit/agentic/how-we-work.md is already there; tkHowWeWork never writes over it.",
      };
      renderWith();
      await act(async () => {
        fireEvent.click(radio("With agents"));
      });
      expect(
        await within(row()).findByText(/is already there; tkHowWeWork never writes over it\./),
      ).toBeTruthy();
      expect(radio("With agents").checked).toBe(true);
    });

    it("Alone, and a refused answer, ask for no note", async () => {
      howIWork = github("agents", "chosen");
      renderWith();
      await act(async () => {
        fireEvent.click(radio("Alone"));
      });
      cleanup();
      howIWork = github();
      writeReply = () =>
        Promise.resolve({
          result: { status: "error", error: "Unknown setting", output: "" },
          config: {},
        });
      renderWith();
      await act(async () => {
        fireEvent.click(radio("With agents"));
      });
      expect(howWeWorkSpy).not.toHaveBeenCalled();
    });

    it("asks in the Space's name, with three radios in exactly these words", () => {
      renderWith();
      expect(labels()).toEqual(["With agents", "Alone", "On a team in Azure"]);
      expect(row().textContent).toContain(
        "Team Agile on for this Space: the standup and triage over the repository's issues.",
      );
    });

    it("on GitHub: two live choices, the agent's answer checked, Azure disabled with its reason", () => {
      renderWith();
      expect(radio("Alone").checked).toBe(true);
      expect(radio("With agents").disabled).toBe(false);
      expect(radio("Alone").disabled).toBe(false);
      expect(radio("On a team in Azure").disabled).toBe(true);
      expect(row().textContent).toContain("this Space's tracker is GitHub");
      cleanup();
      howIWork = github("agents", "chosen");
      renderWith();
      expect(radio("With agents").checked).toBe(true);
    });

    it("on Azure DevOps: On a team in Azure, selected and locked, with the reason", () => {
      howIWork = { answer: "team", source: "derived", tracker: "ado", locked: true, switch: true };
      renderWith();
      expect(radio("On a team in Azure").checked).toBe(true);
      for (const l of ["With agents", "Alone", "On a team in Azure"])
        expect(radio(l).disabled).toBe(true);
      expect(row().textContent).toContain("Their board holds the rituals; Team Agile is off here.");
    });

    it("with no tracker: Alone, selected and locked, saying what connecting unlocks", () => {
      howIWork = {
        answer: "alone",
        source: "derived",
        tracker: "none",
        locked: true,
        switch: true,
      };
      renderWith();
      expect(radio("Alone").checked).toBe(true);
      for (const l of ["With agents", "Alone", "On a team in Azure"])
        expect(radio(l).disabled).toBe(true);
      expect(row().textContent).toContain("Connect a tracker to unlock working with agents.");
    });

    // A locked choice is never hidden, so it has to be readable: its label
    // takes the muted foreground the sentence under it uses, at AA on the
    // drawer's surface (the page's colour) in the first light theme and the
    // dark one the axe smoke audits. Fluent's disabled grey is what it
    // overrules; the circle keeps the disabled look.
    it.each([FIRST_LIGHT, "aurora"])("a locked answer's label reads at AA in %s", (id) => {
      const t = themeById(id)!;
      const fluent = fluentThemeFor(t) as unknown as Record<string, string>;
      render(
        <FluentProvider theme={fluentThemeFor(t)}>
          <HowDoI />
        </FluentProvider>,
      );
      const label = (text: string) =>
        Array.from(row().querySelectorAll("label")).find((l) => l.textContent === text)!;
      const hexOf = (color: string) => fluent[/var\(--(\w+)\)/.exec(color)![1]];
      const locked = cascadedColor(label("On a team in Azure"));
      expect(locked).toBe("var(--colorNeutralForeground3) !important");
      const hex = hexOf(locked);
      expect({ id, hex, ok: contrast(hex, t.page.color) >= 4.5 }).toEqual({ id, hex, ok: true });
      // A live answer is left to Fluent.
      expect(cascadedColor(label("Alone"))).not.toContain("colorNeutralForeground3 !important");
    });

    it("a locked answer's label carries a class a live answer's label does not", () => {
      const labelClass = (text: string) =>
        Array.from(row().querySelectorAll("label")).find((l) => l.textContent === text)!.className;
      renderWith();
      const live = labelClass("Alone");
      expect(labelClass("With agents")).toBe(live);
      expect(labelClass("On a team in Azure")).not.toBe(live);
      cleanup();
      for (const h of [
        { answer: "team", source: "derived", tracker: "ado", locked: true, switch: true },
        { answer: "alone", source: "derived", tracker: "none", locked: true, switch: true },
      ]) {
        howIWork = h;
        renderWith();
        const classes = ["With agents", "Alone", "On a team in Azure"].map(labelClass);
        for (const c of classes) expect(c).not.toBe(live);
        expect(new Set(classes).size).toBe(1);
        cleanup();
      }
    });

    it("a pick writes the Space's answer to the hub through the one writer", async () => {
      renderWith();
      await act(async () => {
        fireEvent.click(radio("With agents"));
      });
      expect(writeSpy).toHaveBeenLastCalledWith({
        set: { "spaces.toolkit.howIWork": "agents" },
        unset: [],
        hub: true,
      });
      expect(radio("With agents").checked).toBe(true);
    });

    it("while the write is pending: the pick shows at once, Saving… beside it, the group busy, the rest locked", async () => {
      let finish: (v: unknown) => void = () => {};
      writeReply = () => new Promise((resolve) => (finish = resolve));
      renderWith();
      await act(async () => {
        fireEvent.click(radio("With agents"));
      });
      expect(radio("With agents").checked).toBe(true);
      expect(within(row()).getByText("Saving…")).toBeTruthy();
      expect(group().getAttribute("aria-busy")).toBe("true");
      expect(radio("Alone").disabled).toBe(true);
      await act(async () => {
        finish(SUCCESS);
      });
      expect(within(row()).queryByText("Saving…")).toBeNull();
      expect(group().getAttribute("aria-busy")).toBe("false");
      expect(radio("With agents").checked).toBe(true);
      expect(radio("Alone").disabled).toBe(false);
    });

    it("a refusal puts the pick back and shows the CLI's sentence", async () => {
      writeReply = () =>
        Promise.resolve({
          result: { status: "error", error: "Unknown setting", output: "" },
          config: {},
        });
      renderWith();
      await act(async () => {
        fireEvent.click(radio("With agents"));
      });
      expect(await screen.findByText("Unknown setting")).toBeTruthy();
      expect(radio("Alone").checked).toBe(true);
      expect(within(row()).queryByText("Saving…")).toBeNull();
    });

    it("with agents chosen and Team Agile's own switch off, it says the answer waits for the switch", () => {
      howIWork = github("agents", "chosen", false);
      renderWith();
      expect(row().textContent).toContain("Team Agile's own switch is off");
      cleanup();
      howIWork = github("agents", "chosen", true);
      renderWith();
      expect(row().textContent).not.toContain("Team Agile's own switch is off");
    });

    it("an agent that has not said leaves every radio disabled", () => {
      howIWork = undefined;
      renderWith();
      for (const l of ["With agents", "Alone", "On a team in Azure"])
        expect(radio(l).disabled).toBe(true);
    });
  });

  it("folds when the drawer arrived at an anchor, and unfolds on a click (D-W11)", () => {
    renderWith("features.growth");
    expect(screen.queryByText("Where do my cards live, and can I move them?")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: /How do I/ }));
    expect(screen.getByText("Where do my cards live, and can I move them?")).toBeTruthy();
  });
});
