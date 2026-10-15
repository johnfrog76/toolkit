import {
  Children,
  cloneElement,
  isValidElement,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  dropLeadingTitle,
  headingIdsOf,
  headingsOf,
  prepareMarkdown,
  sectionOf,
  slugOf,
} from "./prepareMarkdown";
import { usePersistedState } from "./usePersistedState";
import ReactMarkdown from "react-markdown";
import { alignRules, markdownPlugins, markdownPluginsWithIssues } from "./markdownPlugins";
import { Button, Caption1, makeStyles, mergeClasses, tokens } from "@fluentui/react-components";
import { ChevronUpRegular } from "@fluentui/react-icons";
import type { Components } from "react-markdown";
import { ZoomControl } from "./ZoomControl";
import { DocLink } from "./DocLink";
import { resolveImage } from "./docLinks";
import type { DocLinkBase } from "./docLinks";

const useStyles = makeStyles({
  outer: {
    width: "100%",
  },
  toolbar: {
    display: "flex",
    justifyContent: "flex-end",
    paddingBottom: tokens.spacingVerticalXS,
  },
  // A long card: the text in a centred column, and "On this page" beside it --
  // in the third of the card that used to be empty, with the zoom control
  // floating in it. Below 1100px there is no room, and the list folds away
  // above the text instead.
  withContents: {
    "@media (min-width: 1100px)": {
      display: "grid",
      gridTemplateColumns: "minmax(0, 1fr) 210px",
      columnGap: tokens.spacingHorizontalXXL,
      alignItems: "start",
    },
  },
  aside: {
    display: "none",
    "@media (min-width: 1100px)": {
      display: "flex",
      flexDirection: "column",
      gap: tokens.spacingVerticalM,
      position: "sticky",
      top: tokens.spacingVerticalL,
      maxHeight: "calc(100vh - 2rem)",
      overflowY: "auto",
      gridColumn: "2",
      gridRow: "1",
    },
  },
  asideLabel: {
    color: tokens.colorNeutralForeground3,
    textTransform: "uppercase",
    letterSpacing: "0.04em",
  },
  contents: {
    listStyleType: "none",
    margin: 0,
    padding: 0,
    display: "flex",
    flexDirection: "column",
  },
  contentsLink: {
    display: "block",
    width: "100%",
    textAlign: "left",
    font: "inherit",
    fontSize: tokens.fontSizeBase200,
    lineHeight: tokens.lineHeightBase200,
    color: tokens.colorNeutralForeground2,
    backgroundColor: "transparent",
    border: "none",
    borderLeft: `2px solid ${tokens.colorNeutralStroke2}`,
    padding: `${tokens.spacingVerticalXS} ${tokens.spacingHorizontalM}`,
    cursor: "pointer",
    ":hover": { color: tokens.colorNeutralForeground1 },
    ":focus-visible": { outline: `2px solid ${tokens.colorStrokeFocus2}`, outlineOffset: "-2px" },
  },
  // A part of a section: indented under it, the same font, quieter.
  contentsSub: {
    paddingLeft: tokens.spacingHorizontalXXL,
    color: tokens.colorNeutralForeground3,
  },
  contentsHere: {
    color: tokens.colorBrandForeground1,
    borderLeftColor: tokens.colorBrandStroke1,
    fontWeight: tokens.fontWeightSemibold,
  },
  folded: {
    marginBottom: tokens.spacingVerticalM,
    "& summary": { cursor: "pointer", color: tokens.colorNeutralForeground2 },
    "@media (min-width: 1100px)": { display: "none" },
  },
  toolbarWide: { "@media (min-width: 1100px)": { display: "none" } },
  column: { minWidth: 0 },
  content: {
    // 72 characters: the measure a page of prose is comfortable at. It was 80,
    // left-aligned, which is a terminal's width and not a book's.
    maxWidth: "72ch",
    marginLeft: "auto",
    marginRight: "auto",
    "& h2": { scrollMarginTop: "16px" },
    "& h3": { scrollMarginTop: "16px" },
    fontFamily: tokens.fontFamilyBase,
    fontSize: tokens.fontSizeBase300,
    lineHeight: "1.75",
    color: tokens.colorNeutralForeground1,
    "& > *:first-child": { marginTop: 0 },
    "& > *:last-child": { marginBottom: 0 },
    ...alignRules,
  },
  // A generated card's front matter: facts about the file, not part of what it
  // says. Quiet, one line, above the title -- never the page's biggest heading.
  frontMatter: {
    display: "flex",
    flexWrap: "wrap",
    columnGap: tokens.spacingHorizontalL,
    rowGap: tokens.spacingVerticalXXS,
    margin: `0 0 ${tokens.spacingVerticalM}`,
    fontSize: tokens.fontSizeBase200,
    color: tokens.colorNeutralForeground3,
    "& div": { display: "flex", gap: tokens.spacingHorizontalXS },
    "& dt": { fontWeight: tokens.fontWeightSemibold },
    "& dd": { margin: 0 },
  },
  backToTop: {
    display: "flex",
    justifyContent: "flex-end",
    marginTop: tokens.spacingVerticalXL,
    paddingTop: tokens.spacingVerticalM,
    borderTop: `1px solid ${tokens.colorNeutralStroke2}`,
  },
  h1: {
    fontSize: tokens.fontSizeBase600,
    fontWeight: tokens.fontWeightBold,
    marginTop: tokens.spacingVerticalXXL,
    marginBottom: tokens.spacingVerticalM,
    paddingBottom: tokens.spacingVerticalXS,
    borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
  },
  h2: {
    fontSize: tokens.fontSizeBase500,
    fontWeight: tokens.fontWeightSemibold,
    marginTop: tokens.spacingVerticalXXL,
    marginBottom: tokens.spacingVerticalM,
  },
  h3: {
    fontSize: tokens.fontSizeBase400,
    fontWeight: tokens.fontWeightSemibold,
    marginTop: tokens.spacingVerticalXL,
    marginBottom: tokens.spacingVerticalM,
  },
  h4: {
    fontSize: tokens.fontSizeBase300,
    fontWeight: tokens.fontWeightSemibold,
    marginTop: tokens.spacingVerticalXL,
    marginBottom: tokens.spacingVerticalM,
  },
  p: {
    marginTop: 0,
    marginBottom: tokens.spacingVerticalL,
  },
  ul: {
    paddingLeft: "1.75rem",
    marginTop: 0,
    marginBottom: tokens.spacingVerticalL,
  },
  ol: {
    paddingLeft: "1.75rem",
    marginTop: 0,
    marginBottom: tokens.spacingVerticalL,
  },
  li: {
    marginBottom: tokens.spacingVerticalS,
  },
  blockquote: {
    borderLeft: `3px solid ${tokens.colorBrandForeground1}`,
    paddingLeft: tokens.spacingHorizontalL,
    margin: 0,
    marginBottom: tokens.spacingVerticalL,
    color: tokens.colorNeutralForeground2,
    fontStyle: "italic",
  },
  inlineCode: {
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: "0.9em",
    backgroundColor: tokens.colorNeutralBackground3,
    padding: "2px 5px",
    borderRadius: tokens.borderRadiusSmall,
  },
  pre: {
    backgroundColor: tokens.colorNeutralBackground4,
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusMedium,
    padding: `${tokens.spacingVerticalM} ${tokens.spacingHorizontalL}`,
    overflowX: "auto",
    margin: `0 0 ${tokens.spacingVerticalL} 0`,
  },
  blockCode: {
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase200,
    lineHeight: "1.6",
  },
  a: {
    color: tokens.colorBrandForeground1,
    textDecoration: "none",
    "&:hover": { textDecoration: "underline" },
  },
  tableWrapper: {
    overflowX: "auto",
    marginBottom: tokens.spacingVerticalL,
  },
  table: {
    width: "100%",
    borderCollapse: "collapse" as const,
    "& tbody tr:nth-child(even)": {
      backgroundColor: tokens.colorNeutralBackground2,
    },
  },
  th: {
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    padding: `${tokens.spacingVerticalS} ${tokens.spacingHorizontalM}`,
    textAlign: "left" as const,
    backgroundColor: tokens.colorNeutralBackground3,
    fontWeight: tokens.fontWeightSemibold,
  },
  td: {
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    padding: `${tokens.spacingVerticalS} ${tokens.spacingHorizontalM}`,
    textAlign: "left" as const,
  },
  img: {
    maxWidth: "100%",
    borderRadius: tokens.borderRadiusMedium,
    display: "block",
  },
  hr: {
    border: "none",
    borderTop: `1px solid ${tokens.colorNeutralStroke2}`,
    margin: `${tokens.spacingVerticalXL} 0`,
  },
});

