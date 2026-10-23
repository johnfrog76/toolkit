/**
 * The contract file parses here, this half reads it, and the one piece of logic
 * in `consts.ts` -- turning a portable pattern into a JavaScript `RegExp` --
 * does what the other two halves' regex engines do with the same string.
 *
 * The guard at the bottom is the web's third of the three-sided parity check
 * (`Tests/Test-Consts.ps1` and `Tests/test_consts.py` are the others): a literal
 * that lives in `consts.json` must not be retyped in this half's source.
 */

import fs from "node:fs";
import path from "node:path";

import consts from "@consts";

import {
  ASSETS,
  DESIGN,
  DOCS,
  FEATURES,
  FOLDERS,
  RE,
  REMINDERS,
  RITUALS,
  STAMPS,
  STARTWORK,
  STATUS,
  STUDIO,
  TESTS,
  TOKENS,
  VISIBILITY,
  toRegExp,
} from "./consts";

const SRC_DIR = path.resolve(__dirname, "..");

describe("consts.json", () => {
  it("parses, and is the same object the app imports", () => {
    const raw = JSON.parse(
      fs.readFileSync(path.resolve(__dirname, "../../../consts.json"), "utf8"),
    );
    expect(consts).toEqual(raw);
  });

  it("exposes the values this half reads", () => {
    expect(STATUS.backlog).toBe("Backlog");
    expect(STATUS.active).toBe("Active");
    expect(STATUS.inProgress).toBe("In Progress");
    expect(STATUS.codeReview).toBe("Code Review");
    expect(STAMPS.closed).toBe("**Closed:**");
    expect(STAMPS.started).toBe("**Started:**");
    expect(STAMPS.review).toBe("**Review:**");
    expect(STAMPS.outcome).toBe("**Outcome:**");
    expect(TOKENS.prUrl).toBe("PR URL:");
    expect(TOKENS.prReviewHeading).toBe("## PR Review Comments");
    expect(TOKENS.previousRound).toBe("> Previous round:");
    expect(TOKENS.design).toBe("> Design:");
    expect(TOKENS.spec).toBe("> Spec:");
    expect(FOLDERS.current).toBe("current");
    expect(FOLDERS.archive).toBe("archive");
    expect(FOLDERS.backlog).toBe("backlog");
    // The org-scoped flags: the same list the CLI's OrgScopedFeatures and the
    // agent's ORG_FEATURES read, so a second one cannot be added to two halves only.
    expect(FEATURES.spaceScoped).toEqual([
      "sprintAwareness",
      "trainingHoursPerQuarter",
      "suggestions",
    ]);
    // Read by vite.config.ts (outside src/), not by the bundle: the name of the
    // variable Start-Web.ps1 sets and the dev proxy reads.
    expect(consts.env.agentPort).toBe("P20_AGENT_PORT");
    // The two the test runners and the engine share: every TEAMS_WEBHOOK_*
    // variable starts with the prefix, and while the marker is set nothing posts.
    expect(consts.env.teamsWebhookPrefix).toBe("TEAMS_WEBHOOK_");
    expect(consts.env.testRunMarker).toBe("P20_TEST_RUN");
    // Where the agent listens: Start-Agent.ps1 reads it, the web only states it.
    expect(consts.agent.bindHost).toBe("127.0.0.1");
    // The two per-process stand-ins for config.local.json that `Web -Dev -Fixture`
    // hands the agent. The web never reads them -- it reads /api/env -- but
    // the contract is stated on all three sides.
    expect(consts.env.activeSpace).toBe("P20_ACTIVE_SPACE");
    expect(consts.env.features).toBe("P20_FEATURES");
    // Where the agent's on-disk cache goes instead of the user cache folder: the
    // test runners set it, the agent reads it. Stated here for the same reason.
    expect(consts.env.agentCacheDir).toBe("P20_AGENT_CACHE_DIR");
    // The line a send writes under ## Sent, from the web button and from SendTeams -Session.
    expect(STAMPS.sent).toBe("Sent to");
    // Organize's reminders: the footer lines, the due pattern, and the two word lists.
    expect(STAMPS.due).toBe("**Due:**");
    expect(STAMPS.source).toBe("**Source:**");
    expect(STAMPS.ref).toBe("**Ref:**");
    // A card's pictures: the two footer lines, the Space's folder, and what Cover takes.
    expect(STAMPS.cover).toBe("**Cover:**");
    expect(STAMPS.before).toBe("**Before:**");
    expect(FOLDERS.assets).toBe("assets");
    expect(ASSETS.coverExtensions).toEqual(["png", "jpg", "jpeg", "webp", "gif"]);
    expect(ASSETS.coverMaxBytes).toBe(5242880);
    expect(consts.regex.dueLine).toBe(
      String.raw`(?m)^\*\*Due:\*\*[ \t]*(\d{4}-\d{2}-\d{2})(?:T(\d{2}:\d{2}))?`,
    );
    expect(REMINDERS.buckets).toEqual(["overdue", "today", "upcoming"]);
    expect(REMINDERS.snooze).toEqual(["1h", "tomorrow", "nextweek"]);
    // The three halves a test run covers, in run order.
    expect(TESTS.halves).toEqual(["agent", "cli", "web"]);
    expect(TESTS.legacyHalf).toBe("cli");
    // The Docs tab's roots: the agent's path rule and this half's link
    // resolver must agree on what is a doc.
    expect(DOCS.readme).toBe("README.md");
    expect(DOCS.root).toBe("docs");
    expect(DOCS.segment).toBe(String.raw`^[A-Za-z0-9_][A-Za-z0-9._-]*$`);
    // The public landing page's deployed address -- a different thing with a
    // similar name: not a Docs-tab file. Home's foot reads this same address.
    expect(DOCS.landingUrl).toBe("https://johnfrog76.github.io/toolkit/");
    // A shipped Space's old slug -> its new one. Both loaders read it;
    // the web reads /api/env, where the old slug has already become the new.
    expect(consts.spaces.renamed).toEqual({ test: "azure-demo" });
    // The package's own repository: the agent's fallback for a Space that is
    // this package itself when a copy has no git origin; the web reads the
    // answer (`space.isToolkit`), never the address.
    expect(consts.repository.url).toBe("https://github.com/johnfrog76/toolkit");
    // A Space says whether its repository is public: the words the agent
    // serves and the CLI prints, and the line a public write carries.
    expect(VISIBILITY.public).toBe("public");
    expect(VISIBILITY.private).toBe("private");
    expect(VISIBILITY.unknown).toBe("unknown");
    expect(VISIBILITY.publicLine).toBe("This repository is public");
    // The Studio's notes (S2b): the name the three halves agree a note may have,
    // and the thread line the CLI writes and the agent reads.
    expect(STUDIO.noteName).toBe(String.raw`^[A-Za-z0-9][A-Za-z0-9._-]*\.md$`);
    expect(STUDIO.threadLine).toBe("> GitHub:");
    expect(STUDIO.promoteLabel).toBe("design");
    // The Prompts card: the agent's read.
    expect(STUDIO.promptsRoute).toBe("/api/studio/prompts");
    // The Spaces card: every GitHub Space's ledger in one read.
    expect(STUDIO.ledgerRoute).toBe("/api/studio/ledger");
    expect(STUDIO.threadRegex).toBe(
      String.raw`(?m)^>\s*GitHub:\s*(https://github\.com/([^/\s]+)/([^/\s]+)/issues/(\d+))\s*$`,
    );
    expect(toRegExp(STUDIO.noteName).test("board-ideas.md")).toBe(true);
    expect(toRegExp(STUDIO.noteName).test("../hub.json")).toBe(false);
    const thread = toRegExp(STUDIO.threadRegex).exec(
      "# Note\n\n> GitHub: https://github.com/o/r/issues/7\n",
    );
    expect(thread?.[4]).toBe("7");
    // The design lifecycle's identity (L1): the key, the id's shape, the words.
    expect(DESIGN.idKey).toBe("id");
    expect(DESIGN.idRegex).toBe(
      "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    );
    expect(DESIGN.states).toEqual(["Design", "Spec", "Complete", "Archived"]);
    expect(DESIGN.outcomes).toEqual(["shipped", "dropped"]);
    expect(DESIGN.docsLine).toBe("> Docs:");
    expect(toRegExp(DESIGN.docsRegex).exec("# S\n\n> Docs: docs/hub/design.md\n")?.[1]).toBe(
      "docs/hub/design.md",
    );
    expect(toRegExp(DESIGN.idRegex).test("ee925272-9564-4816-8944-e6b39c86339c")).toBe(true);
    expect(toRegExp(DESIGN.idRegex).test("EE925272-9564-4816-8944-e6b39c86339c")).toBe(false);
    // The design a card names: the same four groups .NET and Python read, CRLF included.
    expect(DESIGN.cardLineRegex).toBe(
      "(?m)^>[ \\t]*(Design|Spec):[ \\t]*(?:\\[([^\\]\\r\\n]*)\\]\\(([^)\\r\\n]*)\\))?[ \\t]*([^\\r\\n]*?)[ \\t]*\\r?$",
    );
    expect(
      toRegExp(DESIGN.cardLineRegex)
        .exec(
          "# T\r\n> Design: [Board ideas](../../design/board-ideas.md) ee925272-9564-4816-8944-e6b39c86339c\r\n",
        )
        ?.slice(1),
    ).toEqual([
      "Design",
      "Board ideas",
      "../../design/board-ideas.md",
      "ee925272-9564-4816-8944-e6b39c86339c",
    ]);
    expect(
      toRegExp(DESIGN.cardLineRegex).exec("> Spec: [P.spec.md](../spec/P.spec.md) (D4)")?.[4],
    ).toBe("(D4)");
    // Solitaire Agile's Ritual Engine (docs/modules/solitaire-agile.md, "The routes"):
    // the route the page fetches, and every fixed word of the text the CLI and
    // the agent render. The web shows the agent's text verbatim and types none.
    // (`_` is the key's own explanation, prose; every other key is stated.)
    const { _: ritualsDoc, ...rituals } = RITUALS as typeof RITUALS & { _: string };
    expect(ritualsDoc).toMatch(/Ritual Engine/);
    expect(rituals).toEqual({
      route: "/api/ritual/standup",
      triageRoute: "/api/ritual/triage",
      assignMe: "me",
      ceremoniesFile: "Config/ceremonies.json",
      vocabularyFile: "Config/standup-vocabulary.json",
      workerLabelPrefix: "Routed to",
      walkLabel: "verify-close",
      labelWidth: 9,
      attendRoute: "/api/ritual/standup/attend",
      remindRoute: "/api/ritual/standup/remind",
      remindSource: "standup",
      remindTitle: "Standup",
      remindDays: "Mon-Fri",
      weekdays: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
      grains: ["detail", "work", "brief"],
      numberWords: [
        "zero",
        "one",
        "two",
        "three",
        "four",
        "five",
        "six",
        "seven",
        "eight",
        "nine",
        "ten",
        "eleven",
        "twelve",
      ],
      workHeadRegex: "^(?:[A-Za-z]+:\\s+)?(.+?)(?:\\s+--\\s+|:\\s+|$)",
      workThreadRegex:
        "(?m)^>\\s*GitHub:\\s*<?(?:https://github\\.com/[^/\\s>]+/[^/\\s>]+/issues/|#)(\\d+)",
      workDesignRegex: "design/([A-Za-z0-9][A-Za-z0-9_-]*)\\.md",
      workSmallWordRegex: "^[a-z]{1,3}$",
      proseFoldNames: 4,
      dressGuards: [
        "empty",
        "ref-added",
        "ref-dropped",
        "number",
        "count-dropped",
        "kind",
        "name-dropped",
        "name",
      ],
      dressRefRegex:
        "#\\d+|(?<![\\w#])(?=[A-Z0-9]{0,3}[0-9])(?=[A-Z0-9]{0,3}[A-Z])[ACDEFGHJKMNPQRTUVWXY234679]{4}(?!\\w)",
      dressNumberRegex: "(?<![\\w#])\\d+(?!\\w)",
      dressNameRegex: "(?<![\\w'-])[A-Z][A-Za-z0-9'-]*",
      dressPronounRegex: "^I(?:'[a-z]+)?$",
      motions: ["closed", "started", "inProgress"],
      suggestShapes: ["start", "delegate", "route", "place"],
      suggestOwnerSeat: "fable",
      cornerShapes: ["oneLeft", "manyLeft", "reached", "nothingInReach"],
      suggestExclusions: ["notBillable", "waiting", "inFlight", "theirs", "dismissed"],
      text: {
        title: "Standup -- {date}",
        dateFormat: "dddd d MMMM yyyy",
        queueHeading: "Waiting on you",
        queueEmpty: "Nothing is waiting on you.",
        walk: "Walk",
        tracker: "Tracker",
        yesterday: "Yesterday",
        today: "Today",
        blockers: "Blockers",
        mug: "Mug",
        yesterdayEmpty: "nothing closed",
        todayEmpty: "nothing in flight",
        blockersEmpty: "no blockers",
        blockerSuffix: " (verify-close)",
        noWorkers: "No worker labels in this Space.",
        adoTracker:
          "Azure DevOps is the human team's board, and its standup is the one the team holds; Team Agile reads a GitHub Space's issues and cards, or a local Space's cards.",
        check: "Check",
        checkCardArchived: "{item} -- the card is archived, but the issue is still open.",
        checkIssueClosed: "{item} -- the issue is closed, but the card is not archived.",
        briefWalkOne: "walk",
        briefWalkMany: "walks",
        briefDecideOne: "decision",
        briefDecideMany: "decisions",
        briefLookOne: "look",
        briefLookMany: "looks",
        briefAllPc: "all on the PC",
        briefWhoPc: "the PC",
        briefWhoYou: "you",
        briefClosed: "{n} closed yesterday",
        briefClosedNone: "nothing yesterday",
        briefOpen: "{n} open",
        briefOpenNone: "nothing open",
        briefInFlight: "none in flight",
        briefBlocker: "{n} blocker",
        briefBlockers: "{n} blockers",
        briefWorkerNone: "nothing today",
        briefInFlightUnknown: "In flight is not yet known: every routed issue reads as open.",
        briefNext: "Next: the {kind} -- {n} on {who}.",
        briefNextNone: "Next: nothing is waiting on you.",
        suggestNext: "Next: {sentence} ({command})",
        suggestStart: "{ref} is {why} -- start it?",
        suggestDelegate: "{ref} is {size}-sized and well defined -- send it to the crew?",
        suggestRoute: "{ref} is {why}{nobody} -- route it?",
        suggestNobody: " and nobody has it",
        suggestPlace: "{ref} is {size}-sized but has no milestone -- place it?",
        suggestWhyLast: "the last open {noun} in milestone {milestone}",
        suggestWhyMilestone: "the oldest open {kind} in milestone {milestone}",
        suggestWhyOldest: "the oldest open {kind}",
        suggestNounCard: "card",
        suggestNounIssue: "issue",
        suggestCommandStart: "StartWork {arg}",
        suggestCommandRoute: "Route {arg} -Assign <me|size>",
        suggestCommandPlace: "Route {arg} -Milestone <title>",
        suggestCommandPlaceCard: "Plan {arg} -Milestone <title>",
        cornerOneLeft: "one more {noun} {ref} to get milestone {milestone} - start it now",
        cornerManyLeft: "{n} more {noun} to get milestone {milestone} - start {ref} now",
        cornerReached: "milestone {milestone} reached",
        cornerNothingInReach:
          "no milestone in reach - place a card with Route or on its Sprint line",
        cornerNounCards: "cards",
        cornerNounIssues: "issues",
        cornerNounItems: "items",
        cornerChevron: ">",
        cornerBrief: "Corner: {line}",
        cornerBriefCommand: "Corner: {line} {chevron} ({command})",
        workYesterday: "{name}, {n} closed",
        workToday: "{name}, {n}",
        workBlockers: "{name}, {n} to walk",
        workWalk: "{name}, {n} to walk",
        workGroup: "{name}, {n}",
        proseSentence: "{lead} {body}.",
        proseYesterday: "Yesterday I closed",
        proseYesterdayAlso: "I also closed",
        proseToday: "Today I'm on",
        proseTodayAlso: "I'm also on",
        proseBlockers: "Blocked on",
        proseBlockersAlso: "Also blocked on",
        proseBlockersNone: "Nothing blocked.",
        proseWalk: "Waiting on you to walk",
        proseWalkAlso: "Also to walk",
        proseDecide: "Waiting on you to decide",
        proseDecideAlso: "Also to decide",
        proseLook: "Waiting on you to look at",
        proseLookAlso: "Also to look at",
        proseOne: "{n} in {name}: {item}",
        proseTodayOne: "{name}: {item}",
        proseMany: "{n} in {name} ({refs})",
        proseBare: "{item}",
        proseItem: "{ref}, {clause}",
        proseRefSeparator: ", ",
        proseTodayFold: "{n} more: {names}",
        proseTodayFoldCount: "{n} more designs",
        proseNameSeparator: ", ",
        proseNameLast: " and ",
        itemMotion: "{ref} ({motion}) {title}",
        motionStarted: "started",
        commitOne: "{n} commit",
        commitMany: "{n} commits",
        countsTotal: "Since {date}: {counts}.",
        countsNone: "nothing moved",
        countsSeparator: ", ",
        countsClosed: "{n} closed",
        countsStarted: "{n} started",
        countsInProgress: "{n} in progress",
      },
    });
    // StartWork's hand-off block (D-AR5): the CLI types the four headings and the
    // copy box finds the block's title by the head line's shape.
    const { _: startWorkDoc, ...startWork } = STARTWORK as typeof STARTWORK & { _: string };
    expect(startWorkDoc).toMatch(/hand-off block/);
    expect(startWork).toEqual({
      launchEnvFlag: "startWorkLaunch",
      howWeWorkNote: "agentic/how-we-work.md",
      howWeWorkLine: "How we work here: {path}",
      text: {
        head: "# Start work: {kind} {id} -- {title}",
        howWeWork: "## How we work in {space} ({source})",
        work: "## The work: {kind} {id} ({source})",
        prompt: "## The prompt ({source})",
      },
    });
  });

  // Every key of the contract is stated by this half, so a key added to
  // consts.json fails here until the web says what it resolved for it -- the
  // same rule Tests/Test-Consts.ps1 and Tests/test_consts.py hold.
  it("states every key the contract has", () => {
    expect(Object.keys(consts).sort()).toEqual(
      [
        "_README",
        "agent",
        "assets",
        "design",
        "docs",
        "env",
        "features",
        "folders",
        "regex",
        "reminders",
        "repository",
        "reviews",
        "rituals",
        "spaces",
        "stamps",
        "startWork",
        "status",
        "studio",
        "tests",
        "tokens",
        "version",
        "visibility",
      ].sort(),
    );
  });

  // The product's version, typed once in consts.json. web/package.json carries
  // its own literal and the module manifest carries another, so each is held to
  // the contract by name: a partial bump fails here naming the file left behind.
  // MUST match Tests/Test-Consts.ps1's and Tests/test_consts.py's.
  describe("one version", () => {
    const EXPECTED_VERSION = "1.3.0";
    const pkgRoot = path.resolve(__dirname, "../../..");

    it("is stated by the contract", () => {
      expect(consts.version).toBe(EXPECTED_VERSION);
      expect(consts.version).toMatch(/^\d+\.\d+\.\d+$/);
    });

    it("web/package.json carries the same version", () => {
      const pkg = JSON.parse(fs.readFileSync(path.join(pkgRoot, "web/package.json"), "utf8"));
      expect(`web/package.json says ${pkg.version}`).toBe(
        `web/package.json says ${consts.version}`,
      );
    });

    it("Prompt20Toolkit/Prompt20Toolkit.psd1 carries the same version", () => {
      const manifest = fs.readFileSync(
        path.join(pkgRoot, "Prompt20Toolkit/Prompt20Toolkit.psd1"),
        "utf8",
      );
      const found = /^\s*ModuleVersion\s*=\s*'([^']*)'/m.exec(manifest)?.[1];
      expect(`Prompt20Toolkit/Prompt20Toolkit.psd1 says ${found}`).toBe(
        `Prompt20Toolkit/Prompt20Toolkit.psd1 says ${consts.version}`,
      );
    });
  });
});

