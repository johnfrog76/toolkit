/**
 * The Space anchor: ONE pill at the left of the
 * header, after the wordmark -- a home icon and the Space you are in -- and it
 * IS the Home navigation entry. Click it to go Home; it wears the tabs' active
 * treatment while the location is Home's. The word "Home" left the tab strip;
 * the core workflow still shows, as this anchor.
 *
 * Its FACE is the Space's display name when the Space declares one
 * (`spaces[].name`), the slug otherwise -- the same string the avatar menu's
 * Space list shows. The slug stays everywhere else: the avatar menu's detail
 * line, the hub folder, every verb. This reverses the earlier "slug in the
 * pill" decision for the face only, and the tooltip still carries the slug.
 */
import { Button, Tooltip, makeStyles } from "@fluentui/react-components";
import { HomeFilled, HomeRegular } from "@fluentui/react-icons";
import type { EnvStatus } from "./api";
import type { NavEntry } from "./registry";

type SpaceConfig = Pick<EnvStatus["config"], "activeSpace" | "spaces"> | undefined;

/** What the pill reads, and what its tooltip says. With no Space active the
 *  anchor is the home icon and the entry's own label -- never an empty pill. */
export function spaceFace(
  config: SpaceConfig,
  fallback: string,
): { text: string; tooltip: string; isSpace: boolean } {
  const slug = config?.activeSpace ?? "";
  if (!slug) return { text: fallback, tooltip: fallback, isSpace: false };
  const space = (config?.spaces ?? []).find((s) => s.slug === slug);
  // `name ?? slug`, as the avatar menu's Space list reads it.
  const name = space?.name || slug;
  // Name, slug, address -- in that order, each only where it says something new.
  const parts = [name, ...(name !== slug ? [slug] : []), ...(space?.org ? [space.org] : [])];
  return { text: name, tooltip: parts.join(" · "), isSpace: true };
}

const useStyles = makeStyles({
  pill: {
    // Never wider than the strip: on a phone the face truncates, the icon stays.
    maxWidth: "100%",
    minWidth: 0,
    flexShrink: 1,
  },
  face: {
    display: "inline-block",
    minWidth: 0,
    maxWidth: "14rem",
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
    verticalAlign: "bottom",
    "@media (max-width: 599px)": { maxWidth: "8rem" },
  },
  // Read by a screen reader, not drawn: the icon says "Home" to the eye.
  hidden: {
    position: "absolute",
    width: "1px",
    height: "1px",
    overflow: "hidden",
    clip: "rect(0 0 0 0)",
    whiteSpace: "nowrap",
  },
});

export function SpaceAnchor({
  entry,
  here,
  config,
  onNavigate,
}: {
  entry: NavEntry;
  here: boolean;
  config: SpaceConfig;
  onNavigate: (to: string) => void;
}) {
  const styles = useStyles();
  const face = spaceFace(config, entry.label);
  return (
    <Tooltip content={face.tooltip} relationship="description">
      <Button
        as="a"
        href={entry.to}
        data-space-anchor=""
        className={styles.pill}
        shape="circular"
        size="small"
        // The tabs' active treatment: primary where you are.
        appearance={here ? "primary" : "outline"}
        aria-current={here ? "page" : undefined}
        icon={here ? <HomeFilled /> : <HomeRegular />}
        onClick={(e: React.MouseEvent) => {
          if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button !== 0) return;
          e.preventDefault();
          onNavigate(entry.to);
        }}
      >
        {face.isSpace ? <span className={styles.hidden}>{entry.label}: </span> : null}
        <span className={styles.face}>{face.text}</span>
      </Button>
    </Tooltip>
  );
}
