import { Wordmark } from "../shared/Wordmark";
import { FACES } from "../shared/faces";

// The many faces of ToolKit: every face the app's logo can wear, as a grid of
// small wordmarks in the banner's right column, the blobs cycling through the
// palette. One accessible name for the group; the marks themselves are
// decoration beside the heading's own.

export const FACES_NAME = "The many faces of ToolKit";

/** The blobs' colours, one per face in turn. */
export const FACE_BLOBS = [
  "rgba(34, 211, 238, 0.42)",
  "rgba(244, 114, 182, 0.42)",
  "rgba(245, 158, 11, 0.5)",
  "rgba(129, 140, 248, 0.5)",
  "rgba(52, 211, 153, 0.42)",
  "rgba(251, 113, 133, 0.45)",
];

export function Faces({ line }: { line: string }) {
  return (
    <div className="lp-faces-block">
      <ul className="lp-faces" aria-label={FACES_NAME}>
        {FACES.map((f, i) => (
          <li key={f.id} title={f.name}>
            <Wordmark
              size="100%"
              ink="var(--lp-text)"
              blob={FACE_BLOBS[i % FACE_BLOBS.length]}
              face={f.id}
              title=""
            />
          </li>
        ))}
      </ul>
      <p className="lp-faces-line">{line}</p>
    </div>
  );
}
