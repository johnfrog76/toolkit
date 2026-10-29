import {
  buildNewAdoItemParams,
  buildCloseWorkItemParams,
  buildConfigEdit,
  commandResultMessage,
  configEditNeedsRestart,
  buildNewCardParams,
  buildBillableParams,
  buildMoveParams,
  buildMeetingAgendaParams,
  buildGrowthCloseParams,
  buildGrowthCompleteParams,
  buildNewGrowthParams,
  fileFromCommandOutput,
  buildNewReminderParams,
  buildReminderArchiveParams,
  buildReminderSnoozeParams,
  buildReminderEditParams,
  buildEditWorkItemParams,
  buildStandupRemindParams,
  buildRouteParams,
  buildMoveDesignParams,
  buildCoverParams,
} from "./cliBridge";
import type { CommandResponse } from "./api.ado";

// These tests are the web half of the CLI parameter contract. They assert the
// exact argv the bridge is handed, so a flag renamed or reordered in
// Scripts/New-AdoItem.ps1 or Scripts/Close-WorkItem.ps1 fails here rather than
// at an `az` call nobody can run in CI.

describe("buildNewAdoItemParams", () => {
  it("sends only -Type and -Title when nothing else is filled in", () => {
    expect(buildNewAdoItemParams({ type: "UserStory", title: "Add dark mode toggle" })).toEqual([
      "-Type",
      "UserStory",
      "-Title",
      "Add dark mode toggle",
    ]);
  });

  it("orders every field as New-AdoItem.ps1 declares it", () => {
    expect(
      buildNewAdoItemParams({
        type: "Bug",
        title: "Login fails on Edge",
        description: "Only on the corporate profile",
        project: "Search Coach",
        parent: 195551,
        sprint: "Sprint 72",
        priority: 1,
        points: 3,
        acceptanceCriteria: "- [ ] Sign-in succeeds",
        reproSteps: "1. Go to /login 2. Click Sign in",
        tags: "ux; accessibility",
      }),
    ).toEqual([
      "-Type",
      "Bug",
      "-Title",
      "Login fails on Edge",
      "-Description",
      "Only on the corporate profile",
      "-Project",
      "Search Coach",
      "-Parent",
      "195551",
      "-Sprint",
      "Sprint 72",
      "-Priority",
      "1",
      "-Points",
      "3",
      "-AcceptanceCriteria",
      "- [ ] Sign-in succeeds",
      "-ReproSteps",
      "1. Go to /login 2. Click Sign in",
      "-Tags",
      "ux; accessibility",
    ]);
  });

  it("keeps a value with spaces and punctuation as one argument", () => {
    const params = buildNewAdoItemParams({
      type: "Task",
      title: 'Fix the upload timeout -- "large" files only',
    });
    expect(params).toHaveLength(4);
    expect(params[3]).toBe('Fix the upload timeout -- "large" files only');
  });

  it("omits the script's own unset defaults rather than restating them", () => {
    expect(
      buildNewAdoItemParams({
        type: "Task",
        title: "Update API docs",
        parent: 0,
        priority: 0,
        points: 0,
        description: "",
        project: "",
        sprint: "",
        tags: "",
      }),
    ).toEqual(["-Type", "Task", "-Title", "Update API docs"]);
  });
});

describe("buildCloseWorkItemParams", () => {
  it("leads with the id positionally and names -Comment", () => {
    expect(buildCloseWorkItemParams({ workItemId: 232161, comment: "Fixed in PR 140387" })).toEqual(
      ["232161", "-Comment", "Fixed in PR 140387"],
    );
  });

  it("appends -Reason when one is stated", () => {
    expect(
      buildCloseWorkItemParams({
        workItemId: 232271,
        comment: "Teams host sets role=application",
        reason: "AsDesigned",
      }),
    ).toEqual(["232271", "-Comment", "Teams host sets role=application", "-Reason", "AsDesigned"]);
  });

  it("omits -Reason entirely when there is none, so the CLI applies its per-type default", () => {
    expect(
      buildCloseWorkItemParams({ workItemId: 449, comment: "Delivered in US-448 scope" }),
    ).toEqual(["449", "-Comment", "Delivered in US-448 scope"]);
  });

  it("keeps a multi-line comment with markdown links as one argument", () => {
    const comment = "Fixed in [PR 140387](https://example/pr/140387)\nas part of #178497";
    expect(buildCloseWorkItemParams({ workItemId: 1, comment })[2]).toBe(comment);
  });
});

