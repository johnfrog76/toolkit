import { Badge, Caption1, makeStyles, tokens } from "@fluentui/react-components";
import { GlobeRegular } from "@fluentui/react-icons";
import { useGetSpaceVisibilityQuery } from "../shell/api";
import { VISIBILITY } from "../shell/consts";

// A repository's visibility, as a person reads it -- GitHub's own grammar:
// the word `Public` or `Private` beside the repository's name. One copy, read by
// the New Space dialog's picker (gh's PUBLIC | PRIVATE | INTERNAL), the Spaces
// card's GitHub rows and the active Space's name (the agent's public | private |
// unknown, shell/consts.ts VISIBILITY). Public is the one that draws the eye;
// unknown is said as unknown, never hidden and never guessed.

/** True when the word -- gh's or the agent's, any case -- says public. */
export function isPublicVisibility(v: string | undefined): boolean {
  return (v ?? "").toLowerCase() === VISIBILITY.public;
}

/** `Public`, `Private`, `Internal`, `Visibility unknown`; "" for no visibility at all
 *  (a Space whose tracker is not GitHub, or a repository gh said nothing about). */
export function visibilityLabel(v: string | undefined): string {
  const s = (v ?? "").toLowerCase();
  if (!s) return "";
  if (s === VISIBILITY.unknown) return "Visibility unknown";
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/** True when the Space you are in is a GitHub Space whose repository is public
 *  -- what every write surface asks before it carries the line. Asks
 *  GET /api/visibility only when `onGithub`; unknown and private are false. */
export function useActiveSpaceIsPublic(onGithub: boolean): boolean {
  const { data } = useGetSpaceVisibilityQuery("", { skip: !onGithub });
  return onGithub && isPublicVisibility(data?.visibility);
}

const useLineStyles = makeStyles({
  line: {
    display: "inline-flex",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalXS,
    color: tokens.colorPaletteMarigoldForeground2,
  },
});

/** The one line a write to a public repository carries:
 *  "This repository is public". Said, never asked: no confirmation follows it.
 *  Draws nothing when `show` is false. */
export function PublicLine({ show }: { show: boolean }) {
  const styles = useLineStyles();
  if (!show) return null;
  return (
    <Caption1 className={styles.line} role="note">
      <GlobeRegular aria-hidden="true" />
      {VISIBILITY.publicLine}
    </Caption1>
  );
}

/** The pill: an outline Badge, `informative` for public and `subtle` otherwise.
 *  Draws nothing when there is no visibility to state. */
export function VisibilityBadge({ visibility }: { visibility: string | undefined }) {
  const label = visibilityLabel(visibility);
  if (!label) return null;
  return (
    <Badge
      appearance="outline"
      size="small"
      color={isPublicVisibility(visibility) ? "informative" : "subtle"}
    >
      {label}
    </Badge>
  );
}
