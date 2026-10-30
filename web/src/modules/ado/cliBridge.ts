// The web half of the CLI bridge contract.
//
// Nothing in the web UI changes a card except through `POST /api/cmd/{name}`,
// and that endpoint hands `params` to the PowerShell function as **argv**. One
// array element is one argument: a value with spaces or punctuation is a single
// element, unquoted -- `["Fix the upload timeout", "-Type", "Bug"]`, never a
// pre-joined command string. Escaping is the backend's problem, not ours.
//
// These builders are pure so the parameter contract can be pinned by a test
// rather than discovered against a live `az`. The order and the spelling of
// every flag come from the `param()` block of the script named in each comment;
// if a script's parameters change, the test here is what fails first.

import type { CommandResponse } from "./api.ado";

/** The New ADO Item dialog's fields. Named for the CLI parameters they feed. */
export interface NewAdoItemFields {
  type: "UserStory" | "Task" | "Bug" | "Feature";
  title: string;
  description?: string;
  project?: string;
  parent?: number;
  sprint?: string;
  priority?: number;
  points?: number;
  acceptanceCriteria?: string;
  reproSteps?: string;
  tags?: string;
}

/**
 * argv for `POST /cmd/NewItem` -> `Scripts/New-AdoItem.ps1`.
 *
 * Every parameter of that script is named -- it declares no positional ones --
 * so the array is flag/value pairs in the order the `param()` block declares
 * them: Type, Title, Description, Project, Parent, Sprint, AssignTo, Priority,
 * Points, AcceptanceCriteria, ReproSteps, Tags.
 *
 * Two of those the dialogs never send. `-AssignTo` is omitted so the script
 * falls through to `Resolve-P20Identity` -- the configured identity, which is
 * what the dialog means by "me". `-ReadOnly` is a dry run with no UI control.
 *
 * An empty or zero field is omitted rather than sent blank: `-Parent 0` and
 * `-Priority 0` are the script's own "unset" defaults, and passing them
 * explicitly would only re-state them.
 */
export function buildNewAdoItemParams(fields: NewAdoItemFields): string[] {
  const params: string[] = ["-Type", fields.type, "-Title", fields.title];
  if (fields.description) params.push("-Description", fields.description);
  if (fields.project) params.push("-Project", fields.project);
  if (fields.parent && fields.parent > 0) params.push("-Parent", String(fields.parent));
  if (fields.sprint) params.push("-Sprint", fields.sprint);
  if (fields.priority && fields.priority > 0) params.push("-Priority", String(fields.priority));
  if (fields.points && fields.points > 0) params.push("-Points", String(fields.points));
  if (fields.acceptanceCriteria) params.push("-AcceptanceCriteria", fields.acceptanceCriteria);
  if (fields.reproSteps) params.push("-ReproSteps", fields.reproSteps);
  if (fields.tags) params.push("-Tags", fields.tags);
  return params;
}

/** The "New card" dialog's fields: a card with no work item. */
export interface NewCardFields {
  title: string;
  /** A configured card type name, as `/env.cardTypes` spells it ("User Story"). */
  type: string;
  /** Optional: fills the card's Context (a Task) or Summary (everything else)
   *  in place of `(TBD)`, the same slot an ADO-linked card fills from the work
   *  item's own description. Multi-line is kept, as `-Description <text>`. */
  description?: string;
  /** A picture at birth (docs/hub/cards.md, "A card's pictures"): the temp
   *  path the upload route answered, as `-Cover <path>` -- or `-Before <path>`
   *  when the snap shows what is wrong. The verb copies it in and writes the line. */
  cover?: string;
  before?: string;
}

/** `Cover <card> <image> [-Before] [-Remove]` from the card page (C2): the card
 *  as its filename, the image as the temp path the upload route answered; a
 *  removal sends no image. */
export interface CoverFields {
  card: string;
  image?: string;
  before?: boolean;
  remove?: boolean;
}

