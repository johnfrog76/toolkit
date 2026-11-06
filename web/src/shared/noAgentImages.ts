import { AGENT } from "../shell/consts";

// Where a picture in a document may point: anywhere but the agent.
//
// Markdown is text from elsewhere -- an issue, a comment, a card made from one --
// and drawing it makes the browser ask for each picture. So a picture must never
// be a way to call the agent: this step runs after the sanitiser, on every
// document, and drops a `src` or `srcset` aimed at the API or at this machine.
// Nothing real is lost. Covers are drawn by CardCover, and a document's own
// pictures are built by `assetFor` after this step. The agent refuses the same
// requests by itself (agent/core/request_gate.py), so neither side relies on
// the other.

// A base that cannot match a real page. What is left relative resolves against
// the root, which is the worst case: `../` climbs to it from any page.
const BASE = "http://document.invalid/";

function isLoopback(hostname: string): boolean {
  return (
    hostname === "localhost" ||
    hostname.endsWith(".localhost") ||
    hostname === "0.0.0.0" ||
    hostname === "[::1]" ||
    hostname.startsWith("127.")
  );
}

function decoded(path: string): string {
  try {
    return decodeURIComponent(path);
  } catch {
    return path;
  }
}

/** Whether a URL in a document reaches the agent's API or this machine. */
export function pointsAtAgent(raw: string): boolean {
  let url: URL;
  try {
    url = new URL(raw.trim(), BASE);
  } catch {
    return false;
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") return false;
  if (isLoopback(url.hostname)) return true;
  if (url.origin !== new URL(BASE).origin) return false;
  const path = decoded(url.pathname).replace(/\\/g, "/");
  return path === AGENT.apiPrefix || path.startsWith(`${AGENT.apiPrefix}/`);
}

interface Node {
  type?: string;
  tagName?: string;
  properties?: Record<string, unknown>;
  children?: Node[];
}

/** A `srcset` as its words: each URL is one, and a descriptor reads as no URL
 *  that matters. Commas are left on: a trailing one does not change the host
 *  or the path's start. */
function srcSetWords(value: unknown): string[] {
  const text = Array.isArray(value) ? value.join(" ") : String(value ?? "");
  return text.split(/\s+/).filter(Boolean);
}

function clean(node: Node): void {
  const props = node.properties;
  if (props && (node.tagName === "img" || node.tagName === "source")) {
    if (typeof props.src === "string" && pointsAtAgent(props.src)) delete props.src;
    if (srcSetWords(props.srcSet).some(pointsAtAgent)) delete props.srcSet;
  }
  node.children?.forEach(clean);
}

/** The rehype step. */
export function rehypeNoAgentImages() {
  return clean;
}
