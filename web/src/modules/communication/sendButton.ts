import type { CommunicationEnv, ManagerDetailResponse } from "./api.communication";
import { FOLDERS } from "../../shell/consts";

/**
 * Whether the retro send button is offered, and whether it can be pressed.
 *
 * Pulled out of the component and kept pure because it is a rule, not a
 * rendering detail, and because the thing it decides cannot be tested any other
 * way: the alternative to asserting the rule is pressing a button that posts to
 * a real webhook.
 *
 * Three states, and the third is the one worth having:
 *
 *   absent    postRetroSummary is off -- the workflow does not include a send,
 *             so the button is not part of the page -- or the session is
 *             closed (in archive/): the file is the record, and the PUT that
 *             records a send will not write there, so a send from a closed
 *             session is one the file could never say happened.
 *   disabled  The send exists but cannot happen -- gate 2 unmet, wrong stage,
 *             nothing to send, or it already went. A disabled button that SAYS
 *             WHY is the whole point: the alternative is a live button that
 *             fails on click and only then tells you a variable is unset -- or
 *             one that posts a second, different message to a real person.
 *   enabled   Retro stage, recipient configured, an Agenda with content, and
 *             no send recorded under ## Sent.
 */
export interface SendButtonState {
  /** Render the button at all. */
  shown: boolean;
  enabled: boolean;
  /** Why it is disabled, in words the page can show. Empty when enabled. */
  reason: string;
  /** The recipient key the send would go to. */
  recipient: string;
}

/** What the button reads off the session: its stage, what `## Sent` records,
 *  and the file -- the Agenda is taken from it, because the Agenda is what goes
 *  out (docs/hub/manager.md, "What reads these files"). */
export type SendButtonSession = Pick<ManagerDetailResponse, "session_stage"> &
  Partial<Pick<ManagerDetailResponse, "sent" | "content" | "folder">>;

/** The date on the last `Sent to manager: <date>` line, or the line itself. */
function lastSent(sent: string): string {
  const lines = sent
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);
  const last = lines[lines.length - 1] ?? "";
  return /\d{4}-\d{2}-\d{2}/.exec(last)?.[0] ?? last;
}

export function sendButtonState(
  env: CommunicationEnv | undefined,
  session: SendButtonSession | undefined,
): SendButtonState {
  const recipient = env?.retroChannel ?? "manager";

  // No /env block means the module is off, and an off module has no button.
  if (!env || !env.postRetroSummary) {
    return { shown: false, enabled: false, reason: "", recipient };
  }

  // A closed session is the record. GET serves it; PUT will not write it; so
  // a send from here could post and never be recorded, which is exactly the
  // shape that invites a second press. Not disabled -- absent.
  if (session?.folder === FOLDERS.archive) {
    return { shown: false, enabled: false, reason: "", recipient };
  }

  // Every reason the send cannot happen, not the first one found. The recipient
  // is checked FIRST and always: gate 2 is the one a person has to leave the
  // page to fix, so its variable is named from the moment the page opens rather
  // than revealed at the Retro stage, when it is needed.
  const reasons: string[] = [];

  const entry = env.recipients.find((r) => r.key === recipient);
  if (!entry) {
    reasons.push(`No recipient '${recipient}' is configured.`);
  } else if (!entry.configured) {
    // Name the variable. "Not configured" sends someone reading source; the
    // variable's name sends them to a shell.
    reasons.push(`Set ${entry.webhookEnv} to this recipient's webhook URL.`);
  }

  const stage = session?.session_stage ?? "";
  if (stage !== "retro") {
    reasons.push("The retro summary is sent at the Retro stage.");
  }

  // The file is the record of a send (## Sent). A button that does not read it
  // is one that posts the same retro twice -- once from the assistant's pass,
  // once from here -- and a message to a manager cannot be taken back.
  const sent = (session?.sent ?? "").trim();
  if (sent) {
    reasons.push(`Already sent on ${lastSent(sent)}.`);
  }

  // And there has to be something to send: a fresh scaffold's Agenda is the
  // template's own placeholder, and that is not a message to a person.
  if (session?.content !== undefined && !hasContent(extractSection(session.content, "Agenda"))) {
    reasons.push("The Agenda is empty -- nothing to send.");
  }

  return { shown: true, enabled: reasons.length === 0, reason: reasons.join(" "), recipient };
}

/**
 * The block of the session file the send actually carries.
 *
 * Deliberately the Agenda section and nothing else. The Retro holds a
 * self-assessment, which is private reflection and not a manager-facing note --
 * and a send that took "the whole file" would post it the first time someone
 * wrote one.
 */
export function extractSection(content: string, heading: string): string {
  const re = new RegExp(`## ${heading}\\s*\\n([\\s\\S]*?)(?=\\n## |$)`);
  return content.match(re)?.[1]?.trim() ?? "";
}

/** A section that holds only its own placeholder is empty. */
export function hasContent(section: string): boolean {
  if (!section || section === "TBD") return false;
  if (/^\(populated/m.test(section)) return false;
  if (/^\(filled/m.test(section)) return false;
  if (/^\(nothing/m.test(section)) return false;
  if (/^<!--[\s\S]*-->$/.test(section)) return false;
  return true;
}
