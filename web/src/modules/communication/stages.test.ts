import { WORKFLOW_STAGES, isComplete, nextStageAction, stageAfter, stageOf } from "./stages";

// The three stages in one place: the keys are the file's words under ## Stage
// (what MeetingAgenda -Plan / -Prep / -Retro write), the labels are what a badge
// shows. Two pages used to carry their own copy of this list.

describe("the workflow stages", () => {
  it("are draft, prep, retro -- shown as Plan, Prep, Retro", () => {
    expect(WORKFLOW_STAGES.map((s) => [s.key, s.label])).toEqual([
      ["draft", "Plan"],
      ["prep", "Prep"],
      ["retro", "Retro"],
    ]);
  });

  it("read an unknown or missing word as the first stage", () => {
    expect(stageOf("draft").label).toBe("Plan");
    expect(stageOf("retro").label).toBe("Retro");
    expect(stageOf("").label).toBe("Plan");
    expect(stageOf(undefined).label).toBe("Plan");
    expect(stageOf("nonsense").label).toBe("Plan");
  });

  it("name the stage after this one, and null at the last", () => {
    expect(stageAfter("draft")?.label).toBe("Prep");
    expect(stageAfter("prep")?.label).toBe("Retro");
    expect(stageAfter("retro")).toBeNull();
    // A file with no stage yet is at the first, so Prep is what comes next.
    expect(stageAfter("")?.label).toBe("Prep");
  });

  it("call a session complete only at the last stage", () => {
    expect(isComplete("retro")).toBe(true);
    expect(isComplete("prep")).toBe(false);
    expect(isComplete("draft")).toBe(false);
    expect(isComplete(undefined)).toBe(false);
  });
});

describe("the one stage switch the session page offers", () => {
  // Scripts/Get-MeetingAgenda.ps1: -Plan stamps draft (and creates a missing
  // file), -Prep and -Retro stamp their word on an existing file. Only the
  // stage AHEAD is offered; Close has its own button and its own confirm.
  it("offers the stage ahead, and nothing after Retro", () => {
    expect(nextStageAction("draft")).toBe("Prep");
    expect(nextStageAction("prep")).toBe("Retro");
    expect(nextStageAction("retro")).toBeNull();
  });

  it("offers Plan to a file whose stage is blank or unknown -- the stamp is what is missing", () => {
    expect(nextStageAction("")).toBe("Plan");
    expect(nextStageAction(undefined)).toBe("Plan");
    expect(nextStageAction("nonsense")).toBe("Plan");
  });

  it("offers nothing to a closed session", () => {
    expect(nextStageAction("draft", "archive")).toBeNull();
    expect(nextStageAction("prep", "archive")).toBeNull();
    expect(nextStageAction("draft", "current")).toBe("Prep");
  });
});
