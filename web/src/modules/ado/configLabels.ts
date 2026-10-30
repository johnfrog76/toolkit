// What a setting is CALLED, and one sentence on what it does for you.
//
// The schema (served by /api/config/schema, owned by the Config verb) says what
// a key IS, in the CLI's words: "-Hub", "SwitchSpace", "D-CM". That is right for
// `Config -List` and wrong for a drawer someone opens to change their email. A
// label is a literal only this half types, so it lives in this half
// (consts.json, "WHAT DOES NOT GO HERE"). A key with no entry here still works:
// it shows under its own name with the schema's help, so a new key is never
// hidden -- only plain until someone names it.

export interface SettingWords {
  label: string;
  hint: string;
  /** The switch says the OPPOSITE of the key: on means the key is false. For a
   *  key that is named for showing something, drawn as the "Hide ..." a person
   *  is actually choosing. The file still holds the key. */
  inverted?: boolean;
}

// Keyed by SCHEMA key, so `spaces.<slug>.name` names that field for every Space.
const WORDS: Record<string, SettingWords> = {
  email: {
    label: "Your work email",
    hint: "How the Toolkit finds your Azure DevOps work items and pull requests. Leave it empty to use the account you are signed in to Azure with.",
  },
  branchUser: {
    label: "Your name on branches",
    hint: "Goes in front of every branch the Toolkit names for you, and is the name on your avatar.",
  },
  activeSpace: {
    label: "Space you are working in",
    hint: "Every page and every command shows this Space's cards.",
  },
  promptsRoot: {
    label: "Hub folder",
    hint: "The folder your cards are kept in. It is yours, and separate from the Toolkit itself.",
  },
  wsRoot: {
    label: "Code folder",
    hint: "Where your code repositories are checked out, so the Toolkit can find a project's repo.",
  },
  commandPrefix: {
    label: "Command prefix",
    hint: "What every command starts with in the terminal. Change it and every command is renamed with it.",
  },
  storeSync: {
    label: "How the hub is backed up",
    hint: "git commits and pushes your cards when you sync. none leaves the folder alone.",
  },
  isDemoDismissed: {
    label: "Hide Demo",
    hint: "The sample Spaces the Toolkit ships with -- Demo, the GitHub demo and the Azure demo -- leave the Space lists, so they stop getting in your way. Nothing is deleted: the one you are working in always shows, and turning this off brings them back.",
  },
  "firstRun.welcome": {
    label: "Hide Overview Deck",
    hint: "The banner on Home that offers Introducing ToolKit, a short narrated deck. It hides itself once you watch it or close it; turn this off to bring it back.",
    inverted: true,
  },
  quietStart: {
    label: "Quiet terminal start",
    hint: "Skip the banner the Toolkit prints when a terminal opens.",
  },
  suppressDeprecationHints: {
    label: "Hide renamed-command hints",
    hint: "Stop the one-time note you get when you use a command's old name.",
  },
  "web.agentPort": {
    label: "Agent port",
    hint: "The local port this page talks to the Toolkit through. Change it only if something else needs 4100.",
  },
  "web.corsOrigins": {
    label: "Allowed page addresses",
    hint: "For developing the web UI itself: which dev-server addresses may call the agent. Comma separated.",
  },
  "ai.model": {
    label: "Model for drafts and reviews",
    hint: "The model id behind Suggest a reply, the notes tidy-up, AddPRReview and the standup's dressed sentences. The key itself stays in your environment as ANTHROPIC_API_KEY.",
  },
  "features.growth": {
    label: "Growth",
    hint: "Reviews of your work, goals and your skills page. Adds the Growth tab.",
  },
  "features.communication": {
    label: "Meetings",
    hint: "Agendas and retros for your 1:1s. Adds the Meetings tab.",
  },
  "features.ado": {
    label: "Azure DevOps",
    hint: "Show the Azure DevOps parts of the Toolkit: work items, pull requests and review comments. Leave it unset and it follows the Space you are in -- shown when that Space talks to Azure DevOps, put away when it works from your cards alone.",
  },
  "features.deck": {
    label: "Decks",
    hint: "Present a narrated slide deck from the Toolkit. Adds Decks to the Growth tab.",
  },
  "aliases.<name>.path": {
    label: "Shortcut",
    hint: "A folder you jump to from the terminal by name. A shortcut with no folder is switched off.",
  },
  "spaceCheckouts.<slug>.path": {
    label: "This Space's checkout",
    hint: "Where this Space's repository is cloned on this machine. With it, a product design's menu on the Design tab moves the design in that clone -- staged for you to commit, never committed for you.",
  },
  "spaces.<slug>.name": {
    label: "Display name",
    hint: "What this Space is called in the header and in lists.",
  },
  "spaces.<slug>.status": {
    label: "Status",
    hint: "active talks to the tracker its address names -- GitHub or Azure DevOps. local works from your cards alone. archive is a finished engagement, kept for looking back.",
  },
  "spaces.<slug>.orgType": {
    label: "Kind of work",
    hint: "An engagement for a client, or your own portfolio. Reports read it; nothing else changes.",
  },
  "spaces.<slug>.org": {
    label: "Tracker address",
    hint: "The Space's address -- https://github.com/you/your-repo for GitHub issues, https://dev.azure.com/your-org for Azure DevOps. The address decides which tracker the Space talks to.",
  },
  "spaces.<slug>.tenant": {
    label: "Azure tenant ID",
    hint: "Which directory to sign in to for this Space. Needed only when it is not your default.",
  },
  "spaces.<slug>.promptsFolder": {
    label: "Folder in the hub",
    hint: "The folder inside your hub that holds this Space's cards.",
  },
  "spaces.<slug>.features.trainingHoursPerQuarter": {
    label: "Training hours each quarter",
    hint: "If this Space's engagement requires training every quarter, the hours. The Growth page counts the trainings dated this quarter against it. Leave it empty for no requirement.",
  },
  "spaces.<slug>.howIWork": {
    label: "How you work here",
    hint: "On a GitHub Space: agents turns Team Agile on in this Space (its own switch still has to be on); alone keeps it off. An Azure DevOps Space is on a team and a Space with no tracker is alone -- both follow from the address.",
  },
  "spaces.<slug>.features.sprintAwareness": {
    label: "This team works in sprints",
    hint: "Show sprint names and sprint charts in this Space. Switch it off for a team that works without sprints.",
  },
};

