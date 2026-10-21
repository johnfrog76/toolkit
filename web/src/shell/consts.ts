/**
 * The web half's reader for `consts.json` -- the package's contract file.
 *
 * `consts.json` lives at the PACKAGE root, one level above `web/`, and holds the
 * literals that cross a half boundary: the strings and patterns the CLI, the
 * agent and this app must agree on to the character. It is imported at BUILD
 * time (Vite inlines JSON), so there is no fetch, no runtime dependency on the
 * agent, and a typo is a type error rather than a blank card.
 *
 * It sits outside `web/`, so the import goes through the `@consts` alias --
 * declared in `vite.config.ts`, `tsconfig.json` (`paths`) and `jest.config.mjs`
 * (`moduleNameMapper`), all three -- rather than a `../../..` climb.
 *
 * WHAT DOES NOT BELONG HERE: a label, a tooltip, a route, anything only this
 * half ever types. Those stay in the module that owns them (AGENTS.md, "One
 * place for magic strings"). This file is for the handful of values that stop
 * being true the moment PowerShell or Python changes its copy.
 */

import consts from "@consts";

/** The derived state of a card. There is no status field -- these strings are it. */
export const STATUS = consts.status as {
  active: string;
  inProgress: string;
  codeReview: string;
  done: string;
};

/** Stamps the CLI writes into a card and this app reads back out of one. */
export const STAMPS = consts.stamps as {
  closed: string;
  created: string;
  billable: string;
  /** A person's In Progress and Code Review -- for a card with nothing checked in, or no pull request. */
  started: string;
  review: string;
  /** The line a send writes under `## Sent`: "Sent to <recipient>: <date>". */
  sent: string;
  /** A reminder's footer lines (Organize): when it is due, and where it came from. */
  due: string;
  source: string;
  ref: string;
  /** A card's picture and the other half of a before/after proof (docs/hub/cards.md, "A card's pictures"). */
  cover: string;
  before: string;
  /** What became of a note archived without a spec: `**Outcome:** shipped|dropped` (design lifecycle 4.3). */
  outcome: string;
};

/**
 * The Organize add-on's reminders: the three derived buckets, in display order,
 * and the snooze words -Snooze takes. The agent works the bucket out; this half
 * filters and labels by it.
 */
export const REMINDERS = consts.reminders as {
  buckets: Array<"overdue" | "today" | "upcoming">;
  snooze: Array<"1h" | "tomorrow" | "nextweek">;
};

/**
 * The three halves a test run covers, in the order `{cliPrefix}Test` runs
 * them, and what a summary entry with no `half` is read as. The Health card
 * draws a machine's halves in this order.
 */
export const TESTS = consts.tests as {
  halves: Array<"agent" | "cli" | "web">;
  legacyHalf: "cli";
};

/** Card lines whose exact text is a state gate or a section anchor. */
export const TOKENS = consts.tokens as {
  prUrl: string;
  prReviewHeading: string;
  previousRound: string;
  /** The line a card carries naming its design, and the corpus's hand-written form. */
  design: string;
  spec: string;
};

/** The two folders a card lives in, and the Space's folder for its pictures. */
export const FOLDERS = consts.folders as { current: string; archive: string; assets: string };

/**
 * A card's pictures (docs/hub/cards.md, "A card's pictures"): the image types the
 * CLI's Cover accepts and the agent serves, and the largest it copies. The web
 * reads a cover as the URL the agent serves; it attaches none in this cut.
 */
export const ASSETS = consts.assets as { coverExtensions: string[]; coverMaxBytes: number };

/**
 * Which feature flags are the ORG's rather than the engineer's. `/env` serves the
 * merged view already; this is for anything that has to tell the two scopes apart
 * on the client, so the list is the same one the CLI and the agent read.
 */
export const FEATURES = consts.features as { spaceScoped: string[] };

/**
 * The Docs tab's two roots (D-S12): the README at the repo root and the
 * folder whose markdown sits under it. The agent's /api/docs routes refuse any
 * other path; the reading room's link resolver opens exactly these in the room
 * and sends every other relative link to github.com -- the same rule.
 */
export const DOCS = consts.docs as {
  readme: string;
  root: string;
  segment: string;
  /** The public landing page's deployed address (GitHub Pages) -- a different
   *  thing with a similar name: not a Docs-tab file, the page Home's foot links. */
  landingUrl: string;
};