describe("buildMoveDesignParams", () => {
  // The hub drawer's moves (design lifecycle L3): the name first, the road,
  // always -Hub, then only what the road was given.
  it("a graduation is the name, the road and -Hub", () => {
    expect(buildMoveDesignParams({ name: "board-ideas.md", to: "Spec" })).toEqual([
      "board-ideas.md",
      "-To",
      "Spec",
      "-Hub",
    ]);
  });

  it("a drop carries -Dropped and its reason; a completion its doc; a Space's design its -Space", () => {
    expect(
      buildMoveDesignParams({
        name: "a-second-room.md",
        to: "Archive",
        dropped: true,
        reason: " The Lounge already does this ",
      }),
    ).toEqual([
      "a-second-room.md",
      "-To",
      "Archive",
      "-Hub",
      "-Dropped",
      "-Reason",
      "The Lounge already does this",
    ]);
    expect(
      buildMoveDesignParams({
        name: "board-ideas.md",
        to: "Complete",
        doc: "docs/board.md",
        space: "toolkit",
      }),
    ).toEqual([
      "board-ideas.md",
      "-To",
      "Complete",
      "-Hub",
      "-Space",
      "toolkit",
      "-Doc",
      "docs/board.md",
    ]);
  });

  it("an empty reason, doc or space is left off rather than sent blank", () => {
    expect(
      buildMoveDesignParams({ name: "x.md", to: "Archive", reason: "  ", doc: "", space: "" }),
    ).toEqual(["x.md", "-To", "Archive", "-Hub"]);
  });
});

describe("buildCoverParams", () => {
  // The card page's attach (C2): the card as its filename, the image as
  // the temp path the upload route answered; a before carries -Before; a
  // removal sends -Remove and no image.
  it("a cover is the card and the path", () => {
    expect(
      buildCoverParams({ card: "K7M2-a-card.prompt.md", image: "p20-upload-1/shot.png" }),
    ).toEqual(["K7M2-a-card.prompt.md", "p20-upload-1/shot.png"]);
  });

  it("a before carries -Before; a removal sends -Remove and no image", () => {
    expect(
      buildCoverParams({ card: "K7M2-a-card.prompt.md", image: "x/wrong.png", before: true }),
    ).toEqual(["K7M2-a-card.prompt.md", "x/wrong.png", "-Before"]);
    expect(
      buildCoverParams({ card: "K7M2-a-card.prompt.md", image: "ignored.png", remove: true }),
    ).toEqual(["K7M2-a-card.prompt.md", "-Remove"]);
  });
});

describe("buildNewCardParams with a picture", () => {
  it("adds -Cover or -Before only when a path was given", () => {
    expect(buildNewCardParams({ title: " T ", type: "User Story" })).toEqual([
      "-Title",
      "T",
      "-Type",
      "UserStory",
    ]);
    expect(buildNewCardParams({ title: "T", type: "Task", cover: "u/shot.png" })).toEqual([
      "-Title",
      "T",
      "-Type",
      "Task",
      "-Cover",
      "u/shot.png",
    ]);
    expect(buildNewCardParams({ title: "T", type: "Task", before: "u/wrong.png" })).toEqual([
      "-Title",
      "T",
      "-Type",
      "Task",
      "-Before",
      "u/wrong.png",
    ]);
    expect(buildNewCardParams({ title: "T", type: "Task", cover: " " })).toEqual([
      "-Title",
      "T",
      "-Type",
      "Task",
    ]);
  });
});

