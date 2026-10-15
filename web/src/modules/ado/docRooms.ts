// The rooms a GitHub Space's repo files are read in, and the one base the
// shared viewer resolves a document's links against (D-S12). Two rooms:
//
//   Docs    README.md and the markdown under docs/ -- /docs/<path>
//   Design  one markdown file directly in design/ or spec/ -- /design/<folder>/<name>
//
// Which paths are docs is the contract's rule (consts.json `docs`), the same
// one the agent's /api/docs routes enforce; the design folders are the
// agent's DESIGN_FOLDERS. A relative link to anything else opens on github.com.
import { API_BASE } from "../../shell/api";
import { DOCS, FOLDERS, toRegExp } from "../../shell/consts";
import type { DocLinkBase } from "../../shared/docLinks";

export const DOCS_ROOM = "/docs";
export const DESIGN_ROOM = "/design";
// The two roots, each with an archive/ under it (design lifecycle L2, D-DL1):
// design/x.md, design/archive/x.md, spec/x.spec.md, spec/archive/x.spec.md.
const DESIGN_FOLDERS = ["design", "spec"];
const DESIGN_ARCHIVE = FOLDERS.archive;

/** Is `folder` one of the four design folders? */
export function isDesignFolder(folder: string): boolean {
  const parts = folder.split("/");
  if (!DESIGN_FOLDERS.includes(parts[0])) return false;
  return parts.length === 1 || (parts.length === 2 && parts[1] === DESIGN_ARCHIVE);
}
// The images the agent's asset route serves -- docs.py's ASSET_TYPES; the two
// are held together by Tests/fixtures/docs/paths.json, read by both suites.
const IMAGE = /\.(png|jpe?g|gif|webp|svg)$/i;
const SEGMENT = toRegExp(DOCS.segment);

const encodePath = (path: string) => path.split("/").map(encodeURIComponent).join("/");

/** Every segment one the contract allows -- never '..', '.', empty, a backslash. */
function segmentsOk(path: string): string[] | null {
  if (!path || path.includes("..")) return null;
  const parts = path.split("/");
  return parts.every((p) => SEGMENT.test(p)) ? parts : null;
}

/** README.md, or a markdown file under docs/ -- what the Docs room reads, by
 *  the same rule the agent's routes enforce (docs.py `doc_path`). */
export function isDocPath(path: string): boolean {
  const parts = segmentsOk(path);
  if (!parts) return false;
  if (path === DOCS.readme) return true;
  return parts[0] === DOCS.root && parts.length >= 2 && path.endsWith(".md");
}

/** An image the agent's asset route serves: anywhere in the repository, so a
 *  private repository's pictures load wherever its documents keep them. */
export function isDocAsset(path: string): boolean {
  return segmentsOk(path) !== null && IMAGE.test(path);
}

/** The issue room's address for issue `num` of the Space's repository `name`. */
export function issueRoomPath(num: string | number, name: string): string {
  return `/issue/${num}?repo=${encodeURIComponent(name)}`;
}

/** The Docs room's address for one document. */
export function docsRoomPath(path: string): string {
  return `${DOCS_ROOM}/${encodePath(path)}`;
}

/** The agent route (relative to the API slice's base) for one document. */
export function docsApiPath(path: string): string {
  return `docs/${encodePath(path)}`;
}

/** The Design room's address for one document: the folder may be a root or
 *  its archive (`design/archive`), so each segment is encoded on its own. */
export function designRoomPath(folder: string, name: string): string {
  return `${DESIGN_ROOM}/${encodePath(folder)}/${encodeURIComponent(name)}`;
}

/** The room a repo path opens in, or null when the app has none for it. */
export function roomFor(path: string): string | null {
  if (isDocPath(path)) return docsRoomPath(path);
  const parts = path.split("/");
  const name = parts[parts.length - 1] ?? "";
  const folder = parts.slice(0, -1).join("/");
  if (parts.length >= 2 && isDesignFolder(folder) && name.endsWith(".md")) {
    return designRoomPath(folder, name);
  }
  return null;
}

/**
 * The base a document's links resolve against: its own repo path, and its
 * github.com address -- `https://github.com/<o>/<r>/blob/<ref>/<path>`, from
 * which the blob root every other file sits under is read. Given where the
 * repository's issues are (`https://github.com/<o>/<r>/issues`, the agent's
 * `issues`), a `#N` in the text opens issue N's room; "" leaves it text.
 */
export function repoLinkBase(path: string, htmlUrl: string, issuesUrl = ""): DocLinkBase {
  const blobRoot =
    htmlUrl && htmlUrl.endsWith(path) ? htmlUrl.slice(0, htmlUrl.length - path.length) : "";
  const rawRoot = blobRoot.replace("/blob/", "/raw/");
  const repoName = issuesUrl.split("/").slice(-2, -1)[0] ?? "";
  return {
    ...(issuesUrl && repoName
      ? { issues: { url: issuesUrl, room: (n: string) => issueRoomPath(n, repoName) } }
      : {}),
    path,
    roomFor,
    assetFor: (p) =>
      isDocAsset(p)
        ? `${API_BASE}/docs/asset/${encodePath(p)}`
        : rawRoot
          ? rawRoot + encodePath(p)
          : p,
    outside: (p) => (blobRoot ? blobRoot + encodePath(p) : ""),
  };
}
