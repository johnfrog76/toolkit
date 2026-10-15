/**
 * The Skins dialog -- where a skin is chosen, and the only place (D-L18,
 * docs/modules/lounge.md, "The Skins dialog, and the grant"; the owner: "skins live in a dialog
 * ... they are not part of the lounge ... I might have 20 skins").
 *
 * A scrolling grid of cards: NO SKIN first -- the theme underneath, named --
 * then every scene as a frozen `#still` thumb with its caption, the worn one
 * ringed. One click wears a skin product-wide, in this browser, at once (the
 * grant); the No-skin card takes it off in the same place, and so does
 * picking a theme (D-L17). Under the grid, ONE control: Animate, a switch,
 * DEFAULT OFF (D-L19) -- off is the still frame everywhere, on lets the
 * scene's slow clocks run; the OS's reduced-motion still wins (D-L12).
 *
 * Nothing else asks: no scene dropdown, no apply button, no preview stage.
 * The thumbs are the fitting room.
 */
import {
  Caption1,
  Dialog,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  Switch,
  makeStyles,
  mergeClasses,
  tokens,
} from "@fluentui/react-components";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { isAnimated, useSkinGrant, writeSkinGrant } from "../../shared/skinGrant";
import { usePersistedFlag } from "../../shared/usePersistedState";
import { useWornTheme } from "../../hooks/useWornTheme";
import { ALL_SKINS, SKIN_ANIMATE_KEY } from "./skins";

const useStyles = makeStyles({
  grid: {
    display: "grid",
    gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))",
    gap: tokens.spacingHorizontalM,
    maxHeight: "60vh",
    overflowY: "auto",
    paddingRight: tokens.spacingHorizontalXS,
  },
  card: {
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalXS,
    padding: 0,
    background: "transparent",
    border: "none",
    cursor: "pointer",
    textAlign: "left",
    color: tokens.colorNeutralForeground1,
  },
  face: {
    position: "relative",
    aspectRatio: "16 / 9",
    overflow: "hidden",
    borderRadius: tokens.borderRadiusMedium,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
  },
  faceWorn: {
    border: `2px solid ${tokens.colorBrandForeground2}`,
  },
  frame: {
    position: "absolute",
    inset: 0,
    width: "100%",
    height: "100%",
    border: "none",
    pointerEvents: "none",
  },
  // The No-skin card's face: the theme underneath, as a swatch -- its page
  // colour with its brand as a dot, so the card says what "no skin" looks
  // like in this browser without a scene.
  swatch: {
    position: "absolute",
    inset: 0,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
  },
  swatchDot: {
    width: "28%",
    aspectRatio: "1 / 1",
    borderRadius: "50%",
  },
  caption: {
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase100,
    letterSpacing: "0.12em",
    textTransform: "uppercase",
    color: tokens.colorNeutralForeground3,
    whiteSpace: "nowrap",
    overflow: "hidden",
    textOverflow: "ellipsis",
  },
  animateRow: {
    marginTop: tokens.spacingVerticalM,
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: tokens.spacingHorizontalM,
  },
});

export function SkinsDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const styles = useStyles();
  const grant = useSkinGrant();
  const { chosen } = useWornTheme();
  const { value: restingAnimate, setValue: setRestingAnimate } = usePersistedFlag(
    SKIN_ANIMATE_KEY,
    false,
  );
  const animate = grant ? isAnimated(grant) : restingAnimate;

  const setAnimate = (on: boolean) => {
    setRestingAnimate(on);
    // A worn skin follows the switch LIVE -- the wearer remounts its frame.
    if (grant) writeSkinGrant({ ...grant, animate: on, still: undefined });
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(_e, d) => {
        if (!d.open) onClose();
      }}
    >
      <DialogSurface style={{ maxWidth: "760px" }}>
        <DialogBody>
          <DialogTitle action={<DialogDismiss />}>Skins</DialogTitle>
          <DialogContent>
            <div className={styles.grid}>
              <button
                type="button"
                className={styles.card}
                aria-label="No skin"
                aria-pressed={grant === null}
                onClick={() => writeSkinGrant(null)}
              >
                <span className={mergeClasses(styles.face, grant === null && styles.faceWorn)}>
                  <span className={styles.swatch} style={{ background: chosen.page.color }}>
                    <span
                      className={styles.swatchDot}
                      style={{ background: chosen.brand.background }}
                    />
                  </span>
                </span>
                <span className={styles.caption}>no skin · {chosen.name.toLowerCase()}</span>
              </button>
              {ALL_SKINS.map(({ skinId, scene }) => {
                const worn = grant?.src === scene.src;
                return (
                  <button
                    key={scene.id}
                    type="button"
                    className={styles.card}
                    aria-label={`Wear ${scene.caption.split(" · ")[0]}`}
                    aria-pressed={worn}
                    onClick={() =>
                      writeSkinGrant({ skinId, src: scene.src, caption: scene.caption, animate })
                    }
                  >
                    <span className={mergeClasses(styles.face, worn && styles.faceWorn)}>
                      {/* sandbox="" -- the documents carry zero JavaScript by
                          construction, and the sandbox makes that a browser
                          guarantee; #still is the zero-JS freeze, so the wall
                          of thumbs runs no clocks at all. */}
                      <iframe
                        className={styles.frame}
                        src={`${scene.src}#still`}
                        sandbox=""
                        title={scene.caption}
                        tabIndex={-1}
                        aria-hidden
                      />
                    </span>
                    <span className={styles.caption}>{scene.caption}</span>
                  </button>
                );
              })}
            </div>
            <div className={styles.animateRow}>
              <Caption1>A worn skin holds still unless you let it move.</Caption1>
              <Switch
                label="Animate"
                checked={animate}
                onChange={(_e, d) => setAnimate(d.checked)}
              />
            </div>
          </DialogContent>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
