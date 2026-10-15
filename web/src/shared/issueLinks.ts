// A `#N` in a repository's document is a link to that repository's issue N,
// the way github.com draws it (docs/modules/ado.md, the Docs bullet). A remark
// plugin, so it sees the parsed document: only prose is rewritten -- a `#N`
// inside a code span, a code block, an existing link or raw HTML stays as it
// was written. The plugin is added only when the page's link base says where
// the repository's issues are; with no issues there, `#N` is text.
//
// The mention is a word of its own: `#N` after a space, a bracket or the
// start of a line, never joined to a word, an entity or a path on either side.
import type { Plugin } from "unified";

interface MdNode {
  type: string;
  value?: string;
  url?: string;
  children?: MdNode[];
}

export const ISSUE_MENTION = /(^|[^\w&/#-])#([1-9]\d*)(?![\w-])/g;

// Nodes whose text is already a link: rewriting inside one would nest links.
const SKIP = new Set(["link", "linkReference", "definition"]);

/** One text value as text and link nodes, `#N` linked to `<issuesUrl>/N`. */
export function splitMentions(value: string, issuesUrl: string): MdNode[] {
  const out: MdNode[] = [];
  let last = 0;
  for (const m of value.matchAll(ISSUE_MENTION)) {
    const start = (m.index ?? 0) + m[1].length;
    if (start > last) out.push({ type: "text", value: value.slice(last, start) });
    out.push({
      type: "link",
      url: `${issuesUrl}/${m[2]}`,
      children: [{ type: "text", value: `#${m[2]}` }],
    });
    last = start + 1 + m[2].length;
  }
  if (out.length === 0) return [{ type: "text", value }];
  if (last < value.length) out.push({ type: "text", value: value.slice(last) });
  return out;
}

function walk(node: MdNode, issuesUrl: string): void {
  if (!node.children || SKIP.has(node.type)) return;
  const next: MdNode[] = [];
  for (const child of node.children) {
    if (child.type === "text") next.push(...splitMentions(child.value ?? "", issuesUrl));
    else {
      walk(child, issuesUrl);
      next.push(child);
    }
  }
  node.children = next;
}

/** `[remarkIssueLinks, { url }]`: `url` is the repository's issues on
 *  github.com (`https://github.com/<owner>/<repo>/issues`). */
export const remarkIssueLinks: Plugin<[{ url: string }]> = function (options) {
  const url = options?.url ?? "";
  return (tree) => {
    if (url) walk(tree as unknown as MdNode, url);
  };
};
