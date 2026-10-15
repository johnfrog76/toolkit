import { useState } from "react";
import type { CSSProperties, ReactNode } from "react";
import type { Deck, Slide } from "../../deck/decks/types";
import { Say } from "../../deck/engine/PresenterNoteKit";
import { RITUALS } from "../../../shell/consts";
import type {
  QueueItem,
  RitualItem,
  StandupResponse,
  StandupWorker,
  WorkWorker,
} from "../api.solitaireAgile";
import { STANDUP_DECK_ID } from "../paths";
import { IssuePopover } from "../IssuePopover";
import {
  CAST,
  CastScene,
  castById,
  Mug,
  SPEAKER_COLOR_VAR,
  SpeechBubble,
  STAGE_CLASS,
  StandupKeyframes,
  ThoughtBubble,
  ZoomTile,
  mono,
  pf,
} from "./cast";
import type { TileLook } from "./cast";
import { SEATS, dealSeats, plateFor, seatOf } from "./seats";
import type { Seat } from "./seats";

// ── The standup, played (docs/modules/solitaire-agile.md, "The played view") ─────────
//
// The agent's standup response turned into a Deck the deck engine plays
// unchanged: the Remote Standup's stage (./cast.tsx), the engine's script.
// Three slide kinds and nothing else (docs/modules/solitaire-agile.md, "The played view"):
//
//   the QUEUE   -- what only the human can do; the chair reads it out
//   the CHAIR   -- the PM's seat, the phrasebook's noun-less line
//   a WORKER    -- one lit tile, its three slots, or the mug and its status
//
// in the order queue, chair, each seated worker, chair, queue (D-TA6: the
// queue is first and last). Every slide is the same nine tiles (D-TA17), the
// ritual's plate across the top and the register on it (D-TA13), and its
// Say lines are generated from the slot text so the engine's narration and
// its duration estimate work as they do for any deck. The deck is an
// AUDIOBOOK (decks/types.ts): Suitcase at any width, the browser's voice.
//
// Every fixed word of the standup is the contract's (consts.json
// rituals.text, through RITUALS); the words below are this view's own --
// the plates (./seats.ts) and two queue-kind labels the text has none for yet.
//
// The deck plays at the WORK grain (D-TA20): a person speaks at the grain
// of the work, not the ticket, so a tile says one SENTENCE a group -- the
// response's prose, the sentences the rule wrote from the issues' facts
// ("Yesterday I closed two in Team Agile."): `work.queueProse` for
// the queue, each worker's `prose`, one bubble line and one Say line a sentence,
// nothing re-worded here. Sixteen issues become a few sentences. An agent that
// predates `work` gets the items one by one, as V1 played them. The detail view
// (the page's list) is the ledger.

const T = RITUALS.text;

/** The queue kinds the text does not label yet (decide and look are V2's). */
const DECIDE = "Decide";
const LOOK = "Look";
const CHAIR_TITLE = "The chair";
/** What a tile with no person in it opens with: the mug is a seat reporting
 *  async. The stage's own reading of its tile -- the CLI's text has no tile -- so it
 *  lives here, not in consts.json. */
const ASYNC_OPENER = "My async status:";
const STANDING = "Also standing";

/** One slot's items, as the thought bubble lists them: the detail behind the sentence. */
interface DetailSlot {
  label: string;
  items: RitualItem[];
}

/** What one slide says: the bubble's lines, and the voice's. */
interface Script {
  lines: string[];
  say: string[];
}

/** `#<n> Verify the Studio tab` -- how a bubble shows an issue. */
const shown = (i: RitualItem) => `#${i.number} ${i.title}`;
/** `issue 104, Verify the Studio tab` -- how the voice reads one. */
const spoken = (i: RitualItem) => `issue ${i.number}, ${i.title}`;

/** The date part of asOf, as written (its own offset): the slide ids' stem. */
export function standupDate(asOf: string): string {
  return asOf.slice(0, 10);
}