export function buildCoverParams(fields: CoverFields): string[] {
  const params = [fields.card];
  if (fields.remove) {
    params.push("-Remove");
  } else if (fields.image) {
    params.push(fields.image);
  }
  if (fields.before) params.push("-Before");
  return params;
}

/**
 * `NewPrompt -Title <text> -Type <name>`: a card made from nothing, with no
 * work item and no ADO call. The id is NOT sent -- it is chosen by the CLI's one
 * id engine (`New-P20CardId`), which is how a card made in the browser and a card
 * made in a terminal come out of the same rule (docs/hub/cards.md, "The filename").
 *
 * The type travels without its space: `NewPrompt` accepts "UserStory" for
 * "User Story" precisely because a shell argument with a space is a nuisance.
 * The title is sent as typed; the bridge passes argv, not a command line, so a
 * title with spaces or quotes is one argument.
 */
export function buildNewCardParams(fields: NewCardFields): string[] {
  const params = ["-Title", fields.title.trim(), "-Type", fields.type.replace(/\s+/g, "")];
  if (fields.description?.trim()) params.push("-Description", fields.description);
  if (fields.cover?.trim()) params.push("-Cover", fields.cover.trim());
  if (fields.before?.trim()) params.push("-Before", fields.before.trim());
  return params;
}

/**
 * argv for `POST /cmd/Billable` -> `Scripts/Set-CardBillable.ps1`.
 *
 * The card travels as its FILENAME, which the script matches exactly, in
 * `current/` and then `archive/` -- never as a partial name. `-No` is the whole
 * vocabulary: a card is billable unless it says otherwise, so "billable" is the
 * absence of the switch, and the script removes the line rather than writing
 * "yes".
 */
export function buildBillableParams(fields: { file: string; billable: boolean }): string[] {
  return fields.billable ? ["-Card", fields.file] : ["-Card", fields.file, "-No"];
}

/**
 * argv for `POST /cmd/Move` -> `Scripts/Move-CardLane.ps1`.
 *
 * The card travels as its FILENAME; the lane as the contract's word with its
 * space removed (`InProgress`, `CodeReview`, `Done`), which the script accepts in
 * any case. Done is Archive, exactly -- the script runs it.
 */
export function buildMoveParams(fields: { file: string; to: string }): string[] {
  return ["-Card", fields.file, "-To", fields.to.replace(/\s+/g, "")];
}

/** `NewGrowth -Close <file>`: archive a growth item. The file is the name as the
 *  agent serves it (`filename`), which is the name under growth/current/. */
export function buildGrowthCloseParams(fields: { file: string }): string[] {
  return ["-Close", fields.file];
}

/** `NewGrowth -Complete <file>`: write a goal's Outcome Status line as Achieved.
 *  The file stays in growth/current/; archiving it is `-Close`. */
export function buildGrowthCompleteParams(fields: { file: string }): string[] {
  return ["-Complete", fields.file];
}

/**
 * `WorkReview <review> -Archive | -Delete` -- a review's row's two moves. `review`
 * is the row's own name for its folder, `[archive/]<slug-set>/<start>_<end>`, as
 * the agent reads it off the path.
 */
export function buildWorkReviewParams(review: string, move: "archive" | "delete"): string[] {
  return [review, move === "archive" ? "-Archive" : "-Delete"];
}

/** The New Growth Item dialog's fields. Named for the CLI parameters they feed. */
export interface NewGrowthFields {
  type: "training" | "presentation" | "goal";
  title: string;
  /** YYYY-MM-DD: a training's start, a talk's day, a goal's year. */
  date: string;
  /** YYYY-MM-DD; the verb refuses a training without one. */
  dueDate?: string;
  provider?: string;
  hours?: string;
  notes?: string;
}

