// The ONE plugin configuration every ReactMarkdown call in the app uses.
//
// A README reads in the Toolkit the way it reads on GitHub, and GitHub renders
// the simple HTML a README carries (`<p align="center">`, `<img width>`,
// `<details>`). So raw HTML is parsed (rehype-raw) and then SANITISED
// (rehype-sanitize) with GitHub's own allow-list as the start: nothing that
// executes survives -- no script, style, iframe, no on* handler, no
// javascript: URL. Raw HTML in a card is untrusted text; it is never trusted.
//
// Order matters: sanitise runs AFTER raw, so it sees the HTML raw produced.
import remarkGfm from "remark-gfm";
import rehypeRaw from "rehype-raw";
import rehypeSanitize, { defaultSchema } from "rehype-sanitize";
import type { Options as SanitizeSchema } from "rehype-sanitize";
import type { PluggableList } from "unified";
import { remarkIssueLinks } from "./issueLinks";

// Elements whose `align` GitHub honours; the default schema drops it.
const ALIGNED = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "img", "td", "th"];

const attributes: NonNullable<SanitizeSchema["attributes"]> = {
  ...(defaultSchema.attributes ?? {}),
};
for (const tag of ALIGNED) {
  attributes[tag] = [...(attributes[tag] ?? []), "align"];
}
// An image's size and alt text. A duplicate entry is harmless.
attributes.img = [...(attributes.img ?? []), "width", "height", "alt"];

export const markdownSchema: SanitizeSchema = {
  ...defaultSchema,
  tagNames: [...new Set([...(defaultSchema.tagNames ?? []), "details", "summary"])],
  attributes,
};

export const remarkPlugins: PluggableList = [remarkGfm];
export const rehypePlugins: PluggableList = [rehypeRaw, [rehypeSanitize, markdownSchema]];

/** Spread onto every <ReactMarkdown>: `<ReactMarkdown {...markdownPlugins}>`. */
export const markdownPlugins = { remarkPlugins, rehypePlugins };

/** The same configuration for a repository's document whose issues are at
 *  `issuesUrl`: its `#N` mentions become links (issueLinks.ts). Runs after
 *  GFM, so an autolinked URL is already a link and is left alone. */
export function markdownPluginsWithIssues(issuesUrl: string) {
  return {
    remarkPlugins: [...remarkPlugins, [remarkIssueLinks, { url: issuesUrl }]] as PluggableList,
    rehypePlugins,
  };
}

/** The sanitiser keeps `align`; browsers do not reliably apply the obsolete
 *  attribute under our CSS, so the viewers honour it themselves. Spread into a
 *  makeStyles rule for the container that holds the rendered markdown. */
export const alignRules = {
  "& [align='center']": { textAlign: "center" as const },
  "& [align='right']": { textAlign: "right" as const },
  "& [align='left']": { textAlign: "left" as const },
  // A block image has no text to align; margins do it.
  "& img[align='center']": { marginLeft: "auto", marginRight: "auto" },
  "& img[align='right']": { marginLeft: "auto", marginRight: 0 },
};
