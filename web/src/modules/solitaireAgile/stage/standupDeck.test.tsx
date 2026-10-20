import fs from "node:fs";
import path from "node:path";
import { fireEvent, render, screen, within } from "@testing-library/react";
import { extractSayText } from "../../deck/engine/sayText";
import { RITUALS } from "../../../shell/consts";
import type { RitualItem, StandupResponse } from "../api.solitaireAgile";
import { STANDUP_DECK_ID } from "../paths";
import { fluentThemeFor } from "../../../shell/theme";
import { themeById } from "../../../shell/themeList";
import {
  BUBBLE_Z_INDEX,
  CAST,
  castById,
  LOOK_FILTER,
  SPEAKER_COLOR_VAR,
  SPEECH_MAX_LINES,
  THOUGHT_MAX_HEIGHT,
  REDUCED_MOTION_RULE,
  STAGE_CLASS,
} from "./cast";
import { dealSeats } from "./seats";
import { buildStandupDeck } from "./standupDeck";

// The engine's placement needs layout, which jsdom has none of, so the bubbles'
// `positioning` is recorded as the Popover is drawn and the real Popover
// still draws. The placement itself is the browser walk's.
// The stage reads the chosen theme. The real hook reads matchMedia when it
// is imported, which jsdom has none of, so the theme is a stand-in the test sets.
let mockThemeId = "seaglass";
jest.mock("../../../hooks/useWornTheme", () => ({
  useWornTheme: () => {
    const active = jest.requireActual("../../../shell/themeList").themeById(mockThemeId);
    return { theme: active.mode, active, worn: null, chosen: active, setThemeId: () => {} };
  },
}));

const mockPopovers: { positioning?: Record<string, unknown> }[] = [];
jest.mock("@fluentui/react-components", () => {
  const actual = jest.requireActual("@fluentui/react-components");
  const Popover = (props: { positioning?: Record<string, unknown> }) => {
    mockPopovers.push(props);
    return <actual.Popover {...props} />;
  };
  return { ...actual, Popover };
});

// The played standup (docs/modules/solitaire-agile.md, "The played view"), built
// from the SHARED fixture the CLI and the agent assert
// (Tests/fixtures/rituals/standup.json + the golden texts), with the chair's
// lines and the empty worker's `nothing` sentence picked from Config/standup-vocabulary.json by the
// fixture's own indices -- the route's response, as the contract (4b) says.

const ROOT = path.resolve(__dirname, "../../../../..");
const FIXTURES = path.join(ROOT, "Tests/fixtures/rituals");

interface FixtureCase {
  name: string;
  asOf: string;
  tracker: { ok: boolean; reason: string };
  issues: RitualItem[];
  expected: {
    since: string;
    chair: { openIndex: number; closeIndex: number };
    queue: { walk: number[] };
    workers: {
      label: string;
      name: string;
      yesterday: number[];
      today: number[];
      blockers: number[];
      empty: boolean;
      nothingIndex: number | null;
    }[];
    text: string | null;
  };
}

const table = JSON.parse(fs.readFileSync(path.join(FIXTURES, "standup.json"), "utf8")) as {
  cases: FixtureCase[];
};
const vocab = JSON.parse(fs.readFileSync(path.join(ROOT, RITUALS.vocabularyFile), "utf8")) as {
  phrasebook: string[];
  nothing: string[];
  excuses: string[];
};

function responseFor(name: string): StandupResponse {
  const c = table.cases.find((x) => x.name === name);
  if (!c || !c.expected.text) throw new Error(`no fixture case ${name} with a golden`);
  const byNumber = new Map(c.issues.map((i) => [i.number, i]));
  const items = (ns: number[]): RitualItem[] =>
    ns.map((n) => {
      const i = byNumber.get(n)!;
      return { number: i.number, title: i.title, url: i.url };
    });
  return {
    ceremony: "standup",
    register: "real",
    asOf: c.asOf,
    since: c.expected.since,
    space: "toolkit",
    tracker: c.tracker,
    chair: {
      open: vocab.phrasebook[c.expected.chair.openIndex],
      close: vocab.phrasebook[c.expected.chair.closeIndex],
    },
    queue: { walk: items(c.expected.queue.walk), decide: [], look: [] },
    workers: c.expected.workers.map((w) => ({
      label: w.label,
      name: w.name,
      yesterday: items(w.yesterday),
      today: items(w.today),
      blockers: items(w.blockers),
      empty: w.empty,
      excuse: w.nothingIndex === null ? "" : vocab.nothing[w.nothingIndex],
    })),
    text: fs.readFileSync(path.join(FIXTURES, c.expected.text), "utf8"),
  };
}

const friday = responseFor("friday");
const deck = buildStandupDeck(friday);
const slides = deck.slides();
const say = (i: number) => extractSayText(slides[i].notes);

