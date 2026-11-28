import { Label, makeStyles, mergeClasses, tokens, useId } from "@fluentui/react-components";
import { RefinedPortrait } from "../../shared/refinedFaces";
import type { FaceId } from "../../shared/refinedFaces";
import { portraitChoices } from "./orgChart";

// A seat's portrait question in the seat dialog (docs/modules/solitaire-agile.md,
// "The web UI"), for any seat that takes one: one radio group, drawn as a grid of
// small portraits, each with its name under it, the seat's own default first. The radios are the browser's own, so the arrow keys move the
// choice and Tab enters and leaves the group as one stop; each is hidden behind
// its tile, and the tile shows the choice and the focus.

const useStyles = makeStyles({
  group: { display: "flex", flexDirection: "column", rowGap: tokens.spacingVerticalXS },
  grid: {
    display: "grid",
    gridTemplateColumns: "repeat(auto-fill, minmax(76px, 1fr))",
    gap: tokens.spacingHorizontalS,
  },
  choice: { position: "relative", display: "block", cursor: "pointer" },
  // The radio itself: still there for the keyboard and a screen reader, drawn by its tile.
  input: {
    position: "absolute",
    opacity: 0,
    width: "1px",
    height: "1px",
    margin: 0,
    ":focus-visible + span": {
      outlineStyle: "solid",
      outlineWidth: "2px",
      outlineColor: tokens.colorStrokeFocus2,
      outlineOffset: "2px",
    },
  },
  tile: {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    rowGap: tokens.spacingVerticalXXS,
    padding: tokens.spacingHorizontalXS,
    borderRadius: tokens.borderRadiusMedium,
    border: `${tokens.strokeWidthThin} solid ${tokens.colorNeutralStroke2}`,
    backgroundColor: tokens.colorNeutralBackground1,
    ":hover": { backgroundColor: tokens.colorNeutralBackground1Hover },
  },
  selected: {
    border: `${tokens.strokeWidthThicker} solid ${tokens.colorCompoundBrandStroke}`,
    backgroundColor: tokens.colorBrandBackground2,
    ":hover": { backgroundColor: tokens.colorBrandBackground2Hover },
  },
  // While the dialog writes: the tiles drawn as the disabled controls they are.
  disabledTile: {
    cursor: "not-allowed",
    opacity: 0.55,
    ":hover": { backgroundColor: tokens.colorNeutralBackground1 },
  },
  disabledChoice: { cursor: "not-allowed" },
  picture: {
    width: "56px",
    height: "58px",
    display: "block",
    borderRadius: tokens.borderRadiusMedium,
  },
  name: {
    fontSize: tokens.fontSizeBase200,
    lineHeight: tokens.lineHeightBase200,
    color: tokens.colorNeutralForeground1,
    textAlign: "center",
  },
});

export function PortraitPicker({
  address,
  value,
  defaultFace,
  onChange,
  disabled = false,
}: {
  /** The seat it edits, <position>.<seat>: what the group's test id names. */
  address: string;
  /** The seat's chosen portrait's id, "" for its default. */
  value: string;
  /** The face the seat draws with no portrait: the default choice draws it. */
  defaultFace: FaceId;
  onChange: (value: string) => void;
  disabled?: boolean;
}) {
  const styles = useStyles();
  const labelId = useId("org-portrait-label");
  const name = useId("org-portrait");
  return (
    <div className={styles.group}>
      <Label id={labelId}>Portrait</Label>
      <div
        role="radiogroup"
        aria-labelledby={labelId}
        className={styles.grid}
        data-testid="org-seat-portrait"
        data-seat={address}
      >
        {portraitChoices(defaultFace).map((c) => {
          const checked = c.value === value;
          return (
            <label
              key={c.value || "default"}
              className={mergeClasses(styles.choice, disabled && styles.disabledChoice)}
              data-disabled={disabled ? "true" : undefined}
              data-testid={`org-portrait-${c.value || "default"}`}
            >
              <input
                type="radio"
                name={name}
                value={c.value}
                checked={checked}
                disabled={disabled}
                onChange={() => onChange(c.value)}
                className={styles.input}
              />
              <span
                className={mergeClasses(
                  styles.tile,
                  checked && styles.selected,
                  disabled && styles.disabledTile,
                )}
              >
                <RefinedPortrait face={c.face} className={styles.picture} />
                <span className={styles.name}>{c.label}</span>
              </span>
            </label>
          );
        })}
      </div>
    </div>
  );
}
