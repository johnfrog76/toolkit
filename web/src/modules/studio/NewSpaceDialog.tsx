import { useEffect, useMemo, useState } from "react";
import {
  Badge,
  Body1,
  Button,
  Caption1,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  DialogTrigger,
  Field,
  Input,
  Radio,
  RadioGroup,
  SearchBox,
  Select,
  Spinner,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { thinScrollbar } from "../../shared/thinScrollbar";
import { VisibilityBadge } from "../../shared/visibility";
import type { SpaceInfo } from "../../shell/api";
import { buildNewSpaceParams, commandResultMessage } from "../ado/cliBridge";
import {
  useGetSpaceCandidatesQuery,
  useGetTypedSpaceCandidateQuery,
  useRunNewSpaceMutation,
} from "./api.studio";
import type { SpaceCandidate } from "./api.studio";
import { isRepo, isSlug, normaliseRepo, proposeName, proposeSlug, repoName } from "./newSpace";

// The New Space dialog: the + on the Spaces card. The same dialog the Hub
// Designs card's + opens -- Fluent's Dialog, a title with its dismiss, fields,
// Cancel and the primary action -- and the same write: the verb through the
// bridge (POST /api/cmd/NewSpace), never a native write. One Space per dialog.
//
// What the Space is comes first, as two radios -- a repository, or your own
// cards. The repository area keeps ONE box whatever it holds (the list, the
// reading spinner, the typed field when gh cannot answer, or a line for own
// cards), so nothing below it moves when the choice or the answer changes.
//
// Beyond what you own: an owner selector above the list -- you, your
// organisations, then Collaborator -- whose entries are the verb's own
// (`NewSpace -Discover` names them, `-Owner` takes them), and a search that
// reads as a full owner/name offers one more row, "Add owner/name", chosen like
// any other. A repository you can only read says so in its row.
//
// The Add owner/name row reads that one repository before it is added (the
// verb's -Discover -Repo, GET /api/spaces/candidates?repo=): its Public/Private,
// or -- when gh cannot see it with this login -- "Visibility unknown" and the
// verb's note. The read waits until the search has rested on a full owner/name
// for TYPED_READ_DELAY_MS, so a name typed letter by letter is one read.
const TYPED_READ_DELAY_MS = 400;

const useStyles = makeStyles({
  fields: { display: "flex", flexDirection: "column", rowGap: tokens.spacingVerticalM },
  // One box, one height: the list, the spinner, the fallback and the own-cards
  // line all draw inside it (no layout jump).
  picker: {
    height: "240px",
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalS,
    padding: tokens.spacingVerticalS,
    border: `${tokens.strokeWidthThin} solid ${tokens.colorNeutralStroke2}`,
    borderRadius: tokens.borderRadiusMedium,
    boxSizing: "border-box",
  },
  list: { flex: 1, minHeight: 0, overflowY: "auto", ...thinScrollbar },
  repoLabel: {
    display: "inline-flex",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalS,
    flexWrap: "wrap",
  },
  quiet: { color: tokens.colorNeutralForeground3 },
  centre: { flex: 1, display: "flex", alignItems: "center", justifyContent: "center" },
  error: { color: tokens.colorPaletteRedForeground1, whiteSpace: "pre-wrap" },
});

type Kind = "repo" | "own";

function RepoLabel({ c }: { c: SpaceCandidate }) {
  const styles = useStyles();
  return (
    <span className={styles.repoLabel}>
      <Body1>
        <strong>{c.name}</strong>
      </Body1>
      <Caption1 className={styles.quiet}>{c.owner}</Caption1>
      <VisibilityBadge visibility={c.visibility} />
      {c.isArchived ? (
        <Badge appearance="outline" size="small" color="subtle">
          Archived
        </Badge>
      ) : null}
      {c.readOnly ? (
        <Badge appearance="outline" size="small" color="subtle">
          Read-only
        </Badge>
      ) : null}
      {c.space ? (
        <Caption1 className={styles.quiet}>already a Space: {c.spaceName || c.space}</Caption1>
      ) : null}
    </span>
  );
}

// The Add owner/name row: what the typed repository's own read said -- its
// visibility and marks, "already a Space", or the verb's note when gh cannot see
// it -- and, before that read is in or when it could not run, what it is.
function TypedLabel({
  repo,
  row,
  reading,
}: {
  repo: string;
  row: SpaceCandidate | undefined;
  reading: boolean;
}) {
  const styles = useStyles();
  return (
    <span className={styles.repoLabel}>
      <Body1>
        Add <strong>{repo}</strong>
      </Body1>
      {reading ? (
        <Caption1 className={styles.quiet}>reading its visibility...</Caption1>
      ) : row ? (
        <>
          <VisibilityBadge visibility={row.visibility} />
          {row.isArchived ? (
            <Badge appearance="outline" size="small" color="subtle">
              Archived
            </Badge>
          ) : null}
          {row.readOnly ? (
            <Badge appearance="outline" size="small" color="subtle">
              Read-only
            </Badge>
          ) : null}
          {row.space ? (
            <Caption1 className={styles.quiet}>
              already a Space: {row.spaceName || row.space}
            </Caption1>
          ) : null}
          {row.note ? (
            <Caption1 className={styles.quiet}>{row.note} -- it can still be added</Caption1>
          ) : null}
        </>
      ) : (
        <Caption1 className={styles.quiet}>
          not in this list -- Public or Private is checked when it is added
        </Caption1>
      )}
    </span>
  );
}

export function NewSpaceDialog({
  open,
  spaces,
  onClose,
  onAdded,
}: {
  open: boolean;
  /** The Spaces already declared -- a slug one of them has is refused before Add. */
  spaces: SpaceInfo[];
  onClose: () => void;
  /** Called with the new Space's name once the verb has added it. */
  onAdded: (name: string) => void;
}) {
  const styles = useStyles();
  // "" is your own repositories; anything else is the verb's -Owner.
  const [owner, setOwner] = useState("");
  const candidates = useGetSpaceCandidatesQuery(owner, { skip: !open });
  const [runNewSpace, { isLoading: adding }] = useRunNewSpaceMutation();

  const [kind, setKind] = useState<Kind>("repo");
  const [search, setSearch] = useState("");
  const [picked, setPicked] = useState("");
  const [typed, setTyped] = useState("");
  const [nameInput, setNameInput] = useState("");
  const [nameTouched, setNameTouched] = useState(false);
  const [slugInput, setSlugInput] = useState("");
  const [slugTouched, setSlugTouched] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const reset = () => {
    setOwner("");
    setKind("repo");
    setSearch("");
    setPicked("");
    setTyped("");
    setNameInput("");
    setNameTouched(false);
    setSlugInput("");
    setSlugTouched(false);
    setMessage(null);
  };
  const close = () => {
    reset();
    onClose();
  };

  // The picker, or -- when gh cannot answer, or answers with nothing -- a typed
  // owner/name with the sentence saying why. Never a dead end.
  const answer = candidates.data;
  // GitHub-archived repositories sort last, otherwise in the verb's order.
  const listed = useMemo(() => {
    const repos = answer?.available ? answer.repos : [];
    return [...repos].sort((a, b) => Number(!!a.isArchived) - Number(!!b.isArchived));
  }, [answer]);
  const reading = candidates.isLoading || candidates.isFetching;
  const fallback = !reading && listed.length === 0;
  // The owner selector: the verb's entries, shown whenever it named any --
  // over the list, the spinner and the typed field alike, so another owner is
  // always one choice away. Its value is whose list this is.
  const owners = answer?.owners ?? [];
  const ownerShown = owner || answer?.owner || answer?.account || "";
  const ownerLabel = owners.find((o) => o.value === ownerShown)?.label || ownerShown;
  const fallbackWhy = candidates.error
    ? "The agent did not answer, so your repositories are not listed."
    : candidates.data && !candidates.data.available
      ? candidates.data.reason
      : candidates.data
        ? `gh lists no repositories${ownerLabel ? ` for ${ownerLabel}` : ""}.`
        : "";

  // A search that reads as a full owner/name (or a pasted GitHub address) and is
  // not in the list offers one more row: "Add owner/name".
  const typedRepo = isRepo(search) ? normaliseRepo(search) : "";
  const offerTyped =
    typedRepo !== "" && !listed.some((c) => c.repo.toLowerCase() === typedRepo.toLowerCase());

  // The typed repository's own read, once the search has rested on it.
  const [rested, setRested] = useState("");
  useEffect(() => {
    if (!offerTyped) return undefined;
    const timer = setTimeout(() => setRested(typedRepo), TYPED_READ_DELAY_MS);
    return () => clearTimeout(timer);
  }, [offerTyped, typedRepo]);
  const typedAsk = offerTyped && rested === typedRepo ? typedRepo : "";
  const typedRead = useGetTypedSpaceCandidateQuery(typedAsk, { skip: !open || !typedAsk });
  // currentData, not data: the answer for THIS repository, never the last one typed.
  const typedAnswer = typedAsk ? typedRead.currentData : undefined;
  const typedRow = typedAnswer?.available ? typedAnswer.repos[0] : undefined;
  const typedReading =
    offerTyped && (!typedAsk || typedRead.isLoading || typedRead.isFetching) && !typedAnswer;

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return listed;
    const asRepo = normaliseRepo(search).toLowerCase();
    return listed.filter(
      (c) =>
        c.repo.toLowerCase().includes(q) ||
        c.repo.toLowerCase() === asRepo ||
        (c.description || "").toLowerCase().includes(q),
    );
  }, [listed, search]);

  // What is chosen, and what it proposes. The verb's own proposal for a listed
  // repository; the mirror (newSpace.ts) for a typed one and for own cards.
  const chosen = listed.find((c) => c.repo === picked);
  const typedChosen = offerTyped && picked === typedRepo;
  const repo =
    kind === "repo"
      ? fallback
        ? isRepo(typed)
          ? normaliseRepo(typed)
          : ""
        : chosen
          ? chosen.repo
          : typedChosen && !typedRow?.space
            ? typedRepo
            : ""
      : "";
  const somethingChosen = kind === "own" || repo !== "";
  const proposedName = kind === "repo" ? (chosen?.proposedName ?? proposeName(repoName(repo))) : "";
  const name = kind === "own" || nameTouched ? nameInput : proposedName;
  const proposedSlug =
    kind === "repo"
      ? (chosen?.proposedSlug ?? proposeSlug(repoName(repo)))
      : proposeSlug(nameInput);
  const slug = slugTouched ? slugInput : proposedSlug;

  const taken = spaces.find((s) => s.slug === slug);
  const slugProblem = !slug
    ? null
    : !isSlug(slug)
      ? "Lowercase letters, digits and dashes, starting with a letter."
      : taken
        ? `There is already a Space '${slug}': ${taken.name || taken.slug}.`
        : null;
  const ready = somethingChosen && !!name.trim() && !!slug && !slugProblem && !adding;

  // A new choice of repository is a new proposal: what was typed for the last
  // one does not carry over.
  const choose = (value: string) => {
    setPicked(value);
    setNameTouched(false);
    setSlugTouched(false);
    setMessage(null);
  };

  const add = async () => {
    setMessage(null);
    try {
      const result = await runNewSpace({
        params: buildNewSpaceParams({ slug, name, repo }),
      }).unwrap();
      if (result.status === "success") {
        const added = name.trim();
        reset();
        onAdded(added);
        return;
      }
      // A refusal is the dialog's message, in the verb's own words.
      setMessage(commandResultMessage(result, "Added."));
    } catch {
      setMessage("Could not reach the agent. Nothing was written.");
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(_e, d) => {
        if (!d.open) close();
      }}
    >
      <DialogSurface>
        <DialogBody>
          <DialogTitle action={<DialogDismiss />}>New Space</DialogTitle>
          <DialogContent>
            <div className={styles.fields}>
              <RadioGroup
                layout="horizontal"
                aria-label="What the Space is"
                value={kind}
                onChange={(_e, d) => {
                  setKind(d.value as Kind);
                  setNameTouched(false);
                  setSlugTouched(false);
                  setMessage(null);
                }}
              >
                <Radio value="repo" label="A GitHub repository" />
                <Radio value="own" label="My own cards, no tracker" />
              </RadioGroup>

              <div className={styles.picker} data-testid="new-space-picker">
                {kind === "own" ? (
                  <Caption1 className={styles.quiet}>
                    A Space of your own cards, kept in your hub and tracked by nothing. You can
                    connect it to a tracker later, from its row.
                  </Caption1>
                ) : null}
                {kind === "repo" && owners.length > 0 ? (
                  <Select
                    size="small"
                    aria-label="Owner"
                    value={ownerShown}
                    onChange={(_e, d) => {
                      setOwner(d.value === answer?.account ? "" : d.value);
                      choose("");
                    }}
                  >
                    {owners.map((o) => (
                      <option key={o.value} value={o.value}>
                        {o.label}
                      </option>
                    ))}
                  </Select>
                ) : null}
                {kind === "own" ? null : reading ? (
                  <div className={styles.centre}>
                    <Spinner size="tiny" label="Reading your repositories..." />
                  </div>
                ) : fallback ? (
                  <>
                    <Caption1 className={styles.quiet}>
                      {fallbackWhy} Type the repository instead.
                    </Caption1>
                    <Field label="Repository" hint="owner/name -- for example johnfrog76/toolkit">
                      <Input
                        size="small"
                        value={typed}
                        placeholder="owner/name"
                        onChange={(_, d) => {
                          setTyped(d.value);
                          setNameTouched(false);
                          setSlugTouched(false);
                        }}
                      />
                    </Field>
                  </>
                ) : (
                  <>
                    <SearchBox
                      size="small"
                      aria-label="Search your repositories"
                      placeholder="Search, or type owner/name"
                      value={search}
                      onChange={(_e, d) => setSearch(d.value)}
                    />
                    <div className={styles.list}>
                      {shown.length === 0 && !offerTyped ? (
                        <Caption1 className={styles.quiet}>
                          No repository matches &lsquo;{search}&rsquo;. A full owner/name can be
                          added from here.
                        </Caption1>
                      ) : (
                        <RadioGroup
                          aria-label="Your repositories"
                          value={picked}
                          onChange={(_e, d) => choose(d.value)}
                        >
                          {shown.map((c) => (
                            <Radio
                              key={c.repo}
                              value={c.repo}
                              disabled={!!c.space}
                              label={<RepoLabel c={c} />}
                            />
                          ))}
                          {offerTyped ? (
                            <Radio
                              key={`typed:${typedRepo}`}
                              value={typedRepo}
                              disabled={!!typedRow?.space}
                              label={
                                <TypedLabel
                                  repo={typedRepo}
                                  row={typedRow}
                                  reading={typedReading}
                                />
                              }
                            />
                          ) : null}
                        </RadioGroup>
                      )}
                      {answer?.more && answer.ceiling ? (
                        <Caption1 className={styles.quiet} role="note">
                          The first {answer.ceiling} are listed. For one past them, type its
                          owner/name in the search.
                        </Caption1>
                      ) : null}
                    </div>
                  </>
                )}
              </div>

              <Field label="Name" required hint="What the avatar menu and this card call it.">
                <Input
                  size="small"
                  value={name}
                  disabled={!somethingChosen}
                  placeholder={kind === "own" ? "My notes" : ""}
                  onChange={(_, d) => {
                    setNameInput(d.value);
                    setNameTouched(true);
                  }}
                />
              </Field>
              <Field
                label="Slug"
                required
                hint={slugProblem ? undefined : "The short name it is kept and switched by."}
                validationState={slugProblem ? "error" : "none"}
                validationMessage={slugProblem ?? undefined}
              >
                <Input
                  size="small"
                  value={slug}
                  disabled={!somethingChosen}
                  onChange={(_, d) => {
                    setSlugInput(d.value);
                    setSlugTouched(true);
                  }}
                />
              </Field>
              {message ? (
                <Caption1 role="alert" className={styles.error}>
                  {message}
                </Caption1>
              ) : null}
            </div>
          </DialogContent>
          <DialogActions>
            <DialogTrigger disableButtonEnhancement>
              <Button appearance="secondary">Cancel</Button>
            </DialogTrigger>
            <Button appearance="primary" onClick={add} disabled={!ready}>
              {adding ? "Adding…" : "Add"}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
