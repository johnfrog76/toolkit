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
};

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

function sources(): { file: string; text: string }[] {
  const out: { file: string; text: string }[] = [];
  for (const mod of fs.readdirSync(MODULES)) {
    const dir = path.join(MODULES, mod);
    if (!fs.statSync(dir).isDirectory()) continue;
    for (const name of fs.readdirSync(dir)) {
      if (!/\.tsx$/.test(name) || /\.test\.tsx$/.test(name)) continue;
      out.push({ file: `${mod}/${name}`, text: fs.readFileSync(path.join(dir, name), "utf8") });
    }
  }
  return out;
}

const usesDetailHeader = (text: string) =>
  /^import\s[^;]*\bDetailHeader\b[^;]*from\s+"\.\.\/\.\.\/shared\/DetailHeader"/m.test(text);
const ownsH1 = (text: string) => /\bas="h1"/.test(text);
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
    expect(ownsH1('<Subtitle2 as="h1">x</Subtitle2>')).toBe(true);
  });
});
