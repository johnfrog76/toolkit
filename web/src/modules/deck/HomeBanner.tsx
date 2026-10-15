import { useMemo, useState } from "react";
import type { MouseEvent } from "react";
import { Button, makeStyles, mergeClasses, tokens } from "@fluentui/react-components";
import { DismissRegular } from "@fluentui/react-icons";
import { useNavigate } from "react-router";
import { useWriteConfigMutation } from "../ado/api.ado";
import { CONTENT_PANEL_INSET, DECK_BG } from "./engine/SlideRenderer";
import { theToolkitDeck } from "./decks/the-toolkit";
import { MEDIA } from "./media";
import { SlidePoster } from "./SlidePoster";
import { STILL_POSTERS_CLASS, useStillPostersCss } from "./stillPosters";

// The first-run banner: Introducing ToolKit's first slide,
// an offer to watch it, and a way to say no -- and either answer "writes
// something to the config so it no longer exists". That is
// `firstRun.welcome=false`, through PUT /api/config -> `Config -Set`, the one
// writer; tkStart is what set it true. It is the deck module's contribution to
// Home's `home-banner` slot, so with the deck module off there is no banner and
// Home imports nothing from here. The registry only asks for it once /env says
// `firstRunWelcome`, so it never flashes before /env answers. It offered Meet
// the Toolkit, Kit's draft tour, until the owner swapped in the
// finished, narrated commercial.
//
// Shaped like the Wasteland's home hero (WastelandHome.tsx
// and PosterCard.tsx), minus the carousel (the owner: "bigger and more
// integrated ... the CTA is built into the banner"): the slide IS the banner --
// its own eyebrow, title and lead are the copy, so there is no card header and
// no second paragraph -- in the Wasteland's 3:1 letterbox from md up and the
// whole 16:9 frame below it. Two controls are built into it, over the art:
// the close x top right and Get Started bottom right.
// The art holds still (stillPosters.tsx): a slide's animations run in the
// player, never in the banner.

const FIRST_RUN_WELCOME_KEY = "firstRun.welcome";

const useStyles = makeStyles({
  banner: {
    position: "relative",
    overflow: "hidden",
    cursor: "pointer",
    borderRadius: tokens.borderRadiusMedium,
    border: `${tokens.strokeWidthThin} solid ${tokens.colorNeutralStroke1}`,
    backgroundColor: DECK_BG,
    // Twice the gap between the board's lanes (Board.tsx, `lanes`), so the
    // banner reads as its own block above Home rather than the first row of it
    // (the owner, UAT).
    marginBottom: `calc(2 * ${tokens.spacingHorizontalM})`,
    // The whole authored frame on a phone; the cinematic letterbox once the
    // banner is wide enough to read as one (the Wasteland's hero, same tier).
    aspectRatio: "16 / 9",
    [MEDIA.md]: { aspectRatio: "3 / 1" },
    ":focus-visible": {
      outline: `${tokens.strokeWidthThick} solid ${tokens.colorStrokeFocus2}`,
      outlineOffset: "2px",
    },
  },
  // SlidePoster positions itself against its offset parent, so the freeze
  // wrapper has to fill the banner rather than collapse to nothing.
  poster: { position: "absolute", inset: 0 },
  play: {
    position: "absolute",
    right: tokens.spacingHorizontalL,
    bottom: tokens.spacingVerticalL,
    // A soft scrim keeps the label readable wherever it lands on the slide.
    boxShadow: `0 4px 20px ${DECK_BG}`,
  },
  // Closed the way a dialog is: an x, top right, no label.
  // On its own ground, because the art under it is whatever the slide drew.
  dismiss: {
    position: "absolute",
    top: tokens.spacingVerticalS,
    right: tokens.spacingHorizontalS,
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
  },
});

export function HomeBanner() {
  const styles = useStyles();
  const navigate = useNavigate();
  const [writeConfig] = useWriteConfigMutation();
  useStillPostersCss();
  // Gone the moment it is answered; /env catches up when the write lands.
  const [answered, setAnswered] = useState(false);
  const poster = useMemo(() => theToolkitDeck.slides()[0], []);
  if (answered) return null;

  const answer = (then?: () => void) => {
    setAnswered(true);
    void writeConfig({ set: { [FIRST_RUN_WELCOME_KEY]: false }, unset: [] });
    then?.();
  };
  const watch = () => answer(() => navigate(`/deck/${theToolkitDeck.id}`));
  // The controls sit inside a banner that is itself a click target.
  const only = (fn: () => void) => (e: MouseEvent) => {
    e.stopPropagation();
    fn();
  };

  return (
    <section className={styles.banner} aria-label={theToolkitDeck.title} onClick={watch}>
      <div className={mergeClasses(styles.poster, STILL_POSTERS_CLASS)}>
        <SlidePoster slide={poster} bleedLeft={CONTENT_PANEL_INSET} />
      </div>
      <Button className={styles.play} appearance="primary" onClick={only(watch)}>
        Get Started
      </Button>
      <Button
        className={styles.dismiss}
        appearance="subtle"
        size="small"
        icon={<DismissRegular />}
        aria-label="Hide the Introducing ToolKit banner"
        onClick={only(() => answer())}
      />
    </section>
  );
}

export default HomeBanner;
