import { useCallback, useEffect, useRef, useState } from "react";
import { VERSION } from "./consts";
import type { ChangelogRelease } from "./changelogParse";
import { lazyPart } from "./lazy";
import { menuReleases, onLoadReleases, readSeenVersion, writeSeenVersion } from "./releaseNotes";

// What's new, the shell's: the dialog that tells you what the version you just
// opened brought. Core -- no feature flag, on whether or not a module is on --
// and it reads only the packaged changelog and the running version, no agent
// and no network.
//
// Two ways in: on its own, once per version per browser (the mark is
// releaseNotes.ts's), and from the account menu's "What's new" at any time.
//
// Two chunks, neither in the main bundle: the dialog (the markdown stack) and
// the changelog (changelog.ts, text that grows with every release). A page load
// on a version already shown fetches neither.

/** The dialog, drawn only while open. */
export const WhatsNewDialog = lazyPart(
  () => import("./WhatsNewDialog"),
  (m) => m.WhatsNewDialog,
  null,
);

const loadReleases = (): Promise<ChangelogRelease[]> =>
  import("./changelog").then((m) => m.RELEASES);

export interface WhatsNewSource {
  version: string;
  load: () => Promise<ChangelogRelease[]>;
}

const PACKAGED: WhatsNewSource = { version: VERSION, load: loadReleases };

export function useWhatsNew(source: WhatsNewSource = PACKAGED) {
  const [releases, setReleases] = useState<ChangelogRelease[] | null>(null);
  const started = useRef(false);

  // Once per page: StrictMode runs an effect twice, a ref survives that.
  useEffect(() => {
    if (started.current) return;
    started.current = true;
    if (readSeenVersion() === source.version) return;
    source
      .load()
      .then((all) => {
        const due = onLoadReleases(all, source.version, readSeenVersion());
        if (due.length === 0) return;
        // Marked when it opens, so a reload does not open it again.
        writeSeenVersion(source.version);
        setReleases(due);
      })
      .catch(() => {
        // The notes are a courtesy: a chunk that will not load is no reason to
        // say anything. The menu item tries again when asked.
      });
  }, [source]);

  const open = useCallback(() => {
    source
      .load()
      .then((all) => setReleases(menuReleases(all, source.version)))
      .catch(() => {});
  }, [source]);
  const close = useCallback(() => setReleases(null), []);

  return { releases, open, close };
}
