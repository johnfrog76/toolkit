import { Caption1, Subtitle2, makeStyles, mergeClasses, tokens } from "@fluentui/react-components";
import { useCurrentTheme } from "../hooks/useCurrentTheme";
import { useSkinGrant, writeSkinGrant } from "../shared/skinGrant";
import { THEMES } from "./themeList";
import type { ToolkitTheme } from "./themeList";

// Choosing a theme IS the preview: it applies at once, to the whole page, and
// there is nothing to save. It is this browser's preference -- like the Face --
// and never reaches config or the agent, so it does not belong to the batched
// Save at the foot of the drawer and never reports "unsaved".

const useStyles = makeStyles({
  section: { display: "flex", flexDirection: "column", gap: tokens.spacingVerticalS },
  lede: { color: tokens.colorNeutralForeground2 },
  columns: {
    display: "grid",
    gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
    gap: tokens.spacingHorizontalM,
  },
  column: { display: "flex", flexDirection: "column", gap: tokens.spacingVerticalXS, minWidth: 0 },
  columnLabel: {
    color: tokens.colorNeutralForeground3,
    textTransform: "uppercase",
    letterSpacing: "0.04em",
  },
  option: {
    display: "grid",
    gridTemplateColumns: "44px minmax(0, 1fr)",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalS,
    padding: tokens.spacingVerticalXS,
    textAlign: "left",
    font: "inherit",
    color: "inherit",
    cursor: "pointer",
    backgroundColor: "transparent",
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusMedium,
    ":hover": { backgroundColor: tokens.colorNeutralBackground1Hover },
    ":focus-visible": { outline: `2px solid ${tokens.colorStrokeFocus2}`, outlineOffset: "1px" },
  },
  chosen: {
    border: `2px solid ${tokens.colorBrandStroke1}`,
    padding: `calc(${tokens.spacingVerticalXS} - 1px)`,
    backgroundColor: tokens.colorNeutralBackground1,
  },
  // The theme in miniature: its page, a card on it, its accent, its face.
  swatch: {
    position: "relative",
    width: "44px",
    height: "32px",
    borderRadius: tokens.borderRadiusSmall,
    overflow: "hidden",
    border: `1px solid ${tokens.colorNeutralStroke2}`,
  },
  swatchCard: {
    position: "absolute",
    left: "6px",
    right: "6px",
    top: "12px",
    bottom: "5px",
    borderRadius: "2px",
  },
  swatchAccent: {
    position: "absolute",
    left: "9px",
    top: "16px",
    width: "12px",
    height: "5px",
    borderRadius: "2px",
  },
  swatchFace: {
    position: "absolute",
    left: "5px",
    top: "3px",
    width: "7px",
    height: "7px",
    borderRadius: "50%",
  },
  words: { display: "flex", flexDirection: "column", minWidth: 0 },
  name: { fontWeight: tokens.fontWeightSemibold },
  blurb: { color: tokens.colorNeutralForeground3 },
});

function Swatch({ theme }: { theme: ToolkitTheme }) {
  const styles = useStyles();
  const card =
    theme.card ?? (theme.mode === "dark" ? "rgba(255,255,255,0.10)" : "rgba(255,255,255,0.55)");
  return (
    <span
      className={styles.swatch}
      style={{ backgroundColor: theme.page.color, backgroundImage: theme.page.image }}
      aria-hidden
    >
      <span className={styles.swatchFace} style={{ backgroundColor: theme.logo }} />
      <span className={styles.swatchCard} style={{ backgroundColor: card }} />
      <span className={styles.swatchAccent} style={{ backgroundColor: theme.brand.background }} />
    </span>
  );
}

export function ThemePicker() {
  const styles = useStyles();
  const { active, setThemeId } = useCurrentTheme();
  const skinGrant = useSkinGrant();

  const column = (mode: ToolkitTheme["mode"], label: string) => (
    <div className={styles.column} role="group" aria-label={`${label} themes`}>
      <Caption1 className={styles.columnLabel}>{label}</Caption1>
      {THEMES.filter((t) => t.mode === mode).map((t) => (
        <button
          key={t.id}
          type="button"
          className={mergeClasses(styles.option, t.id === active.id && styles.chosen)}
          aria-pressed={t.id === active.id}
          onClick={() => {
            // Same rule as the avatar menu (D-L17): picking a theme takes a
            // worn skin off and sends it home to the Lounge.
            if (skinGrant) writeSkinGrant(null);
            setThemeId(t.id);
          }}
        >
          <Swatch theme={t} />
          <span className={styles.words}>
            <span className={styles.name}>{t.name}</span>
            <Caption1 className={styles.blurb}>{t.blurb}</Caption1>
          </span>
        </button>
      ))}
    </div>
  );

  return (
    <section className={styles.section} aria-labelledby="settings-theme-heading">
      <Subtitle2 id="settings-theme-heading" as="h3">
        Theme
      </Subtitle2>
      <Caption1 className={styles.lede}>
        Pick one and the page changes at once. It is remembered in this browser; nothing to save.
      </Caption1>
      <div className={styles.columns}>
        {column("dark", "Dark")}
        {column("light", "Light")}
      </div>
    </section>
  );
}