/**
 * argv for `POST /cmd/NewGrowth` -> `Scripts/New-GrowthItem.ps1`: a new
 * training, presentation or goal in growth/current/, written by the verb the
 * terminal types, so the browser and the CLI make one file with one writer.
 *
 * Flag/value pairs in the order the `param()` block declares them: Type, Title,
 * Date, DueDate, Provider, Hours, Notes. Only what was given goes on the line --
 * an empty field is omitted, so the verb's own default stands (`TBD` hours, no
 * provider). The verb checks every value again and refuses in its own words.
 */
export function buildNewGrowthParams(fields: NewGrowthFields): string[] {
  const params = ["-Type", fields.type, "-Title", fields.title.trim()];
  if (fields.date.trim()) params.push("-Date", fields.date.trim());
  if (fields.dueDate?.trim()) params.push("-DueDate", fields.dueDate.trim());
  if (fields.provider?.trim()) params.push("-Provider", fields.provider.trim());
  if (fields.hours?.trim()) params.push("-Hours", fields.hours.trim());
  if (fields.notes?.trim()) params.push("-Notes", fields.notes.trim());
  return params;
}

/**
 * The file name on a verb's `FILE: <path>` line, or null when it printed none.
 * `NewGrowth` ends both "Created" and "Already there" with that line; the path
 * is the agent machine's, so either separator ends the folder part.
 */
export function fileFromCommandOutput(output: string | null | undefined): string | null {
  const line = (output ?? "")
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l.startsWith("FILE:"))
    .pop();
  if (!line) return null;
  const name = line.slice("FILE:".length).trim().split(/[\\/]/).pop() ?? "";
  return name || null;
}

/** `NewDesign` (the Studio add-on): a note in the hub's design/. Only what was
 *  given goes on the line -- a note may have no description and name no Space. */
export interface NewDesignFields {
  title: string;
  description?: string;
  space?: string;
}
export function buildNewDesignParams(fields: NewDesignFields): string[] {
  const params = ["-Title", fields.title.trim()];
  if (fields.description?.trim()) params.push("-Description", fields.description.trim());
  if (fields.space?.trim()) params.push("-Space", fields.space.trim());
  return params;
}

/** `NewSpace` (the Studio's + on the Spaces card). Every value the dialog
 *  shows is sent, so what the person saw is what is written; the verb checks each
 *  again and refuses in its own words. `repo` is owner/name, already normalised
 *  (studio/newSpace.ts); with none, the Space is your own cards. */
export interface NewSpaceFields {
  slug: string;
  name: string;
  repo?: string;
}
export function buildNewSpaceParams(fields: NewSpaceFields): string[] {
  const params = ["-Slug", fields.slug.trim(), "-Name", fields.name.trim()];
  if (fields.repo?.trim()) params.push("-Repo", fields.repo.trim());
  return params;
}

/** `RetireSpace` / `RemoveSpace` (a Space's row menu on the Studio's Spaces card).
 *  The slug is positional; `whatIf` is the confirm's preview -- the verb's
 *  own words for what would go and the folder that stays -- and `force` is sent
 *  with a Remove the person has confirmed in that dialog, which named the cards in
 *  current/: the bridge is a caller that cannot answer the verb's own question. */
export interface SpaceLifecycleFields {
  slug: string;
  whatIf?: boolean;
  force?: boolean;
}
export function buildSpaceLifecycleParams(fields: SpaceLifecycleFields): string[] {
  const params = [fields.slug.trim()];
  if (fields.whatIf) params.push("-WhatIf");
  if (fields.force) params.push("-Force");
  return params;
}

/** `NewItem -FromDesign <note>`: Promote a hub design note (the Studio). The
 *  verb takes the issue's title and body from the note, labels it, and writes
 *  the URL back into the note -- so the note's name is the whole argv. */
export function buildPromoteDesignParams(fields: { name: string }): string[] {
  return ["-FromDesign", fields.name];
}