/** Draw one slide's stage and return the helpers to read it. */
function drawStage(i: number) {
  const view = render(<>{slides[i].content}</>);
  const tile = (id: string) => screen.getByTestId(`tile-${id}`);
  const lit = () =>
    CAST.map((c) => c.id).filter((id) => tile(id).getAttribute("data-lit") === "true");
  return { view, tile, lit };
}

describe("the standup deck, from Friday's fixture", () => {
  it("is an audiobook deck with the ritual's id and the text's first line as its title", () => {
    expect(deck.id).toBe(STANDUP_DECK_ID);
    expect(deck.audiobook).toBe(true);
    expect(deck.title).toBe("Standup -- Friday 2 October 2026");
    expect(deck.title).toBe(friday.text.split("\n")[0]);
  });

  it("plays the queue, the chair, one slide a worker in seat order, the chair, the queue (D-TA6)", () => {
    expect(slides.map((s) => s.id)).toEqual([
      "standup-2026-10-02-queue",
      "standup-2026-10-02-chair-open",
      "standup-2026-10-02-fable",
      "standup-2026-10-02-opus",
      "standup-2026-10-02-sonnet",
      "standup-2026-10-02-chair-close",
      "standup-2026-10-02-queue-end",
    ]);
    // The queue first and last, the same script both times.
    expect(say(0)).toBe(say(slides.length - 1));
  });

  it("keeps every slide id across a rebuild", () => {
    expect(
      buildStandupDeck(friday)
        .slides()
        .map((s) => s.id),
    ).toEqual(slides.map((s) => s.id));
  });

  it("the queue: the chair reads what is waiting on you", () => {
    expect(say(0)).toBe(
      `${RITUALS.text.queueHeading}. Walk: issue 104, Verify the Studio tab draws on the PC. Walk: issue 105, Verify the clock fix on Windows.`,
    );
    const { tile, lit } = drawStage(0);
    // The chair speaks and the walk seat is lit; nothing is decided or looked at yet.
    expect(lit()).toEqual(["qa", "pm"]);
    expect(within(tile("pm")).getByText(/Walk #104 Verify the Studio tab/)).toBeTruthy();
  });

  it("the copy panel is the speaker's character, not the bubble again", () => {
    // A worker's slide: title, persona with the label, the motto in its own voice.
    const dev = render(<>{slides[2].copy}</>);
    const copy = dev.getByTestId("standup-copy");
    const hero = castById("dev-hero");
    expect(copy.textContent).toContain(hero.title);
    expect(copy.textContent).toContain(`${hero.label} (fable)`);
    expect(copy.textContent).toContain(hero.motto);
    expect(copy.textContent).not.toMatch(/#107|Port the cast atoms|Yesterday/);
    dev.unmount();
    // The chair's slide: the PM, no label.
    const chair = render(<>{slides[1].copy}</>);
    const pm = castById("pm");
    expect(chair.getByTestId("standup-copy").textContent).toContain(pm.motto);
    expect(chair.getByTestId("standup-copy").textContent).toContain(pm.label);
    expect(chair.getByTestId("standup-copy").textContent).not.toMatch(/\((fable|opus|sonnet)\)/);
    chair.unmount();
    // Every character has a title and a motto that is theirs, not a status.
    for (const c of CAST) {
      expect(c.title.length).toBeGreaterThan(0);
      expect(c.motto).toMatch(/^[IMT]/);
    }
  });

  it("the chair opens and closes with the phrasebook's lines", () => {
    expect(say(1)).toBe("Can we not adjust scope.");
    expect(say(5)).toBe("Let's circle back.");
    const { lit } = drawStage(1);
    expect(lit()).toEqual(["pm"]);
  });

  it("Fable's tile: lit, plated, the three slots as one Say line each", () => {
    expect(say(2)).toBe(
      `Yesterday: issue 107, Port the cast atoms. Today: ${RITUALS.text.todayEmpty}. Blockers: issue 104, Verify the Studio tab draws on the PC.`,
    );
    const { tile, lit } = drawStage(2);
    expect(lit()).toEqual(["dev-hero"]);
    expect(within(tile("dev-hero")).getByText("TEAM LEAD · DEV-HERO (fable)")).toBeTruthy();
    expect(
      within(tile("dev-hero")).getByText(
        /#104 Verify the Studio tab draws on the PC \(verify-close\)/,
      ),
    ).toBeTruthy();
  });

  it("Opus's tile wears its plate", () => {
    const { tile, lit } = drawStage(3);
    expect(lit()).toEqual(["vibemancer"]);
    expect(within(tile("vibemancer")).getByText("AI VIBEMANCER (opus)")).toBeTruthy();
  });

  it("Sonnet had nothing: the mug where the face would be, and its status as the one line (D-TA11)", () => {
    expect(say(4)).toBe("My async status: Nothing on the board for me. All green, no blockers.");
    const { tile, lit } = drawStage(4);
    expect(lit()).toEqual(["minimalist"]);
    expect(within(tile("minimalist")).getByText("MINIMALIST (sonnet)")).toBeTruthy();
    expect(within(tile("minimalist")).getByTestId("stage-mug")).toBeTruthy();
    expect(within(tile("minimalist")).getByTestId("stage-speech-text").textContent).toBe(
      'My async status:\n"Nothing on the board for me. All green, no blockers."',
    );
    // The worker had work: no mug on the tile.
    expect(within(tile("dev-hero")).queryByTestId("stage-mug")).toBeNull();
  });

  it("a thin day: every worker's tile wears the mug, and the status line is under each", () => {
    const thin = {
      ...friday,
      workers: friday.workers.map((w) => ({
        ...w,
        yesterday: [],
        today: [],
        blockers: [],
        empty: true,
        excuse: "Nothing on the board for me. All green, no blockers.",
      })),
    };
    const thinSlides = buildStandupDeck(thin).slides();
    const workerSlides = thinSlides.filter((s) => /-(fable|opus|sonnet)$/.test(s.id));
    expect(workerSlides).toHaveLength(3);
    for (const s of workerSlides) {
      expect(extractSayText(s.notes)).toBe(
        "My async status: Nothing on the board for me. All green, no blockers.",
      );
      const { unmount } = render(<>{s.content}</>);
      const lit = CAST.map((c) => c.id).filter(
        (id) => screen.getByTestId(`tile-${id}`).getAttribute("data-lit") === "true",
      );
      expect(lit).toHaveLength(1);
      const tile = screen.getByTestId(`tile-${lit[0]}`);
      expect(within(tile).getByTestId("stage-mug")).toBeTruthy();
      expect(within(tile).getByTestId("stage-speech-text").textContent).toBe(
        'My async status:\n"Nothing on the board for me. All green, no blockers."',
      );
      unmount();
    }
  });

  it("a worker's slot holding an issue and a card: #143 and 2HNU in the bubble, issue 143 and card 2HNU in the voice, one link and one card popover (never #null)", () => {
    const issue: RitualItem = {
      number: 143,
      title: "Verify the Studio tab",
      url: "https://github.com/o/r/issues/143",
    };
    const card: RitualItem = {
      number: null,
      id: "2HNU",
      title: "Joined source",
      url: "",
      path: "current/Task2HNU-joined.prompt.md",
    };
    const mixed = {
      ...friday,
      workers: friday.workers.map((w) =>
        w.label === "fable" ? { ...w, yesterday: [issue, card], today: [], blockers: [] } : w,
      ),
    };
    const s = buildStandupDeck(mixed).slides()[2];
    const spoken = extractSayText(s.notes);
    expect(spoken).toContain("issue 143, Verify the Studio tab; card 2HNU, Joined source.");
    expect(spoken).not.toContain("null");
    render(<>{s.content}</>);
    const speech = screen.getByTestId("stage-speech-text").textContent ?? "";
    expect(speech).toContain("#143 Verify the Studio tab; 2HNU Joined source");
    expect(speech).not.toContain("null");
    fireEvent.click(screen.getByTestId("stage-thought-trigger"));
    const items = screen.getByTestId("stage-thought-items");
    const links = items.querySelectorAll("a[href]");
    expect(links).toHaveLength(1);
    expect(links[0].textContent).toBe("#143");
    expect(within(items).getByText("2HNU").closest("a")).toBeNull();
    expect(items.textContent).not.toContain("null");
  });

  it("every slide is the same nine tiles, with every seat's plate, the ritual's plate and the register (D-TA13, D-TA17)", () => {
    for (let i = 0; i < slides.length; i++) {
      const { view, tile } = drawStage(i);
      expect(screen.getByTestId("stage-grid").children).toHaveLength(9);
      expect(screen.getByTestId("stage-plate").textContent).toBe(
        "STANDUP -- FRIDAY 2 OCTOBER 2026",
      );
      expect(screen.getByTestId("stage-register").textContent).toBe("REGISTER · REAL");
      expect(within(tile("pm")).getByText("CHAIR · PM")).toBeTruthy();
      expect(within(tile("qa")).getByText("WALK · QA ALCHEMIST")).toBeTruthy();
      expect(within(tile("new-hire")).getByText("DECIDE · NEW HIRE")).toBeTruthy();
      expect(within(tile("designer")).getByText("LOOK · DESIGNER")).toBeTruthy();
      expect(within(tile("ops-dev")).getByText("TRACKER · OPS-DEV")).toBeTruthy();
      expect(within(tile("ultrawide")).getByText("THE WEEK · ULTRAWIDE OVERLORD")).toBeTruthy();
      view.unmount();
    }
  });

  it("reduced motion stills the stage: the rule is in the keyframes, and the stage wears its class", () => {
    expect(REDUCED_MOTION_RULE).toMatch(/^@media \(prefers-reduced-motion: reduce\)/);
    expect(REDUCED_MOTION_RULE).toContain(`.${STAGE_CLASS} * { animation: none !important;`);
    const { view } = drawStage(0);
    const stage = view.container.querySelector(`.${STAGE_CLASS}`);
    expect(stage).not.toBeNull();
    expect(stage!.querySelector("style")!.textContent).toContain(REDUCED_MOTION_RULE);
  });
});

describe("the stage's bubbles", () => {
  const speech = (tile: HTMLElement) => within(tile).queryByTestId("stage-speech");

  it("the speaking tile has a speech surface carrying its slot lines; the others have none", () => {
    const { tile } = drawStage(2);
    const s = speech(tile("dev-hero"));
    expect(s).not.toBeNull();
    expect(s!.textContent).toMatch(/Yesterday {2}#107 Port the cast atoms/);
    expect(s!.textContent).toMatch(/#104 Verify the Studio tab draws on the PC \(verify-close\)/);
    for (const c of CAST) if (c.id !== "dev-hero") expect(speech(tile(c.id))).toBeNull();
  });

  it("the speech surface points at the speaker's face, not the tile's box", () => {
    mockPopovers.length = 0;
    const { tile } = drawStage(2);
    const face = screen.getByTestId("tile-dev-hero-face");
    expect(tile("dev-hero").contains(face)).toBe(true);
    expect(face).not.toBe(tile("dev-hero"));
    const speechPop = mockPopovers.filter((p) => p.positioning && "target" in p.positioning);
    expect(speechPop).toHaveLength(1);
    const pos = speechPop[0].positioning!;
    expect(pos.target).toBe(face);
    expect(pos.target).not.toBe(tile("dev-hero"));
    expect(pos.position).toBe("above");
    expect(pos.align).toBe("center");
  });

  it("a top-row speaker's bubble falls to below, tail still at the face, kept inside the stage -- never shifted sideways", () => {
    mockPopovers.length = 0;
    const { view } = drawStage(0); // the chair speaks the queue; every speaker takes the same positioning
    const speechPop = mockPopovers.filter((p) => p.positioning && "target" in p.positioning);
    expect(speechPop.length).toBeGreaterThan(0);
    const pos = speechPop[0].positioning!;
    expect(pos.fallbackPositions).toEqual(["below"]);
    expect(pos.overflowBoundary).toBe(view.container.querySelector(`.${STAGE_CLASS}`));
    expect(pos.overflowBoundary).not.toBeNull();
  });

  it("the mug tile anchors at the mug, not at the head (D-TA11)", () => {
    drawStage(4);
    const style = screen.getByTestId("tile-minimalist-face").style;
    expect(style.bottom).not.toBe("");
    expect(style.top).toBe("");
  });

  it("the thought bubble's placement is unchanged: its trigger, above, start-aligned", () => {
    mockPopovers.length = 0;
    drawStage(2);
    const thought = mockPopovers.filter((p) => p.positioning && !("target" in p.positioning));
    expect(thought.length).toBeGreaterThan(0);
    expect(thought[0].positioning).toEqual({ position: "above", align: "start" });
  });

  it("the mug's status sentence is the speech surface's one line", () => {
    const { tile } = drawStage(4);
    expect(speech(tile("minimalist"))!.textContent).toBe(
      'My async status:\n"Nothing on the board for me. All green, no blockers."',
    );
  });

  it("a seated tile does not open with the async words; only the mug does", () => {
    const { tile } = drawStage(2);
    expect(speech(tile("dev-hero"))!.textContent).not.toContain("My async status:");
    expect(say(2)).not.toContain("My async status:");
  });

  it("the thought surface is shut until the tile's button is clicked, then holds every slot's items", () => {
    const { tile } = drawStage(2);
    expect(screen.queryByTestId("stage-thought")).toBeNull();
    const trigger = within(tile("dev-hero")).getByTestId("stage-thought-trigger");
    expect(trigger.tagName).toBe("BUTTON"); // a real button: focusable, and Enter and Space click it
    fireEvent.click(trigger);
    const items = within(screen.getByTestId("stage-thought")).getByTestId("stage-thought-items");
    expect(within(items).getByText("Yesterday")).toBeTruthy();
    expect(within(items).getByText("#107")).toBeTruthy();
    expect(within(items).getByText("#104")).toBeTruthy();
    expect(items.textContent).toContain("Port the cast atoms");
    // The empty slot has no list; the thought is not a Say line.
    expect(within(items).queryByText(RITUALS.text.today)).toBeNull();
    expect(
      screen.getByTestId("stage-thought").closest('[data-testid="tile-dev-hero"]'),
    ).not.toBeNull();
  });

  it("Escape closes it", () => {
    const { tile } = drawStage(2);
    const trigger = within(tile("dev-hero")).getByTestId("stage-thought-trigger");
    trigger.focus();
    fireEvent.click(trigger);
    expect(screen.getByTestId("stage-thought")).toBeTruthy();
    fireEvent.keyDown(screen.getByTestId("stage-thought"), { key: "Escape" });
    expect(screen.queryByTestId("stage-thought")).toBeNull();
  });

  it("the deck's own keys do not see the thought's: Escape closes it and Space opens it, and neither reaches the window", () => {
    const seen: string[] = [];
    const onKey = (e: KeyboardEvent) => seen.push(e.key);
    window.addEventListener("keydown", onKey);
    try {
      const { tile } = drawStage(2);
      const trigger = within(tile("dev-hero")).getByTestId("stage-thought-trigger");
      // Space on the trigger: the browser turns it into the click that opens the thought.
      fireEvent.keyDown(trigger, { key: " " });
      fireEvent.click(trigger);
      expect(screen.getByTestId("stage-thought")).toBeTruthy();
      fireEvent.keyDown(screen.getByTestId("stage-thought"), { key: " " });
      fireEvent.keyDown(screen.getByTestId("stage-thought"), { key: "Escape" });
      expect(screen.queryByTestId("stage-thought")).toBeNull();
      // Escape from the focused trigger, with the thought open, is the same.
      fireEvent.click(trigger);
      expect(screen.getByTestId("stage-thought")).toBeTruthy();
      fireEvent.keyDown(trigger, { key: "Escape" });
      expect(screen.queryByTestId("stage-thought")).toBeNull();
      expect(seen).toEqual([]);
      // Keys that are the deck's still reach it.
      fireEvent.keyDown(trigger, { key: "ArrowRight" });
      expect(seen).toEqual(["ArrowRight"]);
    } finally {
      window.removeEventListener("keydown", onKey);
    }
  });

  it("both surfaces sit above the tile's scene layers, on an opaque white ground", () => {
    expect(BUBBLE_Z_INDEX).toBeGreaterThan(4);
    const { tile } = drawStage(2);
    fireEvent.click(within(tile("dev-hero")).getByTestId("stage-thought-trigger"));
    for (const id of ["stage-speech", "stage-thought"]) {
      const el = screen.getByTestId(id);
      expect(el.style.zIndex).toBe(String(BUBBLE_Z_INDEX));
      expect(el.style.background).toMatch(/#fff|rgb\(255, 255, 255\)/);
      expect(el.style.opacity).toBe("1");
    }
  });

  it("the speech bubble clamps its text to four lines, with no scrollbar; the thought is capped and scrolls", () => {
    const { tile } = drawStage(2);
    fireEvent.click(within(tile("dev-hero")).getByTestId("stage-thought-trigger"));
    const speech = screen.getByTestId("stage-speech-text");
    const thought = screen.getByTestId("stage-thought");
    expect(SPEECH_MAX_LINES).toBe(4);
    // (jsdom drops -webkit-box-orient, so only the parts it keeps are asserted.)
    expect(speech.style.display).toBe("-webkit-box");
    expect(speech.style.getPropertyValue("-webkit-line-clamp")).toBe("4");
    expect(speech.style.overflow).toBe("hidden");
    expect(speech.style.maxHeight).toBe("");
    // ...and the speech surface itself does not clip, so its tail shows.
    expect(screen.getByTestId("stage-speech").style.overflowY).toBe("visible");
    expect(thought.style.maxHeight).toBe(THOUGHT_MAX_HEIGHT);
    expect(thought.style.overflowY).toBe("auto");
  });

  it("the deck advancing closes it (the next slide's tiles are new)", () => {
    const view = render(<>{slides[2].content}</>);
    fireEvent.click(screen.getByTestId("stage-thought-trigger"));
    expect(screen.getByTestId("stage-thought")).toBeTruthy();
    view.rerender(<>{slides[3].content}</>);
    expect(screen.queryByTestId("stage-thought")).toBeNull();
  });

  it("a tile with nothing behind its sentence offers no thought", () => {
    const { tile } = drawStage(4); // the mug
    expect(within(tile("minimalist")).queryByTestId("stage-thought-trigger")).toBeNull();
  });

  it("the cloud floats, and the stage's reduced-motion rule stills every animation inside it", () => {
    const { tile, view } = drawStage(2);
    fireEvent.click(within(tile("dev-hero")).getByTestId("stage-thought-trigger"));
    const float = screen
      .getByTestId("stage-thought")
      .querySelector('[data-float="true"]') as HTMLElement;
    expect(float.style.animation).toContain("rs-float");
    expect(view.container.querySelector("style")!.textContent).toContain("@keyframes rs-float");
    expect(screen.getByTestId("stage-thought").closest(`.${STAGE_CLASS}`)).not.toBeNull();
    expect(REDUCED_MOTION_RULE).toContain(`.${STAGE_CLASS} * { animation: none !important;`);
  });

  it("neither bubble is read: the voice's text is the slide's notes alone, and opening a thought changes none", () => {
    const before = slides.map((_, i) => say(i));
    const { tile } = drawStage(2);
    fireEvent.click(within(tile("dev-hero")).getByTestId("stage-thought-trigger"));
    expect(slides.map((_, i) => say(i))).toEqual(before);
    expect(say(2)).not.toContain("Says");
  });
});

describe("the speaker's frame and the three looks", () => {
  const GREEN = "rgb(111, 207, 151)"; // pf.green
  const GREY = "rgb(102, 102, 102)"; // the ghost's dot
  const layer = (tile: HTMLElement) => within(tile).getByTestId("stage-layer");
  const dot = (tile: HTMLElement) => within(tile).getByTestId("stage-dot");
  const frame = (tile: HTMLElement) => within(tile).queryByTestId("stage-frame");
  const framed = (tile: HTMLElement) => frame(tile) !== null;

  it("exactly one tile a slide is the speaker: data-speaking, the 3px frame inside the box, in colour, a green dot", () => {
    for (let i = 0; i < slides.length; i++) {
      const { view, tile } = drawStage(i);
      const speaking = [
        ...view.container.querySelectorAll('[data-speaking="true"]'),
      ] as HTMLElement[];
      expect(speaking).toHaveLength(1);
      expect(speaking[0].getAttribute("data-look")).toBe("speaking");
      const f = frame(speaking[0])!;
      expect(f.style.outline).toMatch(/3px solid/);
      expect(f.style.outline).toContain(`var(${SPEAKER_COLOR_VAR}`);
      expect(f.style.outlineOffset).toBe("-3px");
      expect(layer(speaking[0]).style.filter).toBe("");
      expect(dot(speaking[0]).style.background).toBe(GREEN);
      // nobody else is framed
      for (const c of CAST) if (tile(c.id) !== speaking[0]) expect(framed(tile(c.id))).toBe(false);
      view.unmount();
    }
  });

  it("the queue's chair speaks in colour and the Walk seat is named: black and white at full brightness, the green dot", () => {
    const { tile } = drawStage(0);
    expect(tile("pm").getAttribute("data-look")).toBe("speaking");
    expect(tile("pm").getAttribute("data-speaking")).toBe("true");
    const qa = tile("qa");
    expect(qa.getAttribute("data-lit")).toBe("true");
    expect(qa.getAttribute("data-look")).toBe("named");
    expect(qa.getAttribute("data-speaking")).toBeNull();
    expect(layer(qa).style.filter).toBe("grayscale(1)");
    expect(layer(qa).style.filter).not.toMatch(/brightness/);
    // the dot is outside the filtered picture, so the signal light stays green
    expect(layer(qa).contains(dot(qa))).toBe(false);
    expect(framed(qa)).toBe(false);
    expect(dot(qa).style.background).toBe(GREEN);
  });

  it("every other tile is the ghost as it always was: grayscale, dimmed, the grey dot, unframed", () => {
    const { tile } = drawStage(0);
    for (const c of CAST) {
      if (c.id === "pm" || c.id === "qa") continue;
      expect(tile(c.id).getAttribute("data-look")).toBe("ghost");
      expect(layer(tile(c.id)).style.filter).toBe("grayscale(1) brightness(0.6)");
      expect(dot(tile(c.id)).style.background).toBe(GREY);
      expect(framed(tile(c.id))).toBe(false);
    }
    expect(LOOK_FILTER.ghost).toBe("grayscale(1) brightness(0.6)");
  });

  it("a worker's slide frames the worker alone; the chair and the queue's seats ghost", () => {
    const { tile, view } = drawStage(2);
    expect(tile("dev-hero").getAttribute("data-speaking")).toBe("true");
    expect(view.container.querySelectorAll('[data-look="named"]')).toHaveLength(0);
    expect(tile("pm").getAttribute("data-look")).toBe("ghost");
    expect(tile("qa").getAttribute("data-look")).toBe("ghost");
  });

  it("the mug's excuse is a speaker too: the one tile in colour and in the frame", () => {
    const { tile } = drawStage(4);
    expect(tile("minimalist").getAttribute("data-speaking")).toBe("true");
    expect(framed(tile("minimalist"))).toBe(true);
  });

  it("with no tracker, the tracker's seat is named beside the speaking chair", () => {
    const quiet = buildStandupDeck(responseFor("no-tracker")).slides();
    const view = render(<>{quiet[0].content}</>);
    expect(screen.getByTestId("tile-pm").getAttribute("data-look")).toBe("speaking");
    expect(screen.getByTestId("tile-ops-dev").getAttribute("data-look")).toBe("named");
    expect(view.container.querySelectorAll('[data-speaking="true"]')).toHaveLength(1);
  });

  it("the frame's colour is the stage's own light green, the same on every app theme -- no brand token, no bleed", () => {
    const colorOf = (id: string) => {
      mockThemeId = id;
      const view = render(<>{slides[2].content}</>);
      const stage = view.container.querySelector(`.${STAGE_CLASS}`) as HTMLElement;
      const got = stage.style.getPropertyValue(SPEAKER_COLOR_VAR);
      view.unmount();
      return got;
    };
    try {
      for (const id of ["seaglass", "aurora", "sunny"]) {
        expect(colorOf(id)).toBe("#6fcf97");
        expect(colorOf(id)).not.toBe(fluentThemeFor(themeById(id)!).colorBrandStroke1);
      }
    } finally {
      mockThemeId = "seaglass";
    }
  });
});

describe("the standup deck on a day with no tracker", () => {
  const data = responseFor("no-tracker");
  const s = buildStandupDeck(data).slides();

  it("still plays: queue, chair, chair, queue -- the tracker's reason as the queue", () => {
    expect(s.map((x) => x.id.replace(/^standup-\d{4}-\d{2}-\d{2}-/, ""))).toEqual([
      "queue",
      "chair-open",
      "chair-close",
      "queue-end",
    ]);
    expect(extractSayText(s[0].notes)).toBe(`${RITUALS.text.tracker}: ${data.tracker.reason}`);
  });

  it("lights the tracker's seat to say it", () => {
    render(<>{s[0].content}</>);
    expect(screen.getByTestId("tile-ops-dev").getAttribute("data-lit")).toBe("true");
  });
});

// D-TA20: the deck plays at the WORK grain, spoken as PROSE --
// one bubble line and one Say line a sentence, each the agent's own. The
// sentences are the shared prose table's friday case
// (Tests/fixtures/rituals/standup-prose.json, asserted by the CLI and the
// agent); its workers carry the same three labels as the standup table's
// friday, which supplies the seats, the mug and the excuse.
describe("the standup deck at the work grain, as prose", () => {
  interface ProseFixture {
    cases: {
      name: string;
      expected: { queue: string[]; workers: { label: string; prose: string[] }[]; text: string };
    }[];
  }
  const proseTable = JSON.parse(
    fs.readFileSync(path.join(FIXTURES, "standup-prose.json"), "utf8"),
  ) as ProseFixture;
  const pr = proseTable.cases.find((c) => c.name === "friday")!.expected;
  const data: StandupResponse = {
    ...friday,
    work: {
      queue: { walk: [], decide: [], look: [] },
      workers: pr.workers.map((w) => ({
        label: w.label,
        name: w.label,
        yesterday: [],
        today: [],
        blockers: [],
        prose: w.prose,
      })),
      queueProse: pr.queue,
      text: fs.readFileSync(path.join(FIXTURES, pr.text), "utf8"),
    },
  };
  const s = buildStandupDeck(data).slides();
  const sayOf = (i: number) => extractSayText(s[i].notes);

  it("keeps the same slides and ids", () => {
    expect(s.map((x) => x.id)).toEqual(slides.map((x) => x.id));
  });

  it("the queue: the chair reads the queue's sentences, not one line a ticket", () => {
    // The table's two queue sentences, as written -- the walk group of two, then the one routed to a worker.
    expect(pr.queue).toHaveLength(2);
    expect(sayOf(0)).toBe(pr.queue.join(" "));
  });

  it("Opus speaks its sentences as the agent wrote them, one Say line each", () => {
    expect(sayOf(3)).toBe(
      "Yesterday I closed two in Team Agile (#501, #502). I also closed one in the Studio: #503, Count the foyer rows. Today I'm on two in Team Agile (#504, #505). Nothing blocked.",
    );
    render(<>{s[3].content}</>);
    const tile = screen.getByTestId("tile-vibemancer");
    expect(
      within(tile).getByText(/Yesterday I closed two in Team Agile \(#501, #502\)\./),
    ).toBeTruthy();
    // No slot label is padded in front of a sentence, and no "no blockers" line.
    expect(within(tile).queryByText(new RegExp(RITUALS.text.blockersEmpty))).toBeNull();
  });

  it("Fable, with nothing yesterday, says nothing for it and names the blocker", () => {
    expect(sayOf(2)).toBe(
      "Today I'm on the Studio: #511, the archived-repository mark. I'm also on #512, Rename the slug. Blocked on #513, Verify the Studio tab draws on the PC.",
    );
  });

  it("an empty worker is still the mug and its status", () => {
    expect(sayOf(4)).toBe("My async status: Nothing on the board for me. All green, no blockers.");
  });

  it("an empty queue is the contract's sentence", () => {
    const quiet = { ...data, work: { ...data.work!, queueProse: [] } };
    expect(extractSayText(buildStandupDeck(quiet).slides()[0].notes)).toBe(RITUALS.text.queueEmpty);
  });

  it("with no tracker, the queue is the Tracker line whatever work says", () => {
    const down = {
      ...responseFor("no-tracker"),
      work: { queue: { walk: [], decide: [], look: [] }, workers: [], queueProse: [], text: "" },
    };
    expect(extractSayText(buildStandupDeck(down).slides()[0].notes)).toBe(
      `${RITUALS.text.tracker}: ${down.tracker.reason}`,
    );
  });

  // The dress: the stage reads `spoken` when present, `work` otherwise. The
  // sentences are the shared dress table's reply (Tests/fixtures/rituals/standup-dress.json):
  // what the guard let through in the model's words, the prose where it named a number the read lacks.
  describe("dressed", () => {
    const dressTable = JSON.parse(
      fs.readFileSync(path.join(FIXTURES, "standup-dress.json"), "utf8"),
    ) as {
      reply: { said: string[]; dressed: number; refused: number };
    };
    const opusSaid = [...dressTable.reply.said, RITUALS.text.proseBlockersNone];
    const dressed: StandupResponse = {
      ...data,
      spoken: {
        model: "m",
        workers: [{ label: "opus", prose: opusSaid }],
        dressed: dressTable.reply.dressed,
        refused: dressTable.reply.refused,
      },
    };
    const d = buildStandupDeck(dressed).slides();

    it("keeps the same slides and ids", () => {
      expect(d.map((x) => x.id)).toEqual(slides.map((x) => x.id));
    });

    it("a worker the model dressed speaks the spoken sentences, one Say line and one bubble line each", () => {
      expect(extractSayText(d[3].notes)).toBe(opusSaid.join(" "));
      render(<>{d[3].content}</>);
      const tile = screen.getByTestId("tile-vibemancer");
      expect(
        within(tile).getByText(/Plumbing for the Studio: #503, counted the foyer rows\./),
      ).toBeTruthy();
    });

    it("a long turn: the bubble clamps to four lines but every line stays in the Say notes", () => {
      const long = Array.from({ length: 9 }, (_, i) => `Line number ${i + 1} of a long turn.`);
      const talky: StandupResponse = {
        ...dressed,
        spoken: { ...dressed.spoken!, workers: [{ label: "opus", prose: long }] },
      };
      const slide = buildStandupDeck(talky).slides()[3];
      expect(extractSayText(slide.notes)).toBe(long.join(" "));
      render(<>{slide.content}</>);
      const text = within(screen.getByTestId("tile-vibemancer")).getByTestId("stage-speech-text");
      expect(text.style.getPropertyValue("-webkit-line-clamp")).toBe("4");
      // The clamp is paint only: the text node still holds all nine lines.
      expect(text.textContent).toBe(long.join("\n"));
    });

    it("a worker spoken does not carry speaks its prose", () => {
      expect(extractSayText(d[2].notes)).toBe(sayOf(2));
    });

    it("spoken null is the prose", () => {
      const plain = buildStandupDeck({ ...data, spoken: null }).slides();
      expect(extractSayText(plain[3].notes)).toBe(sayOf(3));
    });

    it("the queue and the mug are never dressed", () => {
      expect(extractSayText(d[0].notes)).toBe(sayOf(0));
      expect(extractSayText(d[4].notes)).toBe(sayOf(4));
    });
  });
});

describe("dealing the seats", () => {
  const w = (label: string) => ({
    label,
    name: label,
    yesterday: [],
    today: [],
    blockers: [],
    empty: true,
    excuse: "",
  });

  it("a worker sits in the seat kept for its label, whatever order it arrives in", () => {
    const { seated } = dealSeats([w("sonnet"), w("fable")]);
    expect(seated.map((x) => [x.seat.castId, x.worker.label])).toEqual([
      ["dev-hero", "fable"],
      ["minimalist", "sonnet"],
    ]);
  });

  it("an unknown worker takes a free worker seat; past three, it stands (nine is the ceiling)", () => {
    const { seated, standing } = dealSeats([w("fable"), w("haiku"), w("gemini"), w("opus")]);
    expect(seated.map((x) => [x.seat.castId, x.worker.label])).toEqual([
      ["dev-hero", "fable"],
      ["vibemancer", "opus"],
      ["minimalist", "haiku"],
    ]);
    expect(standing.map((x) => x.label)).toEqual(["gemini"]);
  });
});
