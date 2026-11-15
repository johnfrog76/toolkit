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
import { itemFacts, itemKey, itemRef, itemSpoken } from "../itemRef";
import {
  CAST,
  CastScene,
  castById,
  SPEAKER_COLOR_VAR,
  STAGE_GRID_CLASS,
  SpeechBubble,
  STAGE_CLASS,
  StandupKeyframes,
  ThoughtBubble,
  ZoomTile,
  mono,
  pf,
} from "./cast";
import type { TileLook } from "./cast";
import { EmptyDesk } from "./EmptyDesk";
import type { MugLook } from "./EmptyDesk";
import { CHAIR_CAST_ID, CHAIR_PLATE, EMPTY_DESK_PLATE, dealRoom, memberPlate } from "./seats";
import type { Seated } from "./seats";

// ── The standup, played (docs/modules/solitaire-agile.md, "The played view") ─────────
//
// The agent's standup response turned into a Deck the deck engine plays
// unchanged: the Remote Standup's stage (./cast.tsx), the engine's script.
// The room is nine windows (./seats.ts): the chair, the present members by
// position, and an empty desk in every other window. The round goes:
//
//   the BOARD   -- the chair reads what is waiting on you, or the tracker's reason
//   the CHAIR   -- the phrasebook's noun-less opening line
//   for each present member, in seat order:
//     the CALL  -- the chair says the member's name
//     the TURN  -- the member's tile speaks its turn, in the frame
//   the CHAIR'S STATUS -- its own turn, last, in the same frame
//   the CLOSE   -- the phrasebook's closing line
//
// An empty desk has no slide: the round passes it in silence. Every face
// drawn speaks at least once. Every slide is the same nine windows (D-TA17),
// the ritual's plate across the top and the register on it (D-TA13), and its
// Say lines are the response's sentences, so the engine's narration and its
// duration estimate work as they do for any deck. The deck is an AUDIOBOOK
// (decks/types.ts): played in Audiobook mode, the browser's voice.
//
// Every fixed word of the standup is the contract's (consts.json
// rituals.text, through RITUALS); the words below are this view's own --
// the plates (./seats.ts), the call, and two queue-kind labels the text has
// none for yet.
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
/** The chair calling a member: the member's name and a full stop. The stage's
 *  own line -- the CLI's round names each member at the head of its line instead. */
export const callLine = (name: string) => `${name}.`;

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

/** `#<n> Verify the Studio tab`, or `2HNU Verify the Studio tab` for a card -- how a bubble shows an item. */
const shown = (i: RitualItem) => `${itemRef(i)} ${i.title}`;
/** `issue 104, Verify the Studio tab`, or `card 2HNU, ...` -- how the voice reads one. */
const spoken = itemSpoken;

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

/** An idle member from an agent whose prose carries no turn for it: its made-up
 *  items as they are (the pair, else the one sentence an older agent sent),
 *  or, with none of those either, its three empty slots. Never a silent face. */
function idleScript(w: StandupWorker): Script | null {
  const said = (w.status?.length ? w.status : [w.excuse]).filter(Boolean);
  return said.length ? { lines: [...said], say: [...said] } : null;
}

/** A worker at the work grain, spoken as prose: its turn, one bubble
 *  line and one Say line a sentence -- the dressed ones (`spoken`) when a model
 *  answered, the prose otherwise. An idle worker's turn is its two made-up
 *  items in the same frame. */
function workerWorkScript(w: StandupWorker, ww: WorkWorker, dressed?: string[]): Script | null {
  const said = dressed ?? ww.prose ?? [];
  if (said.length === 0) return w.empty ? idleScript(w) : null;
  return { lines: [...said], say: [...said] };
}

function workerScript(w: StandupWorker, ww?: WorkWorker, dressed?: string[]): Script {
  const prose = ww ? workerWorkScript(w, ww, dressed) : w.empty ? idleScript(w) : null;
  if (prose) return prose;
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
  /** Lit: the window speaks on this slide (with a bubble) or is called (without). */
  lit?: boolean;
  /** Someone is in this window today: a face, its signal light on. */
  present?: boolean;
  /** The member the chair has just called: in colour, unframed, about to answer. */
  called?: boolean;
  /** Nobody is in this window: the empty desk, with this mug. Never lit, never a bubble. */
  desk?: MugLook;
  /** The bubble's lines, on a lit tile. */
  bubble?: string[];
  /** The detail behind the sentence, for the thought bubble; absent when there is none. */
  detail?: DetailSlot[];
}