/**
 * Whether a GitHub Space's repository is public: the three words the
 * agent serves a Space's visibility as (GET /api/visibility), and the one line
 * a write to a public repository carries. The CLI prints the same words.
 */
export const VISIBILITY = consts.visibility as {
  public: string;
  private: string;
  unknown: string;
  publicLine: string;
};

/**
 * The Studio's design notes (S2b): what a note's file name may be -- the agent's
 * /api/studio/design/{name} refuses any other, and the reading room opens exactly
 * these -- the `> GitHub:` line that names a note's thread, which the CLI
 * writes on Promote and the agent reads back, and the label Promote applies.
 * The Prompts card: the agent's read it asks.
 */
export const STUDIO = consts.studio as {
  noteName: string;
  threadLine: string;
  threadRegex: string;
  promoteLabel: string;
  promptsRoute: string;
};

/**
 * The design lifecycle's identity (docs/hub/design.md, "The file"):
 * the frontmatter key a design's id lives under, the id's shape (a UUID v4,
 * lowercase, hyphenated -- compile it with `toRegExp`), the four state names in
 * road order (the Design tab's groups, L2), the two outcomes, and the `> Docs:`
 * line a Complete spec carries (its regex: group 1 the path).
 */
export const DESIGN = consts.design as {
  idKey: string;
  idRegex: string;
  states: string[];
  outcomes: string[];
  docsLine: string;
  docsRegex: string;
  /** A card's `> Design:` / `> Spec:` line: group 1 the
   *  word, 2 the link's text, 3 its target, 4 the id or a person's words. The
   *  agent serves it parsed as the card's `design`; this half states it. */
  cardLineRegex: string;
};

/**
 * Solitaire Agile's Ritual Engine (docs/modules/solitaire-agile.md, "The routes"):
 * the standup route the agent serves, and every fixed word of the rendering.
 * The CLI's Standup and the agent's route both render the text; this half
 * shows the agent's `text` verbatim and types none of these words itself.
 */
export const RITUALS = consts.rituals as {
  route: string;
  /** Triage's read: the open issues by milestone. */
  triageRoute: string;
  ceremoniesFile: string;
  vocabularyFile: string;
  workerLabelPrefix: string;
  walkLabel: string;
  labelWidth: number;
  /** The reminder to attend: POST it when the standup is shown. */
  attendRoute: string;
  /** GET: the standup reminder as it stands, for the settings row. */
  remindRoute: string;
  remindSource: string;
  remindTitle: string;
  /** The cadence `Standup -Remind` writes when no days are given. */
  remindDays: string;
  /** The day names a cadence is written in, Monday first. */
  weekdays: string[];
  /** The three registers of detail (D-TA20): detail, work, brief. */
  grains: string[];
  /** A count as the voice says it, by index (the work grain's phrases). */
  numberWords: string[];
  /** The work grain's grouping patterns, read by the CLI and the agent. */
  workHeadRegex: string;
  workThreadRegex: string;
  workDesignRegex: string;
  workSmallWordRegex: string;
  /** The also-ons fold (D-SA9): the most groups a folded sentence names. */
  proseFoldNames: number;
  /** The dress guard: its checks in order, and the patterns it reads a
   *  model's sentence with. The agent and the CLI run it; the web reads `spoken`. */
  dressGuards: string[];
  dressRefRegex: string;
  dressNumberRegex: string;
  dressNameRegex: string;
  dressPronounRegex: string;
  /** What moved: a slot item's motion -- closed, started, inProgress --
   *  and the card bullet whose hash it counts. The agent and the CLI read them. */
  motions: string[];
  text: {
    title: string;
    dateFormat: string;
    queueHeading: string;
    queueEmpty: string;
    walk: string;
    tracker: string;
    yesterday: string;
    today: string;
    blockers: string;
    mug: string;
    yesterdayEmpty: string;
    todayEmpty: string;
    blockersEmpty: string;
    blockerSuffix: string;
    noWorkers: string;
    briefWalkOne: string;
    briefWalkMany: string;
    briefDecideOne: string;
    briefDecideMany: string;
    briefLookOne: string;
    briefLookMany: string;
    briefAllPc: string;
    briefWhoPc: string;
    briefWhoYou: string;
    briefClosed: string;
    briefClosedNone: string;
    briefOpen: string;
    briefOpenNone: string;
    briefInFlight: string;
    briefBlocker: string;
    briefBlockers: string;
    briefWorkerNone: string;
    briefInFlightUnknown: string;
    briefNext: string;
    briefNextNone: string;
    /** The work grain's phrases: a slot's first group, then the rest. */
    workYesterday: string;
    workToday: string;
    workBlockers: string;
    workWalk: string;
    workGroup: string;
    /** The prose: the work grain spoken as standup language -- a lead
     *  (prose<Slot>, prose<Slot>Also) and a body (proseBare, prose<Slot>One or
     *  proseOne, prose<Slot>Many or proseMany) joined by proseSentence. */
    proseSentence: string;
    proseYesterday: string;
    proseYesterdayAlso: string;
    proseToday: string;
    proseTodayAlso: string;
    proseBlockers: string;
    proseBlockersAlso: string;
    proseBlockersNone: string;
    proseWalk: string;
    proseWalkAlso: string;
    proseDecide: string;
    proseDecideAlso: string;
    proseLook: string;
    proseLookAlso: string;
    proseOne: string;
    proseTodayOne: string;
    proseMany: string;
    proseBare: string;
    proseItem: string;
    proseRefSeparator: string;
    /** The also-ons fold (D-SA9): the groups after today's first, one sentence. */
    proseTodayFold: string;
    proseTodayFoldCount: string;
    proseNameSeparator: string;
    proseNameLast: string;
    /** What moved: a detail line's motion after its ref, and the counts
     *  line that opens the brief. Already rendered into `text` and `brief`. */
    itemMotion: string;
    motionStarted: string;
    commitOne: string;
    commitMany: string;
    countsTotal: string;
    countsNone: string;
    countsSeparator: string;
    countsClosed: string;
    countsStarted: string;
    countsInProgress: string;
  };
};

