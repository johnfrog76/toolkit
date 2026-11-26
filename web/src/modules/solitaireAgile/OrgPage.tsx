import {
  Badge,
  Body1,
  Body2,
  Button,
  Caption1,
  Dropdown,
  Label,
  MessageBar,
  MessageBarBody,
  Option,
  OptionGroup,
  Subtitle2,
  makeStyles,
  mergeClasses,
  tokens,
  useId,
} from "@fluentui/react-components";
import { useState } from "react";
import { DocumentTextRegular, OrganizationRegular } from "@fluentui/react-icons";
import { Link } from "react-router";
import { EmptyState } from "../../shared/EmptyState";
import type { EmptyMessage } from "../../shared/EmptyState";
import { PanelFrame } from "../../shared/PanelFrame";
import { RefinedBust, bustHeight } from "../../shared/refinedFaces";
import { promptPath } from "../studio/paths";
import { buildStaffActivateParams } from "../ado/cliBridge";
import {
  useGetOrgChartQuery,
  useGetOrgPresetsQuery,
  useRunStaffMutation,
} from "./api.solitaireAgile";
import type { OrgPosition, OrgPreset, OrgRefusal, OrgTreeSummary } from "./api.solitaireAgile";
import { UseOrgDialog, refusalText } from "./UseOrgDialog";
import { OfficeDoor, Plate, SeatCell } from "./OrgParts";
import type { PlacedOffice } from "./orgChart";
import {
  OFFICE_HEIGHT,
  POOL_WORD,
  SIZE,
  layoutChart,
  levelWall,
  plateTitle,
  plateWho,
  positionFaces,
  seatFace,
  seatWhere,
} from "./orgChart";
import { VacantSeat } from "./VacantSeat";

// The Org tab (docs/modules/solitaire-agile.md, "The web UI"): Team Agile's
// fourth page, after Standup, Triage and Releases. It draws the tree the agent
// serves from the hub's org.json (GET /api/ritual/org) and nothing else: offices
// by level, the walls coloured by level, each position centred over the ones
// that report to it, each seat a card with a bust and a plate. A staffed seat is
// in colour; a vacant one is VacantSeat; a position with no seats is a pool,
// one card with its default-model line; the owner's seat is a person. A plate
// names the seat's own roleTitle where it has one, else the position's title,
// then the model by its models.json name (the agent's modelName) or the person;
// the seat's session is on hover. No machine is ever drawn.
//
// An office with a prompt is a link to it in the Studio's reading room
// (promptPath of the position's promptRef); the owner and the pool have none,
// and are not links. The page is a READ: it chooses no tree, draws no active
// state, and writes nothing.
//
// Two dropdowns at the header's right keep looking apart from the org's state
// (docs/modules/solitaire-agile.md, "The web UI"). View picks the org shown:
// the saved orgs first, then the presets as previews (docs/hub/org.md, "Org
// presets", served by GET /api/ritual/org/presets). Active, drawn once an org is
// saved, lists the saved orgs only, with no None, and picking one runs
// Staff -Activate through the bridge (POST /api/cmd/Staff), with no
// confirmation. With no org saved, View opens on the Executive Suite (Small),
// the simplest; with one, on the active org. When the org shown is not the
// active one, one line under the heading says so. On a preview, "Use this org"
// opens the steps (UseOrgDialog.tsx), which save it as a draft through
// Staff -Preset. The page itself writes nothing: org.json's one writer is the
// CLI's Staff verb (docs/hub/org.md, "The one writer: Staff"), reached through
// the bridge, never a route of its own. Hand edits work too.