/**
 * Where each scene's head is, as the top of the head in the tile: the
 * nine scenes are drawn differently (the minimalist sits low, the ultrawide's
 * head is near the top), so one fixed spot would hang the bubble over a
 * different part of each. The bubble's tail points here.
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

/** A window with nobody in it: the ghost look, the signal light off, and nothing to say. */
function DeskTile({ id, label, look }: { id: string; label: string; look: MugLook }) {
  const tint = castById(id).tint;
  return (
    <div
      data-testid={`tile-${id}`}
      data-lit="false"
      data-look="ghost"
      data-desk={look}
      style={{ position: "relative", minHeight: 0 }}
    >
      <ZoomTile tint={tint} label={label} look="ghost">
        <EmptyDesk look={look} tint={tint} />
      </ZoomTile>
    </div>
  );
}

/** A tile and what it says: the speech bubble while it speaks, the thought bubble where there is detail. */
function Tile({ id, label, t }: { id: string; label: string; t: TileState }) {
  const tint = castById(id).tint;
  // The anchor the engine points the speech bubble at: a small element
  // over the speaker's face, not the tile's box. The stage is the boundary the
  // bubble is kept inside.
  const [anchor, setAnchor] = useState<HTMLElement | null>(null);
  const boundary = anchor?.closest<HTMLElement>(`.${STAGE_GRID_CLASS}`) ?? null;
  const detail = (t.detail ?? []).filter((s) => s.items.length > 0);
  // Speaking is "its bubble is open"; named is a face that is there without one.
  const speaking = !!t.lit && !!t.bubble && t.bubble.length > 0;
  const look: TileLook = speaking
    ? "speaking"
    : t.called
      ? "called"
      : t.lit || t.present
        ? "named"
        : "ghost";
  return (
    <div
      data-testid={`tile-${id}`}
      data-lit={t.lit ? "true" : "false"}
      data-look={look}
      data-speaking={speaking ? "true" : undefined}
      style={{ position: "relative", minHeight: 0 }}
    >
      <ZoomTile tint={tint} label={label} look={look}>
        <CastScene id={id} parked />
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
          ...(HEADS[id] ?? { left: "50%", top: "40%" }),
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
                    <li key={itemKey(i)}>
                      <IssuePopover facts={itemFacts(i)} /> {i.title}
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
        className={STAGE_GRID_CLASS}
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
          const t = tiles.get(c.id) ?? {};
          const label = plates.get(c.id) ?? c.label;
          return t.desk ? (
            <DeskTile key={`${slideKey}-${c.id}`} id={c.id} label={label} look={t.desk} />
          ) : (
            <Tile key={`${slideKey}-${c.id}`} id={c.id} label={label} t={t} />
          );
        })}
      </div>
    </div>
  );
}

// ── The copy panel (the engine's right-hand column) ─────────────────────────────────
// Who is speaking, not what they said: the bubble shows the sentence and
// the voice reads it, so a third copy beside the stage was noise. The panel is
// the speaker's character: the title and the persona with the worker's label
// beside it (the one real noun, the same word the issue carries). No motto: a
// made-up line in a character's voice beside a real status would read as a claim
// of work the tracker did not say.

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
          margin: 0,
          fontSize: "1.9rem",
          fontWeight: 800,
          lineHeight: 1.25,
          color: pf.text,
        }}
      >
        {label ? `${member.label} (${label})` : member.label}
      </h2>
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
 * slides with the same ids (`standup-<date>-<part>`), so a rebuild after a
 * refetch keeps the player where it was.
 */