/** The ritual's title: the text's first line, the useful view's header too. */
export function standupTitle(data: StandupResponse): string {
  const at = data.text.indexOf("\n");
  return at < 0 ? data.text : data.text.slice(0, at);
}

function queueScript(data: StandupResponse): Script {
  if (!data.tracker.ok) {
    return {
      lines: [`${T.tracker}  ${data.tracker.reason}`],
      say: [`${T.tracker}: ${data.tracker.reason}`],
    };
  }
  const kinds: [string, QueueItem[]][] = [
    [T.walk, data.queue.walk],
    [DECIDE, data.queue.decide],
    [LOOK, data.queue.look],
  ];
  const lines: string[] = [];
  const say: string[] = [`${T.queueHeading}.`];
  for (const [label, items] of kinds) {
    for (const item of items ?? []) {
      lines.push(`${label}  ${shown(item)}`);
      say.push(`${label}: ${spoken(item)}.`);
    }
  }
  if (lines.length === 0) return { lines: [T.queueEmpty], say: [T.queueEmpty] };
  return { lines: [T.queueHeading, ...lines], say };
}

/** The queue at the work grain, spoken as prose: one bubble line and one
 *  Say line a sentence, exactly as the agent wrote them. */
function queueWorkScript(data: StandupResponse): Script | null {
  const work = data.work;
  if (!work || !data.tracker.ok) return null;
  const said = work.queueProse ?? [];
  if (said.length === 0) return { lines: [T.queueEmpty], say: [T.queueEmpty] };
  return { lines: [...said], say: [...said] };
}

/** The mug and its status sentence (the agent's), opened as async. */
function asyncScript(w: StandupWorker): Script {
  return {
    lines: [ASYNC_OPENER, `"${w.excuse}"`],
    say: [`${ASYNC_OPENER} ${w.excuse}`],
  };
}

/** A worker at the work grain, spoken as prose: its sentences, one bubble
 *  line and one Say line each -- the dressed ones (`spoken`) when a model
 *  answered, the prose otherwise. An empty worker is async (above). */
function workerWorkScript(w: StandupWorker, ww: WorkWorker, dressed?: string[]): Script {
  if (w.empty) return asyncScript(w);
  const said = dressed ?? ww.prose ?? [];
  return { lines: [...said], say: [...said] };
}

function workerScript(w: StandupWorker, ww?: WorkWorker, dressed?: string[]): Script {
  if (ww) return workerWorkScript(w, ww, dressed);
  if (w.empty) return asyncScript(w);
  const slot = (
    label: string,
    items: RitualItem[],
    none: string,
    suffix = "",
  ): [string, string] => [
    items.length
      ? `${label}  ${items.map((i) => shown(i) + suffix).join("; ")}`
      : `${label}  ${none}`,
    items.length ? `${label}: ${items.map(spoken).join("; ")}.` : `${label}: ${none}.`,
  ];
  const rows = [
    slot(T.yesterday, w.yesterday, T.yesterdayEmpty),
    slot(T.today, w.today, T.todayEmpty),
    slot(T.blockers, w.blockers, T.blockersEmpty, T.blockerSuffix),
  ];
  return { lines: rows.map((r) => r[0]), say: rows.map((r) => r[1]) };
}

// ── The stage ────────────────────────────────────────────────────────────────

interface TileState {
  /** Lit: the seat speaks or has something on this slide. Else ghosted. */
  lit?: boolean;
  /** The mug where the face would be (D-TA11). */
  mug?: boolean;
  /** The bubble's lines, on a lit tile. */
  bubble?: string[];
  /** The detail behind the sentence, for the thought bubble; absent when there is none. */
  detail?: DetailSlot[];
}

/** The steaming mug, large, in place of the scene (D-TA11). */
function MugGlyph() {
  return (
    <div data-testid="stage-mug" style={{ position: "absolute", inset: 0, background: "#1d2436" }}>
      <Mug left="40%" bottom="34%" size={56} color={pf.sand} steam />
    </div>
  );
}

