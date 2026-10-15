// The reading room's "document with a thread" face (Studio S2 and S2b): a
// design document -- a repo's design/ or spec/ file, or a hub design note --
// and, when its `> GitHub:` line names an issue that could be read, that
// issue's thread after it, in the SAME markdown, so the one viewer draws both:
// one zoom, one "On this page". Written once, here; the Design room and the
// Studio's note room both compose through it. The thread itself is drawn the
// way the issue's own reading room draws it (issueDocument).
import type { IssueDetail } from "./api.ado";
import { issueDocument } from "./IssueDetailPage";

/** The document, then its thread when it has one and it could be read. */
export function documentWithThread(body: string, thread?: IssueDetail): string {
  const parts = [body.trim() || "_This document is empty._"];
  if (thread && thread.supported && !thread.reason && thread.number) {
    const title = thread.title.replace(/([[\]])/g, "\\$1");
    parts.push(`## The thread: [#${thread.number} ${title}](${thread.url})`, issueDocument(thread));
  }
  return parts.join("\n\n");
}