describe("toRegExp", () => {
  it("lifts a leading (?m) out of the pattern and into a real flag", () => {
    const re = toRegExp("(?m)^PR URL:");
    expect(re.flags).toContain("m");
    expect(re.source).toBe("^PR URL:");
    expect(re.test("# Title\nPR URL: https://x")).toBe(true);
  });

  it("leaves a pattern with no inline flag alone", () => {
    const re = toRegExp("^abc");
    expect(re.flags).toBe("");
    expect(re.source).toBe("^abc");
  });

  it("merges the lifted flag with the caller's", () => {
    expect(toRegExp("(?m)x", "g").flags.split("").sort().join("")).toBe("gm");
  });

  it("throws on an inline flag JavaScript has no equivalent for", () => {
    // A pattern that cannot be expressed in all three engines has stopped being
    // portable, and saying so at build time is the point of keeping it here.
    expect(() => toRegExp("(?x) a b c")).toThrow(/not portable to JavaScript/);
  });

  it("compiles the contract's own patterns and they match real card text", () => {
    expect(RE.prUrlLine.test("# Card\nPR URL: https://dev.azure.com/x")).toBe(true);
    expect(RE.prUrlLine.test("# Card\nPR URL: not-a-url")).toBe(false);
    expect(RE.commitBullet.test("Commits:\n- 80e2168 add grid")).toBe(true);
    expect(RE.commitBullet.test("Commits:\n- (pending)")).toBe(false);
    // The hash is group 1: the standup's commit count reads the lane rule's own bullet.
    const bullet = new RegExp(RE.commitBullet.source, RE.commitBullet.flags.replace("g", ""));
    expect(bullet.exec("Commits:\n- `80e2168` add grid")?.[1]).toBe("80e2168");
  });

  // The shape of a card's id crosses all three halves: a work item number, or the
  // four-character id of a card with no work item. JS has to compile the same
  // string .NET and Python do -- the two lookaheads are the subset they share.
  it("compiles the card-id shape, and agrees with the shared table", () => {
    const table = JSON.parse(
      fs.readFileSync(
        path.resolve(__dirname, "../../../Tests/fixtures/parsers/card-ids.json"),
        "utf8",
      ),
    ) as { arguments: [string, boolean][] };
    for (const [argument, isId] of table.arguments) {
      // The table's arguments are what a person TYPES; the CLI trims and
      // uppercases before it asks, and so does this.
      expect([argument, RE.cardId.test(argument.trim().toUpperCase())]).toEqual([argument, isId]);
    }
    expect(RE.cardId.test("k7m2")).toBe(false); // the shape itself is case-sensitive
    expect(RE.prReviewHeading.test("## PR Review Comments -- Round 2 (PR 35)")).toBe(true);
  });
});

