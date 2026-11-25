/**
 * The File line's words, said once (shared/FilePath.tsx). The visible label
 * names the ACTION and is the button's accessible name; the address itself
 * is the tooltip and the description, never the visible text, so the line is
 * the same width however long the address is.
 */
export const FILE_LINE = {
  /** A local file: the absolute path on this machine. */
  copyPath: "Copy the file path",
  /** An address that is not a local file: a URL. */
  copyLink: "Copy the file link",
  copied: "Copied!",
} as const;