/** `MoveDesign` from the hub drawer (design lifecycle L3): the hub's rows move
 *  through the bridge with `-Hub`, never a native write. The name is the file
 *  the row shows; `-To` is the road; a drop carries its reason, a completion
 *  the path its docs landed in; `-Space` when the design is a Space's own. */
export interface MoveDesignFields {
  name: string;
  to: "Spec" | "Archive" | "Complete";
  dropped?: boolean;
  reason?: string;
  doc?: string;
  space?: string;
}

export function buildMoveDesignParams(fields: MoveDesignFields): string[] {
  const params = [fields.name, "-To", fields.to, "-Hub"];
  if (fields.space?.trim()) params.push("-Space", fields.space.trim());
  if (fields.dropped) params.push("-Dropped");
  if (fields.reason?.trim()) params.push("-Reason", fields.reason.trim());
  if (fields.doc?.trim()) params.push("-Doc", fields.doc.trim());
  return params;
}

/** `MoveDesign -Space <slug>` from the Design tab (#146): a PRODUCT's design,
 *  moved in that Space's checkout on this machine (`spaceCheckouts.<slug>.path`)
 *  -- no `-Hub`, so the verb stages in the clone and never commits. The bridge
 *  runs in the package; `-Space` is how the verb finds the clone, the way
 *  `-Hub` finds the hub. */
export function buildCheckoutMoveDesignParams(
  fields: MoveDesignFields & { space: string },
): string[] {
  const params = [fields.name, "-To", fields.to, "-Space", fields.space.trim()];
  if (fields.dropped) params.push("-Dropped");
  if (fields.reason?.trim()) params.push("-Reason", fields.reason.trim());
  if (fields.doc?.trim()) params.push("-Doc", fields.doc.trim());
  return params;
}

/** The commit line MoveDesign suggests after a staged move, or "" -- the
 *  verb's own words, never retyped here. */
export function suggestedCommitLine(output: string | null | undefined): string {
  const m = /^\s*(git commit -m .+?)\s*$/m.exec(output ?? "");
  return m ? m[1] : "";
}

/** `NewReminder` (the Organize add-on). Only what was given goes on the line:
 *  the verb defaults the source to "manual" and a missing due to none. */
export interface NewReminderFields {
  title: string;
  /** YYYY-MM-DD, YYYY-MM-DDTHH:MM, or a snooze word. */
  due?: string;
  source?: string;
  /** Free text; a card's id here links the reminder to that card
   *  (docs/modules/organize.md, "A ref that names a card"). */
  ref?: string;
}
export function buildNewReminderParams(fields: NewReminderFields): string[] {
  const params = ["-Title", fields.title.trim()];
  if (fields.due?.trim()) params.push("-Due", fields.due.trim());
  if (fields.source?.trim()) params.push("-Source", fields.source.trim());
  if (fields.ref?.trim()) params.push("-Ref", fields.ref.trim());
  return params;
}

/** `Reminders -Id <id> -Snooze <word>`: rewrites **Due:** and nothing else. */
export function buildReminderSnoozeParams(fields: { id: string; word: string }): string[] {
  return ["-Id", fields.id, "-Snooze", fields.word];
}

/** A reminder's editable entry, as the agent serves it and as the Edit dialog
 *  holds it. `due` is exactly the stored shape: "YYYY-MM-DD",
 *  "YYYY-MM-DDTHH:MM", or "" for none. */
export interface ReminderEntry {
  title: string;
  due: string;
  source: string;
  /** "" (or absent) for no ref. */
  ref?: string;
}

/** `Reminders -Id <id> [-Title <t>] [-Due <when> | -NoDue] [-Source <tag>] [-Ref <ref>]`:
 *  corrects the entry. Only what CHANGED goes on the line -- each switch rewrites
 *  its own line, so sending an unchanged one would be a write for nothing.
 *  A due that was set and is now empty is -NoDue; an emptied ref is `-Ref ""`,
 *  which the verb reads as "remove the line". `null` when nothing changed. */
