import fs from "node:fs";
import path from "node:path";
import { fireEvent, render, screen, within } from "@testing-library/react";
import { extractSayText } from "../../deck/engine/sayText";
import { RITUALS } from "../../../shell/consts";
import type { RitualItem, StandupResponse, StandupWorker, WorkWorker } from "../api.solitaireAgile";
import { STANDUP_DECK_ID } from "../paths";
import { fluentThemeFor } from "../../../shell/theme";
import { themeById } from "../../../shell/themeList";
import {
  BUBBLE_Z_INDEX,
  CAST,
  castById,
  SPEAKER_COLOR_VAR,
  SPEECH_MAX_LINES,
  THOUGHT_MAX_HEIGHT,
  REDUCED_MOTION_RULE,
  SPEECH_MAX_WIDTH,
  STAGE_CLASS,
  STAGE_GRID_CLASS,
} from "./cast";
import { MUG_LOOKS, dealMugLooks } from "./EmptyDesk";
import {
  CHAIR_CAST_ID,
  CHAIR_PLATE,
  EMPTY_DESK_PLATE,
  MEMBER_SEATS,
  MEMBER_WINDOWS,
  ROOM_WINDOWS,
  KEPT_WINDOWS,
  dealRoom,
  standupDayOfYear,
} from "./seats";
import { buildStandupDeck, callLine } from "./standupDeck";
import { SlideRenderer } from "../../deck/engine/SlideRenderer";
import { slideSpokenText } from "../../deck/engine/sayText";

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
// from the SHARED fixtures the CLI and the agent assert
// (Tests/fixtures/rituals/standup.json, standup-prose.json, standup-team.json and the
// golden texts), with the chair's lines and an idle worker's two made-up items picked
// from Config/standup-vocabulary.json by the fixtures' own indices -- the route's
// response, as the contract (4b) says. Nothing below types a sentence the fill says.

const ROOT = path.resolve(__dirname, "../../../../..");
const FIXTURES = path.join(ROOT, "Tests/fixtures/rituals");
const T = RITUALS.text;

interface FixtureCase {
  name: string;
  asOf: string;
  tracker: { ok: boolean; reason: string };
  issues: RitualItem[];
  expected: {
    since: string;
    dayOfYear: number;
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
      nothingTodayIndex: number | null;
    }[];
    text: string | null;
  };
}

const readJson = <J,>(file: string): J =>
  JSON.parse(fs.readFileSync(path.join(FIXTURES, file), "utf8")) as J;

const table = readJson<{ cases: FixtureCase[] }>("standup.json");
const vocab = JSON.parse(fs.readFileSync(path.join(ROOT, RITUALS.vocabularyFile), "utf8")) as {
  phrasebook: string[];
  nothing: string[];
  nothingToday: string[];
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
      status:
        w.nothingIndex === null || w.nothingTodayIndex === null
          ? []
          : [vocab.nothing[w.nothingIndex], vocab.nothingToday[w.nothingTodayIndex]],
    })),
    text: fs.readFileSync(path.join(FIXTURES, c.expected.text), "utf8"),
  };
}

// The shared prose table: each worker's turn and the chair's own, as the fill says them.
interface ProseFixture {
  cases: {
    name: string;
    expected: {
      queue: string[];
      workers: { label: string; prose: string[] }[];
      chair: string[];
      text: string;
    };
  }[];
}
const proseTable = readJson<ProseFixture>("standup-prose.json");
const proseCase = (name: string) => proseTable.cases.find((c) => c.name === name)!.expected;

/** A work row for a worker: its turn, and no groups (the stage reads only the prose). */
const workRow = (label: string, name: string, prose: string[]): WorkWorker => ({
  label,
  name,
  yesterday: [],
  today: [],
  blockers: [],
  prose,
});

/** An idle worker's two made-up items by the fill's own rule: (day + position) mod each family. */
const idlePair = (day: number, i: number) => [
  vocab.nothing[(day + i) % vocab.nothing.length],
  vocab.nothingToday[(day + i) % vocab.nothingToday.length],
];
/** An idle worker's turn: its pair in the frame, as the prose table's idle worker says it. */
const idleTurn = (pair: string[]) => [T.turnOpen, ...pair, T.proseBlockersNone, T.turnClose];

const friday = responseFor("friday");
// The friday case's one idle worker: its two made-up items, yesterday's then today's.
const SONNET_PAIR = friday.workers.find((w) => w.label === "sonnet")!.status;
const deck = buildStandupDeck(friday);
const slides = deck.slides();
const say = (i: number) => extractSayText(slides[i].notes);
const idOf = (s: { id: string }) => s.id.replace(/^standup-\d{4}-\d{2}-\d{2}-/, "");
/** Friday's slides by their part: the board, the call, the turn, the chair's status. */
const at = (part: string) => slides.findIndex((s) => idOf(s) === part);

/** Draw one slide's stage and return the helpers to read it. */
function drawStage(i: number, from = slides) {
  const view = render(<>{from[i].content}</>);
  const tile = (id: string) => screen.getByTestId(`tile-${id}`);
  const lit = () =>
    CAST.map((c) => c.id).filter((id) => tile(id).getAttribute("data-lit") === "true");
  return { view, tile, lit };
}

