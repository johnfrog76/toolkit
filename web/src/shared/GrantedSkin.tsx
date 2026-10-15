/**
 * The shell WEARS a granted skin; it never chooses one (D-L18; docs/modules/lounge.md,
 * "The Skins dialog, and the grant"). The Lounge's Skins dialog writes the grant
 * (shared/skinGrant.ts is the one owner of the key and its change event) and
 * this layer -- which imports nothing from any module -- renders that
 * document behind every page in this browser: a fixed, fully sandboxed,
 * zero-JavaScript iframe at FULL STRENGTH -- no scrim (the owner: "I don't think
 * the background should dial it back at all"). Legibility is the worn
 * THEME's job: while a grant is on, App dresses the whole product in the
 * skin's own SKIN_THEMES record, whose wood-toned translucent cards are the
 * surfaces the work sits on. The toolkit becomes the room. Shrimp may graze
 * on Billing, at full brightness, under a card that can still be read.
 *
 * Undoing happens where the doing did -- the dialog's No-skin card -- or by
 * picking a theme (D-L17), the everyday way back. This layer has no
 * control, no state of its own, and renders nothing at all when no grant is
 * written -- absent, not disabled.
 */
import { makeStyles } from "@fluentui/react-components";
import { isAnimated, useSkinGrant } from "./skinGrant";

const useStyles = makeStyles({
  // NO negative z-index, on purpose: a negative-z fixed element paints in
  // the ROOT stacking context's negative layer, which sits BELOW in-flow
  // block backgrounds -- and FluentProvider paints the theme's page image on
  // itself as exactly such a background, so the skin rendered invisibly
  // underneath the theme's own wallpaper (found live on the first grant).
  // DOM ORDER is the mechanism instead: this layer is rendered before
  // `.root`, whose position: relative lifts every page above it, so the
  // paint order is provider background -> the skin -> the scrim -> the app.
  frame: {
    position: "fixed",
    inset: 0,
    width: "100%",
    height: "100%",
    border: "none",
    pointerEvents: "none",
  },
});

export function GrantedSkin() {
  const styles = useStyles();
  const grant = useSkinGrant();
  if (!grant) return null;
  // #still is the zero-JS freeze: the document's own body:target rule stops
  // every clock at the resting pose -- and it is the DEFAULT (D-L19: Animate
  // off unless the person turned it on in the Skins dialog). The key makes
  // React remount the frame when it flips, so the fragment is honored on an
  // already-open app.
  const src = isAnimated(grant) ? grant.src : `${grant.src}#still`;
  return (
    <iframe
      key={src}
      className={styles.frame}
      src={src}
      sandbox=""
      title={grant.caption}
      aria-hidden
    />
  );
}
