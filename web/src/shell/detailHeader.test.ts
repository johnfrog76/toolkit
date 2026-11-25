/**
 * The rule behind "every record page shares one header": a page that shows ONE
 * record draws its header with `DetailHeader` (shared/DetailHeader.tsx) -- back,
 * title, meta, the File line, the actions in the house order -- and never builds
 * one by hand. Read from the source, as lazyModules.test.ts reads the descriptors,
 * so a new page cannot drift quietly.
 *
 * A page that owns an h1 of its own is either a record page (and uses the
 * component) or is named below with the reason it is not one.
 */
import fs from "node:fs";
import path from "node:path";

const MODULES = path.join(__dirname, "..", "modules");

/** Not a record: a form, a ledger, or a ritual view. Each with its reason. */
const NOT_A_RECORD: Record<string, string> = {
  "ado/ConnectPage.tsx": "a connect form; it has no record to point at",
  "ado/Billing.tsx": "the billing ledger, a panel of figures",
  "solitaireAgile/StandupPage.tsx": "today's round, derived; not a file",
  "solitaireAgile/TriagePage.tsx": "the tracker's queue, a list",
  "solitaireAgile/OrgPage.tsx": "the org's tree, a view over many seats",
  "solitaireAgile/MilestonesPage.tsx": "the releases, a list",
  "ado/DocsLanding.tsx":
    "the Docs tab, a landing page: its title is the page's h1, with the README under it",
  "deck/engine/PresenterNotes.tsx":
    "the presenter's notes window, part of the player; not a page of a record",
};

/** Panels and landing pages that fill a PanelFrame's headerLeft with a panel's own title. */
const CARD = "a card or list panel's own title, or a landing page; not one record";
const PANEL_HEADERS: Record<string, string> = Object.fromEntries(
  [
    "ado/ModulesCard.tsx",
    "ado/DocsLanding.tsx",
    "ado/CreatePrompt.tsx",
    "ado/Dashboard.tsx",
    "ado/ConnectAdoCard.tsx",
    "ado/FacePicker.tsx",
    "ado/MilestonesCard.tsx",
    "ado/PRCommentsList.tsx",
    "ado/EngagementSummary.tsx",
    "ado/BurnCard.tsx",
    "ado/WorkBreakdown.tsx",
    "ado/IssueReportCard.tsx",
    "ado/MyPRs.tsx",
    "ado/SprintVelocity.tsx",
    "ado/EnvCard.tsx",
    "ado/DeploysCard.tsx",
    "ado/DesignList.tsx",
    "lounge/WordRing.tsx",
    "lounge/TicTacToe.tsx",
    "lounge/GoBoard.tsx",
    "growth/SkillsSnapshot.tsx",
  ].map((f) => [f, CARD]),
);

/** Every record page, so removing the component from one is caught too. */
const RECORD_PAGES = [
  "ado/DocsDocPage.tsx",
  "ado/DesignDocPage.tsx",
  "ado/IssueDetailPage.tsx",
  "ado/PromptDetailPage.tsx",
  "ado/ReviewPage.tsx",
  "ado/PRCommentsDetail.tsx",
  "communication/ManagerDetailPage.tsx",
  "communication/ManagerSessionPage.tsx",
  "growth/GoalDetailPage.tsx",
  "growth/SkillsPage.tsx",
  "organize/ReferencePage.tsx",
  "deck/DeckPage.tsx",
  "studio/DesignNotePage.tsx",
  "studio/PromptPage.tsx",
];

function walk(dir: string, rel: string, out: { file: string; text: string }[]) {
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    if (fs.statSync(full).isDirectory()) {
      walk(full, `${rel}${name}/`, out);
    } else if (/\.tsx$/.test(name) && !/\.test\.tsx$/.test(name)) {
      out.push({ file: `${rel}${name}`, text: fs.readFileSync(full, "utf8") });
    }
  }
}

function sources(): { file: string; text: string }[] {
  const out: { file: string; text: string }[] = [];
  walk(MODULES, "", out);
  return out;
}