const useStyles = makeStyles({
  body: { display: "flex", flexDirection: "column", minWidth: 0 },
  // The org's description, under its title. Its type is Fluent's Body2 (16px,
  // the step at 1rem); this only places it, and 35em keeps a line near 78 characters.
  description: {
    marginTop: tokens.spacingVerticalS,
    marginBottom: 0,
    maxWidth: "35em",
    color: tokens.colorNeutralForeground2,
  },
  select: { minWidth: "220px" },
  selects: { display: "flex", columnGap: tokens.spacingHorizontalL, alignItems: "center" },
  // A dropdown with its visible label before it: "View" and "Active".
  labelled: { display: "flex", alignItems: "center", columnGap: tokens.spacingHorizontalS },
  // The line under the heading, and Use this org beside it on a preview.
  lineRow: {
    display: "flex",
    alignItems: "center",
    columnGap: tokens.spacingHorizontalM,
    marginTop: tokens.spacingVerticalXS,
  },
  notActive: { color: tokens.colorNeutralForeground2 },
  refusal: { marginTop: tokens.spacingVerticalS, whiteSpace: "pre-wrap" },
  // The chart is as wide as its tree; a narrow window scrolls it, not the page.
  scroller: {
    overflowX: "auto",
    paddingTop: tokens.spacingVerticalL,
    paddingBottom: tokens.spacingVerticalL,
  },
  chart: { position: "relative", marginLeft: "auto", marginRight: "auto" },
  lines: { position: "absolute", left: 0, top: 0, overflow: "visible" },
  office: {
    position: "absolute",
    boxSizing: "border-box",
    padding: `${SIZE.pad}px`,
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    borderRadius: "16px",
    color: "inherit",
    textDecorationLine: "none",
  },
  // Several seats in one office: a row of cards in a room of their own.
  room: {
    backgroundColor: tokens.colorNeutralBackgroundAlpha,
    outlineWidth: "1px",
    outlineStyle: "solid",
    outlineColor: tokens.colorNeutralStroke2,
  },
  link: {
    cursor: "pointer",
    ":hover": { backgroundColor: tokens.colorNeutralBackground1Hover },
    ":hover .org-sign-text": { textDecorationLine: "underline" },
    ":focus-visible": {
      outlineWidth: "2px",
      outlineStyle: "solid",
      outlineColor: tokens.colorStrokeFocus2,
    },
  },
  sign: {
    height: `${SIZE.sign}px`,
    display: "flex",
    alignItems: "flex-start",
    columnGap: tokens.spacingHorizontalXS,
    maxWidth: "100%",
    color: tokens.colorNeutralForeground2,
    fontSize: tokens.fontSizeBase200,
    lineHeight: tokens.lineHeightBase200,
    fontWeight: tokens.fontWeightSemibold,
    whiteSpace: "nowrap",
  },
  signText: { overflow: "hidden", textOverflow: "ellipsis" },
  seats: { display: "flex", columnGap: `${SIZE.seatGap}px` },
  poolLine: {
    marginTop: tokens.spacingVerticalS,
    maxWidth: `${SIZE.poolCell}px`,
    textAlign: "center",
    color: tokens.colorNeutralForeground2,
    fontSize: tokens.fontSizeBase200,
    lineHeight: tokens.lineHeightBase200,
  },
});

// -- One office's cards -----------------------------------------------------

const BUST_W = 96;
const POOL_BUST_W = 72;
const POOL_STEP = 42;

/** The bust's place in a door: centred, standing on the sill. */
const bustY = (width: number) => SIZE.door.height - 7 - bustHeight(width) + 2.5;

function StaffedSeat({
  position,
  seatIndex,
  order,
}: {
  position: OrgPosition;
  seatIndex: number;
  order: number;
}) {
  const seat = position.seats[seatIndex];
  const { wall, shade } = levelWall(position.level);
  const where = seatWhere(seat);
  return (
    <SeatCell state="staffed">
      <OfficeDoor wall={wall} shade={shade}>
        <RefinedBust
          face={seatFace(position, seatIndex, order)}
          width={BUST_W}
          x={(SIZE.door.width - BUST_W) / 2}
          y={bustY(BUST_W)}
        />
      </OfficeDoor>
      <Plate
        position={plateTitle(position, seat)}
        who={plateWho(seat)}
        where={where || undefined}
        session={seat.session ?? undefined}
      />
    </SeatCell>
  );
}

/** A position with no seats: one wider card, a few of its faces side by side,
 *  `POSITION · pool` on the plate and its default-model line under it. */
