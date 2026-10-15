// The studio's people: three of the cast, one for each way of working, each
// in their own window with one line in their own voice (the design note, "The
// three people", D-LP5). The cast's mottos stay in the stage's cast.tsx;
// these lines are the page's.

import type { WayId } from "./copy";

/** One person on the landing page: who, which way of working, and their line. */
export interface LandingPerson {
  /** A cast id from the stage's cast.tsx. */
  castId: "minimalist" | "pm" | "dev-hero";
  /** The character's title on the stage. */
  title: string;
  /** The way of working this person stands for. */
  way: WayId;
  /** One sentence in the person's own voice. */
  line: string;
}

export const PEOPLE: readonly LandingPerson[] = [
  {
    castId: "minimalist",
    title: "IC",
    way: "alone",
    line: "One card, one file, nothing else open. I like a clean canvas.",
  },
  {
    castId: "pm",
    title: "PM",
    way: "team",
    line: "The board is the board. My cards just stopped drifting from it.",
  },
  {
    castId: "dev-hero",
    title: "Team lead",
    way: "agents",
    line: "Nine of them take the issues. I take the decisions.",
  },
];