export function buildStandupDeck(data: StandupResponse): Deck {
  const title = standupTitle(data);
  const stem = `standup-${standupDate(data.asOf)}`;
  const { members, desks } = dealRoom(data);

  // Every window's plate for this standup: the chair's, each member's persona
  // with its label, and the desks'.
  const plates = new Map<string, string>([[CHAIR_CAST_ID, CHAIR_PLATE]]);
  for (const m of members) plates.set(m.castId, memberPlate(m, m.worker.label));
  for (const d of desks) plates.set(d.castId, EMPTY_DESK_PLATE);

  /** The tile states every slide starts from: the faces that are there, and the desks. */
  const base = (): Map<string, TileState> => {
    const m = new Map<string, TileState>([[CHAIR_CAST_ID, { present: true }]]);
    for (const s of members) m.set(s.castId, { present: true });
    for (const d of desks) m.set(d.castId, { desk: d.look });
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

  /** The queue's items behind the chair's sentences, for its thought bubble. */
  const queueDetail = (): DetailSlot[] =>
    data.tracker.ok
      ? [
          { label: T.walk, items: data.queue.walk ?? [] },
          { label: DECIDE, items: data.queue.decide ?? [] },
          { label: LOOK, items: data.queue.look ?? [] },
        ]
      : [];

  /** One slide where the chair speaks; `called` is the member it names, in colour, listening. */
  const chairSays = (
    id: string,
    slideTitle: string | undefined,
    script: Script,
    detail: DetailSlot[] = [],
    called?: string,
  ): Slide => {
    const tiles = base();
    tiles.set(CHAIR_CAST_ID, { present: true, lit: true, bubble: script.lines, detail });
    if (called) tiles.set(called, { present: true, lit: true, called: true });
    return {
      id,
      title: slideTitle,
      content: stage(id, tiles),
      copy: <Copy castId={CHAIR_CAST_ID} />,
      notes: notesOf(script.say),
    };
  };

  // The board: what is waiting on you, or -- the tracker's alarm -- why it could not be read.
  const boardSlide = () =>
    chairSays(`${stem}-queue`, title, queueWorkScript(data) ?? queueScript(data), queueDetail());

  // A phrasebook line, quoted on the bubble as the text quotes it.
  const phraseSlide = (id: string, line: string, extra: string[] = []) =>
    chairSays(id, CHAIR_TITLE, { lines: [`"${line}"`, ...extra], say: [line, ...extra] });

  // The chair's own status, last: its turn in the frame. From an agent that
  // predates it, the board again, as the stage closed before; with no tracker
  // the turn is empty and the chair has none to give (the text prints none).
  const chairStatusSlide = (): Slide | null => {
    const own = data.work?.chairProse;
    if (own && own.length === 0) return null;
    const script = own
      ? { lines: [...own], say: [...own] }
      : (queueWorkScript(data) ?? queueScript(data));
    return chairSays(`${stem}-chair-status`, CHAIR_TITLE, script, queueDetail());
  };

  const grained = new Map((data.work?.workers ?? []).map((w) => [w.label, w]));
  // The dress: read when present, the prose (`work`) otherwise.
  const dressed = new Map((data.spoken?.workers ?? []).map((w) => [w.label, w.prose]));

  // The chair calls the member by name; the member's window is in colour, listening.
  // No title: the narrator reads a slide's title before its lines, and the call is
  // heard as the chair saying the name and nothing else.
  const callSlide = ({ castId, worker }: Seated): Slide => {
    const line = callLine(worker.name || worker.label);
    return chairSays(
      `${stem}-call-${worker.label}`,
      undefined,
      { lines: [line], say: [line] },
      [],
      castId,
    );
  };

  const turnSlide = ({ castId, worker }: Seated): Slide => {
    const script = workerScript(worker, grained.get(worker.label), dressed.get(worker.label));
    const tiles = base();
    tiles.set(castId, {
      present: true,
      lit: true,
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
    // No title either: the chair has just said the name, so the turn is not announced again.
    return {
      id,
      content: stage(id, tiles),
      copy: <Copy castId={castId} label={worker.label} />,
      notes: notesOf(script.say),
    };
  };

  // The chair's opening line, and what the room has to know before the round:
  // no worker routes in this Space (only when the tracker answered -- a
  // tracker that did not has already said so on the board).
  const openExtra = data.tracker.ok && (data.workers ?? []).length === 0 ? [T.noWorkers] : [];
  const status = chairStatusSlide();

  const slides: Slide[] = [
    boardSlide(),
    phraseSlide(`${stem}-chair-open`, data.chair.open, openExtra),
    ...members.flatMap((m) => [callSlide(m), turnSlide(m)]),
    ...(status ? [status] : []),
    phraseSlide(`${stem}-chair-close`, data.chair.close),
  ];

  return {
    id: STANDUP_DECK_ID,
    title,
    summary:
      "Today's standup, played on the Remote Standup's stage: the board, the chair calling each member and their turns, the chair's own status, nine windows with an empty desk wherever nobody sits.",
    audiobook: true,
    slides: () => slides,
  };
}
