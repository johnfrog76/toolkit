import { Caption1, makeStyles, tokens } from "@fluentui/react-components";
import { ImageOffRegular } from "@fluentui/react-icons";
import { STAMPS } from "../../shell/consts";

// A card's pictures (docs/hub/cards.md, "A card's pictures"): the cover on
// the board's card face, a thumbnail in the Home list's meta line, and the cover
// -- or Before and After side by side -- on the card page.
//
// The agent serves `cover` and `before` as URLs of GET /api/assets/..., or null
// (agent/core/assets.py). Null is the whole of "no picture": no line, a file that
// is missing, a path outside the Space's assets/. So a card with no cover draws
// NOTHING here -- no slot, no gap -- and its face is exactly what it was before
// covers existed. Attaching one is the CLI's `Cover` verb; this cut has no
// control for it in the browser (see AttachCover.tsx).
//
// The face and the thumbnail are a background, not an <img>: an image inside a
// draggable card is itself draggable, and the board's drag must carry the card.

const useStyles = makeStyles({
  // Full width of the card face, edge to edge, fixed 16:10, cropped to fit. The
  // negative margin undoes the card's own padding so the picture is the card's top.
  face: {
    margin: `calc(-1 * ${tokens.spacingVerticalS}) calc(-1 * ${tokens.spacingVerticalS}) 0`,
    aspectRatio: "16 / 10",
    backgroundSize: "cover",
    backgroundPosition: "center top",
    backgroundRepeat: "no-repeat",
    backgroundColor: tokens.colorNeutralBackground3,
    borderTopLeftRadius: tokens.borderRadiusMedium,
    borderTopRightRadius: tokens.borderRadiusMedium,
    borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
  },
  // Small, inside the meta line: a row without one does not move.
  thumb: {
    width: "40px",
    aspectRatio: "16 / 10",
    flex: "0 0 auto",
    backgroundSize: "cover",
    backgroundPosition: "center top",
    backgroundRepeat: "no-repeat",
    backgroundColor: tokens.colorNeutralBackground3,
    borderRadius: tokens.borderRadiusSmall,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    alignSelf: "center",
  },
  pictures: {
    display: "grid",
    gridTemplateColumns: "repeat(auto-fit, minmax(min(100%, 260px), 1fr))",
    gap: tokens.spacingHorizontalM,
    marginTop: tokens.spacingVerticalS,
  },
  figure: {
    margin: 0,
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalXS,
    minWidth: 0,
  },
  image: {
    display: "block",
    width: "100%",
    maxHeight: "480px",
    objectFit: "contain",
    objectPosition: "left top",
    borderRadius: tokens.borderRadiusMedium,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    backgroundColor: tokens.colorNeutralBackground3,
  },
  missing: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    padding: tokens.spacingVerticalS,
    color: tokens.colorNeutralForeground3,
    border: `1px dashed ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusMedium,
  },
  label: { color: tokens.colorNeutralForeground3 },
});

function backgroundOf(url: string): string {
  // The agent percent-encodes every segment, so the URL carries no quote.
  return `url(${JSON.stringify(url)})`;
}

/** The top of the board's card face. Nothing at all when there is no cover. */
export function BoardCover({ cover, label }: { cover?: string | null; label: string }) {
  const styles = useStyles();
  if (!cover) return null;
  return (
    <div
      className={styles.face}
      role="img"
      aria-label={`Cover of ${label}`}
      data-card-cover=""
      style={{ backgroundImage: backgroundOf(cover) }}
    />
  );
}

/** The Home list's thumbnail, inside the meta line. Nothing when there is no cover. */
export function CoverThumb({ cover, label }: { cover?: string | null; label: string }) {
  const styles = useStyles();
  if (!cover) return null;
  return (
    <div
      className={styles.thumb}
      role="img"
      aria-label={`Cover of ${label}`}
      data-cover-thumb=""
      style={{ backgroundImage: backgroundOf(cover) }}
    />
  );
}

/**
 * The value a card's line names, as written -- or null when there is no line.
 * Read from the card's own text, so the page can tell "no picture" from "a line
 * whose file is missing": the model serves null for both.
 */
export function imageLine(content: string, stamp: string): string | null {
  const escaped = stamp.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const m = new RegExp(`^${escaped}[ \\t]*(\\S[^\\r\\n]*?)[ \\t]*\\r?$`, "m").exec(content ?? "");
  return m ? m[1] : null;
}

function Picture({
  url,
  line,
  alt,
  caption,
}: {
  url?: string | null;
  line: string | null;
  alt: string;
  caption?: string;
}) {
  const styles = useStyles();
  return (
    <figure className={styles.figure}>
      {caption ? <Caption1 className={styles.label}>{caption}</Caption1> : null}
      {url ? (
        <img className={styles.image} src={url} alt={alt} />
      ) : (
        // The line is the truth, and it names a file that is not there (or not
        // inside the Space's assets/). Said, rather than drawn as a broken image.
        <div className={styles.missing} role="note" data-image-missing="">
          <ImageOffRegular aria-hidden />
          <Caption1>
            The image is missing: <code>{line}</code>
          </Caption1>
        </div>
      )}
    </figure>
  );
}

/**
 * The card page's pictures, under its header. A cover alone is drawn as itself;
 * with a `before`, the two side by side, labelled Before and After. A card with
 * neither line draws nothing.
 */
export function CardPictures({
  cover,
  before,
  content,
  label,
}: {
  cover?: string | null;
  before?: string | null;
  content: string;
  label: string;
}) {
  const styles = useStyles();
  const coverLine = imageLine(content, STAMPS.cover);
  const beforeLine = imageLine(content, STAMPS.before);
  if (!coverLine && !beforeLine) return null;
  if (!beforeLine) {
    return (
      <div className={styles.pictures} data-card-pictures="">
        <Picture url={cover} line={coverLine} alt={`Cover of ${label}`} />
      </div>
    );
  }
  return (
    <div className={styles.pictures} data-card-pictures="">
      <Picture url={before} line={beforeLine} alt={`Before: ${label}`} caption="Before" />
      {coverLine ? (
        <Picture url={cover} line={coverLine} alt={`After: ${label}`} caption="After" />
      ) : null}
    </div>
  );
}