function PoolSeat({ position, order }: { position: OrgPosition; order: number }) {
  const styles = useStyles();
  const { wall, shade } = levelWall(position.level);
  const faces = positionFaces(position, order);
  const span = (faces.length - 1) * POOL_STEP + POOL_BUST_W;
  const start = (SIZE.poolDoor.width - span) / 2;
  return (
    <SeatCell state="pool" pool>
      <OfficeDoor wall={wall} shade={shade} width={SIZE.poolDoor.width}>
        {faces.map((face, i) => (
          <RefinedBust
            key={`${face}-${i}`}
            face={face}
            width={POOL_BUST_W}
            x={start + i * POOL_STEP}
            y={bustY(POOL_BUST_W)}
          />
        ))}
      </OfficeDoor>
      <Plate position={position.title} who={POOL_WORD} />
      {position.defaultModel ? (
        <Caption1 className={styles.poolLine} data-testid="org-pool-line">
          {position.defaultModelName ?? position.defaultModel}
        </Caption1>
      ) : null}
    </SeatCell>
  );
}

function Office({ office }: { office: PlacedOffice }) {
  const styles = useStyles();
  const p = office.position;
  const room = p.seats.length > 1;
  const style = { left: office.left, top: office.top, width: office.width };
  const body = (
    <>
      <div className={styles.sign}>
        {p.promptTitle ? (
          <>
            <DocumentTextRegular aria-hidden />
            <span className={mergeClasses("org-sign-text", styles.signText)}>{p.promptTitle}</span>
          </>
        ) : null}
      </div>
      <div className={styles.seats}>
        {p.seats.length === 0 ? (
          <PoolSeat position={p} order={office.order} />
        ) : (
          p.seats.map((seat, i) =>
            seat.state === "vacant" ? (
              <VacantSeat
                key={seat.id}
                seatId={seat.id}
                position={plateTitle(p, seat)}
                level={p.level}
                where={seatWhere(seat) || undefined}
                session={seat.session ?? undefined}
              />
            ) : (
              <StaffedSeat key={seat.id} position={p} seatIndex={i} order={office.order} />
            ),
          )
        )}
      </div>
    </>
  );
  const className = mergeClasses(styles.office, room && styles.room);
  if (p.promptRef) {
    return (
      <Link
        to={promptPath(p.promptRef)}
        className={mergeClasses(className, styles.link)}
        style={style}
        title={`Open the prompt: ${p.promptTitle ?? p.title}`}
        data-testid="org-office"
        data-position={p.id}
      >
        {body}
      </Link>
    );
  }
  return (
    <div className={className} style={style} data-testid="org-office" data-position={p.id}>
      {body}
    </div>
  );
}

// -- The lines between offices ----------------------------------------------

/** From the foot of an office (its plate, or its room) down to the top of each
 *  office that reports to it: down, across, down. */
function Lines({ lines, width, height }: ReturnType<typeof layoutChart>) {
  const styles = useStyles();
  const foot = (o: PlacedOffice) =>
    o.top + (o.position.seats.length > 1 ? OFFICE_HEIGHT : OFFICE_HEIGHT - SIZE.pad);
  // Into a room at its top; into a single office at its sign, or at its door
  // where it has no sign (no prompt), so the line never stops short.
  const head = (o: PlacedOffice) =>
    o.top + (o.position.seats.length > 1 ? 0 : SIZE.pad + (o.position.promptTitle ? 0 : SIZE.sign));
  return (
    <svg className={styles.lines} width={width} height={height} aria-hidden="true">
      {lines.map(({ from, to }) => {
        const y1 = foot(from);
        const y2 = head(to);
        const mid = Math.round((y1 + y2) / 2);
        return (
          <path
            key={`${from.position.id}-${to.position.id}`}
            d={`M ${from.cx} ${y1} V ${mid} H ${to.cx} V ${y2}`}
            fill="none"
            stroke={tokens.colorNeutralStrokeAccessible}
            strokeWidth="2.2"
            strokeLinejoin="round"
            strokeLinecap="round"
          />
        );
      })}
    </svg>
  );
}

// -- The page ---------------------------------------------------------------

