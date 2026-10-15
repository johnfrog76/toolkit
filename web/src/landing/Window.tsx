import { useEffect } from "react";
import {
  CAST,
  CastScene,
  REDUCED_MOTION_RULE,
  STAGE_CLASS,
  StandupKeyframes,
  ZoomTile,
} from "../modules/solitaireAgile/stage/cast";
import type { LandingPerson } from "./people";

// One of the cast in their own Zoom window, the standup's tile with the
// figure's scene parked, and their line in a bubble: the person delivers it.

export function Window({ person }: { person: LandingPerson }) {
  const member = CAST.find((c) => c.id === person.castId)!;
  return (
    <div className={`lp-window ${STAGE_CLASS}`}>
      <div className="lp-window-tile">
        <ZoomTile tint={member.tint} label={member.label} pillState="green">
          <CastScene id={person.castId} parked />
        </ZoomTile>
        <figure className="lp-bubble">
          <blockquote>{person.line}</blockquote>
        </figure>
      </div>
    </div>
  );
}

/** The stage's keyframes and reduced-motion rule, once on the page. */
export function WindowStyles() {
  useEffect(() => {
    const style = document.createElement("style");
    style.textContent = REDUCED_MOTION_RULE;
    document.head.appendChild(style);
    return () => style.remove();
  }, []);
  return <StandupKeyframes />;
}
