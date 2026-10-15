/**
 * "How do I…" -- the settings drawer's first section (docs/CONFIGURATION.md, "Settings by workflow: the questions, and the one list behind them";
 * D-W1, D-W4, D-W6, D-W11): every question of Config/settings-workflows.json as
 * a row -- the question, one sentence, the state as the CLI computed it, and
 * the door. Core, no flag: a module that is off still has its question here,
 * because the inventory names what exists.
 *
 * Folds when the drawer opened AT an anchor (D-W11): a deep link is on its way
 * to a key's row and should not scroll past the questions. The fold is a
 * button, so the questions are one click away either way.
 *
 * The state chip's words are the CLI's three, verbatim. The tooltip carries
 * the key and the CLI line, so the web and the terminal say the same thing.
 *
 * An entry with `answers` ("How do you want to work in {space}?") is
 * asked here, not only answered: the Space's question, one radio per answer,
 * and a pick runs `Config -Set <answerKey>=<value> -Hub` through PUT
 * /api/config -- the one writer, the same line a terminal types. What is
 * checked, and what can be picked, is the agent's answer for the Space you are
 * in (/env howIWork); the web never re-derives it.
 */
import { useState } from "react";
import {
  Badge,
  Body1,
  Body1Strong,
  Button,
  Caption1,
  Radio,
  RadioGroup,
  Spinner,
  Tooltip,
  makeStyles,
  tokens,
  useId,
} from "@fluentui/react-components";
import { ChevronDownRegular, ChevronRightRegular } from "@fluentui/react-icons";
import { useNavigate } from "react-router";
import { useGetEnvQuery, useGetSurfacesQuery } from "./api";
import type { HowIWork } from "./api";
import { useOpenSettings } from "./cards";
import { useWriteConfigMutation } from "./registry";
import {
  WORKFLOW_ENTRIES,
  answerLive,
  answerTarget,
  entryAnchor,
  entryConfigLines,
  entryQuestion,
  entryRoute,
  entryState,
} from "./settingsWorkflows";
import type { SurfaceState, TrackerKind, WorkflowEntry } from "./settingsWorkflows";

const useStyles = makeStyles({
  section: {
    marginBottom: tokens.spacingVerticalL,
  },
  head: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    background: "transparent",
    border: "none",
    padding: `${tokens.spacingVerticalS} 0`,
    cursor: "pointer",
    color: tokens.colorNeutralForeground1,
    font: "inherit",
  },
  row: {
    display: "grid",
    gridTemplateColumns: "1fr auto",
    columnGap: tokens.spacingHorizontalM,
    rowGap: tokens.spacingVerticalXXS,
    padding: `${tokens.spacingVerticalS} 0`,
    borderBottom: `1px solid ${tokens.colorNeutralStroke2}`,
    alignItems: "center",
  },
  sentence: {
    color: tokens.colorNeutralForeground3,
    gridColumn: "1 / -1",
  },
  right: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
  },
  unavailable: {
    color: tokens.colorNeutralForeground3,
    padding: `${tokens.spacingVerticalS} 0`,
  },
  answers: {
    gridColumn: "1 / -1",
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalXS,
  },
  // The spinner stands BESIDE the group, so the group gives it room
  // rather than the row wrapping it underneath in a narrow drawer.
  answerGroup: {
    display: "flex",
    alignItems: "flex-start",
    columnGap: tokens.spacingHorizontalM,
  },
  answerRadios: {
    flex: "1 1 auto",
    minWidth: 0,
  },
  saving: {
    flexShrink: 0,
    paddingTop: tokens.spacingVerticalS,
  },
  answer: {
    display: "flex",
    flexDirection: "column",
  },
  answerSentence: {
    color: tokens.colorNeutralForeground3,
    // Under the radio's label, past the circle.
    paddingLeft: "32px",
  },
  why: {
    color: tokens.colorNeutralForeground3,
  },
  // A choice the Space cannot make keeps the circle's disabled look; its label
  // reads as the sentence under it does, not as Fluent's disabled grey. Fluent
  // sets that grey with `input:disabled ~ label`, which outranks any plain
  // class on the label, so this one is important.
  lockedLabel: {
    color: `${tokens.colorNeutralForeground3} !important`,
  },
  refused: {
    color: tokens.colorPaletteRedForeground1,
  },
});

/**
 * The radios of an entry that asks. Every answer is drawn -- one the
 * Space cannot make is disabled, never hidden, and `why` says in one sentence
 * why for this Space's tracker -- and the one checked is the agent's (/env
 * howIWork). A pick writes `<answerKey>=<value>` with -Hub through the one
 * config writer and shows at once: the radio is checked, the others are
 * locked, a tiny "Saving…" spinner stands beside the group and the group is
 * announced busy. A refusal puts the pick back and shows the CLI's sentence.
 */
