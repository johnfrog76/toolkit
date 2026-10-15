// Which repo paths the Docs room reads (D-S12) -- the SAME table the
// agent's path rule is held to (Tests/test_docs.py), so a link the room opens
// is never a route the agent refuses -- and the base both rooms hand the viewer.
import fs from "node:fs";
import path from "node:path";
import { isDocAsset, isDocPath, issueRoomPath, repoLinkBase, roomFor } from "./docRooms";
import { resolveImage, resolveLink } from "../../shared/docLinks";

const table = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, "../../../../Tests/fixtures/docs/paths.json"), "utf8"),
) as { paths: [string, boolean, boolean][] };

describe("the docs path rule, from the shared table", () => {
  it.each(table.paths)("%j: document %s, asset %s", (p, isDoc, isAsset) => {
    expect([isDocPath(p), isDocAsset(p)]).toEqual([isDoc, isAsset]);
  });
});

describe("roomFor: one resolver for both rooms", () => {
  it.each([
    ["README.md", "/docs/README.md"],
    ["docs/modules/ado.md", "/docs/docs/modules/ado.md"],
    ["design/board-note.md", "/design/design/board-note.md"],
    ["spec/toolkit-studio.spec.md", "/design/spec/toolkit-studio.spec.md"],
    // The archive under each root (design lifecycle L2) opens in the same room.
    ["design/archive/old.md", "/design/design/archive/old.md"],
    ["spec/archive/old.spec.md", "/design/spec/archive/old.spec.md"],
    ["design/archive/deeper/x.md", null],
    ["spec/old/x.md", null],
    ["AGENTS.md", null],
  ])("%s -> %s", (p, want) => {
    expect(roomFor(p)).toBe(want);
  });
});

describe("repoLinkBase", () => {
  const url = "https://github.com/johnfrog76/toolkit/blob/main/spec/toolkit-studio.spec.md";
  const b = repoLinkBase("spec/toolkit-studio.spec.md", url);

  it("a spec's link to its design note opens the note in the Design room", () => {
    expect(resolveLink("../design/studio-note.md", b)).toEqual({
      kind: "room",
      to: "/design/design/studio-note.md",
    });
  });

  it("a spec's link into docs/ opens the Docs room", () => {
    expect(resolveLink("../docs/CLI.md#the-workflow", b)).toEqual({
      kind: "room",
      to: "/docs/docs/CLI.md#the-workflow",
    });
  });

  it("anything else opens on github.com, under the document's own blob root", () => {
    const r = resolveLink("../AGENTS.md", b);
    expect(r.kind === "out" && r.href).toBe(
      "https://github.com/johnfrog76/toolkit/blob/main/AGENTS.md",
    );
  });

  it("every repo image goes through the agent, wherever the repository keeps it", () => {
    const readme = repoLinkBase("README.md", "https://github.com/o/r/blob/main/README.md");
    const guide = repoLinkBase(
      "docs/hub/guide.md",
      "https://github.com/o/r/blob/main/docs/hub/guide.md",
    );
    expect(resolveImage("docs/images/board.png", readme)).toBe(
      "/api/docs/asset/docs/images/board.png",
    );
    expect(resolveImage("assets/logo.png", readme)).toBe("/api/docs/asset/assets/logo.png");
    // A relative path above docs/ resolves into the repository, then the agent.
    expect(resolveImage("../../assets/logo.png", guide)).toBe("/api/docs/asset/assets/logo.png");
    // A repository-root path, the way a README written for github.com may say it.
    expect(resolveImage("/assets/logo.png", guide)).toBe("/api/docs/asset/assets/logo.png");
    expect(resolveImage("diagram.png", b)).toBe("/api/docs/asset/spec/diagram.png");
  });

  it("a path that climbs out of the repository never reaches the agent", () => {
    const guide = repoLinkBase("docs/guide.md", "https://github.com/o/r/blob/main/docs/guide.md");
    expect(resolveImage("../../logo.png", guide)).toBe("../../logo.png");
  });

  it("an image the path rule refuses is github.com's raw view, never the agent", () => {
    const readme = repoLinkBase("README.md", "https://github.com/o/r/blob/main/README.md");
    expect(resolveImage("assets/my logo.png", readme)).toBe(
      "https://github.com/o/r/raw/main/assets/my%20logo.png",
    );
  });
});

describe("repoLinkBase: the repository's issues", () => {
  const url = "https://github.com/o/r/blob/main/README.md";

  it("with its issues known, an issue of the repository opens the issue's room", () => {
    const b = repoLinkBase("README.md", url, "https://github.com/o/r/issues");
    expect(b.issues?.url).toBe("https://github.com/o/r/issues");
    expect(resolveLink("https://github.com/o/r/issues/93", b)).toEqual({
      kind: "room",
      to: issueRoomPath(93, "r"),
    });
    expect(issueRoomPath(93, "r")).toBe("/issue/93?repo=r");
  });

  it("another repository's issue, or a pull request, stays out on github.com", () => {
    const b = repoLinkBase("README.md", url, "https://github.com/o/r/issues");
    for (const href of [
      "https://github.com/o/other/issues/1",
      "https://github.com/o/r/pull/4",
      "https://github.com/o/r/issues/new",
    ]) {
      expect(resolveLink(href, b)).toEqual({ kind: "out", href });
    }
  });

  it("with none, there is no issue base and the link stays out", () => {
    const b = repoLinkBase("README.md", url);
    expect(b.issues).toBeUndefined();
    expect(resolveLink("https://github.com/o/r/issues/93", b).kind).toBe("out");
  });
});
