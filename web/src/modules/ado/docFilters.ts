// The Design and Docs tabs' filters, held ONCE for two readers, the way
// the Issues tab's are (useIssueChoices): the filter drawer sets them, the list
// applies them. Pure rules here, so every axis is tested without a render; the
// values are remembered per browser (useSharedPersistedValue).
import { useSharedPersistedValue } from "../../shared/usePersistedState";
import type { Design, DocEntry } from "./api.ado";

export const DESIGN_TEXT_KEY = "ado.design.text";
export const DESIGN_KIND_KEY = "ado.design.kind";
export const DOCS_TEXT_KEY = "ado.docs.text";
export const DOCS_FOLDER_KEY = "ado.docs.folder";

/** "all" is off, on every axis. */
export const ALL = "all";

/** Design's kinds, in the words a person uses: a design that is a note alone,
 *  or one that has graduated to a spec (the unit is the design since L2, so
 *  the kind is what the design HAS, not which folder one file sits in). */
export const DESIGN_KINDS: { value: string; label: string }[] = [
  { value: "design", label: "design note" },
  { value: "spec", label: "spec" },
];

/** "Fuzzy", as the other tabs' search is (issueMatches): every word found in
 *  the haystack, in any order, case ignored. No typo tolerance -- a word is a
 *  substring -- so what matches is always something you can see in the row. */
export function fuzzyMatch(haystack: string, text: string): boolean {
  const words = text.toLowerCase().split(/\s+/).filter(Boolean);
  if (words.length === 0) return true;
  const hay = haystack.toLowerCase();
  return words.every((w) => hay.includes(w));
}

/** Design: text over the TITLE, the description, the id and the FILE NAMES
 *  of its note and spec (one box, all at once -- the row prints the name, so a
 *  reader who remembers `toolkit-getting-started.md` finds it), and the kind --
 *  "spec" is a design that has one, "design" one that is a note alone. The
 *  repo's Design tab and the hub's Designs card both filter by this one rule. */
export function designMatches(
  d: Pick<Design, "title" | "description" | "id" | "note" | "spec">,
  text: string,
  kind: string,
): boolean {
  if (kind === "spec" && !d.spec) return false;
  if (kind === "design" && d.spec) return false;
  return fuzzyMatch(
    `${d.title} ${d.description} ${d.id} ${d.note?.name ?? ""} ${d.spec?.name ?? ""}`,
    text,
  );
}

/** Docs: text over the row's path, and the folder, exactly. The tree has not
 *  opened the files, so a document's first heading is not known to it: the
 *  path -- which carries the file's name -- is the row's title here. */
export function docMatches(
  d: Pick<DocEntry, "path" | "folder">,
  text: string,
  folder: string,
): boolean {
  if (folder !== ALL && d.folder !== folder) return false;
  return fuzzyMatch(d.path, text);
}

/** The folders the tree actually has, in path order. */
export function docFolders(items: Pick<DocEntry, "folder">[]): string[] {
  return [...new Set(items.map((d) => d.folder).filter(Boolean))].sort();
}

export function useDesignFilters() {
  const text = useSharedPersistedValue(DESIGN_TEXT_KEY, "");
  const kind = useSharedPersistedValue(
    DESIGN_KIND_KEY,
    ALL,
    (v) => v === ALL || DESIGN_KINDS.some((k) => k.value === v),
  );
  return { text: text.value, setText: text.setValue, kind: kind.value, setKind: kind.setValue };
}

export function useDocsFilters() {
  const text = useSharedPersistedValue(DOCS_TEXT_KEY, "");
  const folder = useSharedPersistedValue(DOCS_FOLDER_KEY, ALL);
  return {
    text: text.value,
    setText: text.setValue,
    folder: folder.value,
    setFolder: folder.setValue,
  };
}

/** The tab's one-line account of what is set, for the header: a filter must
 *  never hide rows with nothing on screen saying so. Empty when nothing is. */
export function filterSummary(axis: string | undefined, text: string): string {
  const out: string[] = [];
  if (axis) out.push(axis);
  if (text.trim()) out.push(`matching "${text.trim()}"`);
  return out.join(" · ");
}