/**
 * Where each scene's head is, as the top of the head in the tile: the
 * nine scenes are drawn differently (the minimalist sits low, the ultrawide's
 * head is near the top), so one fixed spot would hang the bubble over a
 * different part of each. The bubble's tail points here; the mug's rim on a mug
 * tile (D-TA11).
 */
const HEADS: Record<string, { left: string; top: string }> = {
  "dev-hero": { left: "50%", top: "38%" },
  "ops-dev": { left: "50%", top: "58%" },
  minimalist: { left: "50%", top: "66%" },
  "new-hire": { left: "23%", top: "60%" },
  vibemancer: { left: "50%", top: "53%" },
  ultrawide: { left: "50%", top: "16%" },
  qa: { left: "44%", top: "45%" },
  pm: { left: "50%", top: "45%" },
  designer: { left: "50%", top: "42%" },
};
const MUG_FACE = { left: "calc(40% + 28px)", bottom: "calc(34% + 56px)" } as const;

/** A tile and what it says: the speech bubble while it speaks, the thought bubble where there is detail. */
function Tile({ id, label, t }: { id: string; label: string; t: TileState }) {
  // The anchor the engine points the speech bubble at: a small element
  // over the speaker's face, not the tile's box. The stage is the boundary the
  // bubble is kept inside.
  const [anchor, setAnchor] = useState<HTMLElement | null>(null);
  const boundary = anchor?.closest<HTMLElement>(`.${STAGE_CLASS}`) ?? null;
  const detail = (t.detail ?? []).filter((s) => s.items.length > 0);
  // Speaking is "its bubble is open"; named is lit without one.
  const speaking = !!t.lit && !!t.bubble && t.bubble.length > 0;
  const look: TileLook = speaking ? "speaking" : t.lit ? "named" : "ghost";
  return (
    <div
      data-testid={`tile-${id}`}
      data-lit={t.lit ? "true" : "false"}
      data-look={look}
      data-speaking={speaking ? "true" : undefined}
      style={{ position: "relative", minHeight: 0 }}
    >
      <ZoomTile tint={CAST.find((c) => c.id === id)!.tint} label={label} look={look}>
        {t.mug ? <MugGlyph /> : <CastScene id={id} parked />}
      </ZoomTile>
      <div
        ref={setAnchor}
        data-testid={`tile-${id}-face`}
        aria-hidden
        style={{
          position: "absolute",
          width: "1px",
          height: "1px",
          pointerEvents: "none",
          ...(t.mug ? MUG_FACE : (HEADS[id] ?? { left: "50%", top: "40%" })),
        }}
      />
      {t.lit && t.bubble && t.bubble.length > 0 && (
        <SpeechBubble anchor={anchor} boundary={boundary}>
          {t.bubble.join("\n")}
        </SpeechBubble>
      )}
      {t.lit && detail.length > 0 && (
        <ThoughtBubble label={`What ${label} did not say`}>
          <div
            data-testid="stage-thought-items"
            style={{ display: "flex", flexDirection: "column", gap: "6px", fontSize: "0.7rem" }}
          >
            {detail.map((s) => (
              <div key={s.label}>
                <strong>{s.label}</strong>
                <ul style={{ margin: 0, paddingLeft: "16px" }}>
                  {s.items.map((i) => (
                    <li key={i.number}>
                      <IssuePopover facts={{ title: i.title, label: `#${i.number}`, url: i.url }} />{" "}
                      {i.title}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </ThoughtBubble>
      )}
    </div>
  );
}

function StageView({
  plate,
  register,
  tiles,
  plates,
  slideKey,
}: {
  slideKey: string;
  plate: string;
  register: string;
  tiles: Map<string, TileState>;
  plates: Map<string, string>;
}) {
  // The speaker's frame is the stage's own green -- the register badge's at the top
  // right and the speaker's name-dot: a colour of the room's palette, never a
  // theme's brand token, so nothing the app wears reaches the room.
  const speaker = pf.green;
  return (
    <div
      className={STAGE_CLASS}
      data-speaker-color={speaker}
      style={{
        ...({ [SPEAKER_COLOR_VAR]: speaker } as CSSProperties),
        position: "relative",
        width: "100%",
        height: "100%",
        overflow: "hidden",
        background: pf.bg,
        borderRadius: "10px",
        display: "flex",
        flexDirection: "column",
      }}
    >
      <StandupKeyframes />
      {/* The plate: the ritual's title, and the register always beside it. */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          gap: "12px",
          padding: "12px 18px 0",
          fontFamily: mono,
          color: pf.text,
        }}
      >
        <span
          data-testid="stage-plate"
          style={{ fontSize: "0.9rem", fontWeight: 700, letterSpacing: "0.18em" }}
        >
          {plate.toUpperCase()}
        </span>
        <span
          data-testid="stage-register"
          style={{
            fontSize: "0.62rem",
            fontWeight: 700,
            letterSpacing: "0.14em",
            color: "#0c2417",
            background: pf.green,
            borderRadius: "999px",
            padding: "3px 10px",
            flexShrink: 0,
          }}
        >
          REGISTER · {register.toUpperCase()}
        </span>
      </div>
      <div
        data-testid="stage-grid"
        style={{
          flex: 1,
          minHeight: 0,
          margin: "12px 18px 18px",
          display: "grid",
          gridTemplateColumns: "repeat(3, 1fr)",
          gridAutoRows: "1fr",
          gap: "10px",
        }}
      >
        {CAST.map((c) => {
          return (
            <Tile
              key={`${slideKey}-${c.id}`}
              id={c.id}
              label={plates.get(c.id) ?? c.label}
              t={tiles.get(c.id) ?? {}}
            />
          );
        })}
      </div>
    </div>
  );
}

// ── The copy panel (the engine's right 40%) ─────────────────────────────────
// Who is speaking, not what they said: the bubble shows the sentence and
// the voice reads it, so a third copy beside the stage was noise. The panel is
// the speaker's character: the title, the persona with the worker's label beside
// it (the one real noun, the same word the issue carries), and the motto in the
// character's own voice.

function Copy({ castId, label }: { castId: string; label?: string }) {
  const member = castById(castId);
  return (
    <div
      data-testid="standup-copy"
      style={{
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        height: "100%",
        padding: "32px 40px",
      }}
    >
      <p
        style={{
          margin: "0 0 12px",
          fontSize: "0.8rem",
          fontWeight: 700,
          letterSpacing: "0.14em",
          textTransform: "uppercase",
          color: pf.brand,
        }}
      >
        {member.title}
      </p>
      <h2
        style={{
          margin: "0 0 16px",
          fontSize: "1.9rem",
          fontWeight: 800,
          lineHeight: 1.25,
          color: pf.text,
        }}
      >
        {label ? `${member.label} (${label})` : member.label}
      </h2>
      <p
        style={{
          margin: 0,
          fontSize: "1.05rem",
          fontStyle: "italic",
          lineHeight: 1.5,
          color: pf.muted,
        }}
      >
        &mdash; {member.motto}
      </p>
    </div>
  );
}

/** The whole Say block for a slide: one <Say> per line, in order. */
function notesOf(say: string[]): ReactNode {
  return (
    <>
      {say.map((s, i) => (
        <Say key={i}>{s}</Say>
      ))}
    </>
  );
}

/**
 * The Deck for one standup response. Pure: the same response builds the same
 * slides with the same ids (`standup-<date>-<seat>`), so a rebuild after a
 * refetch keeps the player where it was.
 */
export function buildStandupDeck(data: StandupResponse): Deck {
  const title = standupTitle(data);
  const stem = `standup-${standupDate(data.asOf)}`;
  const { seated, standing } = dealSeats(data.workers ?? []);

  // Every tile's plate for this standup: the dealt workers wear their own
  // label; a worker seat nobody sits in today keeps its role and persona.
  const plates = new Map<string, string>();
  for (const seat of SEATS) plates.set(seat.castId, plateFor(seat));
  for (const { seat, worker } of seated) plates.set(seat.castId, plateFor(seat, worker.label));
  const mugs = new Set(seated.filter((s) => s.worker.empty).map((s) => s.seat.castId));

  /** The base tile states every slide starts from: the mugs, the tracker's alarm. */
  const base = (): Map<string, TileState> => {
    const m = new Map<string, TileState>();
    for (const id of mugs) m.set(id, { mug: true });
    return m;
  };
  const stage = (slideKey: string, tiles: Map<string, TileState>) => (
    <StageView
      slideKey={slideKey}
      plate={title}
      register={data.register}
      tiles={tiles}
      plates={plates}
    />
  );

  const chair = seatOf("chair");
  const queueSlide = (id: string): Slide => {
    const script = queueWorkScript(data) ?? queueScript(data);
    const tiles = base();
    tiles.set(chair.castId, {
      lit: true,
      bubble: script.lines,
      detail: data.tracker.ok
        ? [
            { label: T.walk, items: data.queue.walk ?? [] },
            { label: DECIDE, items: data.queue.decide ?? [] },
            { label: LOOK, items: data.queue.look ?? [] },
          ]
        : [],
    });
    if (!data.tracker.ok) tiles.set(seatOf("tracker").castId, { lit: true });
    if (data.queue.walk?.length) tiles.set(seatOf("walk").castId, { lit: true });
    if (data.queue.decide?.length) tiles.set(seatOf("decide").castId, { lit: true });
    if (data.queue.look?.length) tiles.set(seatOf("look").castId, { lit: true });
    return {
      id,
      title,
      content: stage(id, tiles),
      copy: <Copy castId={chair.castId} />,
      notes: notesOf(script.say),
    };
  };

  const chairSlide = (id: string, line: string, extra: string[] = []): Slide => {
    const lines = [`"${line}"`, ...extra];
    const tiles = base();
    tiles.set(chair.castId, { lit: true, bubble: lines });
    return {
      id,
      title: CHAIR_TITLE,
      content: stage(id, tiles),
      copy: <Copy castId={chair.castId} />,
      notes: notesOf([line, ...extra]),
    };
  };

  const grained = new Map((data.work?.workers ?? []).map((w) => [w.label, w]));
  // The dress: read when present, the prose (`work`) otherwise.
  const dressed = new Map((data.spoken?.workers ?? []).map((w) => [w.label, w.prose]));
  const workerSlide = (seat: Seat, worker: StandupWorker): Slide => {
    const script = workerScript(worker, grained.get(worker.label), dressed.get(worker.label));
    const tiles = base();
    tiles.set(seat.castId, {
      lit: true,
      mug: worker.empty,
      bubble: script.lines,
      detail: worker.empty
        ? []
        : [
            { label: T.yesterday, items: worker.yesterday },
            { label: T.today, items: worker.today },
            { label: T.blockers, items: worker.blockers },
          ],
    });
    const id = `${stem}-${worker.label}`;
    return {
      id,
      title: worker.name,
      content: stage(id, tiles),
      copy: <Copy castId={seat.castId} label={worker.label} />,
      notes: notesOf(script.say),
    };
  };

  // The chair's opening line, and what the room has to know before the tiles:
  // no worker routes in this Space (only when the tracker answered -- a
  // tracker that did not has already said so on the queue).
  const openExtra = data.tracker.ok && (data.workers ?? []).length === 0 ? [T.noWorkers] : [];
  const closeExtra = standing.length
    ? [`${STANDING}: ${standing.map((w) => w.name).join(", ")}.`]
    : [];

  const slides: Slide[] = [
    queueSlide(`${stem}-queue`),
    chairSlide(`${stem}-chair-open`, data.chair.open, openExtra),
    ...seated.map(({ seat, worker }) => workerSlide(seat, worker)),
    chairSlide(`${stem}-chair-close`, data.chair.close, closeExtra),
    queueSlide(`${stem}-queue-end`),
  ];

  return {
    id: STANDUP_DECK_ID,
    title,
    summary:
      "Today's standup, played on the Remote Standup's stage: the queue, the chair, one tile a worker.",
    audiobook: true,
    slides: () => slides,
  };
}