describe("commandResultMessage", () => {
  const base: CommandResponse = {
    command: "NewAdoItem",
    status: "success",
    exit_code: 0,
    output: null,
    error: null,
    duration: 12,
  };

  it("shows the command's output on success, falling back when it printed nothing", () => {
    expect(commandResultMessage({ ...base, output: "Created #451" }, "✓ Done")).toBe(
      "Created #451",
    );
    expect(commandResultMessage(base, "✓ Done")).toBe("✓ Done");
  });

  it("ignores blank lines around a successful command's output", () => {
    expect(commandResultMessage({ ...base, output: "\n\n  Already there.\n\n" }, "✓ Done")).toBe(
      "Already there.",
    );
    expect(commandResultMessage({ ...base, output: "\n  \n" }, "✓ Done")).toBe("✓ Done");
  });

  it("labels each of the three failure statuses", () => {
    expect(
      commandResultMessage({ ...base, status: "rejected", error: "Unknown command" }, "✓"),
    ).toBe("✗ Rejected: Unknown command");
    expect(commandResultMessage({ ...base, status: "timeout", error: "After 30s" }, "✓")).toBe(
      "✗ Timed out: After 30s",
    );
    expect(commandResultMessage({ ...base, status: "error", error: "az not logged in" }, "✓")).toBe(
      "✗ Failed: az not logged in",
    );
  });

  it("shows whatever the command printed before it failed", () => {
    expect(
      commandResultMessage(
        { ...base, status: "error", error: "Exit code 1", output: "[!] -Title is required." },
        "✓",
      ),
    ).toBe("✗ Failed: Exit code 1\n\n[!] -Title is required.");
  });

  it("falls back to the output alone, then to Unknown error, when there is no error text", () => {
    expect(
      commandResultMessage({ ...base, status: "error", output: "[!] No project matching" }, "✓"),
    ).toBe("✗ Failed\n\n[!] No project matching");
    expect(commandResultMessage({ ...base, status: "error" }, "✓")).toBe("✗ Failed: Unknown error");
  });
});

// The config card's half of the same contract. `PUT /api/config` carries
// `{ set, unset }`, the agent turns it into the `Config` verb's two argv tokens,
// and the verb validates every value against the schema -- so what is pinned
// here is the one thing the browser decides: the TYPE each form value goes out
// as, and what an emptied field means.

describe("buildConfigEdit", () => {
  it("sends a string field as a string", () => {
    expect(
      buildConfigEdit([{ key: "email", type: "string", value: "someone@example.com" }]),
    ).toEqual({
      set: { email: "someone@example.com" },
      unset: [],
    });
  });

  it("sends a boolean as a boolean, not as the string a toggle holds", () => {
    expect(buildConfigEdit([{ key: "features.growth", type: "bool", value: "true" }])).toEqual({
      set: { "features.growth": true },
      unset: [],
    });
    expect(buildConfigEdit([{ key: "features.growth", type: "bool", value: "false" }])).toEqual({
      set: { "features.growth": false },
      unset: [],
    });
  });

  it("sends an int as a number", () => {
    expect(buildConfigEdit([{ key: "web.agentPort", type: "int", value: " 4200 " }])).toEqual({
      set: { "web.agentPort": 4200 },
      unset: [],
    });
  });

  it("turns a comma-separated array field into a real array", () => {
    expect(
      buildConfigEdit([
        {
          key: "web.corsOrigins",
          type: "array",
          value: "http://localhost:5174, http://localhost:5173",
        },
      ]),
    ).toEqual({
      set: { "web.corsOrigins": ["http://localhost:5174", "http://localhost:5173"] },
      unset: [],
    });
  });

  it("drops empty entries from an array rather than sending blanks", () => {
    expect(buildConfigEdit([{ key: "web.corsOrigins", type: "array", value: "a,,  ,b," }])).toEqual(
      {
        set: { "web.corsOrigins": ["a", "b"] },
        unset: [],
      },
    );
  });

  it("treats a cleared field as an unset, never as an empty value", () => {
    // Every machine key overrides something -- the shipped default, or the hub
    // -- so emptying one means stop overriding. Writing "" would pin the empty
    // value, and `email: ""` is the config gap this card exists to close.
    expect(buildConfigEdit([{ key: "email", type: "string", value: "   " }])).toEqual({
      set: {},
      unset: ["email"],
    });
  });

  it("carries an explicit unset list through, without duplicating it", () => {
    expect(
      buildConfigEdit([{ key: "email", type: "string", value: "" }], ["email", "wsRoot"]),
    ).toEqual({ set: {}, unset: ["email", "wsRoot"] });
  });

  it("batches several fields into one payload, which is one CLI call", () => {
    expect(
      buildConfigEdit([
        { key: "email", type: "string", value: "someone@example.com" },
        { key: "features.growth", type: "bool", value: "true" },
        { key: "spaces.acme.status", type: "enum", value: "archive" },
        { key: "wsRoot", type: "path", value: "" },
      ]),
    ).toEqual({
      set: {
        email: "someone@example.com",
        "features.growth": true,
        "spaces.acme.status": "archive",
      },
      unset: ["wsRoot"],
    });
  });
});

