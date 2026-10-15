/**
 * A meeting stopwatch for the 1:1 detail page.
 *
 * Module-local rather than in shared/: it came across with this page, nothing
 * else in the app uses it, and shared/ is the shell's common ground -- a module
 * does not get to add to it on the way past. If a second module ever wants a
 * timer, that is the moment to promote it.
 */
import { useEffect, useRef, useState } from "react";
import { Button, Caption1, makeStyles, tokens } from "@fluentui/react-components";
import { PlayRegular, PauseRegular, ArrowCounterclockwiseRegular } from "@fluentui/react-icons";

const useStyles = makeStyles({
  root: {
    display: "flex",
    alignItems: "center",
    gap: tokens.spacingHorizontalXS,
  },
  clock: {
    fontFamily: tokens.fontFamilyMonospace,
    minWidth: "3.5em",
    textAlign: "center" as const,
  },
});

function formatElapsed(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

export function Timer() {
  const styles = useStyles();
  const [running, setRunning] = useState(false);
  const [elapsedMs, setElapsedMs] = useState(0);
  const startedAtRef = useRef<number | null>(null);

  useEffect(() => {
    if (!running) return;
    const id = setInterval(() => {
      setElapsedMs(Date.now() - (startedAtRef.current ?? Date.now()));
    }, 1000);
    return () => clearInterval(id);
  }, [running]);

  const handleToggle = () => {
    if (running) {
      setRunning(false);
      return;
    }
    startedAtRef.current = Date.now() - elapsedMs;
    setRunning(true);
  };

  const handleReset = () => {
    setRunning(false);
    setElapsedMs(0);
  };

  return (
    <div className={styles.root}>
      <Caption1 className={styles.clock}>{formatElapsed(elapsedMs)}</Caption1>
      <Button
        appearance="subtle"
        size="small"
        icon={running ? <PauseRegular /> : <PlayRegular />}
        onClick={handleToggle}
        title={running ? "Pause" : "Start"}
      />
      <Button
        appearance="subtle"
        size="small"
        icon={<ArrowCounterclockwiseRegular />}
        onClick={handleReset}
        title="Reset"
      />
    </div>
  );
}
