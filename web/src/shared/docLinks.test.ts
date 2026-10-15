// Where a link in a repo's document goes (D-S12): the three kinds, and
// the image rule beside them, against a base like the one the Docs and Design
// rooms hand the viewer. The rooms' own rule (which paths are docs) is pinned
// by docRooms.test.ts against the shared fixture; here it is a stand-in.
import { joinRepoPath, outsideTitle, resolveImage, resolveLink } from "./docLinks";
import type { DocLinkBase } from "./docLinks";

const BLOB = "https://github.com/o/r/blob/main/";
const base = (path: string): DocLinkBase => ({
  path,
  roomFor: (p) =>
    p === "README.md" || (p.startsWith("docs/") && p.endsWith(".md")) ? `/docs/${p}` : null,
  assetFor: (p) => `/api/docs/asset/${p}`,
  outside: (p) => BLOB + p,
});

describe("joinRepoPath", () => {
  it.each([
    ["docs", "CLI.md", "docs/CLI.md"],
    ["docs/modules", "../CLI.md", "docs/CLI.md"],
    ["docs", "../VERIFY.md", "VERIFY.md"],
    ["", "docs/CLI.md", "docs/CLI.md"],
    ["docs/modules", "./ado.md", "docs/modules/ado.md"],
    ["docs/modules", "/README.md", "README.md"],
    ["docs", "../../x.md", null],
  ])("%s + %s -> %s", (folder, rel, want) => {
    expect(joinRepoPath(folder, rel)).toBe(want);
  });
});

describe("resolveLink: the three kinds", () => {
  it("1. a relative .md link opens that document in the room, anchor kept", () => {
    expect(resolveLink("docs/CLI.md", base("README.md"))).toEqual({
      kind: "room",
      to: "/docs/docs/CLI.md",
    });
    expect(resolveLink("CLI.md#the-workflow", base("docs/CLI.md"))).toEqual({
      kind: "room",
      to: "/docs/docs/CLI.md#the-workflow",
    });
    expect(resolveLink("../CLI.md#command-reference", base("docs/modules/ado.md"))).toEqual({
      kind: "room",
      to: "/docs/docs/CLI.md#command-reference",
    });
    expect(resolveLink("../README.md", base("docs/CLI.md"))).toEqual({
      kind: "room",
      to: "/docs/README.md",
    });
  });

  it("2. a #anchor scrolls within the page, with or without a base", () => {
    expect(resolveLink("#known-gaps", base("README.md"))).toEqual({
      kind: "anchor",
      id: "known-gaps",
    });
    expect(resolveLink("#a%20b")).toEqual({ kind: "anchor", id: "a b" });
  });

  it("3. an absolute link leaves in a new tab, as today", () => {
    expect(resolveLink("https://example.com/x", base("README.md"))).toEqual({
      kind: "out",
      href: "https://example.com/x",
    });
    expect(resolveLink("mailto:a@b.c", base("README.md"))).toEqual({
      kind: "out",
      href: "mailto:a@b.c",
    });
  });

  it("a relative link outside README.md and docs/ opens on github.com, and says so", () => {
    expect(resolveLink("../AGENTS.md", base("docs/CLI.md"))).toEqual({
      kind: "out",
      href: `${BLOB}AGENTS.md`,
      title: outsideTitle("AGENTS.md"),
    });
    expect(resolveLink("VERIFY.md#gate-12", base("README.md"))).toEqual({
      kind: "out",
      href: `${BLOB}VERIFY.md#gate-12`,
      title: outsideTitle("VERIFY.md"),
    });
    expect(outsideTitle("AGENTS.md")).toMatch(/on GitHub, in a new tab/);
  });

  it("with no base -- a card, an issue -- a relative link is left as written", () => {
    expect(resolveLink("docs/CLI.md")).toEqual({ kind: "out", href: "docs/CLI.md" });
  });

  it("a link that climbs above the repo is left as written", () => {
    expect(resolveLink("../../x.md", base("docs/CLI.md"))).toEqual({
      kind: "out",
      href: "../../x.md",
    });
  });
});

describe("resolveImage", () => {
  it("serves a relative image through the page's asset route, resolved against the document's folder", () => {
    expect(resolveImage("docs/images/board.png", base("README.md"))).toBe(
      "/api/docs/asset/docs/images/board.png",
    );
    expect(resolveImage("../images/board.png", base("docs/modules/ado.md"))).toBe(
      "/api/docs/asset/docs/images/board.png",
    );
  });

  it("leaves an absolute or data image, and any image with no base, alone", () => {
    expect(resolveImage("https://x.test/a.png", base("README.md"))).toBe("https://x.test/a.png");
    expect(resolveImage("data:image/png;base64,AA", base("README.md"))).toBe(
      "data:image/png;base64,AA",
    );
    expect(resolveImage("a.png")).toBe("a.png");
  });
});
