/**
 * The connect wizard, `/connect/:slug` (docs/CONFIGURATION.md, "Settings by workflow: the questions, and the one list behind them";
 * D-W12 to D-W17): four steps, each named as whose it is, over the ONE
 * verb -- `Connect <slug>` reports the steps with -AsJson and each step is the
 * same verb with one switch, run through the bridge. The page holds no
 * state the verb does not; every write is Config's, through the CLI.
 *
 * A Space's grain follows its tracker (D-W17), and step 1 says so: an Azure
 * DevOps Space is an organisation with projects inside it; a GitHub Space is
 * one repo; a Space with no address works from your cards alone -- a whole
 * shape, not a missing step. Step 2 is SAID and CHECKED, never run: the exact
 * command, and a button that asks again. Discovery lists what the address
 * holds; picking writes projects (ADO) or the repo-grained address (GitHub).
 * The last step is sprint awareness. A shipped demo Space -- the Azure demo,
 * the GitHub demo -- graduates from here too (D-W15): your slug, its
 * folder moved, made active.
 */
import { useState } from "react";
import { useParams } from "react-router";
import {
  Badge,
  Body1,
  Body1Strong,
  Button,
  Caption1,
  Checkbox,
  Input,
  Radio,
  RadioGroup,
  Subtitle2,
  Switch,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { BackButton } from "../../shared/BackButton";
import { PageCard } from "../../shared/PageCard";
import { PageGrid } from "../../shell/cards";
import { useConnectStepMutation, useGetConnectStateQuery } from "./api.ado";
import type { CommandResponse } from "./api.ado";

export interface ConnectReport {
  slug: string;
  name: string;
  active: boolean;
  example: boolean;
  address: string;
  tracker: "ado" | "github" | "none";
  grain: string;
  status: string;
  steps: {
    address: { done: boolean; yours: boolean };
    signIn: {
      done: boolean;
      yours: boolean;
      tool: string;
      installed: boolean;
      identity: string;
      command: string;
    };
    projects: {
      done: boolean;
      yours: boolean;
      configured: { name: string; repo?: string }[];
      available: { name: string; repo?: string; repos?: string[]; defaultBranch?: string }[];
    };
    sprint: { done: boolean; yours: boolean; on: boolean };
  };
  did: string[];
  whatIf: boolean;
}

/** The verb's one JSON line, out of whatever else it printed. */
export function parseReport(res: CommandResponse | undefined): ConnectReport | null {
  const line = (res?.output ?? "")
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.startsWith("{"))
    .pop();
  if (!line) return null;
  try {
    return JSON.parse(line) as ConnectReport;
  } catch {
    return null;
  }
}

const useStyles = makeStyles({
  step: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalS,
    padding: `${tokens.spacingVerticalS} 0`,
  },
  who: { color: tokens.colorNeutralForeground3 },
  row: { display: "flex", alignItems: "center", gap: tokens.spacingHorizontalS, flexWrap: "wrap" },
  code: {
    fontFamily: tokens.fontFamilyMonospace,
    backgroundColor: tokens.colorNeutralBackground3,
    padding: `${tokens.spacingVerticalXS} ${tokens.spacingHorizontalS}`,
    borderRadius: tokens.borderRadiusMedium,
  },
  error: { color: tokens.colorPaletteRedForeground1 },
  list: { display: "flex", flexDirection: "column", gap: tokens.spacingVerticalXS },
});

function StepHeader({
  n,
  title,
  done,
  yours,
}: {
  n: number;
  title: string;
  done: boolean;
  yours: boolean;
}) {
  const styles = useStyles();
  return (
    <div className={styles.row}>
      <Badge
        appearance={done ? "filled" : "outline"}
        color={done ? "success" : "informative"}
        size="small"
      >
        {done ? "done" : `step ${n}`}
      </Badge>
      <Subtitle2 as="h2">{title}</Subtitle2>
      <Caption1 className={styles.who}>{yours ? "yours" : "ours"}</Caption1>
    </div>
  );
}

