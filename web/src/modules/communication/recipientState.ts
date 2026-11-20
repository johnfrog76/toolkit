import type { CommunicationEnv, CommunicationRecipient } from "./api.communication";

/**
 * What a Teams recipient's state is called, and how to set it up -- the one
 * place the Environment card's rows (EnvRecipients) and the session page's send
 * button (sendButton) read their words from, so the two cannot drift apart.
 *
 * A state is a few neutral words, never an instruction: an unset webhook is an
 * optional setting nobody has set up yet, not an error. How to set it up, and
 * the environment variable's name, belong in the info text only.
 */
export type RecipientState = "ready" | "unset" | "off" | "person";

export const RECIPIENT_STATE_LABEL: Record<RecipientState, string> = {
  ready: "Ready",
  unset: "Webhook not set",
  off: "Sending off on this server",
  person: "No webhook needed",
};

/** The section's title on the Environment card. */
export const RECIPIENTS_TITLE = "Teams messages";

/**
 * Which state a recipient is in. `sendingOff` is the server's own answer (it
 * was started for review or testing and posts nothing), and it comes first: on
 * such a server a webhook is removed on purpose, so "not set" would be wrong.
 */
export function recipientState(
  r: Pick<CommunicationRecipient, "type" | "configured">,
  sendingOff: boolean | undefined,
): RecipientState {
  if (sendingOff) return "off";
  if (r.type === "person") return "person";
  return r.configured ? "ready" : "unset";
}

/** The how-to behind the info icon. The only place the variable is named. */
export function recipientHowTo(
  r: Pick<CommunicationRecipient, "webhookEnv">,
  state: RecipientState,
): string {
  switch (state) {
    case "ready":
      return `${r.webhookEnv} is set, and this server can send. Its value is never shown.`;
    case "unset":
      return `Optional. To set it up, create a webhook in Teams and put ${r.webhookEnv}=<its URL> in .env in the package root (copy .env.example), then restart the agent.`;
    case "off":
      return "This server was started for review or testing, so it sends nothing. There is nothing to fix here.";
    case "person":
      return "A person is kept for direct messages, which are not sent yet. Nothing is posted to a person, so there is no webhook to set.";
  }
}

/** A display name without its route: "My Manager (DM via Workflow)" -> "My Manager". */
function plainName(display: string): string {
  return display.replace(/\s*\([^)]*\)\s*$/, "").trim() || display;
}

/**
 * What a recipient does, in plain words: who it reaches and how. The recipient
 * the retro goes to is the manager's direct message; any other webhook is a
 * post to a channel; a person is never posted to.
 */
export function recipientLabel(
  r: Pick<CommunicationRecipient, "key" | "display" | "type">,
  retroChannel: CommunicationEnv["retroChannel"],
): string {
  if (r.type === "person") return `${plainName(r.display)}: a person, not posted to`;
  if (r.key === retroChannel) return "Your manager: Teams direct message";
  return `${plainName(r.display)}: Teams post`;
}
