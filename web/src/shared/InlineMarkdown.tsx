// One line of markdown, drawn inline: a changelog entry, a list item's text.
//
// The same renderer and the same remark plugins as every other markdown in the
// app (markdownPlugins.ts) -- GFM, so `code`, **bold**, _emphasis_, ~~struck~~
// and links read as they do on GitHub -- but only the INLINE elements: a
// heading, a list, a table, a quote or a code block written into the line is
// drawn as its text, never as a block of its own, and its paragraph wrapper is
// dropped, so the line sits inside whatever element holds it. Raw HTML is not
// parsed at all (no rehype-raw): a `<b>` in the text is skipped, never drawn.
// With `issuesUrl`, a `#N` is a link to that repository's issue N.
import type { ReactNode } from "react";
import ReactMarkdown from "react-markdown";
import type { Components } from "react-markdown";
import { makeStyles, tokens } from "@fluentui/react-components";
import { remarkPlugins } from "./markdownPlugins";
import { remarkIssueLinks } from "./issueLinks";

/** The elements an inline line may draw; anything else is unwrapped to its text. */
export const INLINE_ELEMENTS = ["p", "code", "strong", "em", "del", "a", "br"];

const useStyles = makeStyles({
  code: {
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: "0.92em",
    backgroundColor: tokens.colorNeutralBackground3,
    padding: "0 4px",
    borderRadius: tokens.borderRadiusSmall,
  },
  link: { color: tokens.colorBrandForegroundLink },
});

export function InlineMarkdown({ children, issuesUrl }: { children: string; issuesUrl?: string }) {
  const styles = useStyles();
  const components: Components = {
    // The paragraph is the line itself: no block around it.
    p: ({ children: inner }: { children?: ReactNode }) => <span>{inner}</span>,
    code: ({ children: inner }: { children?: ReactNode }) => (
      <code className={styles.code}>{inner}</code>
    ),
    a: ({ href, children: inner }: { href?: string; children?: ReactNode }) => (
      <a className={styles.link} href={href} target="_blank" rel="noopener noreferrer">
        {inner}
      </a>
    ),
  };
  const plugins = issuesUrl
    ? [...remarkPlugins, [remarkIssueLinks, { url: issuesUrl }]]
    : remarkPlugins;
  return (
    <ReactMarkdown
      remarkPlugins={plugins as typeof remarkPlugins}
      skipHtml
      allowedElements={INLINE_ELEMENTS}
      unwrapDisallowed
      components={components}
    >
      {children}
    </ReactMarkdown>
  );
}