export function buildReminderEditParams(fields: {
  id: string;
  was: ReminderEntry;
  now: ReminderEntry;
}): string[] | null {
  const { was, now } = fields;
  const params = ["-Id", fields.id];
  const title = now.title.trim();
  const due = now.due.trim();
  const source = now.source.trim();
  if (title !== was.title) params.push("-Title", title);
  if (due !== was.due) {
    if (due) params.push("-Due", due);
    else params.push("-NoDue");
  }
  if (source !== was.source) params.push("-Source", source);
  const ref = (now.ref ?? "").trim();
  if (ref !== (was.ref ?? "")) params.push("-Ref", ref);
  return params.length > 2 ? params : null;
}

/** `Reminders -Id <id> -Archive`: moves it to reminders/archive/ and stamps it. */
export function buildReminderArchiveParams(fields: { id: string }): string[] {
  return ["-Id", fields.id, "-Archive"];
}

/** `Standup -Remind <HH:mm> [-Days <Mon,Wed,...>]` (Team Agile): the
 *  reminder to attend, written by Organize's verbs. The days are ONE argv
 *  element, comma-joined -- the script's `[string[]]$Days` takes the list and
 *  splits it again. No days is no `-Days`, and the verb's default (Mon-Fri). */
export function buildStandupRemindParams(fields: { time: string; days: string[] }): string[] {
  const params = ["-Remind", fields.time.trim()];
  if (fields.days.length > 0) params.push("-Days", fields.days.join(","));
  return params;
}

/** `Route <n|id> [-Size <label>] [-Assign <me|size>] [-Milestone <title>] [-Severity <sev>]
 *  [-DeepWater] [-Space <slug>]` (Team Agile triage; Scripts/Set-Route.ps1). The issue
 *  number is the positional argument; each answer given is its own switch, and
 *  the verb makes one `gh issue edit` per switch. A milestone title with spaces
 *  is ONE element. Only what was answered goes on the line. `assign` is who takes
 *  it (D-AR10): `me` makes you the assignee; a size is the -Size write. */
export interface RouteFields {
  number: number;
  size?: string;
  assign?: string;
  milestone?: string;
  severity?: string;
  deepWater?: boolean;
  space?: string;
}
export function buildRouteParams(fields: RouteFields): string[] {
  const params = [String(fields.number)];
  if (fields.size?.trim()) params.push("-Size", fields.size.trim());
  if (fields.assign?.trim()) params.push("-Assign", fields.assign.trim());
  if (fields.milestone?.trim()) params.push("-Milestone", fields.milestone.trim());
  if (fields.severity?.trim()) params.push("-Severity", fields.severity.trim());
  if (fields.deepWater) params.push("-DeepWater");
  if (fields.space?.trim()) params.push("-Space", fields.space.trim());
  return params;
}

/** One of `MeetingAgenda`'s four switches. `Plan`, `Prep` and `Retro` stamp a
 *  stage; `Close` moves the file. They are the script's own spellings. */
export type MeetingAgendaAction = "Plan" | "Prep" | "Retro" | "Close";

export interface MeetingAgendaFields {
  /** YYYY-MM-DD -- the record's date, as the agent serves it (`date`), never
   *  parsed out of the filename here. */
  date: string;
  /** The series: "" (or absent) is the 1:1, which the script calls `1on1` and
   *  takes as its default; anything else is a slug the script validates. */
  series?: string;
  action: MeetingAgendaAction;
}

