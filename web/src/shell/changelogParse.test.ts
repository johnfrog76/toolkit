import { findRelease, parseChangelog } from "./changelogParse";

const FILE = [
  "# Changelog",
  "",
  "Prose before the first section is not an entry.",
  "",
  "## [Unreleased]",
  "",
  "### Added",
  "",
  "- Something waiting for a release.",
  "",
  "## [1.7.0] - 2026-11-22",
  "",
  "### Added",
  "",
  "- First, with `code` and **bold**.",
  "- Second, wrapped",
  "  onto a second line,",
  "  and a third.",
  "",
  "### Fixed",
  "",
  "- A fix with a [link](docs/CLI.md).",
  "",
  "## [1.6.0] - 2026-11-09",
  "",
  "### Changed",
  "",
  "- Older.",
  "",
  "### Removed",
  "",
  "- Gone.",
  "",
  "## [1.5.0]",
  "",
  "### Added",
  "",
  "- No date on this one.",
  "",
].join("\n");

describe("parseChangelog", () => {
  const releases = parseChangelog(FILE);

  it("reads the released sections, newest first, and leaves [Unreleased] out", () => {
    expect(releases.map((r) => r.version)).toEqual(["1.7.0", "1.6.0", "1.5.0"]);
    expect(JSON.stringify(releases)).not.toContain("waiting for a release");
  });

  it("reads the date, or an empty one", () => {
    expect(releases.map((r) => r.date)).toEqual(["2026-11-22", "2026-11-09", ""]);
  });

  it("keeps the section's own headings in the file's order", () => {
    expect(releases[0].groups.map((g) => g.heading)).toEqual(["Added", "Fixed"]);
    expect(releases[1].groups.map((g) => g.heading)).toEqual(["Changed", "Removed"]);
  });

  it("makes an entry of each dash line and joins its continuation lines", () => {
    expect(releases[0].groups[0].entries).toEqual([
      "First, with `code` and **bold**.",
      "Second, wrapped onto a second line, and a third.",
    ]);
    expect(releases[0].groups[1].entries).toEqual(["A fix with a [link](docs/CLI.md)."]);
  });

  it("reads a CRLF file as it reads an LF one", () => {
    expect(parseChangelog(FILE.replace(/\n/g, "\r\n"))).toEqual(releases);
  });

  it("is empty for a file with no released section, and for no text", () => {
    expect(parseChangelog("## [Unreleased]\n\n### Added\n\n- x\n")).toEqual([]);
    expect(parseChangelog("")).toEqual([]);
  });

  it("finds a version's section, and nothing for a version without one", () => {
    expect(findRelease(releases, "1.6.0")?.groups[1].entries).toEqual(["Gone."]);
    expect(findRelease(releases, "9.9.9")).toBeUndefined();
  });
});