describe("the room", () => {
  it("is nine windows -- the cast, and the largest room a Space may state -- the chair's one of them", () => {
    expect(ROOM_WINDOWS).toBe(CAST.length);
    expect(ROOM_WINDOWS).toBe(Math.max(...RITUALS.teamSizes));
    expect(MEMBER_SEATS).toBe(ROOM_WINDOWS - 1);
    expect(MEMBER_WINDOWS).toHaveLength(MEMBER_SEATS);
    expect(MEMBER_WINDOWS.map((w) => w.castId)).not.toContain(CHAIR_CAST_ID);
    // The member windows are the cast in its order, the chair's left out; each wears its persona.
    expect(MEMBER_WINDOWS.map((w) => w.castId)).toEqual(
      CAST.map((c) => c.id).filter((id) => id !== CHAIR_CAST_ID),
    );
    for (const w of MEMBER_WINDOWS) expect(w.persona).toBe(castById(w.castId).label);
  });

  it("counts the day of the year as the fill does: 1-based, from the date as written", () => {
    for (const c of table.cases) expect(standupDayOfYear(c.asOf)).toBe(c.expected.dayOfYear);
    expect(standupDayOfYear("2026-01-01T00:30:00+14:00")).toBe(1);
    expect(standupDayOfYear("2028-12-31T23:59:00-12:00")).toBe(366);
  });

  it("seats a kept label in its own persona's window, in speaking order, and deals the rest their mugs by the day", () => {
    expect(KEPT_WINDOWS).toEqual({ fable: "dev-hero", opus: "vibemancer", sonnet: "minimalist" });
    // One label to a window.
    expect(new Set(Object.values(KEPT_WINDOWS)).size).toBe(Object.keys(KEPT_WINDOWS).length);
    const room = dealRoom(friday);
    expect(room.members.map((m) => [m.castId, m.worker.label])).toEqual([
      ["dev-hero", "fable"],
      ["vibemancer", "opus"],
      ["minimalist", "sonnet"],
    ]);
    expect(room.desks.map((d) => d.castId)).toEqual([
      "ops-dev",
      "new-hire",
      "ultrawide",
      "qa",
      "designer",
    ]);
    expect(room.desks.map((d) => d.look)).toEqual(
      dealMugLooks(standupDayOfYear(friday.asOf), MEMBER_SEATS - 3),
    );
  });

  it("a kept label matches whatever its case, and keeps its window whatever order it arrives in", () => {
    const [fable, opus, sonnet] = friday.workers;
    const room = dealRoom({ ...friday, workers: [sonnet, { ...opus, label: "Opus" }, fable] });
    expect(room.members.map((m) => [m.castId, m.worker.label])).toEqual([
      ["minimalist", "sonnet"],
      ["vibemancer", "Opus"],
      ["dev-hero", "fable"],
    ]);
  });

  it("any other label is dealt by position into the free windows, in cast order", () => {
    const w = (label: string) => ({ ...friday.workers[2], label, name: label });
    const room = dealRoom({ ...friday, workers: [w("haiku"), w("opus"), w("gemini")] });
    expect(room.members.map((m) => [m.castId, m.worker.label])).toEqual([
      ["dev-hero", "haiku"],
      ["vibemancer", "opus"],
      ["ops-dev", "gemini"],
    ]);
  });

  it("a kept label out today leaves its window empty -- nobody else's face takes it -- so no face moves when it is back", () => {
    const [fable, opus, sonnet] = friday.workers;
    const extra = (label: string) => ({ ...sonnet, label, name: label });
    const today = dealRoom({
      ...friday,
      workers: [{ ...fable, present: false }, extra("haiku"), opus, sonnet],
    });
    expect(today.members.map((m) => [m.castId, m.worker.label])).toEqual([
      ["ops-dev", "haiku"],
      ["vibemancer", "opus"],
      ["minimalist", "sonnet"],
    ]);
    expect(today.desks.map((d) => d.castId)).toContain("dev-hero");
    const back = dealRoom({ ...friday, workers: [fable, extra("haiku"), opus, sonnet] });
    for (const m of today.members)
      expect(back.members.find((x) => x.worker.label === m.worker.label)!.castId).toBe(m.castId);
  });

  it("a kept window this Space has no label for is an ordinary window, dealt by position", () => {
    const w = (label: string) => ({ ...friday.workers[2], label, name: label });
    const room = dealRoom({ ...friday, workers: ["a", "b", "c", "d", "e", "f", "g", "h"].map(w) });
    expect(room.members.map((m) => m.castId)).toEqual(MEMBER_WINDOWS.map((m) => m.castId));
    expect(room.desks).toEqual([]);
  });

  it("never drops a present member: when the free windows run out, a kept window an absent member left takes the next", () => {
    const [fable, opus, sonnet] = friday.workers;
    const w = (label: string) => ({ ...sonnet, label, name: label });
    const others = ["a", "b", "c", "d", "e", "f", "g"].map(w);
    const room = dealRoom({
      ...friday,
      workers: [{ ...fable, present: false }, opus, { ...sonnet, present: false }, ...others],
    });
    expect(room.members).toHaveLength(MEMBER_SEATS);
    expect(room.desks).toEqual([]);
    expect(room.members.find((m) => m.worker.label === "opus")!.castId).toBe("vibemancer");
    // The five free windows first, in cast order, then the kept windows left empty, in cast order.
    expect(room.members.filter((m) => m.worker.label !== "opus").map((m) => m.castId)).toEqual([
      "ops-dev",
      "new-hire",
      "ultrawide",
      "qa",
      "designer",
      "dev-hero",
      "minimalist",
    ]);
    // Speaking order is the response's, whichever window each sits in.
    expect(room.members.map((m) => m.worker.label)).toEqual([
      "opus",
      ...others.map((o) => o.label),
    ]);
  });

  it("a face never changes window because its work changed", () => {
    const idle = {
      ...friday,
      workers: friday.workers.map((w) => ({ ...w, yesterday: [], today: [], blockers: [] })),
    };
    expect(dealRoom(idle).members.map((m) => m.castId)).toEqual(
      dealRoom(friday).members.map((m) => m.castId),
    );
  });

  it("seats only the present, and an older agent's response -- no present -- seats everyone, capped at the room", () => {
    const many = Array.from({ length: 10 }, (_, i) => ({ ...friday.workers[2], label: `w${i}` }));
    expect(dealRoom({ ...friday, workers: many }).members).toHaveLength(MEMBER_SEATS);
    const marked = many.map((w, i) => ({ ...w, present: i % 2 === 0 }));
    expect(dealRoom({ ...friday, workers: marked }).members.map((m) => m.worker.label)).toEqual([
      "w0",
      "w2",
      "w4",
      "w6",
      "w8",
    ]);
    expect(dealRoom({ ...friday, workers: [] })).toEqual({
      members: [],
      desks: MEMBER_WINDOWS.map((w, i) => ({
        ...w,
        look: dealMugLooks(standupDayOfYear(friday.asOf), MEMBER_SEATS)[i],
      })),
    });
  });
});