describe("no half retypes a contract literal", () => {
  // Only the DISTINCTIVE literals are grep-able. "Active", "current" and
  // "archive" are ordinary English that this half uses for labels, filters and
  // org status, so a text search for them would be noise rather than a guard --
  // those are held by the parity test instead, which asserts all three halves
  // resolve the same value.
  const GUARDED: Array<[string, string]> = [
    ["stamps.closed", STAMPS.closed],
    ["stamps.created", consts.stamps.created],
    ["stamps.billable", STAMPS.billable],
    ["stamps.assigned", STAMPS.assigned],
    ["stamps.started", STAMPS.started],
    ["stamps.review", STAMPS.review],
    ["stamps.cover", STAMPS.cover],
    ["stamps.before", STAMPS.before],
    ["stamps.outcome", STAMPS.outcome],
    ["tokens.prUrl", TOKENS.prUrl],
    ["tokens.prReviewHeading", TOKENS.prReviewHeading],
    ["tokens.previousRound", TOKENS.previousRound],
    // The agent serves a card's design line parsed; the page never reads the line itself.
    ["tokens.design", TOKENS.design],
    ["regex.commitBullet", consts.regex.commitBullet],
    ["env.agentPort", consts.env.agentPort],
    ["env.testRunMarker", consts.env.testRunMarker],
    ["env.activeSpace", consts.env.activeSpace],
    ["env.features", consts.env.features],
    // Solitaire Agile: the route, and the distinctive words of the rendering --
    // the page shows the agent's text and must never assemble its own.
    ["rituals.route", RITUALS.route],
    ["studio.promptsRoute", STUDIO.promptsRoute],
    ["studio.ledgerRoute", STUDIO.ledgerRoute],
    ["visibility.publicLine", VISIBILITY.publicLine],
    ["rituals.text.title", RITUALS.text.title],
    ["rituals.text.queueHeading", RITUALS.text.queueHeading],
    ["rituals.text.queueEmpty", RITUALS.text.queueEmpty],
    ["rituals.text.todayEmpty", RITUALS.text.todayEmpty],
    ["rituals.text.noWorkers", RITUALS.text.noWorkers],
    // The hand-off block: the CLI builds it; the copy box shows it verbatim.
    ["startWork.text.head", STARTWORK.text.head],
    ["startWork.text.howWeWork", STARTWORK.text.howWeWork],
    // stamps.due is not guarded on this side: the web never parses a due line
    // (GET /api/reminders serves it parsed), and "**Due:**" is ordinary sample
    // markdown in the reading-room tests.
  ];

  // The allowlist, and why each entry is on it:
  //   consts.ts        -- the reader. It names the keys, not the values.
  //   consts.test.ts   -- this file, which asserts the values.
  //   toolkit-figures  -- Introducing ToolKit's slide art. It DRAWS a card open in
  //                       an editor, footer and all, as a picture a person reads;
  //                       it parses nothing. Templates keep their literal text
  //                       for the same reason (AGENTS.md, "One place for magic
  //                       strings").
  // A comment explaining a literal is fine; a comparison against one is not, so
  // the scan skips `//` and `/* */` lines rather than whole files.
  const ALLOWED = new Set([
    "shell/consts.ts",
    "shell/consts.test.ts",
    "modules/deck/decks/toolkit-figures.tsx",
  ]);

  function walk(dir: string, out: string[] = []): string[] {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full, out);
      else if (/\.tsx?$/.test(entry.name)) out.push(full);
    }
    return out;
  }

  // The /env field for StartWork's launch (startWork.launchEnvFlag): the page reads it
  // as env[STARTWORK.launchEnvFlag]. An interface cannot take a computed name, so the
  // EnvStatus field in shell/api.ts spells it -- that one line, and no other.
  it("startWork.launchEnvFlag is read, not retyped -- but for EnvStatus's one field", () => {
    const value = STARTWORK.launchEnvFlag;
    expect(value).toBe("startWorkLaunch");
    const found: string[] = [];
    for (const file of walk(SRC_DIR)) {
      const rel = path.relative(SRC_DIR, file).split(path.sep).join("/");
      if (ALLOWED.has(rel)) continue;
      fs.readFileSync(file, "utf8")
        .split("\n")
        .forEach((line) => {
          const code = line.trim();
          if (code.startsWith("//") || code.startsWith("*") || code.startsWith("/*")) return;
          if (line.includes(value)) found.push(`${rel}:${code}`);
        });
    }
    expect(found).toEqual([`shell/api.ts:${value}?: boolean;`]);
  });

  it.each(GUARDED)("%s is read, not retyped", (key, value) => {
    const offenders: string[] = [];
    for (const file of walk(SRC_DIR)) {
      const rel = path.relative(SRC_DIR, file).split(path.sep).join("/");
      if (ALLOWED.has(rel)) continue;
      const lines = fs.readFileSync(file, "utf8").split("\n");
      lines.forEach((line, i) => {
        const code = line.trim();
        if (code.startsWith("//") || code.startsWith("*") || code.startsWith("/*")) return;
        if (line.includes(value)) offenders.push(`${rel}:${i + 1}`);
      });
    }
    expect(offenders).toEqual([]);
    expect(key).toBeTruthy();
  });
});
