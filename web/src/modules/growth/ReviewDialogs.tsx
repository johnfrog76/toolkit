import { useState } from "react";
import {
  Body1,
  Button,
  Caption1,
  Checkbox,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  DialogTrigger,
  Field,
  Input,
  Spinner,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { DocumentSearchRegular } from "@fluentui/react-icons";
import { DialogDismiss } from "../../shared/DialogDismiss";
import type { SpaceInfo } from "../../shell/api";
import { useGenerateReviewMutation } from "./api.growth";
import { localToday, previousMonth } from "../../utility/dates";

// The Reviews panel's dialogs: the review scaffold, the resume scaffold, and
// how a resume update works. Each is mounted only while open, so each opening
// starts from the default range.

const prevMonthStart = () => previousMonth().start;
const prevMonthEnd = () => previousMonth().end;

const useStyles = makeStyles({
  markdownBody: {
    lineHeight: "1.6",
    "& h3": {
      fontSize: tokens.fontSizeBase300,
      fontWeight: tokens.fontWeightSemibold,
      marginTop: tokens.spacingVerticalM,
      marginBottom: tokens.spacingVerticalXS,
    },
    "& p": { marginTop: 0, marginBottom: tokens.spacingVerticalS },
    "& ul": { paddingLeft: "1.5rem", marginBottom: tokens.spacingVerticalS },
    "& li": { marginBottom: tokens.spacingVerticalXS },
    "& strong": { fontWeight: tokens.fontWeightSemibold },
    "& code": {
      fontFamily: tokens.fontFamilyMonospace,
      fontSize: tokens.fontSizeBase200,
      backgroundColor: tokens.colorNeutralBackground3,
      padding: "1px 4px",
      borderRadius: tokens.borderRadiusSmall,
    },
  },
  dialogFields: {
    display: "flex",
    flexDirection: "column" as const,
    gap: tokens.spacingVerticalM,
    paddingTop: tokens.spacingVerticalS,
  },
  dateRow: {
    display: "flex",
    gap: tokens.spacingHorizontalM,
    alignItems: "flex-end",
  },
  successBox: {
    display: "flex",
    flexDirection: "column" as const,
    gap: tokens.spacingVerticalXS,
    marginTop: tokens.spacingVerticalS,
    padding: tokens.spacingVerticalS,
    backgroundColor: tokens.colorNeutralBackground3,
    borderRadius: tokens.borderRadiusMedium,
  },
});

interface CloseProps {
  onClose: () => void;
}

/** How a resume update works: the resume item's own explanation. */
export function ResumeInfoDialog({ onClose }: CloseProps) {
  const styles = useStyles();
  return (
    <Dialog
      open
      onOpenChange={(_e, d) => {
        if (!d.open) onClose();
      }}
    >
      <DialogSurface>
        <DialogBody>
          <DialogTitle action={<DialogDismiss />}>Updating Your Resume</DialogTitle>
          <DialogContent>
            <div className={styles.markdownBody}>
              <p>
                Resume updates use an <strong>agentic workflow</strong> in Copilot Chat. The agent
                scans your work artifacts, reads review reports, and patches{" "}
                <code>resume/resume.md</code> with new accomplishments.
              </p>
              <h3>Slash command (recommended)</h3>
              <p>In Copilot Chat, type:</p>
              <code>/update-resume since January 2026</code>
              <p style={{ marginTop: tokens.spacingVerticalS }}>
                The agent will scan <code>archive/</code>, <code>spec/</code>, <code>reviews/</code>
                , and <code>growth/</code> for work in that date range, then update the{" "}
                <strong>Recent Work</strong> section of your resume.
              </p>
              <h3>Workflow</h3>
              <ol>
                <li>
                  Use <strong>Generate scaffold</strong> (via the overflow menu on the resume card)
                  to scaffold what artifacts exist for a date range
                </li>
                <li>
                  Run <code>/update-resume</code> in Copilot Chat — the agent reads the scaffold +
                  existing resume and writes updates
                </li>
                <li>Review changes, then commit via the Review page</li>
              </ol>
              <h3>Output</h3>
              <p>
                Changes are written directly to <code>resume/resume.md</code> and appear in the
                Resume viewer.
              </p>
            </div>
          </DialogContent>
          <DialogActions>
            <DialogTrigger disableButtonEnhancement>
              <Button appearance="secondary">Close</Button>
            </DialogTrigger>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}

/** The resume scaffold for a date range, in the active Space. */
export function GenerateResumeDialog({
  activeSpace,
  onClose,
}: CloseProps & { activeSpace: string }) {
  const styles = useStyles();
  const [generateResume, { isLoading: isGenerating }] = useGenerateReviewMutation();
  const [startDate, setStartDate] = useState(prevMonthStart);
  const [endDate, setEndDate] = useState(prevMonthEnd);
  const [generateError, setGenerateError] = useState<string | null>(null);
  const [generateMeta, setGenerateMeta] = useState<{
    filePath: string;
    filesIncluded: number;
  } | null>(null);

  const handleGenerate = async () => {
    setGenerateError(null);
    setGenerateMeta(null);
    try {
      const data = await generateResume({
        start_date: startDate,
        end_date: endDate,
        slugs: activeSpace ? [activeSpace] : [],
      }).unwrap();
      setGenerateMeta({ filePath: data.file_path, filesIncluded: data.files_included });
    } catch (e) {
      const err = e as { data?: { detail?: string }; error?: string };
      setGenerateError(err.data?.detail ?? err.error ?? "Generation failed");
    }
  };

  return (
    <Dialog
      open
      onOpenChange={(_e, d) => {
        if (!d.open) onClose();
      }}
    >
      <DialogSurface>
        <DialogBody>
          <DialogTitle action={<DialogDismiss />}>Generate Resume Scaffold</DialogTitle>
          <DialogContent>
            <div className={styles.dialogFields}>
              <div className={styles.dateRow}>
                <Field label="Start date">
                  <Input
                    type="date"
                    size="small"
                    value={startDate}
                    max={endDate}
                    onChange={(_, d) => setStartDate(d.value)}
                    style={{ width: "145px" }}
                  />
                </Field>
                <Field label="End date">
                  <Input
                    type="date"
                    size="small"
                    value={endDate}
                    min={startDate}
                    max={localToday()}
                    onChange={(_, d) => setEndDate(d.value)}
                    style={{ width: "145px" }}
                  />
                </Field>
              </div>
              {generateError && (
                <Body1 style={{ color: tokens.colorPaletteRedForeground1 }}>{generateError}</Body1>
              )}
              {generateMeta && (
                <div className={styles.successBox}>
                  <Body1>
                    <strong>{generateMeta.filesIncluded}</strong> artifacts found
                  </Body1>
                  <Caption1 style={{ color: tokens.colorNeutralForeground3 }}>
                    {generateMeta.filePath}
                  </Caption1>
                  <Caption1 style={{ marginTop: tokens.spacingVerticalXS }}>
                    Now run{" "}
                    <code style={{ fontFamily: tokens.fontFamilyMonospace }}>/update-resume</code>{" "}
                    in Copilot Chat.
                  </Caption1>
                </div>
              )}
            </div>
          </DialogContent>
          <DialogActions>
            <DialogTrigger disableButtonEnhancement>
              <Button appearance="secondary" disabled={isGenerating}>
                {generateMeta ? "Done" : "Cancel"}
              </Button>
            </DialogTrigger>
            {!generateMeta && (
              <Button
                icon={
                  isGenerating ? (
                    <Spinner size="tiny" aria-label="Generating..." />
                  ) : (
                    <DocumentSearchRegular />
                  )
                }
                appearance="primary"
                disabled={isGenerating || !startDate || !endDate}
                onClick={handleGenerate}
              >
                {isGenerating ? "Generating…" : "Generate"}
              </Button>
            )}
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}

/** The review scaffold for a date range, over the Spaces ticked. */
export function GenerateReviewDialog({
  orgs,
  activeSpace,
  onClose,
}: CloseProps & { orgs: SpaceInfo[]; activeSpace: string }) {
  const styles = useStyles();
  const [generateReview, { isLoading: isGenerating }] = useGenerateReviewMutation();
  const [startDate, setStartDate] = useState(prevMonthStart);
  const [endDate, setEndDate] = useState(prevMonthEnd);
  const [generateError, setGenerateError] = useState<string | null>(null);
  const [selectedSlugs, setSelectedSlugs] = useState<Set<string>>(
    () => new Set(activeSpace ? [activeSpace] : []),
  );

  const toggleSlug = (s: string, checked: boolean) => {
    setSelectedSlugs((prev) => {
      const next = new Set(prev);
      if (checked) next.add(s);
      else next.delete(s);
      return next;
    });
  };

  const handleGenerate = async () => {
    setGenerateError(null);
    try {
      await generateReview({
        start_date: startDate,
        end_date: endDate,
        slugs: Array.from(selectedSlugs),
      }).unwrap();
      onClose();
    } catch (e) {
      const err = e as { data?: { detail?: string }; error?: string };
      setGenerateError(err.data?.detail ?? err.error ?? "Generation failed");
    }
  };

  return (
    <Dialog
      open
      onOpenChange={(_e, d) => {
        if (!d.open) onClose();
      }}
    >
      <DialogSurface>
        <DialogBody>
          <DialogTitle action={<DialogDismiss />}>Generate Review</DialogTitle>
          <DialogContent>
            <div className={styles.dialogFields}>
              <div className={styles.dateRow}>
                <Field label="Start date">
                  <Input
                    type="date"
                    size="small"
                    value={startDate}
                    max={endDate}
                    onChange={(_, d) => setStartDate(d.value)}
                    style={{ width: "145px" }}
                  />
                </Field>
                <Field label="End date">
                  <Input
                    type="date"
                    size="small"
                    value={endDate}
                    min={startDate}
                    max={localToday()}
                    onChange={(_, d) => setEndDate(d.value)}
                    style={{ width: "145px" }}
                  />
                </Field>
              </div>
              {orgs.length > 0 && (
                <Field label="Spaces" hint="Select one or more spaces to include in this review.">
                  <div
                    style={{
                      display: "flex",
                      flexDirection: "column",
                      gap: tokens.spacingVerticalXS,
                    }}
                  >
                    {orgs.map((o) => (
                      <Checkbox
                        key={o.slug}
                        label={<Caption1>{o.name}</Caption1>}
                        checked={selectedSlugs.has(o.slug)}
                        onChange={(_e, data) => toggleSlug(o.slug, !!data.checked)}
                        disabled={isGenerating}
                      />
                    ))}
                  </div>
                </Field>
              )}
              {generateError && (
                <Body1 style={{ color: tokens.colorPaletteRedForeground1 }}>{generateError}</Body1>
              )}
            </div>
          </DialogContent>
          <DialogActions>
            <DialogTrigger disableButtonEnhancement>
              <Button appearance="secondary" disabled={isGenerating}>
                Cancel
              </Button>
            </DialogTrigger>
            <Button
              icon={
                isGenerating ? (
                  <Spinner size="tiny" aria-label="Generating..." />
                ) : (
                  <DocumentSearchRegular />
                )
              }
              appearance="primary"
              disabled={isGenerating || !startDate || !endDate || selectedSlugs.size === 0}
              onClick={handleGenerate}
            >
              {isGenerating ? "Generating…" : "Generate"}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
