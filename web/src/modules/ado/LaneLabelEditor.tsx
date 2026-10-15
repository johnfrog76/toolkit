import { useState } from "react";
import type { CSSProperties } from "react";
import { Button, Caption1, Input, makeStyles, tokens } from "@fluentui/react-components";
import { EditRegular } from "@fluentui/react-icons";
import { useWriteConfigMutation } from "./api.ado";
import { buildConfigEdit, commandResultMessage } from "./cliBridge";

/**
 * The pencil on a lane header (the owner, annotating the Demo board:
 * "I want to see pencil icon, text exposed as input -- user can enter
 * whatever they want."; "the 16px edit icon always show
 * before the lane title because this allows the count to follow without
 * spacing issue"). Display only, as ever: the write is
 * `spaces.<slug>.laneNames.<key>` through `PUT /api/config` -- the one writer,
 * the `ConfigSettings` precedent verbatim -- never a second implementation.
 * The CONTRACT word (`consts.json` `status`) never travels; only what the
 * board prints changes.
 *
 * THE HOUSE RULE: "an in-place editor occupies the
 * EXACT box of the text it replaces -- same height, baseline and width, same
 * typography tokens, padding that nets to the same box, no extra margin in
 * either state." Three things had to change to hold it:
 *
 * 1. The label used to be a Fluent `Subtitle2` rendered `as="h2"`, and Fluent's
 *    Text primitive sets no margin of its own -- so the `<h2>` carried the
 *    BROWSER's own default heading margin (~0.83em top and bottom), present
 *    only in the resting state. That is the ~20px "extra space on top" the owner
 *    reported: nothing this app drew, a UA default nothing here reset.
 * 2. Editing used to swap the WHOLE row (pencil button and all) for a bare
 *    `Input` mounted outside any row wrapper, at Fluent's own `body1`
 *    typography and its own default field height. Losing the button changed
 *    the row's own cross-axis size, and the input's smaller, regular-weight
 *    type sat in a shorter box than the heading it replaced -- together the
 *    24px hop the owner measured (heading at y=309, input at y=285).
 * 3. The fix: one shared box, `TITLE_STYLE` below -- no margin, one explicit
 *    height, the same four typography tokens Subtitle2 drew from -- worn as
 *    an inline `style` by BOTH the resting label (now a plain `h2`, not
 *    Subtitle2: Subtitle2 draws its own Griffel atomic classes, and Fluent's
 *    `Input` inserts its OWN typography atomic classes on the input slot at
 *    render time too -- in this codebase's jest setup (no Griffel build-time
 *    bucketing plugin) the LATER-inserted class wins a same-specificity
 *    conflict, which is Input's own, not an override passed in beside it. An
 *    inline style has no such ambiguity: it wins over any class, in a test
 *    and in the built app alike) and the input's own `input` slot, and the
 *    pencil button stays mounted in both states so the ROW itself never
 *    changes shape. `LaneLabelEditor.test.tsx` measures the two states'
 *    computed styles rather than trusting the eye.
 */
const TITLE_STYLE: CSSProperties = {
  margin: 0,
  height: tokens.lineHeightBase400,
  boxSizing: "border-box",
  fontFamily: tokens.fontFamilyBase,
  fontSize: tokens.fontSizeBase400,
  lineHeight: tokens.lineHeightBase400,
  fontWeight: tokens.fontWeightSemibold,
};
const useStyles = makeStyles({
  row: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalXS,
  },
  // Opacity, not display -- the button stays in the tab order and reachable
  // by keyboard even while visually quiet. Visible on hover of the WHOLE row
  // (below, driven by JS state -- hovering only the icon's own small hitbox
  // would never reveal it in the first place) or on focus of the button
  // itself, so a keyboard user tabbing to it sees it appear rather than
  // acting on a control they cannot see.
  // Always shown, before the title, at the icon size: a hover-revealed pencil
  // AFTER the title left a gap the count had to jump over. Present in
  // BOTH states now -- editing used to unmount it, which is half of
  // why the row's own height moved.
  pencil: {
    minWidth: "auto",
    padding: 0,
    color: tokens.colorNeutralForeground3,
    ":hover": { color: tokens.colorBrandForeground1 },
  },
  input: {
    minWidth: "8ch",
    maxWidth: "16ch",
    // Fluent's own field padding is a control's, not the heading's -- netted
    // to zero so the outer box titleBox draws is the whole of it.
    padding: 0,
  },
  error: {
    color: tokens.colorPaletteRedForeground1,
  },
});