/** What the agent said when it served no chart: its status and its detail. */
export function orgRefusal(error: unknown): { status?: number | string } & Partial<OrgRefusal> {
  const e = error as { status?: number | string; data?: { detail?: unknown } } | undefined;
  const detail = e?.data?.detail;
  if (detail && typeof detail === "object") {
    const d = detail as Partial<OrgRefusal>;
    return { status: e?.status, kind: d.kind, message: d.message };
  }
  return { status: e?.status, message: typeof detail === "string" ? detail : undefined };
}

/** What the page says for a tree the org file does not have. */
export const UNKNOWN_TREE_DETAIL =
  "The chart asked for is not one of the trees in the hub's org.json. Nothing was drawn.";

/** The no-chart states: no file (404), a file that fails its checks (409), a
 *  tree the file does not have (422, said in the page's words: the agent's
 *  sentence is the terminal's). Each of those is something to know, said
 *  plainly. The error tone is kept for what is left: the agent did not answer,
 *  or answered with a failure of its own. */
function noChart(error: unknown, icon: EmptyMessage["icon"]): EmptyMessage {
  const r = orgRefusal(error);
  if (r.status === 404 && (r.kind === "missing" || r.kind === "no-hub")) {
    return { icon, title: "No org chart yet", detail: r.message };
  }
  if (r.status === 409 && r.kind) {
    return { icon, title: "The org chart could not be read", detail: r.message };
  }
  if (r.status === 422 && r.kind === "unknown-tree") {
    return {
      icon,
      title: "That org chart is not in the file",
      detail: UNKNOWN_TREE_DETAIL,
    };
  }
  return {
    icon,
    tone: "error",
    title: "Could not read the org chart",
    detail: r.message ?? "The agent did not answer. Nothing was read.",
  };
}

/** One tree's positions, drawn: the offices by level and the lines between them. */
function ChartDrawing({ positions }: { positions: OrgPosition[] }) {
  const styles = useStyles();
  const layout = layoutChart(positions);
  return (
    <div className={styles.scroller}>
      <div
        className={styles.chart}
        style={{ width: layout.width, height: layout.height }}
        data-testid="org-chart"
      >
        <Lines {...layout} />
        {layout.offices.map((o) => (
          <Office key={o.position.id} office={o} />
        ))}
      </div>
    </div>
  );
}

/** The value the dropdown holds for the hub's own chart while it has no saved
 *  tree to list (a file that does not read): the page says why. */
export const YOUR_ORG = "";
/** What the dropdown calls the hub's own chart in that case. */
export const YOUR_ORG_LABEL = "Your org";

/** A preset's size as its badge says it: the one mapping from the file's letter
 *  to the word. A size it does not know is shown as written. */
export const PRESET_SIZE_WORDS: Readonly<Record<string, string>> = {
  S: "Small",
  M: "Medium",
  L: "Large",
};

export function presetSizeWord(size: string): string {
  return PRESET_SIZE_WORDS[size] ?? size;
}

/** A preset as the dropdown names it: its title without a leading "The", and
 *  its size -- "Executive Suite (S)". */
export function presetLabel(preset: Pick<OrgPreset, "title" | "size">): string {
  const name = preset.title.replace(/^The\s+/, "");
  return preset.size ? `${name} (${preset.size})` : name;
}

/** The View dropdown's values: a saved tree, or a preset previewed. */
const SAVED = "org:";
const PREVIEW = "preset:";
export const savedView = (id: string) => `${SAVED}${id}`;
export const previewView = (id: string) => `${PREVIEW}${id}`;

/** The one line under the heading when the org shown is not the active one
 *  (docs/modules/solitaire-agile.md, "The web UI"): the accepted copy. */
export function notActiveLine(
  shown: "draft" | "preview" | "active",
  activeTitle: string | null,
): string | null {
  if (shown === "active") return null;
  if (shown === "draft") return `A draft. Your active org is ${activeTitle}.`;
  return activeTitle
    ? `A preview. Your active org is ${activeTitle}.`
    : "A preview. Nothing is saved yet.";
}