/**
 * argv for `POST /cmd/MeetingAgenda` -> `Scripts/Get-MeetingAgenda.ps1`.
 *
 * Every parameter is named, in the order the `param()` block declares them:
 * `-Date`, then `-Type`, then the one switch. `-Type` is the series and is sent
 * only for a series that is not the 1:1 -- the script's default is `1on1`, the
 * agent serves the 1:1 as `""`, and sending either spelling would only restate
 * the default. A record's filename is `<series>-YYYY-MM-DD.md` or
 * `YYYY-MM-DD.md`, so date and series together name the file the script acts on.
 *
 * `-Close` is the one that moves a file, which is why the page puts a confirm in
 * front of it and nothing else. The script closes whatever stage the record is
 * in -- it does not check completeness -- so "only a complete session offers
 * Close" is the page's rule, not the script's. A `-Close` on a record already in
 * `archive/` is a report, exit 0; one that finds a duplicate in both folders is a
 * stated refusal, exit 2, which the bridge answers as `status: error` with the
 * sentence in `error`.
 */
export function buildMeetingAgendaParams(fields: MeetingAgendaFields): string[] {
  const params: string[] = ["-Date", fields.date];
  const series = (fields.series ?? "").trim();
  if (series && series !== "1on1") params.push("-Type", series);
  params.push(`-${fields.action}`);
  return params;
}

/** The Resolve Work Item dialog's fields. */
export interface CloseWorkItemFields {
  workItemId: number;
  comment: string;
  /**
   * Omitted entirely when the caller has no reason to state. That is not the
   * same as sending the default: `Close-WorkItem.ps1` branches on
   * `$PSBoundParameters.ContainsKey('Reason')`, so an unsent `-Reason` closes a
   * Bug as Fixed and everything else as Completed, while `-Reason Fixed` on a
   * User Story asks ADO for a reason its process may not accept.
   */
  reason?: string;
}

/**
 * argv for `POST /cmd/CloseItem` -> `Scripts/Close-WorkItem.ps1`.
 *
 * `Id` is Position 0, so the id leads the array bare. `Comment` is declared at
 * Position 1 but is passed by name, as the script's own help and examples do:
 * a comment beginning with `-` would otherwise bind as a parameter name.
 */
export interface EditWorkItemFields {
  id: number;
  title?: string;
  sprint?: string;
  addTag?: string;
  removeTag?: string;
  assignTo?: string;
  /** The tracker's own pin: true pins, false unpins, absent leaves it. */
  pinned?: boolean;
}

/** The edit flow: the same verb the CLI types, through the bridge. */
export function buildEditWorkItemParams(fields: EditWorkItemFields): string[] {
  const params: string[] = [String(fields.id)];
  if (fields.title) params.push("-Title", fields.title);
  if (fields.sprint) params.push("-Sprint", fields.sprint);
  if (fields.addTag) params.push("-AddTag", fields.addTag);
  if (fields.removeTag) params.push("-RemoveTag", fields.removeTag);
  if (fields.assignTo) params.push("-AssignTo", fields.assignTo);
  if (fields.pinned === true) params.push("-Pin");
  if (fields.pinned === false) params.push("-Unpin");
  return params;
}

export function buildCloseWorkItemParams(fields: CloseWorkItemFields): string[] {
  const params: string[] = [String(fields.workItemId), "-Comment", fields.comment];
  if (fields.reason) params.push("-Reason", fields.reason);
  return params;
}

/**
 * One readable line (or two paragraphs) for a `CommandResponse`, whichever of
 * the four statuses came back.
 *
 * `success` shows the command's own stdout. The other three are the bridge's
 * vocabulary, not the retired native routes' ad-hoc error shapes: `rejected`
 * means the bridge refused before running anything -- an unknown command name,
 * a gate -- `timeout` means it ran and was cut off, and `error` means it ran and
 * failed. All three carry `error`, and any of them may also carry the `output`
 * the command managed to print first, which is usually where the CLI's own
 * `[!]` line is.
 */
