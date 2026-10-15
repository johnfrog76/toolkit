import * as fs from "fs";
import * as path from "path";
import { isRepo, isSlug, normaliseRepo, proposeName, proposeSlug, repoName } from "./newSpace";
import { buildNewSpaceParams } from "../ado/cliBridge";

// The dialog's mirror of what NewSpace proposes, held to the verb by ONE
// table: Tests/fixtures/spaces/proposals.json, which the verb's suite runs
// through `NewSpace -Repo ... -WhatIf -AsJson` too. A row the two disagree on is
// a bug in one of them.
interface Row {
  repo: string;
  slug: string;
  name: string;
  valid: boolean;
}
const TABLE: { rows: Row[] } = JSON.parse(
  fs.readFileSync(
    path.resolve(__dirname, "../../../../Tests/fixtures/spaces/proposals.json"),
    "utf-8",
  ),
);

describe("what a repository's name proposes, over the shared table", () => {
  it("has rows to read", () => {
    expect(TABLE.rows.length).toBeGreaterThan(5);
  });
  it.each(TABLE.rows.map((r) => [r.repo, r] as const))("%s", (_name, row) => {
    expect(proposeSlug(row.repo)).toBe(row.slug);
    expect(proposeName(row.repo)).toBe(row.name);
    expect(isSlug(row.slug)).toBe(row.valid);
  });
});

describe("a repository, as typed or pasted", () => {
  it("reads a pasted address as owner/name, as the verb does", () => {
    expect(normaliseRepo("https://github.com/tester/Notes_App.git")).toBe("tester/Notes_App");
    expect(normaliseRepo(" github.com/tester/x/ ")).toBe("tester/x");
    expect(repoName("https://github.com/tester/juggling-engine")).toBe("juggling-engine");
  });
  it("accepts owner/name and nothing else", () => {
    expect(isRepo("tester/juggling-engine")).toBe(true);
    expect(isRepo("https://github.com/tester/juggling-engine")).toBe(true);
    expect(isRepo("not-a-repo")).toBe(false);
    expect(isRepo("a/b/c")).toBe(false);
    expect(isRepo("")).toBe(false);
  });
});

describe("the argv the + sends", () => {
  it("sends the slug and name it showed, and the repository when there is one", () => {
    expect(
      buildNewSpaceParams({ slug: "jug", name: " Juggling ", repo: "tester/juggling-engine" }),
    ).toEqual(["-Slug", "jug", "-Name", "Juggling", "-Repo", "tester/juggling-engine"]);
    expect(buildNewSpaceParams({ slug: "notes", name: "Notes" })).toEqual([
      "-Slug",
      "notes",
      "-Name",
      "Notes",
    ]);
  });
});