// The text is set at 14px and was opened at "125%" -- which says the base size
// was wrong, not that everyone wants it bigger. The scale is built in now, so
// 100% IS the comfortable size and the control means what it says.
const BASE_SCALE = 1.25;
const CONTENTS_FROM = 3; // fewer headings than this and a list is just noise

interface Props {
  content: string;
  /** The title the page's own header already shows. The card's opening h1 is
   *  dropped when it says exactly the same thing. */
  titleAbove?: string;
  maxHeight?: string | number;
  style?: React.CSSProperties;
  /** A repo's document: where it sits in the repo and which paths have
   *  a room. Given, its relative links open in the app, its images come
   *  through the page's asset route, and its headings wear GitHub's ids so
   *  the anchors written against github.com land; with the repository's
   *  issues in it, a `#N` in the text opens that issue's room. Absent, links
   *  are as ever. */
  links?: DocLinkBase;
  /** A heading id to bring into view once the text is drawn -- the `#anchor`
   *  a room link carried in its address. */
  anchor?: string;
}

export function MarkdownViewer({ content, titleAbove, maxHeight, style, links, anchor }: Props) {
  const styles = useStyles();
  // Remembered: someone who reads at 125% reads everything at 125%.
  const { value: zoom, setValue: storeZoom } = usePersistedState<number>(
    "toolkit-reading-zoom",
    1,
    (v): v is number => typeof v === "number" && v >= 0.5 && v <= 2,
  );
  // ZoomControl speaks in updater functions; the store takes a value.
  const setZoom = (fn: (z: number) => number) => storeZoom(fn(zoom));
  const prepared = useMemo(() => {
    const p = prepareMarkdown(content);
    return { ...p, body: dropLeadingTitle(p.body, titleAbove) };
  }, [content, titleAbove]);
  // A repository's document whose issues are known links its `#N` mentions;
  // everything else renders with the one shared configuration.
  const issuesUrl = links?.issues?.url ?? "";
  const plugins = useMemo(
    () => (issuesUrl ? markdownPluginsWithIssues(issuesUrl) : markdownPlugins),
    [issuesUrl],
  );
  // A scrolling box of its own (the presenter's notes) is not a page to navigate.
  const idStyle = links ? "github" : "card";
  const headings = useMemo(
    () => (maxHeight === undefined ? headingsOf(prepared.body, idStyle) : []),
    [prepared.body, maxHeight, idStyle],
  );
  const hasContents = headings.length >= CONTENTS_FROM;
  // The id each rendered heading gets, by its line in the body -- the same id
  // the list points at, which slugOf(text) alone cannot promise when two
  // headings share their words.
  // A repo's document gives EVERY heading its GitHub id, h1 to h6: an anchor
  // may point at any of them.
  const idByLine = useMemo(
    () =>
      idStyle === "github"
        ? headingIdsOf(prepared.body)
        : new Map(headings.map((h) => [h.line, h.id])),
    [idStyle, prepared.body, headings],
  );
  const [here, setHere] = useState<string | null>(null);
  // Inside a part of a section, the section is marked too.
  const hereSection = useMemo(() => sectionOf(headings, here), [headings, here]);
  const topRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);

  const scrollToTop = () => {
    if (maxHeight !== undefined && contentRef.current) {
      contentRef.current.scrollTop = 0;
    } else {
      topRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  };

  // Which section is being read: the last heading to have passed the top
  // third of the window. Measured on scroll -- an IntersectionObserver only
  // reports the headings that CROSSED a line since it last spoke, so a jump
  // from the contents list left it naming the section you had come from.
  useEffect(() => {
    if (!hasContents) return;
    const root = contentRef.current;
    if (!root) return;
    let frame = 0;
    const measure = () => {
      frame = 0;
      const line = window.innerHeight * 0.3;
      let current = headings[0]?.id ?? null;
      for (const h of headings) {
        const el = root.querySelector(`#${CSS.escape(h.id)}`);
        if (el && el.getBoundingClientRect().top <= line) current = h.id;
      }
      setHere(current);
    };
    const onScroll = () => {
      if (!frame) frame = window.requestAnimationFrame(measure);
    };
    measure();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
      if (frame) window.cancelAnimationFrame(frame);
    };
  }, [headings, hasContents]);

  const jumpTo = useCallback((id: string, behavior: ScrollBehavior = "smooth") => {
    const el = contentRef.current?.querySelector<HTMLElement>(`#${CSS.escape(id)}`);
    if (!el) return;
    el.scrollIntoView({ behavior, block: "start" });
    el.focus({ preventScroll: true });
  }, []);

  // The anchor a room link carried: once the text it names is drawn.
  useEffect(() => {
    if (anchor) jumpTo(anchor, "auto");
  }, [anchor, prepared.body, jumpTo]);

  const contentsList = (
    <ul className={styles.contents}>
      {headings.map((h) => (
        <li key={h.id}>
          <button
            type="button"
            className={mergeClasses(
              styles.contentsLink,
              h.level === 3 && styles.contentsSub,
              (here === h.id || hereSection === h.id) && styles.contentsHere,
            )}
            aria-current={here === h.id ? "location" : undefined}
            onClick={() => jumpTo(h.id)}
          >
            {h.text}
          </button>
        </li>
      ))}
    </ul>
  );

  // Memoised: a new `components` object is a new component TYPE for every tag,
  // so each scroll-driven re-render remounted the whole card -- and dropped the
  // focus a contents link had just put on a heading.
  const components: Components = useMemo(
    () => ({
      h1({ node, ...props }) {
        return (
          <h1
            className={styles.h1}
            id={idByLine.get(node?.position?.start.line ?? -1)}
            {...props}
          />
        );
      },
      h2({ node, children, ...props }) {
        // The same id "On this page" points at: by the heading's line when the
        // list has it, else from its words alone -- a heading with emphasis in
        // it still slugs to its words.
        const id = idByLine.get(node?.position?.start.line ?? -1) ?? slugOf(flatText(children));
        return (
          <h2 className={styles.h2} id={id} tabIndex={-1} {...props}>
            {children}
          </h2>
        );
      },
      h3({ node, children, ...props }) {
        const id = idByLine.get(node?.position?.start.line ?? -1) ?? slugOf(flatText(children));
        return (
          <h3 className={styles.h3} id={id} tabIndex={-1} {...props}>
            {children}
          </h3>
        );
      },
      h4({ node, ...props }) {
        return (
          <h4
            className={styles.h4}
            id={idByLine.get(node?.position?.start.line ?? -1)}
            {...props}
          />
        );
      },
      p({ node: _n, ...props }) {
        return <p className={styles.p} {...props} />;
      },
      ul({ node: _n, ...props }) {
        return <ul className={styles.ul} {...props} />;
      },
      ol({ node: _n, ...props }) {
        return <ol className={styles.ol} {...props} />;
      },
      li({ node, children, ...props }) {
        // A task-list item's checkbox is named by the item's own words
        // (axe's label): GFM renders a bare <input type="checkbox" disabled>.
        const named = String(props.className ?? "").includes("task-list-item")
          ? labelTaskCheckbox(children, taskItemText(node).trim())
          : children;
        return (
          <li className={styles.li} {...props}>
            {named}
          </li>
        );
      },
      blockquote({ node: _n, ...props }) {
        return <blockquote className={styles.blockquote} {...props} />;
      },
      code({ node: _n, children: c, className }) {
        const isBlock = /language-/.test(className ?? "") || String(c).includes("\n");
        return isBlock ? (
          <code className={styles.blockCode}>{c}</code>
        ) : (
          <code className={styles.inlineCode}>{c}</code>
        );
      },
      pre({ node: _n, ...props }) {
        return <pre className={styles.pre} {...props} />;
      },
      // Where a link goes is decided once, in docLinks.ts: a room, an
      // anchor on this page, or out in a new tab.
      a({ node: _n, href, children: c }) {
        return (
          <DocLink href={href} base={links} onAnchor={jumpTo} className={styles.a}>
            {c}
          </DocLink>
        );
      },
      table({ node: _n, children: c }) {
        return (
          <div className={styles.tableWrapper}>
            <table className={styles.table}>{c}</table>
          </div>
        );
      },
      th({ node: _n, ...props }) {
        return <th className={styles.th} {...props} />;
      },
      td({ node: _n, ...props }) {
        return <td className={styles.td} {...props} />;
      },
      // Markdown's image and a raw-HTML <img> (rehype-raw) both arrive
      // here, so both go through resolveImage; width and height are the
      // author's, kept.
      img({ node: _n, src, alt, width, height }) {
        return (
          <img
            src={resolveImage(src, links)}
            alt={alt}
            width={width}
            height={height}
            className={styles.img}
          />
        );
      },
      hr() {
        return <hr className={styles.hr} />;
      },
    }),
    [styles, idByLine, links, jumpTo],
  );

  return (
    <div
      ref={topRef}
      className={mergeClasses(styles.outer, hasContents && styles.withContents)}
      style={style}
    >
      {hasContents ? (
        <nav className={styles.aside} aria-label="On this page">
          <ZoomControl zoom={zoom} setZoom={setZoom} min={0.5} max={2} step={0.25} />
          <Caption1 className={styles.asideLabel}>On this page</Caption1>
          {contentsList}
        </nav>
      ) : null}
      <div className={styles.column}>
        <div className={mergeClasses(styles.toolbar, hasContents && styles.toolbarWide)}>
          <ZoomControl zoom={zoom} setZoom={setZoom} min={0.5} max={2} step={0.25} />
        </div>
        {hasContents ? (
          <details className={styles.folded}>
            <summary>On this page</summary>
            {contentsList}
          </details>
        ) : null}
        <div
          ref={contentRef}
          className={styles.content}
          style={{
            zoom: zoom * BASE_SCALE,
            ...(maxHeight !== undefined ? { maxHeight, overflowY: "auto" } : {}),
          }}
        >
          {prepared.frontMatter.length > 0 ? (
            <dl className={styles.frontMatter}>
              {prepared.frontMatter.map(([key, value]) => (
                <div key={key}>
                  <dt>{key}</dt>
                  <dd>{value}</dd>
                </div>
              ))}
            </dl>
          ) : null}
          <ReactMarkdown {...plugins} components={components}>
            {prepared.body}
          </ReactMarkdown>
        </div>
        <div className={styles.backToTop}>
          <Button
            appearance="subtle"
            size="small"
            icon={<ChevronUpRegular />}
            onClick={scrollToTop}
          >
            Top
          </Button>
        </div>
      </div>
    </div>
  );
}