/** `aliases.Hub.path` -> `aliases.<name>.path`; `spaces.demo.name` -> `spaces.<slug>.name`;
 *  `spaceCheckouts.demo.path` -> `spaceCheckouts.<slug>.path`. */
export function schemaKeyOf(key: string): string {
  const alias = /^aliases\.[^.]+\.(.+)$/.exec(key);
  if (alias) return `aliases.<name>.${alias[1]}`;
  const checkout = /^spaceCheckouts\.[^.]+\.(.+)$/.exec(key);
  if (checkout) return `spaceCheckouts.<slug>.${checkout[1]}`;
  const org = /^spaces\.[^.]+\.(.+)$/.exec(key);
  if (org) return `spaces.<slug>.${org[1]}`;
  return key;
}

export function wordsFor(key: string, schemaHelp: string): SettingWords & { named: boolean } {
  const words = WORDS[schemaKeyOf(key)];
  if (!words) return { label: key, hint: schemaHelp, named: false };
  // A shortcut's label carries its own name: "Shortcut: Hub".
  const alias = /^aliases\.([^.]+)\.path$/.exec(key);
  return { ...words, label: alias ? `${words.label}: ${alias[1]}` : words.label, named: true };
}

/** Every schema key this file names -- so a test can tell a typo from a new key. */
export const NAMED_SCHEMA_KEYS = Object.keys(WORDS);
