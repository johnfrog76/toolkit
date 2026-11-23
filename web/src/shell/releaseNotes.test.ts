import type { ChangelogRelease } from "./changelogParse";
import {
  WHATS_NEW_SEEN_KEY,
  menuReleases,
  onLoadReleases,
  readSeenVersion,
  resetWhatsNewMemory,
  writeSeenVersion,
} from "./releaseNotes";

const rel = (version: string): ChangelogRelease => ({ version, date: "", groups: [] });
const FILE = ["1.7.0", "1.6.0", "1.5.0", "1.4.0"].map(rel);
const names = (rs: ChangelogRelease[]) => rs.map((r) => r.version);

describe("onLoadReleases: what opens on its own", () => {
  it.each<[string, string, string | null, string[]]>([
    ["no mark at all: the running version only", "1.7.0", null, ["1.7.0"]],
    ["already shown: nothing", "1.7.0", "1.7.0", []],
    ["the next version after the last shown: that one", "1.7.0", "1.6.0", ["1.7.0"]],
    ["versions skipped: each, newest first", "1.7.0", "1.4.0", ["1.7.0", "1.6.0", "1.5.0"]],
    ["a mark the file does not know: the running version only", "1.7.0", "0.1.0", ["1.7.0"]],
    ["a newer version was shown (a downgrade): nothing", "1.5.0", "1.7.0", []],
    ["an unreleased build (no section): nothing", "1.8.0", "1.6.0", []],
    ["an unreleased build, no mark: nothing", "1.8.0", null, []],
  ])("%s", (_label, running, seen, expected) => {
    expect(names(onLoadReleases(FILE, running, seen))).toEqual(expected);
  });
});

describe("menuReleases: what the menu item shows", () => {
  it("is the running version's section", () => {
    expect(names(menuReleases(FILE, "1.6.0"))).toEqual(["1.6.0"]);
  });
  it("is the newest released section on an unreleased build", () => {
    expect(names(menuReleases(FILE, "1.8.0"))).toEqual(["1.7.0"]);
  });
  it("is empty when the file has no release", () => {
    expect(menuReleases([], "1.0.0")).toEqual([]);
  });
});

describe("the browser's mark", () => {
  beforeEach(() => {
    resetWhatsNewMemory();
    window.localStorage.clear();
  });
  afterEach(() => jest.restoreAllMocks());

  it("is one version under one key", () => {
    expect(readSeenVersion()).toBeNull();
    writeSeenVersion("1.7.0");
    expect(window.localStorage.getItem(WHATS_NEW_SEEN_KEY)).toBe("1.7.0");
    expect(readSeenVersion()).toBe("1.7.0");
  });

  it("holds in the page's memory when storage throws, and never throws itself", () => {
    jest.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("denied");
    });
    jest.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("denied");
    });
    expect(() => readSeenVersion()).not.toThrow();
    expect(readSeenVersion()).toBeNull();
    expect(() => writeSeenVersion("1.7.0")).not.toThrow();
    expect(readSeenVersion()).toBe("1.7.0");
  });
});