describe("configEditNeedsRestart", () => {
  it("is false for everything the agent re-reads per request", () => {
    expect(
      configEditNeedsRestart(buildConfigEdit([{ key: "email", type: "string", value: "a@b.c" }])),
    ).toBe(false);
  });

  it("is true for the two keys bound at agent startup", () => {
    expect(
      configEditNeedsRestart(
        buildConfigEdit([{ key: "web.agentPort", type: "int", value: "4200" }]),
      ),
    ).toBe(true);
    expect(
      configEditNeedsRestart(
        buildConfigEdit([{ key: "web.corsOrigins", type: "array", value: "" }]),
      ),
    ).toBe(true);
  });
});

describe("buildNewCardParams", () => {
  it("sends a title and a type, and never an id", () => {
    expect(buildNewCardParams({ title: "Wallet ticket from a QR code", type: "Spike" })).toEqual([
      "-Title",
      "Wallet ticket from a QR code",
      "-Type",
      "Spike",
    ]);
  });

  it("sends a two-word type without its space, as NewPrompt accepts it", () => {
    expect(buildNewCardParams({ title: "Show the ticket", type: "User Story" })[3]).toBe(
      "UserStory",
    );
  });

  it("keeps a title with quotes and spaces as ONE argument, trimmed", () => {
    const params = buildNewCardParams({ title: '  The "big" one  ', type: "Task" });
    expect(params).toHaveLength(4);
    expect(params[1]).toBe('The "big" one');
  });
});

describe("buildBillableParams", () => {
  // Scripts/Set-CardBillable.ps1: -Card is the filename, matched EXACTLY; -No is
  // the whole vocabulary, because a card is billable unless it says otherwise.
  const file = "Spike-K7M2-wallet-ticket.prompt.md";

  it("names the card by its filename and adds -No to take it off Daily", () => {
    expect(buildBillableParams({ file, billable: false })).toEqual(["-Card", file, "-No"]);
  });

  it("sends no switch at all to make it billable again -- there is no -Yes", () => {
    expect(buildBillableParams({ file, billable: true })).toEqual(["-Card", file]);
  });
});

describe("buildGrowthCloseParams", () => {
  // Scripts/New-GrowthItem.ps1: -Close takes the file name under growth/current/.
  it("is -Close and the file, nothing else", () => {
    expect(
      buildGrowthCloseParams({ file: "training-2026-09-01-clean-architecture.prompt.md" }),
    ).toEqual(["-Close", "training-2026-09-01-clean-architecture.prompt.md"]);
  });
});

describe("buildGrowthCompleteParams", () => {
  // Scripts/New-GrowthItem.ps1: -Complete takes a goal's file name under growth/current/.
  it("is -Complete and the file, nothing else", () => {
    expect(buildGrowthCompleteParams({ file: "goal-2026-learn-rust.prompt.md" })).toEqual([
      "-Complete",
      "goal-2026-learn-rust.prompt.md",
    ]);
  });
});