function Answers({
  entry,
  question,
  target,
  how,
}: {
  entry: WorkflowEntry;
  question: string;
  target: string;
  how: HowIWork | undefined;
}) {
  const styles = useStyles();
  const baseId = useId("how-answer");
  const [writeConfig] = useWriteConfigMutation();
  const [picked, setPicked] = useState<string | undefined>(undefined);
  const [saving, setSaving] = useState(false);
  const [refused, setRefused] = useState<string | null>(null);
  const answers = entry.answers ?? [];
  // No answer from the agent (an older one, or not yet): nothing can be picked.
  const tracker: TrackerKind = how?.tracker ?? "none";
  const locked = how ? how.locked : true;
  const value = picked ?? how?.answer ?? "";
  const why = how ? entry.why?.[tracker] : undefined;
  const waitsOnSwitch = !!how && !locked && value === "agents" && how.switch !== true;

  async function pick(next: string) {
    const answer = answers.find((a) => a.value === next);
    if (!answer || saving || !answerLive(answer, tracker, locked)) return;
    setPicked(next);
    setRefused(null);
    setSaving(true);
    try {
      const reply = await writeConfig({ set: { [target]: next }, unset: [], hub: true }).unwrap();
      if (reply.result.status !== "success") {
        setPicked(undefined);
        setRefused(reply.result.error || reply.result.output || "Config -Set refused.");
      }
    } catch {
      setPicked(undefined);
      setRefused("The agent did not answer -- nothing was set.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className={styles.answers}>
      <div className={styles.answerGroup}>
        <RadioGroup
          className={styles.answerRadios}
          value={value}
          aria-label={question}
          aria-busy={saving}
          onChange={(_e, d) => void pick(d.value)}
        >
          {answers.map((a) => {
            const live = answerLive(a, tracker, locked);
            return (
              <div key={a.value} className={styles.answer}>
                <Radio
                  value={a.value}
                  label={{ children: a.label, className: live ? undefined : styles.lockedLabel }}
                  aria-describedby={`${baseId}-${a.value}`}
                  disabled={!live || (saving && a.value !== value)}
                />
                <Caption1 id={`${baseId}-${a.value}`} className={styles.answerSentence}>
                  {a.sentence}
                </Caption1>
              </div>
            );
          })}
        </RadioGroup>
        {saving ? <Spinner className={styles.saving} size="tiny" label="Saving…" /> : null}
      </div>
      {why ? <Caption1 className={styles.why}>{why}</Caption1> : null}
      {waitsOnSwitch ? (
        <Caption1 className={styles.why}>
          Team Agile&apos;s own switch is off, so With agents waits for it -- Change turns it on.
        </Caption1>
      ) : null}
      {refused ? <Caption1 className={styles.refused}>{refused}</Caption1> : null}
    </div>
  );
}

const STATE_COLOR: Record<SurfaceState, "success" | "informative" | "warning"> = {
  on: "success",
  off: "informative",
  "not configured": "warning",
};

/** The door's label: Change for a key; Set it up for a journey -- its own page
 *  when it has one (the connect wizard), else the drawer at its first key. */
export function doorLabel(entry: WorkflowEntry): string | null {
  if (entry.door === "sentence") return null;
  if (entry.door === "walk") return entry.anchor || entry.route ? "Set it up" : null;
  return "Change";
}

export function HowDoI({ anchor }: { anchor?: string }) {
  const styles = useStyles();
  const openSettings = useOpenSettings();
  const navigate = useNavigate();
  const { data, isError } = useGetSurfacesQuery();
  // The declared Spaces, so a question about one demo Space walks THAT Space
  // when it is here, and yours when it is not.
  const { data: env } = useGetEnvQuery();
  const declared = env?.config?.spaces ?? [];
  // Folded on arrival at an anchor (D-W11); a click unfolds, and the choice
  // lasts for this opening of the drawer.
  const [folded, setFolded] = useState(Boolean(anchor));
  const surfaces = data?.surfaces ?? [];
  const activeSpace = data?.activeSpace ?? env?.config?.activeSpace ?? "";
  // The Space's own name for a question that names it ({space}).
  const spaceName = declared.find((s) => s.slug === activeSpace)?.name || activeSpace;

  return (
    <section className={styles.section} aria-labelledby="how-do-i-heading">
      <button
        type="button"
        className={styles.head}
        onClick={() => setFolded((f) => !f)}
        aria-expanded={!folded}
        aria-controls="how-do-i-list"
      >
        {folded ? <ChevronRightRegular /> : <ChevronDownRegular />}
        <Body1Strong id="how-do-i-heading">How do I…</Body1Strong>
        <Caption1>{WORKFLOW_ENTRIES.length} questions</Caption1>
      </button>
      {folded ? null : (
        <div id="how-do-i-list">
          {isError ? (
            <Caption1 className={styles.unavailable}>
              The states are the CLI&apos;s, and it did not answer -- the questions still stand, the
              chips do not.
            </Caption1>
          ) : null}
          {WORKFLOW_ENTRIES.map((entry) => {
            const state = entryState(entry, surfaces);
            const label = doorLabel(entry);
            const target = entryAnchor(entry, activeSpace);
            const page = entryRoute(entry, activeSpace, declared);
            const lines = entryConfigLines(entry, surfaces);
            const tip = [entry.surfaces.join(", "), ...lines].join("\n");
            const question = entryQuestion(entry, spaceName);
            const answerKey = answerTarget(entry, activeSpace);
            return (
              <div key={entry.id} className={styles.row} data-workflow-entry={entry.id}>
                <Tooltip
                  content={<span style={{ whiteSpace: "pre-line" }}>{tip}</span>}
                  relationship="description"
                >
                  <Body1Strong>{question}</Body1Strong>
                </Tooltip>
                <div className={styles.right}>
                  {surfaces.length > 0 ? (
                    <Badge appearance="tint" size="small" color={STATE_COLOR[state]}>
                      {state}
                    </Badge>
                  ) : null}
                  {label && (page || target) ? (
                    <Button
                      size="small"
                      appearance="secondary"
                      onClick={() => (page ? navigate(page) : openSettings(target!))}
                    >
                      {label}
                    </Button>
                  ) : null}
                </div>
                <Body1 className={styles.sentence}>{entry.sentence}</Body1>
                {entry.answers && answerKey ? (
                  <Answers
                    // A pick belongs to the Space it was made in: a Space switch
                    // with the drawer open starts from that Space's own answer.
                    key={activeSpace}
                    entry={entry}
                    question={question}
                    target={answerKey}
                    how={env?.howIWork}
                  />
                ) : null}
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