const usesDetailHeader = (text: string) =>
  /^import\s[^;]*\bDetailHeader\b[^;]*from\s+"\.\.\/\.\.\/shared\/DetailHeader"/m.test(text);
/** An h1 of a file's own, in any of the three shapes JSX has for one. */
const ownsH1 = (text: string) => /<h1[\s>]|\bas=(?:"h1"|\{\s*["'`]h1["'`]\s*\})/.test(text);
/** A PanelFrame header filled by hand. */
const fillsHeaderLeft = (text: string) => /\bheaderLeft=/.test(text);
const buildsOwnBackButton = (text: string) =>
  /^import\s[^;]*\bBackButton\b[^;]*from\s+"\.\.\/\.\.\/shared\/BackButton"/m.test(text);

describe("every record page draws its header with DetailHeader", () => {
  const all = sources();

  it.each(RECORD_PAGES)("%s uses DetailHeader", (file) => {
    const hit = all.find((s) => s.file === file);
    expect(hit).toBeDefined();
    expect(usesDetailHeader(hit!.text)).toBe(true);
  });

  it("no module page owns an h1 of its own unless it is named as not a record", () => {
    const offenders = all
      .filter((s) => ownsH1(s.text) && !usesDetailHeader(s.text) && !(s.file in NOT_A_RECORD))
      .map((s) => s.file);
    expect(offenders).toEqual([]);
  });

  it("no module file fills a PanelFrame's headerLeft without DetailHeader unless it is named", () => {
    const offenders = all
      .filter(
        (s) =>
          fillsHeaderLeft(s.text) &&
          !usesDetailHeader(s.text) &&
          !(s.file in NOT_A_RECORD) &&
          !(s.file in PANEL_HEADERS),
      )
      .map((s) => s.file);
    expect(offenders).toEqual([]);
  });

  it("every panel named as not a record still fills headerLeft by hand", () => {
    for (const file of Object.keys(PANEL_HEADERS)) {
      const hit = all.find((s) => s.file === file);
      expect(hit).toBeDefined();
      expect(fillsHeaderLeft(hit!.text)).toBe(true);
      expect(usesDetailHeader(hit!.text)).toBe(false);
    }
  });

  it("no record page wires its own back button", () => {
    const offenders = all
      .filter((s) => buildsOwnBackButton(s.text) && !(s.file in NOT_A_RECORD))
      .map((s) => s.file);
    expect(offenders).toEqual([]);
  });

  it("the list of pages that are not records names only files that exist and still own an h1", () => {
    for (const file of Object.keys(NOT_A_RECORD)) {
      const hit = all.find((s) => s.file === file);
      expect(hit).toBeDefined();
      expect(ownsH1(hit!.text)).toBe(true);
    }
  });

  it("the rule reads what it thinks it reads", () => {
    expect(usesDetailHeader('import { DetailHeader } from "../../shared/DetailHeader";\n')).toBe(
      true,
    );
    expect(usesDetailHeader("// DetailHeader\n")).toBe(false);
    expect(usesDetailHeader('import { DetailHeader } from "../../shared/DetailHeader";')).toBe(
      true,
    );
  });

  it("the h1 matcher catches each shape, and nothing else", () => {
    expect(ownsH1('<Subtitle2 as="h1">x</Subtitle2>')).toBe(true);
    expect(ownsH1("<Subtitle2 as={'h1'}>x</Subtitle2>")).toBe(true);
    expect(ownsH1('<Subtitle2 as={"h1"}>x</Subtitle2>')).toBe(true);
    expect(ownsH1("<h1>x</h1>")).toBe(true);
    expect(ownsH1("<h1\n  className={c}\n>x</h1>")).toBe(true);
    expect(ownsH1('<Subtitle2 as="h2">x</Subtitle2>')).toBe(false);
    expect(ownsH1("<h10>x</h10>")).toBe(false);
  });

  it("the header matcher catches headerLeft passed by hand", () => {
    expect(fillsHeaderLeft("<PanelFrame headerLeft={<b />}>")).toBe(true);
    expect(fillsHeaderLeft("<PanelFrame headerRight={<b />}>")).toBe(false);
  });
});
