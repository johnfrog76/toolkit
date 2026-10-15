import { prepareMarkdown } from "./prepareMarkdown";

describe("prepareMarkdown", () => {
  it("removes a template's instruction comment and leaves no hole in the list", () => {
    const { body } = prepareMarkdown("## Git\n<!-- One commit PER LINE -->\nCommits:\n- (pending)");
    expect(body).toBe("## Git\nCommits:\n- (pending)");
  });

  it("removes a comment that runs over several lines", () => {
    const { body } = prepareMarkdown("before\n<!-- one\ntwo\nthree -->\nafter");
    expect(body).toBe("before\nafter");
  });

  it("keeps the text either side of an inline comment", () => {
    expect(prepareMarkdown("keep <!-- drop --> this").body).toBe("keep  this");
  });

  it("leaves a comment alone inside a fence and inside inline code", () => {
    const fenced = "```html\n<!-- shown -->\n```";
    expect(prepareMarkdown(fenced).body).toBe(fenced);
    expect(prepareMarkdown("write `<!-- note -->` here").body).toBe("write `<!-- note -->` here");
  });

  it("lifts front matter out instead of letting it become a heading", () => {
    const { body, frontMatter } = prepareMarkdown(
      "---\norg: demo\nperiod: 2026-05-11_2026-05-13\n---\n\n# Review",
    );
    expect(frontMatter).toEqual([
      ["org", "demo"],
      ["period", "2026-05-11_2026-05-13"],
    ]);
    expect(body).toBe("# Review");
  });

  it("does not mistake an opening rule and prose for front matter", () => {
    const text = "---\nJust a rule, then a sentence.\n---\nmore";
    expect(prepareMarkdown(text)).toEqual({ body: text, frontMatter: [] });
  });

  it("gives consecutive field lines a line each", () => {
    const { body } = prepareMarkdown(
      "**Sprint:** Sprint 3\n**Story Points:** 5\n**Due:** 2026-09-10",
    );
    expect(body).toBe("**Sprint:** Sprint 3  \n**Story Points:** 5  \n**Due:** 2026-09-10");
  });

  it("breaks plain labels too, and leaves wrapped prose alone", () => {
    expect(prepareMarkdown("Priority: 2 | Severity: 3\nTags: backend").body).toBe(
      "Priority: 2 | Severity: 3  \nTags: backend",
    );
    const prose = "This sentence was wrapped by its author\nand must stay one paragraph.";
    expect(prepareMarkdown(prose).body).toBe(prose);
  });

  it("does not change a card that needs nothing", () => {
    const text = "# Title\n\nA paragraph.\n\n- one\n- two\n";
    expect(prepareMarkdown(text).body).toBe(text);
  });
});