export function commandResultMessage(result: CommandResponse, successFallback: string): string {
  // Trimmed like the failure path below: a verb may open or close with blank lines, and the
  // dialogs that show this keep line breaks.
  if (result.status === "success") return result.output?.trim() || successFallback;

  const label =
    result.status === "rejected"
      ? "Rejected"
      : result.status === "timeout"
        ? "Timed out"
        : "Failed";
  const detail = result.error?.trim() ?? "";
  const output = result.output?.trim() ?? "";

  const head = detail
    ? `✗ ${label}: ${detail}`
    : output
      ? `✗ ${label}`
      : `✗ ${label}: Unknown error`;

  return output ? `${head}\n\n${output}` : head;
}

// ── The config card ─────────────────────────────────────────────────────────
//
// `PUT /api/config` takes `{ set, unset }` and the agent turns that into the
// two argv tokens the `Config` verb reads -- one `-Set` carrying a JSON object,
// one `-Unset` carrying a JSON array. The bridge splats a flat argv list, so a
// repeated `-Set` cannot survive it and the object form is what carries a batch.
//
// That makes the browser's job exactly one thing: turn a form, where every
// control holds a STRING, back into values of the type the schema declares. It
// is a pure function for the same reason the two builders above are -- the
// contract is pinned by a test rather than discovered against a live write.

/** The types a schema row declares. Mirrors Scripts/Get-ConfigSchema.ps1. */
export type ConfigValueType =
  "string" | "path" | "bool" | "int" | "array" | "enum" | "projects" | "object";

export interface ConfigFieldEdit {
  key: string;
  type: ConfigValueType;
  /** What the control holds. A toggle is "true"/"false"; a select is the value. */
  value: string;
}

export interface ConfigEditPayload {
  set: Record<string, string | boolean | number | string[]>;
  unset: string[];
}

/**
 * The body for `PUT /api/config`.
 *
 * Three rules, and each is a decision rather than a detail:
 *
 * - **A cleared field is an UNSET, not an empty string.** Every machine key is
 *   an override of something -- the shipped default, or the hub -- so emptying
 *   one means "stop overriding", which is `-Unset`. Writing `""` would pin the
 *   empty value instead, and `email: ""` is exactly the config gap this card
 *   exists to close.
 * - **An array field is typed as a comma-separated list**, because that is what
 *   a text input can hold and what `web.corsOrigins` reads as. The value goes
 *   out as a real JSON array, so the CLI never has to parse the browser's
 *   punctuation.
 * - **A bool goes out as a boolean and an int as a number**, so the verb's own
 *   validator sees the type it declared rather than a string it has to guess at.
 */
export function buildConfigEdit(
  edits: ConfigFieldEdit[],
  alsoUnset: string[] = [],
): ConfigEditPayload {
  const set: ConfigEditPayload["set"] = {};
  const unset: string[] = [...alsoUnset];

  for (const edit of edits) {
    const raw = edit.value.trim();
    if (raw === "" && edit.type !== "bool") {
      if (!unset.includes(edit.key)) unset.push(edit.key);
      continue;
    }
    if (edit.type === "bool") {
      set[edit.key] = raw === "true";
    } else if (edit.type === "int") {
      set[edit.key] = Number(raw);
    } else if (edit.type === "array") {
      set[edit.key] = raw
        .split(",")
        .map((part) => part.trim())
        .filter((part) => part.length > 0);
    } else {
      set[edit.key] = raw;
    }
  }

  return { set, unset };
}

/**
 * The keys whose value the agent reads once, at startup, so a change to one
 * genuinely needs `tkAgent -Stop; tkAgent`. Everything else is re-read per
 * request, and the two 45-second caches -- the ADO probe and the resolved
 * identity -- are cleared by the write itself.
 */
export const CONFIG_KEYS_NEEDING_RESTART = ["web.agentPort", "web.corsOrigins"];

/** Whether anything in this payload needs the agent restarted. */
export function configEditNeedsRestart(payload: ConfigEditPayload): boolean {
  const touched = [...Object.keys(payload.set), ...payload.unset];
  return touched.some((key) => CONFIG_KEYS_NEEDING_RESTART.includes(key));
}
