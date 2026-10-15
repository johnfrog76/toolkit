// Where a link in a repo's document goes (D-S12) -- written ONCE, here,
// and used by the shared viewer for every room that reads a repo's files (the
// Docs tab and the Design tab). Three kinds, and the rule is the whole file:
//
//   room    a relative link to a document the app has a room for (`docs/CLI.md`,
//           `../VERIFY.md` when that resolves into a room, `CLI.md#the-workflow`)
//           opens that room, in the app, its `#anchor` kept;
//   anchor  a `#anchor` scrolls within the page, to the id GitHub would give the
//           heading (prepareMarkdown's `githubSlug`);
//   out     an absolute `http(s)` (or `mailto:`) link leaves in a new tab, as it
//           always did; and so does a relative link to a file with no room here
//           (`AGENTS.md`, `spec/x.spec.md` from the Docs tab) -- on github.com,
//           with a title that says so on hover.
//
// An issue of the document's own repository -- a `#N` mention (issueLinks.ts)
// or its github.com address written out -- opens that issue's room, when the
// page's base says where the repository's issues are.
//
// An image is the fourth question, answered the same way: a relative `src` is
// resolved against the document's own folder and served by the page's
// `assetFor` (the agent's /docs/asset route, or github.com's raw view).
//
// The resolver knows nothing about which rooms exist: the page that mounts the
// viewer hands it a `DocLinkBase` -- the document's own path in the repo and
// three answers about a repo path. With no base (a card, an issue), links
// behave as they always have, and a `#anchor` still scrolls.

export interface DocLinkBase {
  /** The document's own path in the repo, e.g. `docs/modules/ado.md`. */
  path: string;
  /** The app address a repo path opens at, or null when it has no room. */
  roomFor: (repoPath: string) => string | null;
  /** The URL an image at this repo path is served from. */
  assetFor: (repoPath: string) => string;
  /** The file on github.com, for a path with no room. "" when unknown. */
  outside: (repoPath: string) => string;
  /** Where the repository's issues are, when it has them: `url` is their
   *  github.com address (`#N` in the text links to `<url>/N`), and `room` the
   *  app address issue N is read at. Absent, `#N` is text. */
  issues?: { url: string; room: (num: string) => string };
}

export type ResolvedLink =
  | { kind: "room"; to: string }
  | { kind: "anchor"; id: string }
  | { kind: "out"; href: string; title?: string };

const SCHEME = /^[a-z][a-z0-9+.-]*:/i;

/** `base` folder + `rel` path, POSIX-style; null when it climbs above the repo. */
export function joinRepoPath(folder: string, rel: string): string | null {
  const parts = rel.startsWith("/") ? [] : folder.split("/").filter(Boolean);
  for (const seg of rel.split("/")) {
    if (seg === "" || seg === ".") continue;
    if (seg === "..") {
      if (parts.length === 0) return null;
      parts.pop();
    } else parts.push(seg);
  }
  return parts.join("/");
}

function folderOf(path: string): string {
  const i = path.lastIndexOf("/");
  return i < 0 ? "" : path.slice(0, i);
}

function decode(s: string): string {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
}

/** Split `a/b.md?x#frag` into the path and the fragment (the query is dropped:
 *  a repo file has none that matters). */
function splitHref(href: string): [string, string] {
  const hash = href.indexOf("#");
  const frag = hash < 0 ? "" : href.slice(hash + 1);
  let path = hash < 0 ? href : href.slice(0, hash);
  const q = path.indexOf("?");
  if (q >= 0) path = path.slice(0, q);
  return [decode(path), decode(frag)];
}

/** N when `href` is issue N of the repository whose issues are at `issuesUrl`
 *  -- a `#N` mention, or a link written out in full -- else null. */
export function issueNumberOf(href: string, issuesUrl: string): string | null {
  if (!issuesUrl || !href.startsWith(`${issuesUrl}/`)) return null;
  const rest = href.slice(issuesUrl.length + 1);
  return /^[1-9]\d*$/.test(rest) ? rest : null;
}

export function outsideTitle(repoPath: string): string {
  return `Opens ${repoPath} on GitHub, in a new tab -- it is not one of the documents this room reads.`;
}

export function resolveLink(href: string | undefined, base?: DocLinkBase): ResolvedLink {
  const raw = (href ?? "").trim();
  if (raw.startsWith("#")) return { kind: "anchor", id: decode(raw.slice(1)) };
  const issue = base?.issues ? issueNumberOf(raw, base.issues.url) : null;
  if (issue && base?.issues) return { kind: "room", to: base.issues.room(issue) };
  if (!base || !raw || SCHEME.test(raw) || raw.startsWith("//")) return { kind: "out", href: raw };
  const [rel, frag] = splitHref(raw);
  // `docs/CLI.md#x` from docs/CLI.md is this page; `#x` was handled above.
  const target = rel === "" ? base.path : joinRepoPath(folderOf(base.path), rel);
  if (target === null) return { kind: "out", href: raw };
  const room = base.roomFor(target);
  if (room !== null)
    return { kind: "room", to: frag ? `${room}#${encodeURIComponent(frag)}` : room };
  const out = base.outside(target);
  if (!out) return { kind: "out", href: raw };
  return {
    kind: "out",
    href: frag ? `${out}#${encodeURIComponent(frag)}` : out,
    title: outsideTitle(target),
  };
}

export function resolveImage(src: string | undefined, base?: DocLinkBase): string | undefined {
  const raw = (src ?? "").trim();
  if (!base || !raw || SCHEME.test(raw) || raw.startsWith("//")) return src;
  const [rel] = splitHref(raw);
  const target = joinRepoPath(folderOf(base.path), rel);
  return target === null ? src : base.assetFor(target);
}