describe("reading a long card", () => {
  const { headingsOf, sectionOf, slugOf, dropLeadingTitle } =
    jest.requireActual("./prepareMarkdown");

  it("lists the h2s and h3s, in order, with a level and the id each one gets", () => {
    const body = "# Title\n\n## Work Item Info\ntext\n### A part of it\n## **Repro** steps\n";
    expect(headingsOf(body)).toEqual([
      { text: "Work Item Info", id: "work-item-info", level: 2, line: 3 },
      { text: "A part of it", id: "a-part-of-it", level: 3, line: 5 },
      { text: "Repro steps", id: "repro-steps", level: 2, line: 6 },
    ]);
  });

  it("stops at h3 -- a list is a menu, not an outline", () => {
    expect(headingsOf("## S\n#### deep\n##### deeper\n").map((h: { id: string }) => h.id)).toEqual([
      "s",
    ]);
  });

  it("lists an h3 with no h2 above it at the top level", () => {
    const body = "### First\ntext\n### Second\n## Section\n### Under it\n";
    expect(headingsOf(body).map((h: { id: string; level: number }) => [h.id, h.level])).toEqual([
      ["first", 2],
      ["second", 2],
      ["section", 2],
      ["under-it", 3],
    ]);
  });

  it("gives two headings with the same words distinct ids, in document order", () => {
    const body = "## Round 1\n### Response\n## Round 2\n### Response\n### Response\n";
    expect(headingsOf(body).map((h: { id: string }) => h.id)).toEqual([
      "round-1",
      "response",
      "round-2",
      "response-2",
      "response-3",
    ]);
  });

  it("names the section a part belongs to, so the marker can light both", () => {
    const headings = headingsOf("### Orphan\n## A\n### A part\n## B\n");
    expect(sectionOf(headings, "a-part")).toBe("a");
    expect(sectionOf(headings, "a")).toBe("a");
    expect(sectionOf(headings, "b")).toBe("b");
    expect(sectionOf(headings, "orphan")).toBe("orphan");
    expect(sectionOf(headings, null)).toBeNull();
    expect(sectionOf(headings, "not-there")).toBeNull();
  });

  it("does not take a heading from inside a fence", () => {
    expect(headingsOf("```md\n## not a heading\n```\n## Real\n")).toEqual([
      { text: "Real", id: "real", level: 2, line: 4 },
    ]);
  });

  it("makes an id out of anything, emoji and punctuation included", () => {
    expect(slugOf("📊 By the Numbers")).toBe("by-the-numbers");
    expect(slugOf("Questions / Blockers")).toBe("questions-blockers");
    expect(slugOf("!!!")).toBe("section");
  });

  it("drops the opening h1 only when the header above already says exactly that", () => {
    const body = "# Bug 141: Search returns duplicates\n\n## Branch\nx";
    expect(dropLeadingTitle(body, "Bug 141:  search returns duplicates")).toBe("## Branch\nx");
    expect(dropLeadingTitle(body, "Something else")).toBe(body);
    expect(dropLeadingTitle(body, undefined)).toBe(body);
    expect(dropLeadingTitle("## No h1 here\n", "No h1 here")).toBe("## No h1 here\n");
  });
});

// A repo's document: its headings wear the ids github.com gives them, so
// the `#anchor` links the docs already use land in the reading room too.
describe("GitHub's heading ids, for a repo's document", () => {
  const { githubSlug, headingIdsOf, headingsOf } = jest.requireActual("./prepareMarkdown");

  it.each([
    ["The bytes a card is written with", "the-bytes-a-card-is-written-with"],
    ["features.ado is not like the other flags", "featuresado-is-not-like-the-other-flags"],
    [
      "The two dates a card carries, and the cards that never got them",
      "the-two-dates-a-card-carries-and-the-cards-that-never-got-them",
    ],
    ["D-CM: how any module contributes commands", "d-cm-how-any-module-contributes-commands"],
    ["3. The two can disagree, and nothing notices", "3-the-two-can-disagree-and-nothing-notices"],
    ["Questions / Blockers", "questions--blockers"],
    ["a -- b", "a----b"],
    ["📊 By the Numbers", "-by-the-numbers"],
    ["snake_case stays", "snake_case-stays"],
  ])("%s -> %s", (text, id) => {
    expect(githubSlug(text)).toBe(id);
  });

  it("gives every level an id, a repeat -1, -2 across levels, and skips fences", () => {
    const body =
      "# Title\n## Round\n```\n## not\n```\n### Round\n#### Round\n## [Linked](x.md) *words* `code`\n";
    expect([...headingIdsOf(body).entries()]).toEqual([
      [1, "title"],
      [2, "round"],
      [6, "round-1"],
      [7, "round-2"],
      [8, "linked-words-code"],
    ]);
  });

  it("the On this page list wears the same ids in github style, the house's otherwise", () => {
    const body = "## Round\n## Round\n";
    expect(headingsOf(body, "github").map((h: { id: string }) => h.id)).toEqual([
      "round",
      "round-1",
    ]);
    expect(headingsOf(body).map((h: { id: string }) => h.id)).toEqual(["round", "round-2"]);
  });
});
