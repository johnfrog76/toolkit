import type { MouseEvent, ReactNode } from "react";
import { Link } from "react-router";
import { resolveLink } from "./docLinks";
import type { DocLinkBase } from "./docLinks";

// One link in a document, drawn by the kind `resolveLink` gives it: a
// room is an in-app Link (the anchor rides along in its address), an anchor
// scrolls this page, and everything else leaves in a new tab -- with the
// title that says why, when it is a repo file this room does not read. Its own
// file so the three kinds can be rendered in a test without react-markdown.

interface Props {
  href?: string;
  base?: DocLinkBase;
  /** Scroll to a heading of this page; the viewer passes its own. */
  onAnchor?: (id: string) => void;
  className?: string;
  children?: ReactNode;
}

export function DocLink({ href, base, onAnchor, className, children }: Props) {
  const r = resolveLink(href, base);
  if (r.kind === "room") {
    return (
      <Link to={r.to} className={className}>
        {children}
      </Link>
    );
  }
  if (r.kind === "anchor") {
    const onClick = (e: MouseEvent<HTMLAnchorElement>) => {
      e.preventDefault();
      onAnchor?.(r.id);
    };
    return (
      <a href={`#${r.id}`} className={className} onClick={onClick}>
        {children}
      </a>
    );
  }
  return (
    <a
      href={r.href}
      className={className}
      target="_blank"
      rel="noopener noreferrer"
      title={r.title}
    >
      {children}
    </a>
  );
}