export function ConnectPage() {
  const styles = useStyles();
  const { slug = "" } = useParams<{ slug: string }>();
  const { data, isFetching, refetch } = useGetConnectStateQuery(slug, { skip: !slug });
  const [step, { isLoading: stepping }] = useConnectStepMutation();
  const report = parseReport(data);
  // The field starts at the report's address and follows it when it changes --
  // noticed while rendering, against the address the last render saw.
  const [address, setAddress] = useState(report?.address ?? "");
  const [seenAddress, setSeenAddress] = useState(report?.address);
  if (seenAddress !== report?.address) {
    setSeenAddress(report?.address);
    if (report) setAddress(report.address ?? "");
  }
  const [picked, setPicked] = useState<string[]>([]);
  const [repo, setRepo] = useState("");
  const [newSlug, setNewSlug] = useState("");
  const [lastError, setLastError] = useState<string | null>(null);
  const [discovered, setDiscovered] = useState<ConnectReport | null>(null);

  const run = async (params: string[]) => {
    setLastError(null);
    try {
      const res = await step({ slug, params }).unwrap();
      if (res.status !== "success")
        setLastError(res.error ?? res.output ?? "The step was refused.");
      return res;
    } catch {
      setLastError("The agent did not answer.");
      return null;
    }
  };

  const discover = async () => {
    const res = await run(["-Discover"]);
    setDiscovered(res ? parseReport(res) : null);
  };

  if (!slug) return null;
  const notFound = data && data.status !== "success" && !report;
  const tracker = report?.tracker ?? "none";
  const available = discovered?.steps.projects.available ?? [];
  const repoGrained = tracker === "github" && report?.grain === "one GitHub repo";

  return (
    <PageGrid>
      <PageCard
        loading={isFetching && !report}
        loadingLabel="Asking the toolkit where this Space stands…"
        headerLeft={
          <span className={styles.row}>
            <BackButton />
            <Subtitle2 as="h1">Connect {report?.name ?? slug}</Subtitle2>
          </span>
        }
        headerRight={
          <Button size="small" appearance="subtle" onClick={() => refetch()} disabled={isFetching}>
            Check again
          </Button>
        }
      >
        {notFound ? (
          <Body1 className={styles.error}>{data?.error ?? data?.output ?? "No such Space."}</Body1>
        ) : null}
        {lastError ? <Body1 className={styles.error}>{lastError}</Body1> : null}
        {report ? (
          <>
            <section className={styles.step} aria-label="Step 1, the address">
              <StepHeader n={1} title="The address" done={report.steps.address.done} yours />
              <Body1>
                {report.address && !report.steps.address.done ? (
                  // Shipped with an address and still local -- the GitHub demo:
                  //the address is here, the connection is not, and
                  // saving it (or your own) is the step.
                  <>
                    <strong>{report.address}</strong> -- {report.grain}. This Space is local until
                    you connect it: keep this address, or give it your own, and connect.
                  </>
                ) : report.address ? (
                  <>
                    <strong>{report.address}</strong> -- {report.grain}.
                  </>
                ) : (
                  <>
                    This Space works from your cards alone -- a whole shape, not a missing step. To
                    connect it, give it an address.
                  </>
                )}
              </Body1>
              <Caption1 className={styles.who}>
                An Azure DevOps Space is an organisation, with projects inside it:
                https://dev.azure.com/&lt;org&gt;. A GitHub Space is one repo:
                https://github.com/&lt;owner&gt;/&lt;repo&gt;. An address makes the Space active.
              </Caption1>
              <div className={styles.row}>
                <Input
                  aria-label="Address"
                  value={address}
                  onChange={(_e, d) => setAddress(d.value)}
                  placeholder="https://dev.azure.com/your-org or https://github.com/owner/repo"
                  style={{ minWidth: "28rem" }}
                />
                <Button
                  appearance="primary"
                  disabled={
                    stepping ||
                    (address === report.address && (report.steps.address.done || !address))
                  }
                  onClick={() => void run(["-Address", address])}
                >
                  {address && address === report.address && !report.steps.address.done
                    ? "Connect"
                    : "Save address"}
                </Button>
              </div>
            </section>

            <section className={styles.step} aria-label="Step 2, sign in">
              <StepHeader n={2} title="Sign in" done={report.steps.signIn.done} yours />
              {tracker === "none" ? (
                <Body1 className={styles.who}>After the address.</Body1>
              ) : !report.steps.signIn.installed ? (
                <Body1>
                  <strong>{report.steps.signIn.tool}</strong> is not installed on this machine.
                  Install it, then run{" "}
                  <span className={styles.code}>{report.steps.signIn.command}</span> yourself, then
                  Check again.
                </Body1>
              ) : report.steps.signIn.done ? (
                <Body1>
                  Signed in to <strong>{report.steps.signIn.tool}</strong>
                  {report.steps.signIn.identity ? <> as {report.steps.signIn.identity}</> : null}.
                </Body1>
              ) : (
                <Body1>
                  Run <span className={styles.code}>{report.steps.signIn.command}</span> in a
                  terminal -- the toolkit never signs in for you -- then Check again.
                </Body1>
              )}
            </section>

            <section className={styles.step} aria-label="Step 3, what the address holds">
              <StepHeader
                n={3}
                title={tracker === "github" ? "The repo" : "The projects"}
                done={report.steps.projects.done || repoGrained}
                yours={false}
              />
              {tracker === "none" ? (
                <Body1 className={styles.who}>After the address.</Body1>
              ) : (
                <>
                  {report.steps.projects.configured.length > 0 ? (
                    <Body1>
                      Working in:{" "}
                      {report.steps.projects.configured
                        .map((p) => (p.repo ? `${p.name}/${p.repo}` : p.name))
                        .join("; ")}
                    </Body1>
                  ) : repoGrained ? (
                    <Body1>
                      This Space is {report.address.replace("https://github.com/", "")}.
                    </Body1>
                  ) : null}
                  <div className={styles.row}>
                    <Button
                      onClick={() => void discover()}
                      disabled={stepping || !report.steps.signIn.done}
                    >
                      {tracker === "github" ? "List the repos" : "List the projects"}
                    </Button>
                    {!report.steps.signIn.done ? (
                      <Caption1 className={styles.who}>after you sign in</Caption1>
                    ) : null}
                  </div>
                  {available.length > 0 && tracker === "github" ? (
                    <div className={styles.list}>
                      <RadioGroup
                        value={repo}
                        onChange={(_e, d) => setRepo(d.value)}
                        aria-label="Pick the one repo this Space is"
                      >
                        {available.map((r) => (
                          <Radio
                            key={r.repo ?? r.name}
                            value={r.repo ?? r.name}
                            label={r.repo ?? r.name}
                          />
                        ))}
                      </RadioGroup>
                      <div>
                        <Button
                          appearance="primary"
                          disabled={!repo || stepping}
                          onClick={() => void run(["-Repo", repo])}
                        >
                          This Space is that repo
                        </Button>
                      </div>
                    </div>
                  ) : null}
                  {available.length > 0 && tracker === "ado" ? (
                    <div className={styles.list}>
                      {available.map((p) => (
                        <Checkbox
                          key={p.name}
                          label={
                            p.repos && p.repos.length > 0
                              ? `${p.name}  (repos: ${p.repos.join(", ")})`
                              : p.name
                          }
                          checked={picked.includes(p.name)}
                          onChange={(_e, d) =>
                            setPicked((prev) =>
                              d.checked ? [...prev, p.name] : prev.filter((x) => x !== p.name),
                            )
                          }
                        />
                      ))}
                      <div>
                        <Button
                          appearance="primary"
                          disabled={picked.length === 0 || stepping}
                          onClick={() =>
                            void run([
                              "-Projects",
                              available
                                .filter((p) => picked.includes(p.name))
                                .map((p) =>
                                  p.repos && p.repos.length > 0
                                    ? `${p.name}/${p.repos[0]}`
                                    : p.name,
                                )
                                .join("; "),
                            ])
                          }
                        >
                          Work in these
                        </Button>
                      </div>
                    </div>
                  ) : null}
                </>
              )}
            </section>

            <section className={styles.step} aria-label="Step 4, sprint awareness">
              <StepHeader
                n={4}
                title="Sprint awareness"
                done={report.steps.sprint.done}
                yours={false}
              />
              {tracker === "github" ? (
                <Body1 className={styles.who}>
                  A GitHub Space has milestones, not sprints. Nothing to set.
                </Body1>
              ) : (
                <Switch
                  label="Read this Space's iterations, so a card can say which sprint it is in"
                  checked={report.steps.sprint.on}
                  disabled={stepping || tracker === "none"}
                  onChange={(_e, d) => void run(["-Sprint", d.checked ? "true" : "false"])}
                />
              )}
            </section>

            {report.example ? (
              <section className={styles.step} aria-label="Make it yours">
                <StepHeader n={5} title="Make it yours" done={false} yours />
                <Body1>
                  {report.name || "This Space"} is one of the shipped demo Spaces. Give it your slug
                  and it becomes your Space: declared from these settings, its cards moved with it,
                  and made active.
                </Body1>
                <div className={styles.row}>
                  <Input
                    aria-label="Your slug"
                    value={newSlug}
                    onChange={(_e, d) => setNewSlug(d.value)}
                    placeholder="acme"
                  />
                  <Button
                    appearance="primary"
                    disabled={!newSlug || stepping}
                    onClick={() => void run(["-As", newSlug])}
                  >
                    Make it mine
                  </Button>
                </div>
              </section>
            ) : null}
          </>
        ) : null}
        <Caption1 className={styles.who}>
          <Body1Strong>In a terminal:</Body1Strong>{" "}
          <span className={styles.code}>tkConnect {slug}</span> walks the same steps.
        </Caption1>
      </PageCard>
    </PageGrid>
  );
}
