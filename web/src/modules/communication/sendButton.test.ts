/**
 * The send button's rule, which is the one thing in this module that cannot be
 * checked any other way: the alternative to asserting it here is pressing a
 * button that posts to a real webhook.
 *
 * Three states and the boundaries between them. The state worth the test is the
 * middle one -- shown but disabled, with a reason -- because that is the whole
 * reason /env reports gate 2 at all. A button that discovers on click that an
 * environment variable is unset has already failed at the job.
 */
import { extractSection, hasContent, sendButtonState } from "./sendButton";
import type { CommunicationEnv, ManagerDetailResponse } from "./api.communication";

function env(over: Partial<CommunicationEnv> = {}): CommunicationEnv {
  return {
    postRetroSummary: true,
    retroChannel: "manager",
    recipients: [
      {
        key: "manager",
        display: "My Manager",
        type: "channel",
        scope: "managerWorkflow",
        webhookEnv: "TEAMS_WEBHOOK_MANAGER",
        configured: true,
      },
    ],
    ...over,
  };
}

// A stage alone: a session with no `sent` and no `content` is the shape an
// older agent serves, and the button's rule reads it as "nothing sent, and the
// Agenda is not known to be empty".
function session(
  stage: string,
  over: Partial<Pick<ManagerDetailResponse, "sent" | "content" | "folder">> = {},
): Pick<ManagerDetailResponse, "session_stage"> & typeof over {
  return { session_stage: stage, ...over };
}

const AGENDA =
  "## Agenda\n- **Work**\n  - the queue timeouts\n\n## Prep\n(populated at the Prep stage)\n";