/**
 * Team Agile's hand-off block (docs/modules/solitaire-agile.md, "StartWork: the
 * hand-off block"): the head line and the three section headings the CLI's
 * `StartWork` types. The copy box shows the block verbatim and finds its title
 * by the head line's shape (D-AR5); it builds none of it.
 */
export const STARTWORK = consts.startWork as {
  text: {
    head: string;
    howWeWork: string;
    work: string;
    prompt: string;
  };
};

/** A card's derived state, as a union built from the contract's own values. */
export type PromptStatus = string;

/**
 * Compile one of the contract's patterns for JavaScript.
 *
 * The patterns travel as strings so all three halves can hold the same one, and
 * they are written in the subset .NET, Python and JS agree on -- with one
 * exception that cannot be: a LEADING INLINE FLAG. `(?m)` is how .NET and
 * Python spell multiline inside a pattern; JS has no inline flag syntax at all
 * and `new RegExp("(?m)...")` throws `Invalid group`. So the flag is lifted out
 * of the pattern and passed as a real flag, which is the same expression by
 * another spelling.
 *
 * Only the flags the three agree on are lifted (`m`, `i`, `s`). Anything else
 * left in a leading group is a pattern that has stopped being portable, and
 * throwing here is how that is noticed at build time rather than in a card.
 */
export function toRegExp(pattern: string, extraFlags = ""): RegExp {
  let body = pattern;
  let flags = extraFlags;
  const lead = /^\(\?([a-z]+)\)/.exec(body);
  if (lead) {
    for (const f of lead[1]) {
      if (f !== "m" && f !== "i" && f !== "s") {
        throw new Error(
          `consts.json: inline flag "(?${lead[1]})" is not portable to JavaScript -- ` +
            `only m, i and s are. Keep such a pattern in the half that needs it.`,
        );
      }
      if (!flags.includes(f)) flags += f;
    }
    body = body.slice(lead[0].length);
  }
  return new RegExp(body, flags);
}

/** The contract's patterns, compiled once for this bundle. */
export const RE = {
  prUrlLine: toRegExp(consts.regex.prUrlLine),
  prReviewHeading: toRegExp(consts.regex.prReviewHeading),
  commitBullet: toRegExp(consts.regex.commitBullet),
  startedLine: toRegExp(consts.regex.startedLine),
  reviewLine: toRegExp(consts.regex.reviewLine),
  /** A meeting record's name: an optional series, then the date. Group 1 the series, group 2 the date. */
  sessionName: toRegExp(consts.regex.sessionName),
  /** A WHOLE string that is a card id: a work item number, or the four-character
   *  id of a card with no work item. Anchored here; the contract's shape is not. */
  cardId: toRegExp(`^(?:${consts.regex.cardId})$`),
};