describe("buildNewGrowthParams", () => {
  // Scripts/New-GrowthItem.ps1: -Type -Title -Date -DueDate -Provider -Hours
  // -Notes, in that order; only what was given goes on the line.
  const rows: [string, Parameters<typeof buildNewGrowthParams>[0], string[]][] = [
    [
      "a goal with only a title and a date",
      { type: "goal", title: "Improve test coverage patterns", date: "2026-01-01" },
      ["-Type", "goal", "-Title", "Improve test coverage patterns", "-Date", "2026-01-01"],
    ],
    [
      "a training with every field",
      {
        type: "training",
        title: "Clean Architecture",
        date: "2026-03-02",
        dueDate: "2026-04-30",
        provider: "Internal Academy",
        hours: "8",
        notes: "Boundaries, and which ones are worth the indirection.",
      },
      [
        "-Type",
        "training",
        "-Title",
        "Clean Architecture",
        "-Date",
        "2026-03-02",
        "-DueDate",
        "2026-04-30",
        "-Provider",
        "Internal Academy",
        "-Hours",
        "8",
        "-Notes",
        "Boundaries, and which ones are worth the indirection.",
      ],
    ],
    [
      "a presentation with notes, blank fields left off and the rest trimmed",
      {
        type: "presentation",
        title: "  Designing for Non-Determinism ",
        date: "2026-05-14",
        dueDate: "",
        provider: "   ",
        hours: "",
        notes: " Testing systems whose answers may differ. ",
      },
      [
        "-Type",
        "presentation",
        "-Title",
        "Designing for Non-Determinism",
        "-Date",
        "2026-05-14",
        "-Notes",
        "Testing systems whose answers may differ.",
      ],
    ],
    [
      "a title that starts with a dash is still one element after -Title",
      { type: "goal", title: "-Type training", date: "2026-02-01" },
      ["-Type", "goal", "-Title", "-Type training", "-Date", "2026-02-01"],
    ],
    [
      "no date is no -Date, and the verb's default (today) stands",
      { type: "goal", title: "Read more code", date: "" },
      ["-Type", "goal", "-Title", "Read more code"],
    ],
  ];

  it.each(rows)("%s", (_label, fields, argv) => {
    expect(buildNewGrowthParams(fields)).toEqual(argv);
  });
});

describe("fileFromCommandOutput", () => {
  // NewGrowth ends "Created" and "Already there" with a `    FILE: <path>` line.
  it.each([
    [
      "a Windows path",
      "Created goal-2026-x.prompt.md\r\n    FILE: C:\\hub\\growth\\current\\goal-2026-x.prompt.md\r\n",
      "goal-2026-x.prompt.md",
    ],
    [
      "a POSIX path",
      "Already there: /hub/growth/current/goal-2026-x.prompt.md\n    FILE: /hub/growth/current/goal-2026-x.prompt.md",
      "goal-2026-x.prompt.md",
    ],
    ["no FILE line", "Error: -Title is required.", null],
    ["no output at all", null, null],
    ["an empty FILE line", "    FILE:   ", null],
  ])("%s", (_label, output, expected) => {
    expect(fileFromCommandOutput(output)).toBe(expected);
  });
});

describe("buildMoveParams", () => {
  // Scripts/Move-CardLane.ps1: -Card is the filename; -To is the contract's word
  // without its space, which the script takes in any case. Done is Archive.
  const file = "Spike-K7M2-wallet-ticket.prompt.md";

  it("sends the lane as the contract's word with its space removed", () => {
    expect(buildMoveParams({ file, to: "In Progress" })).toEqual([
      "-Card",
      file,
      "-To",
      "InProgress",
    ]);
    expect(buildMoveParams({ file, to: "Code Review" })).toEqual([
      "-Card",
      file,
      "-To",
      "CodeReview",
    ]);
    expect(buildMoveParams({ file, to: "Done" })).toEqual(["-Card", file, "-To", "Done"]);
  });
});

