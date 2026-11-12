import fs from "node:fs";
import path from "node:path";
import { panelKindFacts, panelKindFactsOf } from "./panelKindFacts";

/**
 * Every module's panels and pages, read for their kind.
 *
 * A file under src/modules/ that draws a panel or a page (it fills ListPanel,
 * or draws PanelFrame or a Fluent Card) and draws rows -- a `.map()` turning
 * entries into elements -- is a ListPanel: its rows are card items of one
 * height, paged in a pinned foot. One that draws rows without ListPanel fails
 * here, unless it is on one of three lists below, each held exact:
 *
 *   FIXED_ROWS      a fixed set of status rows, figures or chart series, which
 *                   the status, stat and chart kinds will draw;
 *   NOT_A_LIST      a page, a form or a scene whose rows are not records;
 *   NOT_YET_MOVED   a list of records that has not moved onto ListPanel yet.
 *
 * systemPanels.test.ts holds the same rule over the System page by the panels
 * its registration returns; this holds it over every module by file, so a new
 * list cannot stay outside ListPanel quietly, on any page.
 */

const MODULES = path.join(__dirname, "..", "..", "modules");

/** A fixed set of rows that are not records: why each is right. */
const FIXED_ROWS: Record<string, string> = {
  "ado/BurnCard.tsx":
    "the week's figures: a table of a few models and their notes, the stat kind's",
  "ado/EngagementSummary.tsx": "the engagement's figures: a fixed row of stat tiles",
  "ado/EnvCard.tsx": "the machine's checks: a fixed set of status rows, the status kind's",
  "ado/FacePicker.tsx": "the board's faces: a fixed set of tiles to choose from, a scene",
  "ado/IssueReportCard.tsx": "the tracker's figures: stat tiles and a short table of milestones",
  "ado/ModulesCard.tsx": "the add-ons: one fixed status row each, the status kind's",
  "ado/SprintVelocity.tsx": "charts: the rows are a chart's series and its legend",
  "ado/WorkBreakdown.tsx": "a chart: the rows are its series and its legend",
  "growth/SkillsSnapshot.tsx": "the skill tags by group: a legend, not records",
};

/** A page, a form or a scene: why its rows are not a list of records. */
const NOT_A_LIST: Record<string, string> = {
  "ado/Billing.tsx": "Daily: a week of days, each a block of text to copy -- a document",
  "ado/ConnectPage.tsx": "the Connect wizard: its steps and their choices",
  "ado/CreatePrompt.tsx": "the Actions forms: a form's options",
  "ado/DocsLanding.tsx": "the Docs reader's landing page: the documents' paths as a contents list",
  "ado/IssueDetailPage.tsx": "a detail page: one issue, its labels as badges",
  "ado/PRCommentsDetail.tsx": "a conversation: each thread is read whole and answered in place",
  "ado/ReviewPage.tsx": "a detail page: one review, its pending files read whole",
  "deck/DeckPage.tsx": "a detail page: one deck, its tags as badges",
  "lounge/TicTacToe.tsx": "a game: the board's cells",
  "lounge/WordRing.tsx": "a game: the ring's letters and the words kept",
  "solitaireAgile/StandupPage.tsx": "the Standup page: the grain tabs and the brief's lines",
  "solitaireAgile/TriagePage.tsx": "the Triage page: one issue at a time, and the choices for it",
};

/** Lists of records still drawn by hand, and what each waits on. */
const NOT_YET_MOVED: Record<string, string> = {
  "ado/Dashboard.tsx": "Home's Build: pipeline runs, a line list",
  "ado/DeploysCard.tsx": "Home's Deploys: a line list",
  "ado/DesignSearchInside.tsx": "Home's Designs and specs: the matches inside, with the list",
  "ado/MilestonesCard.tsx": "Home's Milestones: waits on one shape for milestones",
  "ado/MyPRs.tsx": "Home's My PRs",
  "ado/PRCommentsList.tsx": "Home's PR Comments",
  "solitaireAgile/MilestonesPage.tsx":
    "Team Agile's Releases: waits on the tab's timeline and a named progress bar in the card item",
};

