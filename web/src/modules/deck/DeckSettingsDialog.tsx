import { useState } from "react";
import {
  Button,
  Dialog,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  Label,
  Radio,
  RadioGroup,
  Tooltip,
  useId,
} from "@fluentui/react-components";
import { SettingsRegular } from "@fluentui/react-icons";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { DECK_SETTINGS_LABEL } from "./engine/narrationConstants";
import { MODE_LABEL } from "./SettingsForm";
import { OPENING_MODES, type OpeningMode, useDeckOpening } from "./deckOpening";
import { ViewportProvider, useViewport } from "./viewport";

// The deck page's gear and the small dialog it opens: how a listed deck opens,
// kept per browser (deckOpening.ts). A dialog, not a drawer, so it stays apart
// from the app's own Settings drawer. One row, in the viewer's sheet's words:
// Mode, with Paging and Audiobook, and Podium beside them -- except on a phone,
// which never gets Podium (the engine's rule), so it is not offered there.

function OpeningRow() {
  const labelId = useId("deck-opening");
  const { mode, setMode } = useDeckOpening();
  const { isMobile } = useViewport();
  const offered = (Object.keys(OPENING_MODES) as OpeningMode[]).filter(
    (m) => m !== "podium" || !isMobile,
  );
  // A remembered Podium opens on the viewer's bar on a phone, so the row says
  // what will actually happen there: Paging or Audiobook, whichever is kept.
  const shown: OpeningMode = mode === "podium" && isMobile ? "paging" : mode;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "4px" }}>
      <Label id={labelId}>{MODE_LABEL}</Label>
      <RadioGroup
        aria-labelledby={labelId}
        layout="horizontal"
        value={shown}
        onChange={(_, data) => setMode(data.value as OpeningMode)}
      >
        {offered.map((m) => (
          <Radio key={m} value={m} label={OPENING_MODES[m]} />
        ))}
      </RadioGroup>
    </div>
  );
}

export function DeckSettingsDialog() {
  const [open, setOpen] = useState(false);
  return (
    <ViewportProvider>
      <Dialog open={open} onOpenChange={(_e, d) => setOpen(d.open)}>
        <Tooltip content={DECK_SETTINGS_LABEL} relationship="label">
          <Button
            appearance="subtle"
            icon={<SettingsRegular />}
            aria-label={DECK_SETTINGS_LABEL}
            onClick={() => setOpen(true)}
          />
        </Tooltip>
        <DialogSurface style={{ maxWidth: "400px" }}>
          <DialogBody>
            <DialogTitle action={<DialogDismiss />}>{DECK_SETTINGS_LABEL}</DialogTitle>
            <DialogContent>
              <OpeningRow />
            </DialogContent>
          </DialogBody>
        </DialogSurface>
      </Dialog>
    </ViewportProvider>
  );
}