describe("the retro send button", () => {
  it("is enabled at the retro stage with a configured recipient", () => {
    const state = sendButtonState(env(), session("retro"));
    expect(state).toEqual({
      shown: true,
      enabled: true,
      reason: "",
      info: "",
      recipient: "manager",
    });
  });

  it("is absent when postRetroSummary is off", () => {
    // Not disabled -- absent. The workflow does not include a send, so there is
    // nothing to explain.
    const state = sendButtonState(env({ postRetroSummary: false }), session("retro"));
    expect(state.shown).toBe(false);
    expect(state.reason).toBe("");
  });

  it("is absent on a closed session -- the write-back could never record the send", () => {
    // GET serves an archived session; PUT looks in current/ only. A button here
    // posts a message the file never says happened, and invites a second press.
    const state = sendButtonState(
      env(),
      session("retro", { sent: "", content: AGENDA, folder: "archive" }),
    );
    expect(state.shown).toBe(false);
    expect(sendButtonState(env(), session("retro", { folder: "current" })).shown).toBe(true);
  });

  it("is absent when /env carries no communication block at all", () => {
    expect(sendButtonState(undefined, session("retro")).shown).toBe(false);
  });

  it.each(["draft", "prep", ""])("is disabled at the %s stage, and says so", (stage) => {
    const state = sendButtonState(env(), session(stage));
    expect(state.shown).toBe(true);
    expect(state.enabled).toBe(false);
    expect(state.reason).toMatch(/Retro stage/);
  });

  it("is disabled with no session loaded", () => {
    expect(sendButtonState(env(), undefined).enabled).toBe(false);
  });

  it("says Webhook not set when gate 2 is unmet, with the variable in the info text only", () => {
    const state = sendButtonState(
      env({ recipients: [{ ...env().recipients[0], configured: false }] }),
      session("retro"),
    );
    expect(state.enabled).toBe(false);
    // A state in a few neutral words, not an instruction. The variable's name
    // is how-to, and how-to is behind the info icon.
    expect(state.reason).toBe("Webhook not set.");
    expect(state.reason).not.toContain("TEAMS_WEBHOOK_MANAGER");
    expect(state.info).toContain("TEAMS_WEBHOOK_MANAGER");
  });

  it.each([true, false])(
    "says Sending off on this server when the server says so (webhook set: %s)",
    (configured) => {
      // A server started for review or testing removes the webhooks and sets
      // the run marker. Nothing is misconfigured and there is nothing to set,
      // so neither the reason nor the info names the variable.
      const state = sendButtonState(
        env({ sendingOff: true, recipients: [{ ...env().recipients[0], configured }] }),
        session("retro"),
      );
      expect(state.enabled).toBe(false);
      expect(state.reason).toBe("Sending off on this server.");
      expect(state.info).not.toContain("TEAMS_WEBHOOK_MANAGER");
      expect(state.info).not.toBe("");
    },
  );

  it("reads an agent that reports no sendingOff as one that can send", () => {
    expect(sendButtonState(env({ sendingOff: undefined }), session("retro")).enabled).toBe(true);
  });

  it("asks a person recipient for no webhook", () => {
    const state = sendButtonState(
      env({ recipients: [{ ...env().recipients[0], type: "person", configured: false }] }),
      session("retro"),
    );
    expect(state.enabled).toBe(false);
    expect(state.reason).toBe("No webhook needed.");
    expect(state.info).not.toContain("TEAMS_WEBHOOK_MANAGER");
  });

  it("carries no info when the recipient is not what holds the send back", () => {
    expect(sendButtonState(env(), session("draft")).info).toBe("");
  });

  it("says the recipient's state BEFORE the Retro stage, with the stage reason after it", () => {
    // The recipient is the one a person has to leave the page to fix, so it is
    // said from the moment the page opens -- not revealed at the moment of
    // sending. It used to return on the stage check first, and before Retro
    // the only reason was ever "sent at the Retro stage".
    const state = sendButtonState(
      env({ recipients: [{ ...env().recipients[0], configured: false }] }),
      session("draft"),
    );
    expect(state.shown).toBe(true);
    expect(state.enabled).toBe(false);
    expect(state.reason).toBe("Webhook not set. The retro summary is sent at the Retro stage.");
  });

  it("is enabled with an Agenda that has content and nothing under ## Sent", () => {
    const state = sendButtonState(env(), session("retro", { sent: "", content: AGENDA }));
    expect(state).toEqual({
      shown: true,
      enabled: true,
      reason: "",
      info: "",
      recipient: "manager",
    });
  });

  it("is disabled once the file records a send, and says when", () => {
    // The file is the record: an assistant following the prompt adds the same
    // line, so the button reads it rather than its own state -- a message to a
    // manager cannot be taken back.
    const state = sendButtonState(
      env(),
      session("retro", { sent: "Sent to manager: 2026-02-05", content: AGENDA }),
    );
    expect(state.enabled).toBe(false);
    expect(state.reason).toBe("Already sent on 2026-02-05.");
  });

  it("names the LAST send when there were several", () => {
    const state = sendButtonState(
      env(),
      session("retro", {
        sent: "Sent to manager: 2026-02-05\nSent to manager: 2026-02-06",
        content: AGENDA,
      }),
    );
    expect(state.reason).toBe("Already sent on 2026-02-06.");
  });

  it("is disabled when the Agenda holds only the template's placeholder", () => {
    const state = sendButtonState(
      env(),
      session("retro", {
        sent: "",
        content: "## Agenda\n(populated by the Plan pass)\n\n## Prep\n",
      }),
    );
    expect(state.enabled).toBe(false);
    expect(state.reason).toBe("The Agenda is empty -- nothing to send.");
  });

  it("joins every reason that holds, the recipient's first", () => {
    const state = sendButtonState(
      env({ recipients: [{ ...env().recipients[0], configured: false }] }),
      session("draft", { sent: "Sent to manager: 2026-02-05", content: "## Agenda\nTBD\n" }),
    );
    expect(state.reason).toBe(
      "Webhook not set. " +
        "The retro summary is sent at the Retro stage. " +
        "Already sent on 2026-02-05. " +
        "The Agenda is empty -- nothing to send.",
    );
  });

  it("is disabled when the configured retro channel has no recipient entry", () => {
    const state = sendButtonState(env({ retroChannel: "nobody" }), session("retro"));
    expect(state.enabled).toBe(false);
    expect(state.reason).toContain("nobody");
  });

  it("sends to the channel config names, not to a hardcoded key", () => {
    const state = sendButtonState(
      env({
        retroChannel: "skip-level",
        recipients: [
          { ...env().recipients[0], key: "skip-level", webhookEnv: "TEAMS_WEBHOOK_SKIP_LEVEL" },
        ],
      }),
      session("retro"),
    );
    expect(state.recipient).toBe("skip-level");
    expect(state.enabled).toBe(true);
  });
});

describe("what the send carries", () => {
  const file = [
    "# 2026-02-05",
    "",
    "## Stage",
    "retro",
    "",
    "## Agenda",
    "- **Work**",
    "  - the queue timeouts",
    "",
    "## Prep",
    "(populated at the Prep stage)",
    "",
    "## Retro",
    "**Summary**",
    "covered the spike",
    "",
    "**Self-assessment**",
    "asked for the date rather than arguing the case",
    "",
    "## Sent",
    "(nothing sent yet)",
    "",
  ].join("\n");

  it("takes the Agenda section and stops at the next heading", () => {
    const agenda = extractSection(file, "Agenda");
    expect(agenda).toContain("the queue timeouts");
    expect(agenda).not.toContain("## Prep");
  });

  it("never carries the self-assessment", () => {
    // Private reflection, not a manager-facing note. A send that took "the
    // session" rather than one section would post it.
    expect(extractSection(file, "Agenda")).not.toContain("Self-assessment");
  });

  it("reads a section holding only its own placeholder as empty", () => {
    expect(hasContent(extractSection(file, "Prep"))).toBe(false);
    expect(hasContent(extractSection(file, "Sent"))).toBe(false);
    expect(hasContent(extractSection(file, "Agenda"))).toBe(true);
  });

  it("reads a missing section as empty rather than throwing", () => {
    expect(extractSection(file, "Nothing Like This")).toBe("");
    expect(hasContent("")).toBe(false);
  });
});
