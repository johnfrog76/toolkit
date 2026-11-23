import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  Button,
  DialogActions,
  DialogTrigger,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { DialogDismiss } from "../shared/DialogDismiss";
import { MarkdownBlock } from "../shared/MarkdownBlock";
import type { ChangelogRelease } from "./changelogParse";

// What's new: the release notes of the running version, the changelog section's
// lines under its own headings in the file's order. The entries are the file's
// markdown (code spans, bold, links), drawn by the app's one markdown block.
// Opened by WhatsNew.tsx -- on its own once per version, or from the account
// menu -- and loaded as a chunk of its own, because the markdown stack is not
// the shell's to carry on every page.

const useStyles = makeStyles({
  surface: { maxWidth: "640px" },
  version: {
    margin: `${tokens.spacingVerticalM} 0 0`,
    fontSize: tokens.fontSizeBase400,
    fontWeight: tokens.fontWeightSemibold,
  },
  heading: {
    margin: `${tokens.spacingVerticalM} 0 ${tokens.spacingVerticalXS}`,
    fontSize: tokens.fontSizeBase300,
    fontWeight: tokens.fontWeightSemibold,
  },
});

/** The dialog's title: the release version, the newest one shown. */
export const whatsNewTitle = (releases: ChangelogRelease[]): string =>
  releases.length > 0 ? `What's new in ${releases[0].version}` : "What's new";

export function WhatsNewDialog({
  releases,
  onClose,
}: {
  releases: ChangelogRelease[];
  onClose: () => void;
}) {
  const styles = useStyles();
  const several = releases.length > 1;
  return (
    <Dialog open onOpenChange={(_e, d) => !d.open && onClose()}>
      <DialogSurface className={styles.surface} data-testid="whats-new-dialog">
        <DialogBody>
          <DialogTitle action={<DialogDismiss />}>{whatsNewTitle(releases)}</DialogTitle>
          <DialogContent>
            {releases.map((release) => (
              <section key={release.version} aria-label={`Version ${release.version}`}>
                {several ? (
                  <h3 className={styles.version}>
                    {release.version}
                    {release.date ? ` - ${release.date}` : ""}
                  </h3>
                ) : null}
                {release.groups.map((group) => (
                  <div key={group.heading}>
                    <h4 className={styles.heading}>{group.heading}</h4>
                    <MarkdownBlock>{group.entries.map((e) => `- ${e}`).join("\n")}</MarkdownBlock>
                  </div>
                ))}
              </section>
            ))}
          </DialogContent>
          <DialogActions>
            <DialogTrigger disableButtonEnhancement>
              <Button appearance="primary">Close</Button>
            </DialogTrigger>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