describe("buildMeetingAgendaParams", () => {
  // Scripts/Get-MeetingAgenda.ps1: -Date, -Type (the series; default 1on1),
  // then one of the four switches. The filename is <series>-YYYY-MM-DD.md or
  // YYYY-MM-DD.md for the 1:1, so date and series together name the record.

  it("closes a 1:1 by its date, with no -Type -- the script's default is the 1:1", () => {
    expect(buildMeetingAgendaParams({ date: "2026-02-05", series: "", action: "Close" })).toEqual([
      "-Date",
      "2026-02-05",
      "-Close",
    ]);
    expect(buildMeetingAgendaParams({ date: "2026-02-05", action: "Close" })).toEqual([
      "-Date",
      "2026-02-05",
      "-Close",
    ]);
    // The script's own spelling of the default is not sent either.
    expect(
      buildMeetingAgendaParams({ date: "2026-02-05", series: "1on1", action: "Close" }),
    ).toEqual(["-Date", "2026-02-05", "-Close"]);
  });

  it("names the series with -Type, between the date and the switch", () => {
    expect(
      buildMeetingAgendaParams({ date: "2026-03-12", series: "client-weekly", action: "Close" }),
    ).toEqual(["-Date", "2026-03-12", "-Type", "client-weekly", "-Close"]);
  });

  it("spells each stage switch the way the script declares it", () => {
    for (const action of ["Plan", "Prep", "Retro"] as const) {
      expect(buildMeetingAgendaParams({ date: "2026-01-08", action })).toEqual([
        "-Date",
        "2026-01-08",
        `-${action}`,
      ]);
    }
  });
});

describe("the reminder builders", () => {
  // Scripts/New-Reminder.ps1 and Scripts/Get-Reminders.ps1, by name -- the bridge
  // splats the argv, so -Id binds to the verb's first parameter by name.
  it("a reminder edit sends only what changed, and an emptied due as -NoDue", () => {
    const was = { title: "Check with Arturo", due: "2026-09-24T09:00", source: "manual" };
    expect(buildReminderEditParams({ id: "3ND7", was, now: { ...was } })).toBeNull();
    expect(
      buildReminderEditParams({ id: "3ND7", was, now: { ...was, title: " Check with Arturo " } }),
    ).toBeNull();
    expect(
      buildReminderEditParams({ id: "3ND7", was, now: { ...was, due: "2026-09-25T14:30" } }),
    ).toEqual(["-Id", "3ND7", "-Due", "2026-09-25T14:30"]);
    expect(
      buildReminderEditParams({ id: "3ND7", was, now: { ...was, due: "2026-09-25" } }),
    ).toEqual(["-Id", "3ND7", "-Due", "2026-09-25"]);
    expect(buildReminderEditParams({ id: "3ND7", was, now: { ...was, due: "" } })).toEqual([
      "-Id",
      "3ND7",
      "-NoDue",
    ]);
    expect(
      buildReminderEditParams({
        id: "3ND7",
        was,
        now: { title: "Call Arturo", due: was.due, source: "goal" },
      }),
    ).toEqual(["-Id", "3ND7", "-Title", "Call Arturo", "-Source", "goal"]);
  });

  it("NewReminder sends only what was given", () => {
    expect(buildNewReminderParams({ title: "  Review goals " })).toEqual([
      "-Title",
      "Review goals",
    ]);
    expect(buildNewReminderParams({ title: "Book it", due: "tomorrow", source: "goal" })).toEqual([
      "-Title",
      "Book it",
      "-Due",
      "tomorrow",
      "-Source",
      "goal",
    ]);
    expect(buildNewReminderParams({ title: "x", due: " ", source: "" })).toEqual(["-Title", "x"]);
    expect(buildNewReminderParams({ title: "Chase it", ref: " K7M2 " })).toEqual([
      "-Title",
      "Chase it",
      "-Ref",
      "K7M2",
    ]);
    expect(buildNewReminderParams({ title: "x", ref: " " })).toEqual(["-Title", "x"]);
  });
  it("a reminder edit sends a changed ref, and an emptied one as an empty -Ref", () => {
    const was = { title: "Chase it", due: "", source: "manual", ref: "214" };
    expect(buildReminderEditParams({ id: "3ND7", was, now: { ...was, ref: " 214 " } })).toBeNull();
    expect(buildReminderEditParams({ id: "3ND7", was, now: { ...was, ref: "K7M2" } })).toEqual([
      "-Id",
      "3ND7",
      "-Ref",
      "K7M2",
    ]);
    expect(buildReminderEditParams({ id: "3ND7", was, now: { ...was, ref: "" } })).toEqual([
      "-Id",
      "3ND7",
      "-Ref",
      "",
    ]);
    expect(
      buildReminderEditParams({ id: "3ND7", was: { ...was, ref: "" }, now: { ...was, ref: "41" } }),
    ).toEqual(["-Id", "3ND7", "-Ref", "41"]);
  });
  it("Snooze is the id and the word", () => {
    expect(buildReminderSnoozeParams({ id: "K7M2", word: "1h" })).toEqual([
      "-Id",
      "K7M2",
      "-Snooze",
      "1h",
    ]);
  });
  it("Archive is the id and the switch", () => {
    expect(buildReminderArchiveParams({ id: "K7M2" })).toEqual(["-Id", "K7M2", "-Archive"]);
  });
});

