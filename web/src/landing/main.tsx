import { StrictMode, useCallback, useState } from "react";
import { createRoot } from "react-dom/client";
import { Landing } from "./Landing";
import { CommercialPlayer } from "./Commercial";
import { theToolkitDeck } from "../modules/deck/decks/the-toolkit";
import "./landing.css";

// The landing page's entry: web/landing.html loads this and nothing else of
// the app -- no router, no store, no agent, no /env, no module registry
// (D-LP2). The words are the page's own (copy.ts).

function Page() {
  const [playing, setPlaying] = useState(false);
  const [returned, setReturned] = useState(false);
  const play = useCallback(() => setPlaying(true), []);
  const stop = useCallback(() => {
    setPlaying(false);
    setReturned(true);
  }, []);
  // The deck plays in its own room, alone on the page, so the page's
  // landmarks and the room's are never on screen together.
  if (playing) return <CommercialPlayer onExit={stop} />;
  return <Landing onPlay={play} playLabel={`Play ${theToolkitDeck.title}`} focusCta={returned} />;
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <Page />
  </StrictMode>,
);
