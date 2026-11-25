/**
 * The packaged changelog as data. Pure: text in, releases out, no import of the
 * file itself (that is `changelog.ts`, the one module that reads it).
 *
 * The file is Keep a Changelog: `## [x.y.z] - date` sections newest first, each
 * holding `### Added|Changed|Fixed|Removed` groups of `- ` entries. The section
 * `## [Unreleased]` is not a release and is left out.
 */

import { CHANGELOG } from "./consts";

export interface ChangelogGroup {
  /** The group's own heading, as written: Added, Changed, Fixed, Removed. */
  heading: string;
  /** One entry per `- ` line, its continuation lines joined with a space. */
  entries: string[];
}

export interface ChangelogRelease {
  version: string;
  /** The date after the version, or "" when the section has none. */
  date: string;
  groups: ChangelogGroup[];
}

// The section heading is the contract's (consts.json changelog.releaseHeadingRegex):
// the agent reads a Space's changelog by the same one.
const RELEASE_HEADING = new RegExp(CHANGELOG.releaseHeadingRegex);
const UNRELEASED = /^unreleased$/i;
const GROUP_HEADING = /^###\s+(.+?)\s*$/;
const ANY_HEADING = /^#{1,6}\s/;
const ENTRY = /^-\s+(.*)$/;

/** Every released section of the file, in the file's order (newest first). */
export function parseChangelog(text: string): ChangelogRelease[] {
  const releases: ChangelogRelease[] = [];
  let release: ChangelogRelease | null = null;
  let group: ChangelogGroup | null = null;
  // The entry still being written, which a following non-blank line continues.
  let open: { group: ChangelogGroup; index: number } | null = null;

  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trimEnd();
    const section = RELEASE_HEADING.exec(line);
    if (section) {
      group = null;
      open = null;
      release = UNRELEASED.test(section[1])
        ? null
        : { version: section[1], date: section[2] ?? "", groups: [] };
      if (release) releases.push(release);
      continue;
    }
    if (!release) continue;
    const heading = GROUP_HEADING.exec(line);
    if (heading) {
      group = { heading: heading[1], entries: [] };
      release.groups.push(group);
      open = null;
      continue;
    }
    if (ANY_HEADING.test(line)) {
      group = null;
      open = null;
      continue;
    }
    if (!group) continue;
    if (line.trim() === "") {
      open = null;
      continue;
    }
    const entry = ENTRY.exec(line);
    if (entry) {
      group.entries.push(entry[1]);
      open = { group, index: group.entries.length - 1 };
      continue;
    }
    if (open) {
      open.group.entries[open.index] += ` ${line.trim()}`;
    }
  }
  return releases;
}

/** The section for one version, or undefined when the file has none. */
export const findRelease = (
  releases: ChangelogRelease[],
  version: string,
): ChangelogRelease | undefined => releases.find((r) => r.version === version);
