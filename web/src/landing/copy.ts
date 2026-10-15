// The landing page's words. Written for a visitor who has installed nothing,
// and kept apart from the README on purpose: the README is the front door on
// GitHub and this is the front door on the web, each crafted for its reader
// (the design note, D-LP1 as revised). Edit here; nothing reads the README.

export type WayId = "alone" | "team" | "agents";

export const COPY = {
  /** The offering, in the banner. */
  offering: "The many faces of ToolKit: work by yourself, on a team, or with agents.",
  bullets: ["Your Space", "Your Work", "Your Studio"],
  /** Under the many faces. */
  facesLine: "How you work is up to you.",
  /** The eyebrow over the three ways. */
  eyebrow: "ToolKit supports your vibe",
  ways: [
    {
      id: "alone" as WayId,
      heading: "Work by yourself",
      text: "Plain Markdown prompt cards, one per piece of work. Works offline, with no login, no network call and no tracker.",
    },
    {
      id: "team" as WayId,
      heading: "Work on a team",
      text: "The same cards, linked one to one with the items on your GitHub or Azure DevOps board, so your local context and the team's board stay in step.",
    },
    {
      id: "agents" as WayId,
      heading: "Work with agents",
      text: "The Team Agile tab, the standup and triage over the repository's issues, and the Studio's prompts for the way you work, so a crew of agents can take issues, open pull requests and report back while you decide.",
    },
  ],
  quickStartHeading: "Quick start",
  quickStart: [
    "Import-Module ./utilities.psm1 -Force                   # this shell",
    "tkInstallAutoload                                       # every future shell",
    "tkStart                                                 # a hub of sample cards, and the web UI open",
    'tkNewPrompt -Title "Timeout on large files" -Type Bug   # a card of your own, no tracker needed',
    "tkStatus                                                # every open card and its derived state",
  ],
  repository: "https://github.com/johnfrog76/toolkit",
  documents: [
    { label: "Quick start", path: "docs/QUICKSTART.md" },
    { label: "Configuration", path: "docs/CONFIGURATION.md" },
    { label: "The CLI", path: "docs/CLI.md" },
    { label: "Testing", path: "docs/TESTING.md" },
    { label: "The agent and the web UI", path: "docs/ARCHITECTURE.md" },
    { label: "The modules", path: "docs/modules/README.md" },
    { label: "Known gaps", path: "docs/KNOWN-GAPS.md" },
    { label: "Contributing", path: "docs/CONTRIBUTING.md" },
    { label: "Third-party notices", path: "THIRD-PARTY-NOTICES.md" },
    { label: "Security", path: "SECURITY.md" },
    { label: "License", path: "LICENSE" },
  ],
  /** Where the baked clips can play, the page says they are synthetic. */
  narration:
    "The commercial is read by synthetic voices: Azure neural text-to-speech, baked from the deck's own lines.",
} as const;

export type LandingCopy = typeof COPY;

/** A file's address in the repository. */
export function fileUrl(repository: string, path: string): string {
  return `${repository}/blob/HEAD/${path}`;
}