export interface LaneLabelEditorProps {
  /** The label as the board currently prints it -- the org's own word, or
   *  the contract's when the org has set none. */
  label: string;
  /** The dotted config key this lane's label lives at for the active org --
   *  build with `laneConfigKey(orgSlug, status)`. `null` while there is no
   *  active org (an archived-org retrospective, or the sample's local board
   *  with nothing configured yet) hides the pencil rather than offering an
   *  edit that has nowhere to write. */
  configKey: string | null;
}

export function LaneLabelEditor({ label, configKey }: LaneLabelEditorProps) {
  const styles = useStyles();
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(label);
  const [error, setError] = useState<string | null>(null);
  const [writeConfig, { isLoading }] = useWriteConfigMutation();

  if (!configKey) {
    return <h2 style={TITLE_STYLE}>{label}</h2>;
  }

  const startEditing = () => {
    setDraft(label);
    setError(null);
    setEditing(true);
  };

  const cancel = () => {
    setError(null);
    setEditing(false);
  };

  const save = async () => {
    // A blank value is buildConfigEdit's existing "clear a field" shape --
    // -Unset, never an empty string -- which for a display-only org field is
    // exactly "restore the space's default word".
    const payload = buildConfigEdit([{ key: configKey, type: "string", value: draft }]);
    setError(null);
    // The board's own rule for a card move (Board.tsx): no optimistic update,
    // and a refusal leaves it exactly where it was. The rename follows it now
    // -- it used to exit editing and swap back to the OLD label the
    // instant Enter was pressed, before the write had even reached the agent,
    // which is indistinguishable from "the rename did not persist" whenever
    // the write then failed (a hub that is not writable, a value the schema
    // refuses) with nobody told why.
    try {
      const reply = await writeConfig(payload).unwrap();
      if (reply.result.status === "success") setEditing(false);
      else setError(commandResultMessage(reply.result, "The lane was not renamed."));
    } catch {
      setError("Could not reach the agent. The lane was not renamed.");
    }
  };

  return (
    <div className={styles.row}>
      <Button
        className={styles.pencil}
        appearance="transparent"
        size="small"
        icon={<EditRegular fontSize={16} />}
        aria-label={`Rename the ${label} lane`}
        onClick={editing ? undefined : startEditing}
        disabled={editing}
      />
      {editing ? (
        <>
          <Input
            className={styles.input}
            style={TITLE_STYLE}
            input={{ style: TITLE_STYLE }}
            size="small"
            autoFocus
            value={draft}
            disabled={isLoading}
            aria-label={`Rename the ${label} lane`}
            onChange={(_e, d) => {
              setDraft(d.value);
              setError(null);
            }}
            onKeyDown={(e) => {
              if (e.key === "Enter") void save();
              else if (e.key === "Escape") cancel();
            }}
            // Blur CANCELS rather than saves: Escape unmounts this input, and a
            // save on blur would race whether the browser also fires a blur for
            // that removal. Only Enter -- an explicit, unambiguous commit --
            // writes anything.
            onBlur={cancel}
          />
          {error ? <Caption1 className={styles.error}>{error}</Caption1> : null}
        </>
      ) : (
        <h2 style={TITLE_STYLE}>{label}</h2>
      )}
    </div>
  );
}
