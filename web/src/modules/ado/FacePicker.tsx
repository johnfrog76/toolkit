import { Body1Strong, Caption2, Subtitle2, tokens } from "@fluentui/react-components";
import { makeStyles, mergeClasses } from "@griffel/react";
import { PageCard } from "../../shared/PageCard";
import { FACES } from "../../shared/faces";
import { useFacePref } from "../../hooks/useFacePref";
import { useWornTheme } from "../../hooks/useWornTheme";
import type { Face } from "../../shared/faces";

const useStyles = makeStyles({
  grid: {
    display: "grid",
    // auto-fit, not a fixed four: `1fr` is minmax(auto, 1fr), so four columns
    // could never be narrower than their widest tile and the card ran past a
    // 430px viewport with Kitty and Stoic clipped. This wraps instead.
    gridTemplateColumns: "repeat(auto-fit, minmax(72px, 1fr))",
    gap: "1rem 2rem",
    margin: "2rem auto",
    // Full width, explicitly: an auto-fit track list in a shrink-to-fit box
    // resolves to ONE column, which turned the picker into a 12-row tower on a
    // phone. The card is the width; the tracks fill it.
    width: "100%",
    // ...but no wider than four tiles. auto-fit alone would put five across a
    // desktop card, and desktop was not the defect -- the phone was. Centred by
    // the auto margin above.
    maxWidth: "26rem",
  },
  tile: {
    minWidth: 0,
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: tokens.spacingVerticalXS,
    padding: tokens.spacingVerticalS,
    borderRadius: tokens.borderRadiusMedium,
    border: `2px solid transparent`,
    cursor: "pointer",
    background: "transparent",
    transition: "background 0.15s, border-color 0.15s",
    ":hover": {
      background: tokens.colorNeutralBackground2Hover,
    },
  },
  tileSelected: {
    background: tokens.colorNeutralBackground2,
  },
  circle: {
    width: "48px",
    height: "48px",
    borderRadius: "50%",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    fontSize: "22px",
    userSelect: "none",
    flexShrink: 0,
  },
  faceChar: {
    display: "inline-block",
    lineHeight: 1,
    fontWeight: "400",
  },
  name: {
    color: tokens.colorNeutralForeground2,
  },
  nameSelected: {
    color: tokens.colorBrandForeground1,
    fontWeight: "600",
  },
  hint: {
    color: tokens.colorNeutralForeground4,
    paddingTop: tokens.spacingVerticalXS,
  },
});

interface FaceTileProps {
  face: Face;
  selected: boolean;
  blobColor: string;
  onSelect: () => void;
}

function FaceTile({ face, selected, blobColor, onSelect }: FaceTileProps) {
  const styles = useStyles();
  const { theme } = useWornTheme();
  const cfg = theme === "dark" ? face.dark : face.light;

  const rotate = cfg.rotate === "0deg" ? undefined : `rotate(${cfg.rotate})`;

  return (
    <button
      className={mergeClasses(styles.tile, selected && styles.tileSelected)}
      onClick={onSelect}
      title={face.name}
      type="button"
      // A set of toggles where exactly one is on: the pressed state is how a
      // screen reader hears which face is current.
      aria-pressed={selected}
    >
      <div className={styles.circle} style={{ backgroundColor: blobColor }}>
        {/* The face is DRAWN with characters (Smooch's mouth is a 3); the
            tile's name is the accessible text, so the drawing is decorative. */}
        <span
          className={styles.faceChar}
          style={rotate ? { transform: rotate } : undefined}
          aria-hidden
        >
          {cfg.content}
        </span>
      </div>
      <Caption2 className={mergeClasses(styles.name, selected && styles.nameSelected)}>
        {face.name}
      </Caption2>
    </button>
  );
}

export function FacePicker() {
  const styles = useStyles();
  const { faceId, setFaceId } = useFacePref();
  const { active } = useWornTheme();

  const blobColor = active.logo;

  return (
    // No count badge: the card lives in the Lounge (spec D-L24), where no
    // numeral stands, and a count of faces was a number for its own sake.
    <PageCard headerLeft={<Subtitle2>Face</Subtitle2>}>
      <Body1Strong className={styles.hint}>
        Your ToolKit&apos;s got moods. Pick the one that matches yours today!
      </Body1Strong>
      <div className={styles.grid}>
        {FACES.map((face) => (
          <FaceTile
            key={face.id}
            face={face}
            selected={faceId === face.id}
            blobColor={blobColor}
            onSelect={() => setFaceId(face.id)}
          />
        ))}
      </div>
    </PageCard>
  );
}