/** A task-list item's words: its text, without the checkbox and without any
 *  list nested under it (those items name their own). Read from the hast node. */
function taskItemText(node: unknown): string {
  if (!node || typeof node !== "object") return "";
  const n = node as { type?: string; value?: string; tagName?: string; children?: unknown[] };
  if (n.type === "text") return n.value ?? "";
  if (n.tagName === "ul" || n.tagName === "ol" || n.tagName === "input") return "";
  return (n.children ?? []).map(taskItemText).join("");
}

/** The item's checkbox, given `label` as its accessible name. A tight list puts
 *  the checkbox straight in the <li>; a loose one puts it in the item's first <p>. */
function labelTaskCheckbox(children: React.ReactNode, label: string): React.ReactNode {
  if (!label) return children;
  const visit = (child: React.ReactNode, depth: number): React.ReactNode => {
    if (!isValidElement(child)) return child;
    const props = child.props as {
      type?: string;
      children?: React.ReactNode;
      node?: { tagName?: string };
    };
    if (props.type === "checkbox")
      return cloneElement(child as React.ReactElement<{ "aria-label"?: string }>, {
        "aria-label": label,
      });
    // The paragraph arrives as the `p` override above, which carries its hast node.
    if (depth === 0 && (child.type === "p" || props.node?.tagName === "p")) {
      return cloneElement(
        child,
        undefined,
        Children.map(props.children, (c) => visit(c, 1)),
      );
    }
    return child;
  };
  return Children.map(children, (c) => visit(c, 0));
}

function flatText(node: React.ReactNode): string {
  if (node === null || node === undefined || typeof node === "boolean") return "";
  if (typeof node === "string" || typeof node === "number") return String(node);
  if (Array.isArray(node)) return node.map(flatText).join("");
  if (typeof node === "object" && "props" in node) {
    return flatText((node as { props: { children?: React.ReactNode } }).props.children);
  }
  return "";
}