/** View, at the right of the panel's header: the saved orgs, then the presets. */
function ViewSelect({
  saved,
  presets,
  view,
  label,
  yours,
  onPick,
}: {
  saved: OrgTreeSummary[];
  presets: OrgPreset[];
  view: string;
  label: string;
  yours: boolean;
  onPick: (value: string) => void;
}) {
  const styles = useStyles();
  const id = useId("org-view");
  return (
    <span className={styles.labelled}>
      <Label htmlFor={id}>View</Label>
      <Dropdown
        id={id}
        className={styles.select}
        value={label}
        selectedOptions={[view]}
        onOptionSelect={(_, d) => onPick(d.optionValue ?? YOUR_ORG)}
        data-testid="org-preset-select"
      >
        {saved.length > 0 ? (
          <OptionGroup label="Your orgs">
            {saved.map((t) => (
              <Option key={t.id} value={savedView(t.id)}>
                {t.title}
              </Option>
            ))}
          </OptionGroup>
        ) : yours ? (
          <Option value={YOUR_ORG}>{YOUR_ORG_LABEL}</Option>
        ) : null}
        <OptionGroup label="Presets">
          {presets.map((p) => (
            <Option key={p.id} value={previewView(p.id)}>
              {presetLabel(p)}
            </Option>
          ))}
        </OptionGroup>
      </Dropdown>
    </span>
  );
}

/** Active, beside View once an org is saved: the saved orgs only, no None.
 *  Picking one runs Staff -Activate through the bridge, with no confirmation. */
function ActiveSelect({
  saved,
  active,
  busy,
  onPick,
}: {
  saved: OrgTreeSummary[];
  active: OrgTreeSummary;
  busy: boolean;
  onPick: (id: string) => void;
}) {
  const styles = useStyles();
  const id = useId("org-active");
  return (
    <span className={styles.labelled}>
      <Label htmlFor={id}>Active</Label>
      <Dropdown
        id={id}
        className={styles.select}
        value={active.title}
        selectedOptions={[active.id]}
        disabled={busy}
        onOptionSelect={(_, d) =>
          d.optionValue && d.optionValue !== active.id && onPick(d.optionValue)
        }
        data-testid="org-active-select"
      >
        {saved.map((t) => (
          <Option key={t.id} value={t.id}>
            {t.title}
          </Option>
        ))}
      </Dropdown>
    </span>
  );
}

/** What the page is called: the org shown's title, else the page's own name
 *  while there is no chart. */
export const ORG_PAGE_TITLE = "Org chart";

/** Is this read a hub with no org yet (no file, or no hub named)? */
function noOrgYet(error: unknown): boolean {
  const r = orgRefusal(error);
  return r.status === 404 && (r.kind === "missing" || r.kind === "no-hub");
}

