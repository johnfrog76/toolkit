/**
 * The orchestrating answer writes the team's page (docs/modules/studio.md,
 * "HowWeWork"). When "With agents" is chosen for a Space in the Settings
 * drawer's "How do you want to work in <Space>?", and the answer is set:
 *
 * - the Prompts listing already carries the Space's how-we-work note: NO call;
 * - otherwise the CLI's own verb runs through the bridge,
 *   POST /api/cmd/HowWeWork <slug>, and the answer shows the verb's line for
 *   the repository's AGENTS.md -- or, refused, the verb's own stated sentence.
 *
 * No rule of its own: whether a note is there is the agent's listing, the
 * write and every refusal are the verb's. The shell reaches this file through a
 * dynamic import (registry.ts, useWriteHowWeWork), so it and the Studio's
 * endpoints arrive only when the answer is picked.
 */
import type { ThunkDispatch, UnknownAction } from "@reduxjs/toolkit";
import { STARTWORK } from "../../shell/consts";
import type { CommandResponse } from "../ado/api.ado";
import { adoEndpoints } from "../ado/api.ado";
import { studioEndpoints } from "./api.studio";
import type { PromptListRow, PromptsResponse } from "./api.studio";

/** What happened after the answer: nothing to do, the note written, or refused. */
export type HowWeWorkOutcome =
  { kind: "listed" } | { kind: "written"; line: string } | { kind: "refused"; sentence: string };

/** Whether the listing carries the Space's note: one of yours at the note's path. */
export function noteListed(rows: Pick<PromptListRow, "group" | "path">[]): boolean {
  return rows.some((r) => r.group === "yours" && r.path.endsWith(STARTWORK.howWeWorkNote));
}

/** The verb's AGENTS.md line, found in its output by the contract's shape. */
export function pasteLine(output: string | null | undefined): string {
  const head = STARTWORK.howWeWorkLine.split("{path}")[0];
  const found = (output ?? "")
    .split(/\r?\n/)
    .map((l) => l.trim())
    .find((l) => l.startsWith(head));
  return found ?? "";
}

export interface HowWeWorkDeps {
  /** The Prompts listing, as the agent serves it for the Space you are in. */
  listPrompts: () => Promise<PromptsResponse>;
  /** One verb through the bridge. */
  runCommand: (name: string, params: string[]) => Promise<CommandResponse>;
}

export async function writeHowWeWork(deps: HowWeWorkDeps, slug: string): Promise<HowWeWorkOutcome> {
  let rows: PromptListRow[] = [];
  try {
    rows = (await deps.listPrompts()).prompts ?? [];
  } catch {
    // An unread listing is not a listed note: the verb is asked, and it never
    // writes over a note that is there.
    rows = [];
  }
  if (noteListed(rows)) return { kind: "listed" };
  let reply: CommandResponse;
  try {
    reply = await deps.runCommand("HowWeWork", [slug]);
  } catch {
    return {
      kind: "refused",
      sentence: "The agent did not answer -- the how-we-work note was not written.",
    };
  }
  if (reply.status === "success") return { kind: "written", line: pasteLine(reply.output) };
  return {
    kind: "refused",
    sentence: (reply.error || reply.output || "HowWeWork refused.").trim(),
  };
}

// The store's dispatch, loosely typed: the endpoints' thunks are all it carries.
type Dispatch = ThunkDispatch<unknown, unknown, UnknownAction>;

/** writeHowWeWork over the store: the listing read fresh, the verb through the bridge,
 *  and the Prompts card told to read again once the note is written. */
export async function writeHowWeWorkWith(
  dispatch: Dispatch,
  slug: string,
): Promise<HowWeWorkOutcome> {
  const outcome = await writeHowWeWork(
    {
      listPrompts: async () => {
        const sub = dispatch(
          studioEndpoints.endpoints.getPrompts.initiate(undefined, { forceRefetch: true }),
        );
        try {
          return await sub.unwrap();
        } finally {
          sub.unsubscribe();
        }
      },
      runCommand: (name, params) =>
        dispatch(adoEndpoints.endpoints.runCommand.initiate({ name, params })).unwrap(),
    },
    slug,
  );
  if (outcome.kind === "written") dispatch(studioEndpoints.util.invalidateTags(["Prompts"]));
  return outcome;
}
