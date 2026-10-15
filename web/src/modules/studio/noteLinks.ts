// The base a hub design note's links resolve against -- handed to the ONE
// resolver, shared/docLinks.ts, the way the Design and Docs rooms hand it a
// repo's base. A hub note is not in a repo: a relative link to a sibling note
// (`other-idea.md`) opens that note's room here; anything else has no room and
// no github.com page to fall back on, so it is left as written.
import { STUDIO, toRegExp } from "../../shell/consts";
import type { DocLinkBase } from "../../shared/docLinks";
import { notePath } from "./paths";

const NOTE_NAME = toRegExp(STUDIO.noteName);

export function noteLinkBase(folder: string, name: string): DocLinkBase {
  return {
    path: `${folder}/${name}`,
    roomFor: (p) => {
      const parts = p.split("/");
      return parts.length === 2 && parts[0] === folder && NOTE_NAME.test(parts[1])
        ? notePath(parts[1])
        : null;
    },
    // The hub serves no files to the browser; an image keeps the path it was given.
    assetFor: (p) => p,
    outside: () => "",
  };
}