export function OrgPage() {
  const styles = useStyles();
  const ours = useGetOrgChartQuery("");
  const presetsQuery = useGetOrgPresetsQuery();
  const [runStaff, { isLoading: writing }] = useRunStaffMutation();
  const presets = presetsQuery.data?.presets ?? [];
  const icon = <OrganizationRegular />;

  const oursData = ours.data && !ours.error ? ours.data : null;
  const saved: OrgTreeSummary[] =
    oursData?.trees ??
    (oursData
      ? [
          {
            id: oursData.tree.id,
            title: oursData.tree.title,
            size: oursData.tree.size,
            preset: oursData.tree.preset,
            active: true,
          },
        ]
      : []);
  const active = saved.find((t) => t.active) ?? null;
  const small = presets.find((p) => p.size === "S") ?? presets[0];

  // Which org is shown: what was picked, else the active org, else -- with no
  // org saved yet -- the Executive Suite (Small) preview, the simplest.
  const [picked, setPicked] = useState<string | null>(null);
  const fallback = active
    ? savedView(active.id)
    : noOrgYet(ours.error) && small
      ? previewView(small.id)
      : YOUR_ORG;
  let view = picked ?? fallback;
  if (view.startsWith(SAVED) && !saved.some((t) => savedView(t.id) === view)) view = fallback;
  const preset = view.startsWith(PREVIEW)
    ? presets.find((p) => previewView(p.id) === view)
    : undefined;
  const savedId = view.startsWith(SAVED) ? view.slice(SAVED.length) : "";
  const other = useGetOrgChartQuery(savedId, { skip: !savedId || savedId === active?.id });

  const [useOpen, setUseOpen] = useState(false);
  const [note, setNote] = useState<{ text: string; away: boolean } | null>(null);

  const chart = preset
    ? preset.chart
    : savedId && savedId !== active?.id
      ? other.data && !other.error
        ? other.data
        : null
      : oursData;
  const shown: "draft" | "preview" | "active" = preset
    ? "preview"
    : savedId && savedId !== active?.id
      ? "draft"
      : "active";
  const line = notActiveLine(shown, active?.title ?? null);

  const loading = ours.isLoading || (shown === "draft" && other.isLoading);
  const noOrg =
    ours.isLoading || oursData ? undefined : <EmptyState {...noChart(ours.error, icon)} />;
  // With no preset to offer, the page is the hub's chart alone, as it always was.
  const empty = presets.length === 0 ? noOrg : undefined;
  const title = chart ? chart.tree.title : ORG_PAGE_TITLE;
  const size = chart?.tree.size ?? null;
  const description = preset ? preset.description : (chart?.tree.description ?? null);
  const label = preset
    ? presetLabel(preset)
    : savedId
      ? (saved.find((t) => t.id === savedId)?.title ?? title)
      : YOUR_ORG_LABEL;

  const activate = async (id: string) => {
    setNote(null);
    try {
      const result = await runStaff({ params: buildStaffActivateParams(id) }).unwrap();
      if (result.status === "success") setPicked(savedView(id));
      else setNote({ text: refusalText(result), away: false });
    } catch {
      setNote({ text: "Could not reach the agent. The active org was not changed.", away: true });
    }
  };

  const saveRun = async (params: string[]) => runStaff({ params }).unwrap();
  const afterSave = async () => {
    const before = new Set(saved.map((t) => t.id));
    setUseOpen(false);
    const fresh = await ours.refetch();
    const added = fresh.data?.trees?.find((t) => !before.has(t.id));
    if (added) setPicked(savedView(added.id));
  };

  return (
    <div className={styles.body}>
      <PanelFrame
        loading={loading}
        loadingLabel="Reading the org chart..."
        empty={empty}
        headerLeft={
          <>
            {icon}
            <Subtitle2 as="h1" data-testid="org-heading">
              {title}
            </Subtitle2>
            {size ? (
              <Badge appearance="tint" color="subtle" size="medium" data-testid="org-preset-size">
                {presetSizeWord(size)}
              </Badge>
            ) : null}
          </>
        }
        headerRight={
          presets.length > 0 ? (
            <div className={styles.selects}>
              <ViewSelect
                saved={saved}
                presets={presets}
                view={view}
                label={label}
                yours={!oursData}
                onPick={(v) => {
                  setNote(null);
                  setPicked(v);
                }}
              />
              {active ? (
                <ActiveSelect saved={saved} active={active} busy={writing} onPick={activate} />
              ) : null}
            </div>
          ) : undefined
        }
      >
        {line || preset || note ? (
          <div className={styles.lineRow}>
            {line ? (
              <Body1 className={styles.notActive} data-testid="org-not-active">
                {line}
              </Body1>
            ) : null}
            {preset ? (
              <Button
                appearance="primary"
                size="small"
                onClick={() => setUseOpen(true)}
                data-testid="org-use"
              >
                Use this org
              </Button>
            ) : null}
          </div>
        ) : null}
        {note ? (
          note.away ? (
            <MessageBar intent="error" data-testid="org-note">
              <MessageBarBody>{note.text}</MessageBarBody>
            </MessageBar>
          ) : (
            <Body1 className={styles.refusal} role="status" data-testid="org-note">
              {note.text}
            </Body1>
          )
        ) : null}
        {description ? (
          <Body2 as="p" className={styles.description} data-testid="org-preset-description">
            {description}
          </Body2>
        ) : null}
        {chart ? <ChartDrawing positions={chart.tree.positions} /> : (noOrg ?? null)}
      </PanelFrame>
      {useOpen && preset ? (
        <UseOrgDialog
          preset={preset}
          activeTitle={active?.title ?? null}
          run={saveRun}
          onSaved={afterSave}
          onClose={() => setUseOpen(false)}
        />
      ) : null}
    </div>
  );
}
