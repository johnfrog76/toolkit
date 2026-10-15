import { useRef, useState } from "react";
import { Button, Caption1, makeStyles, tokens } from "@fluentui/react-components";
import { DeleteRegular, ImageAddRegular, ImageEditRegular } from "@fluentui/react-icons";
import { CardActions } from "../../shared/CardActions";
import type { CardAction } from "../../shared/CardActions";
import { ConfirmDialog } from "../../shared/ConfirmDialog";
import { ImageDropZone } from "../../shared/ImageDropZone";
import { StatusMessage } from "../../shared/StatusMessage";
import { STAMPS } from "../../shell/consts";
import { useAttachCoverMutation, useUploadAssetMutation } from "./api.ado";
import { imageLine } from "./CardCover";
import { buildCoverParams, commandResultMessage } from "./cliBridge";

// Attach a card's picture from the browser (docs/hub/cards.md, "A card's pictures").
// One writer still: the bytes go to the upload route,
// which answers a temp path and writes nothing into the hub; then the Cover
// verb runs through the bridge with that path. The page re-reads the card
// when the verb has written its line.
//
// Where the control lives: a VISIBLE drop zone, with a file
// picker and paste as the other ways in. With no cover the zone IS the
// cover's box, under the header, the same 16:10 the picture will fill -- so
// nothing jumps when the picture lands. With a cover, the header's actions
// take over: Replace cover, Add before, Remove cover.

const useStyles = makeStyles({
  zoneBox: { marginBottom: tokens.spacingVerticalM },
  row: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalS,
    marginTop: tokens.spacingVerticalS,
  },
});

type Kind = "cover" | "before";

export function useAttach(filename: string, onDone: () => void) {
  const [upload, uploadState] = useUploadAssetMutation();
  const [attach, attachState] = useAttachCoverMutation();
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const busy = uploadState.isLoading || attachState.isLoading;

  const run = async (params: string[], doneWord: string) => {
    setError(null);
    setMessage(null);
    try {
      const result = await attach({ params }).unwrap();
      if (result.status === "success") {
        setMessage(commandResultMessage(result, doneWord));
        onDone();
        return true;
      }
      setError(commandResultMessage(result, doneWord));
    } catch {
      setError("Could not reach the agent. Nothing was written.");
    }
    return false;
  };

  /** Upload the file, then the verb with the path it answered. */
  const send = async (file: File, kind: Kind) => {
    setError(null);
    setMessage(null);
    let path = "";
    try {
      path = (await upload({ file }).unwrap()).path;
    } catch (e) {
      const detail = (e as { data?: { detail?: string } } | undefined)?.data?.detail;
      setError(detail ?? "Could not upload the picture. Nothing was written.");
      return false;
    }
    return run(
      buildCoverParams({ card: filename, image: path, before: kind === "before" }),
      "Attached.",
    );
  };
  const remove = () => run(buildCoverParams({ card: filename, remove: true }), "Removed.");

  return { send, remove, busy, message, error, clearMessage: () => setMessage(null) };
}

/** The header's actions for a card that has a cover: Replace, Add before, Remove. */
export function AttachActions({
  filename,
  content,
  onDone,
  onAsk,
}: {
  filename: string;
  content: string;
  onDone: () => void;
  /** Open the dialog that holds a drop zone for this kind. */
  onAsk: (kind: Kind) => void;
}) {
  const hasCover = !!imageLine(content, STAMPS.cover);
  const hasBefore = !!imageLine(content, STAMPS.before);
  const [confirming, setConfirming] = useState(false);
  const { remove, busy, error } = useAttach(filename, onDone);
  if (!hasCover) return null;
  const secondary: CardAction[] = [
    {
      icon: <ImageAddRegular />,
      label: hasBefore ? "Replace before" : "Add before",
      onClick: () => onAsk("before"),
    },
    {
      icon: <DeleteRegular />,
      label: "Remove cover",
      onClick: () => setConfirming(true),
      dividerBefore: true,
    },
  ];
  return (
    <>
      <CardActions
        primaryAction={{
          icon: <ImageEditRegular />,
          label: "Replace cover",
          onClick: () => onAsk("cover"),
          disabled: busy,
        }}
        menuLabel="Actions for the cover"
        secondaryActions={secondary}
      />
      <ConfirmDialog
        open={confirming}
        title="Remove the cover?"
        what={
          <>
            Delete the picture from the Space&apos;s assets/ and the card&apos;s Cover line. The
            card keeps everything else.
          </>
        }
        confirmLabel="Remove"
        busy={busy}
        message={error}
        onConfirm={async () => {
          if (await remove()) setConfirming(false);
        }}
        onCancel={() => setConfirming(false)}
      />
    </>
  );
}

/** The zone in the cover's box when the card has no cover; and the dialog-less
 *  attach for a before or a replacement, drawn under the pictures when asked. */
export function AttachZone({
  filename,
  content,
  kind,
  onDone,
  onClose,
}: {
  filename: string;
  content: string;
  /** What the zone attaches; "cover" when the card has none, else what the header asked for. */
  kind: Kind;
  onDone: () => void;
  /** Present when the zone was opened from the header: Cancel closes it. */
  onClose?: () => void;
}) {
  const styles = useStyles();
  const [file, setFile] = useState<File | null>(null);
  // The button a dropped picture waits for: the zone names it and focuses it.
  const attachRef = useRef<HTMLButtonElement>(null);
  const { send, busy, message, error, clearMessage } = useAttach(filename, onDone);
  const hasCover = !!imageLine(content, STAMPS.cover);
  const label =
    kind === "before"
      ? imageLine(content, STAMPS.before)
        ? "Replace before"
        : "Add before"
      : hasCover
        ? "Replace cover"
        : "Add cover";
  return (
    <div className={styles.zoneBox} data-attach-zone={kind}>
      <ImageDropZone
        label={label}
        hint={
          kind === "before"
            ? "A snap of what was wrong."
            : "A snap of what landed: the card's picture on the board."
        }
        file={file}
        onFile={setFile}
        disabled={busy}
        next={attachRef}
      />
      <div className={styles.row}>
        <Button
          ref={attachRef}
          appearance="primary"
          size="small"
          disabled={!file || busy}
          onClick={async () => {
            if (file && (await send(file, kind))) setFile(null);
          }}
        >
          {busy ? "Attaching…" : label}
        </Button>
        {onClose ? (
          <Button appearance="secondary" size="small" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
        ) : null}
        {error ? (
          <Caption1 role="alert" style={{ color: tokens.colorPaletteRedForeground1 }}>
            {error}
          </Caption1>
        ) : null}
      </div>
      {message ? (
        <StatusMessage status="success" onDismiss={clearMessage}>
          {message}
        </StatusMessage>
      ) : null}
    </div>
  );
}
