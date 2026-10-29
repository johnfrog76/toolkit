import type { HubSync } from "../../shell/api";
import { checkedTime, hubSyncWords } from "./hubSync";

// The words for every state the agent's hubSync block can be in, one row each.
// The rule they keep: behind is never shown without the time it was read, and
// "in step" is said only after a fetch -- never as the default.

const AT = "2026-10-29T10:42:00+00:00";
const at = checkedTime(AT);

function sync(over: Partial<HubSync>): HubSync {
  return {
    storeSync: "git",
    state: "on",
    ahead: 0,
    behind: null,
    checkedAt: null,
    checkFailed: null,
    checking: false,
    error: null,
    ...over,
  };
}

describe("hubSyncWords", () => {
  it("says nothing under storeSync none, or from an older agent", () => {
    expect(hubSyncWords(sync({ state: "off", storeSync: "none" }))).toBeNull();
    expect(hubSyncWords(undefined)).toBeNull();
  });

  it.each([
    ["never fetched, nothing ahead", {}, ["not checked against the remote yet"], false, false],
    [
      "never fetched, ahead",
      { ahead: 2 },
      ["ahead by 2", "not checked against the remote yet"],
      false,
      false,
    ],
    [
      "checking",
      { ahead: 1, checking: true },
      ["ahead by 1", "checking the remote..."],
      false,
      false,
    ],
    ["fetched, behind", { behind: 3, checkedAt: AT }, [`behind by 3, checked ${at}`], false, false],
    [
      "fetched, ahead only",
      { ahead: 1, behind: 0, checkedAt: AT },
      ["ahead by 1", `not behind, checked ${at}`],
      false,
      false,
    ],
    ["fetched, in step", { behind: 0, checkedAt: AT }, [`in step, checked ${at}`], true, false],
    [
      "a failed check keeps the last count and its time",
      { behind: 2, checkedAt: AT, checkFailed: "fatal: unable to access" },
      [`behind by 2, last checked ${at}; the latest check failed: fatal: unable to access`],
      false,
      true,
    ],
    [
      "a failed check after an in-step one is not in step",
      { behind: 0, checkedAt: AT, checkFailed: "fatal: unable to access" },
      [`check failed, last checked ${at}: fatal: unable to access`],
      false,
      true,
    ],
    [
      "a first check that failed",
      { checkFailed: "fatal: unable to access" },
      ["check failed: fatal: unable to access"],
      false,
      true,
    ],
    [
      "the local read failed",
      { ahead: null, error: "fatal: no upstream configured for branch 'main'" },
      ["fatal: no upstream configured for branch 'main'"],
      false,
      true,
    ],
  ] as [string, Partial<HubSync>, string[], boolean, boolean][])(
    "%s",
    (_name, over, parts, inStep, warn) => {
      expect(hubSyncWords(sync(over))).toEqual({ parts, inStep, warn });
    },
  );

  it("never says in step before a fetch", () => {
    const words = hubSyncWords(sync({ ahead: 0, behind: 0, checkedAt: null }));
    expect(words?.inStep).toBe(false);
    expect(words?.parts.join(" ")).not.toMatch(/in step/);
  });

  it("writes the check's time as HH:MM", () => {
    expect(at).toMatch(/^\d{2}:\d{2}$/);
  });
});
