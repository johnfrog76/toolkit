/**
 * The New Space dialog's rules -- the web's mirror of what `NewSpace`
 * proposes and accepts (Scripts/New-Space.ps1).
 *
 * The verb decides: it re-checks every value and refuses with its own sentence,
 * which the dialog shows. These exist so the dialog can SHOW the proposal before
 * anything runs -- the slug and name a typed `owner/name` would get -- and so Add
 * is not offered for a slug the verb would refuse. They are held to the verb's
 * own rule by one shared table, Tests/fixtures/spaces/proposals.json, asserted
 * here (newSpace.test.ts) and by the verb's suite (tkTestToolkit -NewSpace).
 */

/** A slug: lowercase letters, digits and dashes, starting with a letter. */
export const SLUG_PATTERN = /^[a-z][a-z0-9-]*$/;

/** owner/name, as the verb reads it. */
const REPO_PATTERN = /^[A-Za-z0-9][A-Za-z0-9-]*\/[A-Za-z0-9._-]+$/;

/** The slug a repository's name (or a Space's name) proposes: lowercased, every
 *  run of anything but a-z and 0-9 one dash, trimmed of dashes. */
export function proposeSlug(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

/** The display name a repository's name proposes: dashes, underscores and dots
 *  as spaces, each word's first letter capitalised, the rest kept. */
export function proposeName(text: string): string {
  return text
    .replace(/[-_.]+/g, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

export function isSlug(text: string): boolean {
  return SLUG_PATTERN.test(text);
}

/** A pasted https://github.com/owner/name(.git) reads as owner/name, as the verb reads it. */
export function normaliseRepo(text: string): string {
  return text
    .trim()
    .replace(/^(https?:\/\/)?(www\.)?github\.com\//i, "")
    .replace(/^\/+|\/+$/g, "")
    .replace(/\.git$/i, "");
}

export function isRepo(text: string): boolean {
  return REPO_PATTERN.test(normaliseRepo(text));
}

/** The repository's name -- the part after the slash. */
export function repoName(repo: string): string {
  const r = normaliseRepo(repo);
  const i = r.indexOf("/");
  return i >= 0 ? r.slice(i + 1) : r;
}
