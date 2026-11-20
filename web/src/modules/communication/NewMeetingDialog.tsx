import { useState } from "react";
import { useNavigate } from "react-router";
import {
  Button,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  DialogTrigger,
  Dropdown,
  Input,
  Link,
  Option,
  makeStyles,
  tokens,
} from "@fluentui/react-components";
import { DialogDismiss } from "../../shared/DialogDismiss";
import { nextWeekday } from "../../utility/dates";
import { useCreateManagerSessionMutation } from "./api.communication";
import { oneOnOnePath } from "./paths";

const HOURS = Array.from({ length: 12 }, (_, i) => String(i + 1));

const MINUTES = [
  { value: "0", label: "00" },
  { value: "15", label: "15" },
  { value: "30", label: "30" },
  { value: "45", label: "45" },
];

function nextThursday(): string {
  return nextWeekday(4);
}

const useStyles = makeStyles({
  dialogFields: {
    display: "flex",
    flexDirection: "column" as const,
    gap: tokens.spacingVerticalM,
    paddingTop: tokens.spacingVerticalS,
  },
  timeRow: {
    display: "flex",
    gap: tokens.spacingHorizontalS,
    alignItems: "center",
  },
});

/**
 * The New 1:1 dialog: scaffolds the next session and opens it. Mounted only
 * while open.
 */
export function NewMeetingDialog({ onClose }: { onClose: () => void }) {
  const styles = useStyles();
  const navigate = useNavigate();
  const [createSession, { isLoading: creating }] = useCreateManagerSessionMutation();
  const [newDate, setNewDate] = useState(nextThursday);
  const [newHour, setNewHour] = useState("10");
  const [newMinute, setNewMinute] = useState("0");
  const [newAmPm, setNewAmPm] = useState("AM");

  // Another recurring meeting than the 1:1 -- a series. An IC with one meeting
  // never meets the word: the field is behind one link, and blank means the 1:1
  // (docs/modules/communication.md, "The frontend").
  const [anotherMeeting, setAnotherMeeting] = useState(false);
  const [newSeries, setNewSeries] = useState("");
  const seriesSlug = newSeries.trim().toLowerCase().replace(/\s+/g, "-");
  const seriesOk = seriesSlug === "" || /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(seriesSlug);

  const handleSubmit = async () => {
    try {
      const result = await createSession({ date: newDate, series: seriesSlug }).unwrap();
      onClose();
      navigate(oneOnOnePath(result.filename));
    } catch {}
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
          <DialogTitle action={<DialogDismiss />}>
            {seriesSlug ? `New ${seriesSlug}` : "New 1:1"}
          </DialogTitle>
          <DialogContent>
            <div className={styles.dialogFields}>
              <Input
                type="date"
                size="small"
                value={newDate}
                onChange={(_, d) => setNewDate(d.value)}
                aria-label="Session date"
                style={{ width: "150px" }}
              />
              {anotherMeeting ? (
                <Input
                  size="small"
                  value={newSeries}
                  onChange={(_, d) => setNewSeries(d.value)}
                  aria-label="Which meeting"
                  placeholder="which meeting? e.g. client-weekly"
                  style={{ width: "220px" }}
                />
              ) : (
                <Link as="button" onClick={() => setAnotherMeeting(true)}>
                  Another meeting than the 1:1?
                </Link>
              )}
              <div className={styles.timeRow}>
                <Dropdown
                  size="small"
                  value={newHour}
                  selectedOptions={[newHour]}
                  onOptionSelect={(_e, d) => setNewHour(d.optionValue ?? "10")}
                  style={{ minWidth: "60px" }}
                  aria-label="Hour"
                >
                  {HOURS.map((h) => (
                    <Option key={h} value={h}>
                      {h}
                    </Option>
                  ))}
                </Dropdown>
                <Dropdown
                  size="small"
                  value={MINUTES.find((m) => m.value === newMinute)?.label ?? ""}
                  selectedOptions={[newMinute]}
                  onOptionSelect={(_e, d) => setNewMinute(d.optionValue ?? "0")}
                  style={{ minWidth: "60px" }}
                  aria-label="Minute"
                >
                  {MINUTES.map((m) => (
                    <Option key={m.value} value={m.value}>
                      {m.label}
                    </Option>
                  ))}
                </Dropdown>
                <Dropdown
                  size="small"
                  value={newAmPm}
                  selectedOptions={[newAmPm]}
                  onOptionSelect={(_e, d) => setNewAmPm(d.optionValue ?? "AM")}
                  style={{ minWidth: "65px" }}
                  aria-label="AM or PM"
                >
                  <Option value="AM">AM</Option>
                  <Option value="PM">PM</Option>
                </Dropdown>
              </div>
            </div>
          </DialogContent>
          <DialogActions>
            <DialogTrigger disableButtonEnhancement>
              <Button appearance="secondary">Cancel</Button>
            </DialogTrigger>
            <Button
              appearance="primary"
              onClick={handleSubmit}
              disabled={!seriesOk || creating || !newDate}
            >
              {creating ? "Creating…" : "Submit"}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
}
