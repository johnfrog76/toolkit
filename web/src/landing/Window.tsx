import type { CSSProperties } from "react";
import { RefinedPortrait } from "../shared/refinedFaces";
import type { LandingPerson } from "./people";

// One of the cast on a testimonial card: their portrait in the refined style,
// a dark plate on the picture's edge with their title, and their line under
// it. The portrait is decoration; the plate and the line carry the meaning.
// The faces are the shared refined cast's (shared/refinedFaces.tsx); the
// quote mark's colour is the card's own.

/** Each person's opening quote mark, a shade of their picture. */
const QUOTE: Record<LandingPerson["castId"], string> = {
  minimalist: "#6c727c",
  pm: "#916067",
  "dev-hero": "#586d9c",
};

/** The colour of a person's opening quote mark, for the card to wear. */
export function quoteColour(castId: LandingPerson["castId"]): string {
  return QUOTE[castId];
}

export function Window({ person }: { person: LandingPerson }) {
  const style = { "--lp-quote": quoteColour(person.castId) } as CSSProperties;
  return (
    <figure className="lp-window lp-card" style={style}>
      <div className="lp-card-pic">
        <RefinedPortrait face={person.castId} className="lp-card-portrait" />
      </div>
      <p className="lp-card-plate">{person.title}</p>
      <blockquote className="lp-card-line">{person.line}</blockquote>
    </figure>
  );
}