describe("the standup deck, from Friday's fixture", () => {
  it("is an audiobook deck with the ritual's id and the text's first line as its title", () => {
    expect(deck.id).toBe(STANDUP_DECK_ID);
    expect(deck.audiobook).toBe(true);
    expect(deck.title).toBe("Standup -- Friday 2 October 2026");
    expect(deck.title).toBe(friday.text.split("\n")[0]);
  });

  it("goes round the room: the board, the chair, each member called and answering in seat order, the chair's status, the close", () => {
    expect(slides.map(idOf)).toEqual([
      "queue",
      "chair-open",
      "call-fable",
      "fable",
      "call-opus",
      "opus",
      "call-sonnet",
      "sonnet",
      "chair-status",
      "chair-close",
    ]);
    // From an agent that predates the chair's own turn, its status is the board again (D-TA6).
    expect(say(at("chair-status"))).toBe(say(at("queue")));
  });

  it("keeps every slide id across a rebuild", () => {
    expect(
      buildStandupDeck(friday)
        .slides()
        .map((s) => s.id),
    ).toEqual(slides.map((s) => s.id));
  });

  it("the board: the chair reads what is waiting on you, and no other window lights", () => {
    expect(say(0)).toBe(
      `${T.queueHeading}. Walk: issue 104, Verify the Studio tab draws on the PC. Walk: issue 105, Verify the clock fix on Windows.`,
    );
    const { tile, lit } = drawStage(0);
    expect(lit()).toEqual(["pm"]);
    expect(within(tile("pm")).getByText(/Walk #104 Verify the Studio tab/)).toBeTruthy();
  });

  it("the call: the chair says the member's name, and the member's window is called -- in colour, unframed, listening", () => {
    for (const w of friday.workers) {
      const i = at(`call-${w.label}`);
      expect(say(i)).toBe(callLine(w.name));
      expect(callLine(w.name)).toBe(`${w.name}.`);
      // The narrator hears the name once: no title is read before it.
      expect(slideSpokenText(slides[i])).toBe(`${w.name}.`);
      const { view, tile, lit } = drawStage(i);
      const seat = dealRoom(friday).members.find((m) => m.worker.label === w.label)!.castId;
      expect(lit()).toEqual(CAST.map((c) => c.id).filter((id) => id === "pm" || id === seat));
      expect(tile("pm").getAttribute("data-look")).toBe("speaking");
      expect(tile(seat).getAttribute("data-look")).toBe("called");
      expect(within(tile(seat)).getByTestId("stage-layer").style.filter).toBe("");
      expect(within(tile(seat)).queryByTestId("stage-frame")).toBeNull();
      // The called mark shows on any tint: on the called window, and on no other.
      expect(view.container.querySelectorAll('[data-testid="stage-called-mark"]')).toHaveLength(1);
      expect(within(tile(seat)).getByTestId("stage-called-mark").style.outline).toMatch(
        /3px dashed/,
      );
      expect(within(tile(seat)).getByTestId("stage-called-mark").style.outline).toContain(
        `var(${SPEAKER_COLOR_VAR}`,
      );
      expect(within(tile(seat)).queryByTestId("stage-speech")).toBeNull();
      expect(view.container.querySelectorAll('[data-testid="stage-frame"]')).toHaveLength(1);
      expect(within(tile("pm")).getByTestId("stage-speech-text").textContent).toBe(`${w.name}.`);
      // The member answers on the next slide, and the narrator does not say the name again.
      expect(idOf(slides[i + 1])).toBe(w.label);
      expect(slideSpokenText(slides[i + 1])).toBe(say(i + 1));
      expect(slideSpokenText(slides[i + 1]).startsWith(w.name)).toBe(false);
      view.unmount();
    }
  });

  it("the copy panel is the speaker's character, not the bubble again", () => {
    // A worker's slide: title, persona with the label, the motto in its own voice.
    const dev = render(<>{slides[at("fable")].copy}</>);
    const copy = dev.getByTestId("standup-copy");
    const hero = castById("dev-hero");
    expect(copy.textContent).toContain(hero.title);
    expect(copy.textContent).toContain(`${hero.label} (fable)`);
    expect(copy.textContent).toContain(hero.motto);
    expect(copy.textContent).not.toMatch(/#107|Port the cast atoms|Yesterday/);
    dev.unmount();
    // The chair's slides, the call's included: the PM, no label.
    for (const part of ["chair-open", "call-fable", "chair-status"]) {
      const chair = render(<>{slides[at(part)].copy}</>);
      const pm = castById("pm");
      expect(chair.getByTestId("standup-copy").textContent).toContain(pm.motto);
      expect(chair.getByTestId("standup-copy").textContent).toContain(pm.label);
      expect(chair.getByTestId("standup-copy").textContent).not.toMatch(/\((fable|opus|sonnet)\)/);
      chair.unmount();
    }
    // Every character has a title and a motto that is theirs, not a status.
    for (const c of CAST) {
      expect(c.title.length).toBeGreaterThan(0);
      expect(c.motto).toMatch(/^[IMT]/);
    }
  });

  it("the chair opens and closes with the phrasebook's lines", () => {
    expect(say(at("chair-open"))).toBe("Can we not adjust scope.");
    expect(say(at("chair-close"))).toBe("Let's circle back.");
    expect(slides.length - 1).toBe(at("chair-close"));
    const { lit } = drawStage(at("chair-open"));
    expect(lit()).toEqual(["pm"]);
  });

  it("Fable's tile: lit, plated PERSONA (label), the three slots as one Say line each", () => {
    expect(say(at("fable"))).toBe(
      `Yesterday: issue 107, Port the cast atoms. Today: ${T.todayEmpty}. Blockers: issue 104, Verify the Studio tab draws on the PC.`,
    );
    const { tile, lit } = drawStage(at("fable"));
    expect(lit()).toEqual(["dev-hero"]);
    expect(within(tile("dev-hero")).getByText("DEV-HERO (fable)")).toBeTruthy();
    expect(
      within(tile("dev-hero")).getByText(
        /#104 Verify the Studio tab draws on the PC \(verify-close\)/,
      ),
    ).toBeTruthy();
  });

  it("Opus's tile wears its plate, in its own persona's window", () => {
    const { tile, lit } = drawStage(at("opus"));
    expect(lit()).toEqual(["vibemancer"]);
    expect(within(tile("vibemancer")).getByText("AI VIBEMANCER (opus)")).toBeTruthy();
  });

  it("Sonnet had nothing: it keeps its face and says its two made-up items, never async", () => {
    expect(SONNET_PAIR).toHaveLength(2);
    expect(say(at("sonnet"))).toBe(SONNET_PAIR.join(" "));
    const { tile, lit } = drawStage(at("sonnet"));
    expect(lit()).toEqual(["minimalist"]);
    expect(within(tile("minimalist")).getByText("MINIMALIST (sonnet)")).toBeTruthy();
    expect(tile("minimalist").getAttribute("data-desk")).toBeNull();
    expect(within(tile("minimalist")).queryByTestId("empty-desk")).toBeNull();
    expect(within(tile("minimalist")).getByTestId("stage-speech-text").textContent).toBe(
      SONNET_PAIR.join("\n"),
    );
  });

  it("an idle worker from an agent older still -- one sentence, no pair -- says that sentence", () => {
    const old = {
      ...friday,
      workers: friday.workers.map((w) => (w.label === "sonnet" ? { ...w, status: [] } : w)),
    };
    const s = buildStandupDeck(old).slides();
    expect(extractSayText(s[at("sonnet")].notes)).toBe(SONNET_PAIR[0]);
  });

  it("a thin day: every worker keeps its face and speaks its own pair", () => {
    const day = standupDayOfYear(friday.asOf);
    const thin = {
      ...friday,
      workers: friday.workers.map((w, i) => ({
        ...w,
        yesterday: [],
        today: [],
        blockers: [],
        empty: true,
        excuse: idlePair(day, i)[0],
        status: idlePair(day, i),
      })),
    };
    const thinSlides = buildStandupDeck(thin).slides();
    const turns = thinSlides.filter((s) => ["fable", "opus", "sonnet"].includes(idOf(s)));
    expect(turns).toHaveLength(3);
    turns.forEach((s, i) => {
      expect(extractSayText(s.notes)).toBe(idlePair(day, i).join(" "));
      const { unmount } = render(<>{s.content}</>);
      const speaking = document.querySelector('[data-speaking="true"]') as HTMLElement;
      expect(speaking.getAttribute("data-desk")).toBeNull();
      expect(within(speaking).queryByTestId("empty-desk")).toBeNull();
      unmount();
    });
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
    const s = buildStandupDeck(mixed).slides()[at("fable")];
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

  it("every slide is the same nine windows -- the chair, each member's persona and label, an empty desk in the rest -- with the ritual's plate and the register (D-TA13, D-TA17)", () => {
    const { desks } = dealRoom(friday);
    for (let i = 0; i < slides.length; i++) {
      const { view, tile } = drawStage(i);
      expect(screen.getByTestId("stage-grid").children).toHaveLength(ROOM_WINDOWS);
      expect(screen.getByTestId("stage-plate").textContent).toBe(
        "STANDUP -- FRIDAY 2 OCTOBER 2026",
      );
      expect(screen.getByTestId("stage-register").textContent).toBe("REGISTER · REAL");
      expect(within(tile("pm")).getByText(CHAIR_PLATE)).toBeTruthy();
      expect(within(tile("dev-hero")).getByText("DEV-HERO (fable)")).toBeTruthy();
      expect(within(tile("vibemancer")).getByText("AI VIBEMANCER (opus)")).toBeTruthy();
      expect(within(tile("minimalist")).getByText("MINIMALIST (sonnet)")).toBeTruthy();
      for (const d of desks) {
        expect(within(tile(d.castId)).getByText(EMPTY_DESK_PLATE)).toBeTruthy();
        expect(tile(d.castId).getAttribute("data-desk")).toBe(d.look);
        expect(within(tile(d.castId)).getByTestId("empty-desk").getAttribute("data-look")).toBe(
          d.look,
        );
      }
      // No role is a window any more.
      expect(view.container.textContent).not.toMatch(
        /TEAM LEAD|WALK ·|DECIDE ·|LOOK ·|TRACKER ·|THE WEEK/,
      );
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
  const FABLE = at("fable");

  it("the speaking tile has a speech surface carrying its slot lines; the others have none", () => {
    const { tile } = drawStage(FABLE);
    const s = speech(tile("dev-hero"));
    expect(s).not.toBeNull();
    expect(s!.textContent).toMatch(/Yesterday {2}#107 Port the cast atoms/);
    expect(s!.textContent).toMatch(/#104 Verify the Studio tab draws on the PC \(verify-close\)/);
    for (const c of CAST) if (c.id !== "dev-hero") expect(speech(tile(c.id))).toBeNull();
  });

  it("the speech surface is the speaking window's own, laid out unseen until the stage has placed it", () => {
    const { tile } = drawStage(FABLE);
    const s = speech(tile("dev-hero"))!;
    // A test's DOM has no layout, so nothing is measured and it is never placed: unseen.
    expect(s.style.visibility).toBe("hidden");
    expect(s.style.position).toBe("absolute");
    // Main's size: up to 260px and never wider than its window, the text at 0.6rem.
    expect(SPEECH_MAX_WIDTH).toBe("min(260px, 100%)");
    expect(s.style.maxWidth).toBe(SPEECH_MAX_WIDTH);
    expect(within(s).getByTestId("stage-speech-text").style.fontSize).toBe("0.6rem");
    expect(within(s).queryByTestId("stage-speech-tail")).toBeNull();
  });

  it("the stage marks what a bubble must keep off: every face there is, and every plate", () => {
    const { view } = drawStage(FABLE);
    const faces = [...view.container.querySelectorAll("[data-face]")].map((f) =>
      f.getAttribute("data-testid")!.replace(/^tile-|-face$/g, ""),
    );
    const { members } = dealRoom(friday);
    expect(faces.sort()).toEqual([CHAIR_CAST_ID, ...members.map((m) => m.castId)].sort());
    expect(view.container.querySelectorAll('[data-testid="stage-plate-label"]')).toHaveLength(
      ROOM_WINDOWS,
    );
    // The bubble is placed inside the grid of windows: the title row is not part of it.
    const grid = view.container.querySelector(`.${STAGE_GRID_CLASS}`)!;
    expect(grid).toBe(screen.getByTestId("stage-grid"));
    expect(grid.contains(screen.getByTestId("stage-plate"))).toBe(false);
  });

  it("the bubble shows a turn's first four lines and the voice says all of it", () => {
    expect(SPEECH_MAX_LINES).toBe(4);
    const { tile } = drawStage(at("opus"));
    const text = within(tile("vibemancer")).getByTestId("stage-speech-text");
    expect(text.style.getPropertyValue("-webkit-line-clamp")).toBe("4");
    // The clamp is paint only: the text node holds every line, and the voice says them.
    expect(text.textContent!.split("\n").length).toBeGreaterThanOrEqual(3);
    expect(say(at("opus")).length).toBeGreaterThan(0);
  });

  it("an empty desk has no face to point at, no bubble and no thought", () => {
    for (let i = 0; i < slides.length; i++) {
      const { view } = drawStage(i);
      for (const d of dealRoom(friday).desks) {
        expect(screen.queryByTestId(`tile-${d.castId}-face`)).toBeNull();
        const desk = screen.getByTestId(`tile-${d.castId}`);
        expect(speech(desk)).toBeNull();
        expect(within(desk).queryByTestId("stage-thought-trigger")).toBeNull();
      }
      view.unmount();
    }
  });

  it("the thought bubble's placement is unchanged: its trigger, above, start-aligned", () => {
    mockPopovers.length = 0;
    const { tile } = drawStage(FABLE);
    const thought = mockPopovers.filter((p) => p.positioning && !("target" in p.positioning));
    expect(thought.length).toBeGreaterThan(0);
    expect(thought[0].positioning).toEqual({ position: "above", align: "start" });
    // ...and its button where it has always been, at the window's left above the plate.
    const trigger = within(tile("dev-hero")).getByTestId("stage-thought-trigger");
    expect([trigger.style.left, trigger.style.bottom]).toEqual(["6px", "30px"]);
  });

  it("an idle member's two made-up items are the speech surface's lines", () => {
    const { tile } = drawStage(at("sonnet"));
    expect(speech(tile("minimalist"))!.textContent).toBe(SONNET_PAIR.join("\n"));
  });

  it("no slide opens with the async words: a present member is not async", () => {
    for (let i = 0; i < slides.length; i++) expect(say(i)).not.toContain("async");
  });

  it("the thought surface is shut until the tile's button is clicked, then holds every slot's items", () => {
    const { tile } = drawStage(FABLE);
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
    expect(within(items).queryByText(T.today)).toBeNull();
    expect(
      screen.getByTestId("stage-thought").closest('[data-testid="tile-dev-hero"]'),
    ).not.toBeNull();
  });

  it("Escape closes it", () => {
    const { tile } = drawStage(FABLE);
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
      const { tile } = drawStage(FABLE);
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
    const { tile } = drawStage(FABLE);
    fireEvent.click(within(tile("dev-hero")).getByTestId("stage-thought-trigger"));
    for (const id of ["stage-speech", "stage-thought"]) {
      const el = screen.getByTestId(id);
      expect(el.style.zIndex).toBe(String(BUBBLE_Z_INDEX));
      expect(el.style.background).toMatch(/#fff|rgb\(255, 255, 255\)/);
      expect(el.style.opacity).toBe("1");
    }
  });

  it("the speech bubble clamps its text to its lines, with no scrollbar; the thought is capped and scrolls", () => {
    const { tile } = drawStage(FABLE);
    fireEvent.click(within(tile("dev-hero")).getByTestId("stage-thought-trigger"));
    const speech = screen.getByTestId("stage-speech-text");
    const thought = screen.getByTestId("stage-thought");
    // (jsdom drops -webkit-box-orient, so only the parts it keeps are asserted.)
    expect(speech.style.display).toBe("-webkit-box");
    expect(speech.style.getPropertyValue("-webkit-line-clamp")).toBe(String(SPEECH_MAX_LINES));
    expect(speech.style.overflow).toBe("hidden");
    expect(speech.style.maxHeight).toBe("");
    // ...and the speech surface itself does not clip, so its tail shows.
    expect(screen.getByTestId("stage-speech").style.overflowY).toBe("visible");
    expect(thought.style.maxHeight).toBe(THOUGHT_MAX_HEIGHT);
    expect(thought.style.overflowY).toBe("auto");
  });

  it("the deck advancing closes it (the next slide's tiles are new)", () => {
    const view = render(<>{slides[FABLE].content}</>);
    fireEvent.click(screen.getByTestId("stage-thought-trigger"));
    expect(screen.getByTestId("stage-thought")).toBeTruthy();
    view.rerender(<>{slides[FABLE + 1].content}</>);
    expect(screen.queryByTestId("stage-thought")).toBeNull();
  });

  it("a tile with nothing behind its sentence offers no thought", () => {
    const { tile } = drawStage(at("sonnet")); // the idle member
    expect(within(tile("minimalist")).queryByTestId("stage-thought-trigger")).toBeNull();
  });

  it("the cloud floats, and the stage's reduced-motion rule stills every animation inside it", () => {
    const { tile, view } = drawStage(FABLE);
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
    const { tile } = drawStage(FABLE);
    fireEvent.click(within(tile("dev-hero")).getByTestId("stage-thought-trigger"));
    expect(slides.map((_, i) => say(i))).toEqual(before);
    expect(say(FABLE)).not.toContain("Says");
  });
});

describe("the speaker's frame and the three looks", () => {
  const GREEN = "rgb(111, 207, 151)"; // pf.green
  const GREY = "rgb(102, 102, 102)"; // an empty desk's dot
  const layer = (tile: HTMLElement) => within(tile).getByTestId("stage-layer");
  const plate = (tile: HTMLElement) => within(tile).getByTestId("stage-plate-label");
  const dot = (tile: HTMLElement) => within(tile).getByTestId("stage-dot");
  const frame = (tile: HTMLElement) => within(tile).queryByTestId("stage-frame");
  const framed = (tile: HTMLElement) => frame(tile) !== null;
  const { members, desks } = dealRoom(friday);

  it("exactly one tile a slide is the speaker: data-speaking, the 3px frame inside the box, a green dot", () => {
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
      // On a call slide one more window is marked, the one called -- nobody else.
      const called = view.container.querySelectorAll('[data-look="called"]');
      expect(called.length).toBe(idOf(slides[i]).startsWith("call-") ? 1 : 0);
      // The called mark is the called window's alone: none on any other slide.
      expect(view.container.querySelectorAll('[data-testid="stage-called-mark"]')).toHaveLength(
        called.length,
      );
      view.unmount();
    }
  });

  it("every window is in full colour on every slide: no picture and no plate is filtered, and nothing is dimmed", () => {
    for (let i = 0; i < slides.length; i++) {
      const { view, tile } = drawStage(i);
      for (const c of CAST) {
        const t = tile(c.id);
        expect(layer(t).style.filter).toBe("");
        expect(layer(t).style.opacity).toBe("");
        expect(plate(t).style.filter).toBe("");
        expect(t.style.filter).toBe("");
      }
      // Nothing on the stage is drawn in black and white or turned down: not a
      // tile, not a layer, not a plate, not a drawing inside one.
      for (const el of view.container.querySelectorAll<HTMLElement>(`.${STAGE_CLASS} *`)) {
        expect(el.style.filter).not.toMatch(/grayscale|brightness|saturate|contrast/);
      }
      view.unmount();
    }
  });

  it("the speaker is told apart by its frame alone, and the called window by its ring alone", () => {
    for (let i = 0; i < slides.length; i++) {
      const { view } = drawStage(i);
      const frames = view.container.querySelectorAll('[data-testid="stage-frame"]');
      expect(frames).toHaveLength(1);
      expect(frames[0].closest('[data-look="speaking"]')).not.toBeNull();
      for (const mark of view.container.querySelectorAll('[data-testid="stage-called-mark"]')) {
        expect(mark.closest('[data-look="called"]')).not.toBeNull();
        expect((mark as HTMLElement).style.outline).toMatch(/3px dashed/);
      }
      view.unmount();
    }
  });

  it("a face that is there and not speaking is named: in colour, its green dot, no frame", () => {
    for (let i = 0; i < slides.length; i++) {
      const { view, tile } = drawStage(i);
      for (const id of [CHAIR_CAST_ID, ...members.map((m) => m.castId)]) {
        const t = tile(id);
        if (t.getAttribute("data-speaking") === "true") continue;
        if (t.getAttribute("data-look") === "called") continue;
        expect(t.getAttribute("data-look")).toBe("named");
        expect(layer(t).style.filter).toBe("");
        // the dot is the plate's, outside the picture: the signal light
        expect(layer(t).contains(dot(t))).toBe(false);
        expect(dot(t).style.background).toBe(GREEN);
        expect(framed(t)).toBe(false);
      }
      view.unmount();
    }
  });

  it("an empty desk is in colour on every slide -- the drink on it, the grey dot, unframed: nobody is there", () => {
    expect(desks.length).toBeGreaterThan(0);
    for (let i = 0; i < slides.length; i++) {
      const { view, tile } = drawStage(i);
      for (const d of desks) {
        const t = tile(d.castId);
        expect(t.getAttribute("data-look")).toBe("ghost");
        expect(t.getAttribute("data-lit")).toBe("false");
        expect(layer(t).style.filter).toBe("");
        expect(plate(t).style.filter).toBe("");
        // What says the seat is empty is the drink on the desk, the one the day dealt.
        expect(within(t).getByTestId("empty-desk").getAttribute("data-look")).toBe(d.look);
        expect(within(t).queryByTestId("empty-desk-mug")).not.toBeNull();
        expect(within(t).queryByTestId("empty-desk-chair")).not.toBeNull();
        expect(t.querySelector("[data-refined]")).toBeNull();
        expect(dot(t).style.background).toBe(GREY);
        expect(framed(t)).toBe(false);
      }
      view.unmount();
    }
  });

  it("every face is the refined cast's, matched by the cast id of its window", () => {
    const { tile } = drawStage(0);
    for (const id of [CHAIR_CAST_ID, ...members.map((m) => m.castId)]) {
      const busts = tile(id).querySelectorAll("[data-refined]");
      expect(busts).toHaveLength(1);
      expect(busts[0].getAttribute("data-refined")).toBe(id);
      expect(busts[0].getAttribute("aria-hidden")).toBe("true");
    }
  });

  it("an idle member is a speaker too: the one tile in the frame", () => {
    const { tile } = drawStage(at("sonnet"));
    expect(tile("minimalist").getAttribute("data-speaking")).toBe("true");
    expect(framed(tile("minimalist"))).toBe(true);
  });

  it("with no tracker, the chair says so and no other window lights for it", () => {
    const quiet = buildStandupDeck(responseFor("no-tracker")).slides();
    const view = render(<>{quiet[0].content}</>);
    expect(screen.getByTestId("tile-pm").getAttribute("data-look")).toBe("speaking");
    // The tracker's window is an empty desk like any other: the alarm is the chair's line.
    expect(screen.getByTestId("tile-ops-dev").getAttribute("data-look")).toBe("ghost");
    expect(screen.getByTestId("tile-ops-dev").getAttribute("data-desk")).not.toBeNull();
    expect(view.container.querySelectorAll('[data-speaking="true"]')).toHaveLength(1);
    expect(view.container.querySelectorAll('[data-lit="true"]')).toHaveLength(1);
  });

  it("the frame's colour is the stage's own light green, the same on every app theme -- no brand token, no bleed", () => {
    const colorOf = (id: string) => {
      mockThemeId = id;
      const view = render(<>{slides[at("fable")].content}</>);
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

  it("still plays: the board, the chair, its status, the close -- the tracker's reason as the board", () => {
    expect(s.map(idOf)).toEqual(["queue", "chair-open", "chair-status", "chair-close"]);
    expect(extractSayText(s[0].notes)).toBe(`${T.tracker}: ${data.tracker.reason}`);
  });

  it("at the work grain the chair has no status to give, and the text prints none", () => {
    const pr = proseCase("no-tracker");
    expect(pr.chair).toEqual([]);
    const down = {
      ...data,
      work: {
        queue: { walk: [], decide: [], look: [] },
        workers: [],
        queueProse: pr.queue,
        chairProse: pr.chair,
        text: "",
      },
    };
    expect(buildStandupDeck(down).slides().map(idOf)).toEqual([
      "queue",
      "chair-open",
      "chair-close",
    ]);
  });
});

// D-TA20: the deck plays at the WORK grain, spoken as PROSE --
// one bubble line and one Say line a sentence, each the agent's own. The
// sentences are the shared prose table's friday case
// (Tests/fixtures/rituals/standup-prose.json, asserted by the CLI and the
// agent); its workers carry the same three labels as the standup table's
// friday, which supplies the seats and the idle worker's pair.
describe("the standup deck at the work grain, as prose", () => {
  const pr = proseCase("friday");
  const data: StandupResponse = {
    ...friday,
    work: {
      queue: { walk: [], decide: [], look: [] },
      workers: pr.workers.map((w) => workRow(w.label, w.label, w.prose)),
      queueProse: pr.queue,
      chairProse: pr.chair,
      text: fs.readFileSync(path.join(FIXTURES, pr.text), "utf8"),
    },
  };
  const s = buildStandupDeck(data).slides();
  const sayOf = (i: number) => extractSayText(s[i].notes);

  it("keeps the same slides and ids", () => {
    expect(s.map((x) => x.id)).toEqual(slides.map((x) => x.id));
  });

  it("the board: the chair reads the queue's sentences, not one line a ticket", () => {
    // The table's two queue sentences, as written -- the walk group of two, then the one routed to a worker.
    expect(pr.queue).toHaveLength(2);
    expect(sayOf(0)).toBe(pr.queue.join(" "));
  });

  it("the chair gives its own status last, in the frame, and never the board's sentences again", () => {
    const i = at("chair-status");
    expect(sayOf(i)).toBe(pr.chair.join(" "));
    expect([pr.chair[0], pr.chair[pr.chair.length - 1]]).toEqual([T.turnOpen, T.turnClose]);
    for (const q of pr.queue) expect(sayOf(i)).not.toContain(q);
    render(<>{s[i].content}</>);
    expect(within(screen.getByTestId("tile-pm")).getByTestId("stage-speech-text").textContent).toBe(
      pr.chair.join("\n"),
    );
  });

  const proseOf = (label: string) => pr.workers.find((w) => w.label === label)!.prose;

  it("Opus speaks its turn as the agent wrote it, one Say line a sentence, in the frame", () => {
    const opus = proseOf("opus");
    expect([opus[0], opus[opus.length - 1]]).toEqual([T.turnOpen, T.turnClose]);
    expect(opus).toContain(T.proseBlockersNone);
    expect(sayOf(at("opus"))).toBe(opus.join(" "));
    render(<>{s[at("opus")].content}</>);
    const tile = screen.getByTestId("tile-vibemancer");
    expect(
      within(tile).getByText(/Yesterday I closed two in Team Agile \(#501, #502\)\./),
    ).toBeTruthy();
    // No slot label is padded in front of a sentence, and no "no blockers" line.
    expect(within(tile).queryByText(new RegExp(T.blockersEmpty))).toBeNull();
  });

  it("Fable, with nothing yesterday, says the fixed line for it and names the blocker", () => {
    const fable = proseOf("fable");
    expect(fable.some((x) => x.startsWith(T.proseYesterday))).toBe(false);
    // Nothing closed and nothing it holds began in the window: the fixed honest line,
    // never a made-up item beside its real today.
    expect(fable[1]).toBe(T.proseYesterdayNone);
    expect(fable.filter((x) => SONNET_PAIR.includes(x))).toEqual([]);
    expect(fable.some((x) => x.startsWith(T.proseBlockers))).toBe(true);
    expect(fable).not.toContain(T.proseBlockersNone);
    expect(sayOf(at("fable"))).toBe(fable.join(" "));
  });

  it("an idle worker speaks its turn: its two made-up items in the frame", () => {
    const sonnet = proseOf("sonnet");
    expect(sonnet).toEqual(idleTurn(SONNET_PAIR));
    expect(sayOf(at("sonnet"))).toBe(sonnet.join(" "));
  });

  it("an idle worker from an agent whose prose has no turn says its pair -- never async, never silent", () => {
    const old = {
      ...data,
      work: {
        ...data.work!,
        workers: data.work!.workers.map((w) => (w.label === "sonnet" ? { ...w, prose: [] } : w)),
      },
    };
    expect(extractSayText(buildStandupDeck(old).slides()[at("sonnet")].notes)).toBe(
      SONNET_PAIR.join(" "),
    );
  });

  it("an empty queue is the contract's sentence", () => {
    const quiet = { ...data, work: { ...data.work!, queueProse: [] } };
    expect(extractSayText(buildStandupDeck(quiet).slides()[0].notes)).toBe(T.queueEmpty);
  });

  it("with no tracker, the board is the Tracker line whatever work says", () => {
    const down = {
      ...responseFor("no-tracker"),
      work: { queue: { walk: [], decide: [], look: [] }, workers: [], queueProse: [], text: "" },
    };
    expect(extractSayText(buildStandupDeck(down).slides()[0].notes)).toBe(
      `${T.tracker}: ${down.tracker.reason}`,
    );
  });

  // The dress: the stage reads `spoken` when present, `work` otherwise. The
  // sentences are the shared dress table's reply (Tests/fixtures/rituals/standup-dress.json):
  // what the guard let through in the model's words, the prose where it named a number the read lacks.
  describe("dressed", () => {
    const dressTable = readJson<{ reply: { said: string[]; dressed: number; refused: number } }>(
      "standup-dress.json",
    );
    const opusSaid = [T.turnOpen, ...dressTable.reply.said, T.proseBlockersNone, T.turnClose];
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
      expect(extractSayText(d[at("opus")].notes)).toBe(opusSaid.join(" "));
      render(<>{d[at("opus")].content}</>);
      const tile = screen.getByTestId("tile-vibemancer");
      expect(
        within(tile).getByText(/Plumbing for the Studio: #503, counted the foyer rows\./),
      ).toBeTruthy();
    });

    it("a long turn: the bubble clamps but every line stays in the Say notes", () => {
      const long = Array.from({ length: 9 }, (_, i) => `Line number ${i + 1} of a long turn.`);
      const talky: StandupResponse = {
        ...dressed,
        spoken: { ...dressed.spoken!, workers: [{ label: "opus", prose: long }] },
      };
      const slide = buildStandupDeck(talky).slides()[at("opus")];
      expect(extractSayText(slide.notes)).toBe(long.join(" "));
      render(<>{slide.content}</>);
      const text = within(screen.getByTestId("tile-vibemancer")).getByTestId("stage-speech-text");
      expect(text.style.getPropertyValue("-webkit-line-clamp")).toBe(String(SPEECH_MAX_LINES));
      // The clamp is paint only: the text node still holds all nine lines.
      expect(text.textContent).toBe(long.join("\n"));
    });

    it("a worker spoken does not carry speaks its prose", () => {
      expect(extractSayText(d[at("fable")].notes)).toBe(sayOf(at("fable")));
    });

    it("spoken null is the prose", () => {
      const plain = buildStandupDeck({ ...data, spoken: null }).slides();
      expect(extractSayText(plain[at("opus")].notes)).toBe(sayOf(at("opus")));
    });

    it("the board, the calls, the chair's status and an idle member are never dressed", () => {
      for (const part of ["queue", "call-opus", "chair-status", "sonnet"])
        expect(extractSayText(d[at(part)].notes)).toBe(sayOf(at(part)));
    });
  });
});

// ── No silent face ───────────────────────────────────────────────────────────
// Every window that draws a face -- the chair and each seated member -- has at
// least one slide where it speaks; every other window is an empty desk, never
// lit, on no slide. Held over every shape of room a response can give.

/** Play every slide and say who spoke, and which windows were desks. */
function playRoom(data: StandupResponse) {
  const s = buildStandupDeck(data).slides();
  const spoke = new Map<string, number>();
  const desks = new Set<string>();
  for (const slide of s) {
    const view = render(<>{slide.content}</>);
    const speaking = [...view.container.querySelectorAll('[data-speaking="true"]')];
    expect(speaking).toHaveLength(1);
    const id = speaking[0].getAttribute("data-testid")!.replace(/^tile-/, "");
    expect(
      within(speaking[0] as HTMLElement).getByTestId("stage-speech-text").textContent,
    ).not.toBe("");
    expect(extractSayText(slide.notes)).not.toBe("");
    spoke.set(id, (spoke.get(id) ?? 0) + 1);
    for (const d of view.container.querySelectorAll("[data-desk]")) {
      const at = d.getAttribute("data-testid")!.replace(/^tile-/, "");
      desks.add(at);
      expect(d.getAttribute("data-lit")).toBe("false");
      expect(d.getAttribute("data-look")).toBe("ghost");
    }
    view.unmount();
  }
  const faces = CAST.map((c) => c.id).filter((id) => !desks.has(id));
  return { slides: s, spoke, desks, faces };
}

function expectNoSilentFace(data: StandupResponse, members: number) {
  const room = playRoom(data);
  expect(room.faces).toHaveLength(1 + members);
  expect(room.desks.size).toBe(ROOM_WINDOWS - 1 - members);
  for (const face of room.faces) expect(room.spoke.get(face) ?? 0).toBeGreaterThan(0);
  for (const desk of room.desks) expect(room.spoke.has(desk)).toBe(false);
  // The desks in one room each have a different mug.
  const looks = dealRoom(data).desks.map((d) => d.look);
  expect(new Set(looks).size).toBe(looks.length);
  return room;
}

// The owner's demo room, held: the chair; two members with tracker work (the prose
// table's two working members); three idle members, each saying its own made-up pair by the
// fill's rule; three empty desks. The members' labels and names are the fixtures'
// own -- the team table's four and the joined table's card tile -- in label order.
const teamTable = readJson<{
  cases: { name: string; teamSize: number | null; expected: TeamExpected }[];
}>("standup-team.json");
interface TeamExpected {
  team: { size: number };
  workers: { label: string; name: string; empty: boolean; present: boolean }[];
  work: string;
}
const joined = readJson<{ cases: { name: string; expected: { workers: StandupWorker[] } }[] }>(
  "standup-joined.json",
);

function demoRoom(): StandupResponse {
  const day = standupDayOfYear(friday.asOf);
  const pr = proseCase("friday");
  const named = new Map(
    [
      ...teamTable.cases[0].expected.workers,
      ...joined.cases.find((c) => c.name === "together")!.expected.workers,
    ].map((w) => [w.label, w.name]),
  );
  const working = new Map(friday.workers.filter((w) => !w.empty).map((w) => [w.label, w]));
  const labels = ["fable", "haiku", "opus", "sonnet", "widgets"];
  const workers: StandupWorker[] = [];
  const rows: WorkWorker[] = [];
  labels.forEach((label, i) => {
    const name = named.get(label)!;
    const busy = working.get(label);
    if (busy) {
      workers.push({ ...busy, present: true });
      rows.push(workRow(label, name, pr.workers.find((w) => w.label === label)!.prose));
      return;
    }
    const pair = idlePair(day, i);
    workers.push({
      label,
      name,
      yesterday: [],
      today: [],
      blockers: [],
      empty: true,
      excuse: pair[0],
      status: pair,
      present: true,
    });
    rows.push(workRow(label, name, idleTurn(pair)));
  });
  return {
    ...friday,
    team: { size: ROOM_WINDOWS },
    workers,
    work: {
      queue: { walk: [], decide: [], look: [] },
      workers: rows,
      queueProse: pr.queue,
      chairProse: demoChair(day, labels.length),
      text: fs.readFileSync(path.join(FIXTURES, pr.text), "utf8"),
    },
  };
}

/** The chair's own turn in a room of `n` workers: the prose table's friday turn, its
 *  made-up yesterday picked as the fill picks it -- nothing[(d + n) mod len], after
 *  every worker's -- so it never repeats a member's. */
function demoChair(day: number, n: number): string[] {
  const chair = proseCase("friday").chair;
  return [chair[0], vocab.nothing[(day + n) % vocab.nothing.length], ...chair.slice(2)];
}

describe("no silent face", () => {
  it("the chair's made-up yesterday here is the fill's: the prose table's, in its room of three", () => {
    const day = standupDayOfYear(friday.asOf);
    expect(proseCase("friday").workers).toHaveLength(3);
    expect(demoChair(day, 3)).toEqual(proseCase("friday").chair);
  });

  it("the idle pair rule here is the fill's: it gives the shared table's indices", () => {
    for (const c of table.cases)
      c.expected.workers.forEach((w, i) => {
        if (w.nothingIndex === null) return;
        expect(idlePair(c.expected.dayOfYear, i)).toEqual([
          vocab.nothing[w.nothingIndex],
          vocab.nothingToday[w.nothingTodayIndex!],
        ]);
      });
  });

  describe("the demo room: the chair, two members with work, three idle, three empty desks", () => {
    const data = demoRoom();
    const { members, desks } = dealRoom(data);
    let room: ReturnType<typeof playRoom>;

    it("every face speaks and every other window is an empty desk with a mug of its own", () => {
      room = expectNoSilentFace(data, 5);
    });

    it("seats the kept three in their own windows and the other two by position, and leaves three desks", () => {
      expect(members.map((m) => [m.castId, m.worker.label])).toEqual([
        ["dev-hero", "fable"],
        ["ops-dev", "haiku"],
        ["vibemancer", "opus"],
        ["minimalist", "sonnet"],
        ["new-hire", "widgets"],
      ]);
      expect(desks.map((d) => d.castId)).toEqual(["ultrawide", "qa", "designer"]);
      expect(new Set(desks.map((d) => d.look)).size).toBe(3);
      for (const d of desks) expect(MUG_LOOKS).toContain(d.look);
    });

    it("the chair speaks the board, its open, each call, its status and its close; each member speaks once", () => {
      expect(room.spoke.get(CHAIR_CAST_ID)).toBe(4 + members.length);
      for (const m of members) expect(room.spoke.get(m.castId)).toBe(1);
      expect(room.slides.map(idOf)).toEqual([
        "queue",
        "chair-open",
        ...members.flatMap((m) => [`call-${m.worker.label}`, m.worker.label]),
        "chair-status",
        "chair-close",
      ]);
    });

    it("each idle member keeps its face, lit while it speaks, and says a pair no other says", () => {
      const idle = members.filter((m) => m.worker.empty);
      expect(idle).toHaveLength(3);
      const said = idle.map((m) => {
        const slide = room.slides.find((s) => idOf(s) === m.worker.label)!;
        const view = render(<>{slide.content}</>);
        const t = screen.getByTestId(`tile-${m.castId}`);
        expect(t.getAttribute("data-look")).toBe("speaking");
        expect(within(t).queryByTestId("empty-desk")).toBeNull();
        expect(within(t).getByTestId("stage-speech-text").textContent).toBe(
          idleTurn(m.worker.status).join("\n"),
        );
        view.unmount();
        return m.worker.status.join(" ");
      });
      expect(new Set(said).size).toBe(3);
      const chairSaid = data.work!.chairProse!.join(" ");
      for (const m of idle)
        for (const line of m.worker.status) expect(chairSaid).not.toContain(line);
      for (const m of idle) expect(m.worker.status[0]).not.toBe(m.worker.status[1]);
    });

    it("the two with work speak their tracker turns", () => {
      const pr = proseCase("friday");
      for (const label of ["fable", "opus"]) {
        const slide = room.slides.find((s) => idOf(s) === label)!;
        expect(extractSayText(slide.notes)).toBe(
          pr.workers.find((w) => w.label === label)!.prose.join(" "),
        );
      }
    });
  });

  it("a Space with no worker labels, on the issues: no worker at all -- the chair speaks, eight desks", () => {
    const data = responseFor("no-worker-labels");
    expect(data.workers).toEqual([]);
    const room = expectNoSilentFace(data, 0);
    expect(room.faces).toEqual([CHAIR_CAST_ID]);
    expect(extractSayText(room.slides[at("chair-open")].notes)).toContain(T.noWorkers);
  });

  it("a Space with no worker labels, on its cards: the engineer's own tile is a member and speaks", () => {
    const pr = proseCase("cards");
    expect(pr.workers.map((w) => w.label)).toEqual(["widgets"]);
    const own = joined.cases
      .find((c) => c.name === "together")!
      .expected.workers.find((w) => w.label === "widgets")!;
    const data: StandupResponse = {
      ...responseFor("no-worker-labels"),
      source: "cards",
      workers: [
        {
          label: own.label,
          name: own.name,
          yesterday: [],
          today: [],
          blockers: [],
          empty: false,
          excuse: "",
          status: [],
        },
      ],
      work: {
        queue: { walk: [], decide: [], look: [] },
        workers: pr.workers.map((w) => workRow(w.label, own.name, w.prose)),
        queueProse: pr.queue,
        chairProse: pr.chair,
        text: "",
      },
    };
    const room = expectNoSilentFace(data, 1);
    expect(room.faces).toEqual(["dev-hero", CHAIR_CAST_ID]);
  });

  it("the absent workers of a room of three are silent and unseen: two members, six desks", () => {
    const c = teamTable.cases.find((x) => x.name === "absent")!;
    expect(c.expected.team.size).toBe(3);
    // Each present worker's turn, and the chair's, as the work golden prints them.
    const work = fs.readFileSync(path.join(FIXTURES, c.expected.work), "utf8").split("\n");
    const turnOf = (name: string) =>
      work.find((l) => l.startsWith(`${name}: `))!.slice(name.length + 2);
    const data: StandupResponse = {
      ...friday,
      team: c.expected.team,
      workers: c.expected.workers.map((w) => ({
        label: w.label,
        name: w.name,
        yesterday: [],
        today: [],
        blockers: [],
        empty: w.empty,
        excuse: "",
        status: [],
        present: w.present,
      })),
      work: {
        queue: { walk: [], decide: [], look: [] },
        workers: c.expected.workers
          .filter((w) => w.present)
          .map((w) => workRow(w.label, w.name, [turnOf(w.name)])),
        queueProse: [],
        chairProse: [work.find((l) => l.startsWith(T.turnOpen))!],
        text: work.join("\n"),
      },
    };
    const room = expectNoSilentFace(data, 2);
    expect(dealRoom(data).members.map((m) => m.worker.label)).toEqual(["haiku", "sonnet"]);
    const ids = room.slides.map(idOf);
    for (const gone of c.expected.workers.filter((w) => !w.present)) {
      expect(ids.some((id) => id.endsWith(gone.label))).toBe(false);
      for (const s of room.slides) {
        expect(extractSayText(s.notes)).not.toContain(gone.name);
        const view = render(<>{s.content}</>);
        expect(view.container.textContent).not.toContain(`(${gone.label})`);
        view.unmount();
      }
    }
  });

  describe("nine labels or more: the room is full and the rest are out", () => {
    const day = standupDayOfYear(friday.asOf);
    const ten = Array.from({ length: 10 }, (_, i) => {
      const pair = idlePair(day, i);
      return {
        worker: {
          label: `w${i + 1}`,
          name: `W${i + 1}`,
          yesterday: [],
          today: [],
          blockers: [],
          empty: true,
          excuse: pair[0],
          status: pair,
        } as StandupWorker,
        prose: idleTurn(pair),
      };
    });
    const response = (workers: StandupWorker[]): StandupResponse => ({
      ...friday,
      workers,
      work: {
        queue: { walk: [], decide: [], look: [] },
        workers: workers
          .filter((w) => w.present !== false)
          .map((w) => workRow(w.label, w.name, ten.find((t) => t.worker.label === w.label)!.prose)),
        queueProse: [],
        chairProse: proseCase("quiet").chair,
        text: "",
      },
    });

    it("marked present by the fill: eight sit, no desk, the two out are never seen", () => {
      const data = response(ten.map((t, i) => ({ ...t.worker, present: i < MEMBER_SEATS })));
      const room = expectNoSilentFace(data, MEMBER_SEATS);
      expect(room.desks.size).toBe(0);
      expect(room.slides.map(idOf)).not.toContain("w9");
      expect(room.slides.map(idOf)).not.toContain("w10");
    });

    it("from an older agent with no present: the first eight sit, capped at the room", () => {
      const data = response(ten.map((t) => t.worker));
      const room = expectNoSilentFace(data, MEMBER_SEATS);
      expect(dealRoom(data).members.map((m) => m.worker.label)).toEqual(
        ten.slice(0, MEMBER_SEATS).map((t) => t.worker.label),
      );
      expect(room.slides.map(idOf)).not.toContain("w9");
    });
  });

  it("an older agent's response with no work at all still plays every face", () => {
    // friday has no `work`, no `present` and no `team`: the slot lines, everyone present.
    expect(friday.work).toBeUndefined();
    expect(friday.team).toBeUndefined();
    expectNoSilentFace(friday, 3);
  });
});

// The round, played through the engine's own renderer (deck/engine/SlideRenderer.tsx,
// which owns the content panel's key). The stage's slides share one content key,
// so the room stays mounted from slide to slide: a window is one DOM node for the
// whole round, enters once, and only what changed on it is redrawn.
describe("the room stays mounted across the round", () => {
  const ENTRANCE = /rs-pop/;
  function play(i: number) {
    const view = render(<SlideRenderer slide={slides[i]} slideIndex={i} isFullscreen={false} />);
    const go = (n: number) =>
      view.rerender(<SlideRenderer slide={slides[n]} slideIndex={n} isFullscreen={false} />);
    const tile = (id: string) => screen.getByTestId(`tile-${id}`);
    /** The element that carries a window's entrance: the tile inside its wrapper. */
    const entering = (id: string) =>
      [...tile(id).querySelectorAll<HTMLElement>("*")].filter((el) =>
        ENTRANCE.test(el.style.animation),
      );
    const nodes = () =>
      new Map(CAST.map((c) => [c.id, { wrap: tile(c.id), pop: entering(c.id)[0] }] as const));
    return { view, go, tile, entering, nodes };
  }
  const speakerOf = (view: ReturnType<typeof render>) =>
    [...view.container.querySelectorAll('[data-speaking="true"]')].map((el) =>
      el.getAttribute("data-testid")!.replace(/^tile-/, ""),
    );

  it("every slide of the round carries the one content key, so the engine keeps the stage", () => {
    const keys = new Set(slides.map((s) => s.contentKey));
    expect(keys.size).toBe(1);
    expect([...keys][0]).toMatch(/^standup-\d{4}-\d{2}-\d{2}-stage$/);
    // The same response builds the same key: a refetch keeps the room too.
    expect(buildStandupDeck(friday).slides()[0].contentKey).toBe(slides[0].contentKey);
  });

  it("when the speaker changes, every window is the same node and none replays its entrance", () => {
    const { view, go, nodes, entering } = play(0);
    const grid = screen.getByTestId("stage-grid");
    const first = nodes();
    // Each window has its entrance once, on the node it was first drawn with.
    for (const c of CAST) expect(entering(c.id)).toHaveLength(1);
    for (let i = 1; i < slides.length; i++) {
      go(i);
      expect(screen.getByTestId("stage-grid")).toBe(grid);
      const now = nodes();
      for (const c of CAST) {
        // The same DOM nodes, wrapper and tile: nothing was remounted, so no
        // animation on it restarted -- the entrance, the steam, the bob.
        expect(now.get(c.id)!.wrap).toBe(first.get(c.id)!.wrap);
        expect(now.get(c.id)!.pop).toBe(first.get(c.id)!.pop);
        // And no new node carries an entrance for that window.
        expect(entering(c.id)).toEqual([first.get(c.id)!.pop]);
      }
    }
    view.unmount();
  });

  it("the windows nobody is speaking in keep their drawings too: the same desk, the same bust", () => {
    const { go, tile } = play(at("call-fable"));
    const drawn = (id: string) =>
      tile(id).querySelector("[data-refined], [data-testid='empty-desk']");
    const before = new Map(CAST.map((c) => [c.id, drawn(c.id)] as const));
    go(at("fable"));
    for (const c of CAST) expect(drawn(c.id)).toBe(before.get(c.id));
  });

  it("the new speaker has the frame and a bubble, the old one has neither", () => {
    const { view, go, tile } = play(at("call-fable"));
    expect(speakerOf(view)).toEqual(["pm"]);
    expect(within(tile("dev-hero")).queryByTestId("stage-called-mark")).not.toBeNull();
    go(at("fable"));
    expect(speakerOf(view)).toEqual(["dev-hero"]);
    expect(within(tile("dev-hero")).queryByTestId("stage-frame")).not.toBeNull();
    expect(within(tile("dev-hero")).queryByTestId("stage-speech")).not.toBeNull();
    expect(within(tile("dev-hero")).queryByTestId("stage-called-mark")).toBeNull();
    expect(tile("dev-hero").getAttribute("data-look")).toBe("speaking");
    expect(within(tile("pm")).queryByTestId("stage-frame")).toBeNull();
    expect(within(tile("pm")).queryByTestId("stage-speech")).toBeNull();
    expect(tile("pm").getAttribute("data-look")).toBe("named");
    // One frame, one bubble, on the whole stage.
    expect(view.container.querySelectorAll('[data-testid="stage-frame"]')).toHaveLength(1);
    expect(view.container.querySelectorAll('[data-testid="stage-speech"]')).toHaveLength(1);
  });

  it("a bubble is its slide's: the chair speaking on two slides running gets a new bubble, with its entrance and the new words", () => {
    // The board, then the chair's opening line: the same window speaks twice.
    const { view, go, tile } = play(0);
    expect(speakerOf(view)).toEqual(["pm"]);
    const bubble = () => within(tile("pm")).getByTestId("stage-speech");
    const first = bubble();
    const firstText = first.textContent;
    go(1);
    expect(speakerOf(view)).toEqual(["pm"]);
    expect(bubble()).not.toBe(first);
    expect(bubble().textContent).not.toBe(firstText);
    expect(bubble().querySelector<HTMLElement>("div")!.style.animation).toMatch(/rs-bubble/);
    // Laid out unseen until the stage places it: the last slide's place is not this one's.
    expect(bubble().style.visibility).toBe("hidden");
  });

  it("a thought left open does not stay open on the next slide", () => {
    const { go, tile } = play(0);
    fireEvent.click(within(tile("pm")).getByTestId("stage-thought-trigger"));
    expect(screen.queryByTestId("stage-thought")).not.toBeNull();
    go(1);
    expect(screen.queryByTestId("stage-thought")).toBeNull();
    // Back on a slide where the chair has detail, the thought is there to open, shut.
    go(0);
    expect(within(tile("pm")).queryByTestId("stage-thought-trigger")).not.toBeNull();
    expect(screen.queryByTestId("stage-thought")).toBeNull();
  });

  it("nothing on the stage runs a set number of times but the two entrances", () => {
    const { view } = play(at("fable"));
    const finite = [...view.container.querySelectorAll<HTMLElement>(`.${STAGE_CLASS} *`)]
      .map((el) => el.style.animation)
      .filter((a) => a && !/infinite/.test(a))
      .map((a) => a.split(" ")[0]);
    expect([...new Set(finite)].sort()).toEqual(["rs-bubble", "rs-pop"]);
  });
});