function panelFiles(dir: string, out: string[] = []): string[] {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) panelFiles(full, out);
    else if (/\.tsx$/.test(entry.name) && !/\.test\.tsx$/.test(entry.name)) out.push(full);
  }
  return out;
}

const rel = (full: string) => path.relative(MODULES, full).split(path.sep).join("/");
const facts = new Map(panelFiles(MODULES).map((full) => [rel(full), panelKindFacts(full)]));
const named = { ...FIXED_ROWS, ...NOT_A_LIST, ...NOT_YET_MOVED };

describe("every module's panels and pages", () => {
  it("reads every module, and finds the list panels on their kind", () => {
    const modules = new Set([...facts.keys()].map((file) => file.split("/")[0]));
    expect([...modules].sort()).toEqual(
      fs
        .readdirSync(MODULES, { withFileTypes: true })
        .filter((e) => e.isDirectory())
        .map((e) => e.name)
        .sort(),
    );
    const onKind = [...facts].filter(([, f]) => f.listPanel).map(([file]) => file);
    expect(onKind.sort()).toEqual([
      "ado/MyWork.tsx",
      "ado/PromptStatus.tsx",
      "ado/TestHealth.tsx",
      "ado/ToolkitLog.tsx",
      "communication/OneOnOne.tsx",
      "deck/DeckPickerCard.tsx",
      "growth/Goals.tsx",
      "growth/ReviewArchive.tsx",
      "organize/RemindersCard.tsx",
      "studio/DesignsCard.tsx",
      "studio/FoyerCard.tsx",
      "studio/PromptsCard.tsx",
    ]);
  });

  it("draws every list in a ListPanel, but for the files named with a reason", () => {
    const offKind = [...facts]
      .filter(([file, f]) => f.framed && f.mapsToJsx && !f.listPanel && !(file in named))
      .map(([file]) => file);
    expect(offKind).toEqual([]);
  });

  it("names no file twice, none that is a ListPanel, and none that draws no rows", () => {
    const names = [
      ...Object.keys(FIXED_ROWS),
      ...Object.keys(NOT_A_LIST),
      ...Object.keys(NOT_YET_MOVED),
    ];
    expect(new Set(names).size).toBe(names.length);
    for (const [file, reason] of Object.entries(named)) {
      const f = facts.get(file);
      expect({ file, known: f !== undefined }).toEqual({ file, known: true });
      expect({ file, framed: f!.framed, listPanel: f!.listPanel, mapsToJsx: f!.mapsToJsx }).toEqual(
        { file, framed: true, listPanel: false, mapsToJsx: true },
      );
      expect(reason.length).toBeGreaterThan(10);
    }
  });

  it("the add-on modules whose lists moved have none left to move", () => {
    const left = Object.keys(NOT_YET_MOVED).filter((file) =>
      /^(growth|organize|communication|deck|studio)\//.test(file),
    );
    expect(left).toEqual([]);
  });
});

describe("the reader has teeth", () => {
  const read = (body: string) =>
    panelKindFactsOf("Thing.tsx", `export const Thing = () => (${body});`);

  it("a frame that maps entries to elements is a list off its kind", () => {
    expect(read("<PanelFrame>{items.map((i) => <Row key={i.id} />)}</PanelFrame>")).toEqual({
      framed: true,
      listPanel: false,
      mapsToJsx: true,
    });
  });

  it("a ListPanel fed data is on its kind, and a map to data draws nothing", () => {
    expect(read("<ListPanel items={items.map((i) => i.id)} />")).toEqual({
      framed: false,
      listPanel: true,
      mapsToJsx: false,
    });
  });

  it("a Fluent Card around mapped rows is read as a panel too", () => {
    expect(read("<Card>{days.map((d) => <Day key={d.date} />)}</Card>").framed).toBe(true);
  });
});