// Team Agile's reminder to attend is Standup -Remind -- the days travel as
// ONE element, and none at all leaves the verb its own default.
describe("buildStandupRemindParams", () => {
  it("is the time, then the days as one comma-joined element", () => {
    expect(buildStandupRemindParams({ time: "09:00", days: ["Mon", "Wed", "Fri"] })).toEqual([
      "-Remind",
      "09:00",
      "-Days",
      "Mon,Wed,Fri",
    ]);
  });
  it("sends no -Days when none are given", () => {
    expect(buildStandupRemindParams({ time: " 17:30 ", days: [] })).toEqual(["-Remind", "17:30"]);
  });
});

// Route's argv -- Scripts/Set-Route.ps1's param() block. The number is
// positional; each answer is one switch, and the verb writes one gh edit each.
describe("buildRouteParams", () => {
  it("puts the issue number first, positional", () => {
    expect(buildRouteParams({ number: 132 })).toEqual(["132"]);
  });

  it("sends each answer as its own switch", () => {
    expect(buildRouteParams({ number: 132, size: "opus" })).toEqual(["132", "-Size", "opus"]);
    expect(buildRouteParams({ number: 132, severity: "sev2" })).toEqual([
      "132",
      "-Severity",
      "sev2",
    ]);
    expect(buildRouteParams({ number: 132, deepWater: true })).toEqual(["132", "-DeepWater"]);
    // Who takes it (D-AR10): me, or a size.
    expect(buildRouteParams({ number: 4, assign: "me" })).toEqual(["4", "-Assign", "me"]);
  });

  it("keeps a milestone title with spaces as ONE argv element", () => {
    expect(buildRouteParams({ number: 7, milestone: " Phase 6: ledgers " })).toEqual([
      "7",
      "-Milestone",
      "Phase 6: ledgers",
    ]);
  });

  it("deep water's Fable move is the size and the label together", () => {
    expect(buildRouteParams({ number: 140, size: "fable", deepWater: true })).toEqual([
      "140",
      "-Size",
      "fable",
      "-DeepWater",
    ]);
  });

  it("all of them, in the usage's order, and -Space last", () => {
    expect(
      buildRouteParams({
        number: 1,
        size: "sonnet",
        milestone: "M",
        severity: "sev3",
        deepWater: true,
        space: "toolkit",
      }),
    ).toEqual([
      "1",
      "-Size",
      "sonnet",
      "-Milestone",
      "M",
      "-Severity",
      "sev3",
      "-DeepWater",
      "-Space",
      "toolkit",
    ]);
  });

  it("sends nothing for an empty answer", () => {
    expect(
      buildRouteParams({
        number: 1,
        size: " ",
        milestone: "",
        severity: undefined,
        deepWater: false,
      }),
    ).toEqual(["1"]);
  });
});

// The pin is EditItem's -Pin / -Unpin -- the tracker's own pin, through
// the same verb; an absent `pinned` sends neither.
describe("buildEditWorkItemParams -- the pin", () => {
  it("pins, unpins, and leaves the pin alone", () => {
    expect(buildEditWorkItemParams({ id: 100, pinned: true })).toEqual(["100", "-Pin"]);
    expect(buildEditWorkItemParams({ id: 100, pinned: false })).toEqual(["100", "-Unpin"]);
    expect(buildEditWorkItemParams({ id: 100, addTag: "sev2" })).toEqual([
      "100",
      "-AddTag",
      "sev2",
    ]);
  });
});
