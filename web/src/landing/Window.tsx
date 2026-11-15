import type { CSSProperties } from "react";
import { RefinedPortrait, quoteColour } from "./refinedFaces";
import type { LandingPerson } from "./people";

// One of the cast on a testimonial card: their portrait in the refined style,
// a dark plate on the picture's edge with their title, and their line under
// it. The portrait is decoration; the plate and the line carry the meaning.

export function Window({ person }: { person: LandingPerson }) {
  const style = { "--lp-quote": quoteColour(person.castId) } as CSSProperties;
  return (
    <figure className="lp-window lp-card" style={style}>
      <div className="lp-card-pic">
        <RefinedPortrait castId={person.castId} />
      </div>
      <p className="lp-card-plate">{person.title}</p>
      <blockquote className="lp-card-line">{person.line}</blockquote>
    </figure>
  );
}
