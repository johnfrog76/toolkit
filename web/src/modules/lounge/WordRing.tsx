/**
 * Zen Word Scrape (D-L21, from the owner's hub note):
 * a ring of five or six letters; type, or click the letters, to form a word;
 * a valid one settles into a quiet list beside the ring. No score, no
 * streak, no timer, no fanfare: when the ring is spent it gives way to the
 * next. The one reward the note asked for is kept where it costs nothing --
 * if the tank is worn and Animate is on, a spent ring advances the scene.
 * No unlocks, ever.
 *
 * Drives from the palette and the tokens (D-L23). The ring and the words
 * found persist per browser, so a ring half-read is there tomorrow.
 */
import { useState } from "react";
import type { KeyboardEvent } from "react";
import {
  Button,
  Caption1,
  Subtitle2,
  makeStyles,
  mergeClasses,
  shorthands,
  tokens,
} from "@fluentui/react-components";
import { PageCard } from "../../shared/PageCard";
import { useLocalPersistedState } from "../../shared/usePersistedState";
import { isAnimated, useSkinGrant, writeSkinGrant } from "../../shared/skinGrant";
import { TANK_SCENES } from "./skins";
import { canMake, isWord, nextRing, wordsFrom } from "./words";

export const WORDS_KEY = "toolkit-lounge-words";

export interface WordsState {
  /** The ring's own word -- what the letters were dealt from. */
  ring: string;
  /** The same letters, in the order they sit around the ring. */
  letters: string;
  found: string[];
}

export function isWordsState(v: unknown): v is WordsState {
  const s = v as WordsState;
  return (
    !!s &&
    typeof s === "object" &&
    typeof s.ring === "string" &&
    typeof s.letters === "string" &&
    s.letters.length === s.ring.length &&
    Array.isArray(s.found) &&
    s.found.every((w) => typeof w === "string")
  );
}

const useStyles = makeStyles({
  table: {
    display: "flex",
    flexWrap: "wrap",
    gap: tokens.spacingHorizontalL,
    alignItems: "flex-start",
    padding: tokens.spacingVerticalS,
    outline: "none",
    ":focus-visible": {
      outline: `1px solid ${tokens.colorBrandForeground2}`,
      borderRadius: tokens.borderRadiusMedium,
    },
  },
  ring: {
    position: "relative",
    width: "180px",
    height: "180px",
    flexShrink: 0,
  },
  letter: {
    position: "absolute",
    width: "36px",
    height: "36px",
    marginLeft: "-18px",
    marginTop: "-18px",
    borderRadius: "50%",
    border: `1px solid ${tokens.colorNeutralStroke2}`,
    background: tokens.colorNeutralBackground1,
    color: tokens.colorNeutralForeground1,
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase400,
    textTransform: "uppercase",
    cursor: "pointer",
    ":hover": {
      ...shorthands.borderColor(tokens.colorBrandForeground2),
      color: tokens.colorBrandForeground2,
    },
  },
  letterUsed: {
    opacity: 0.35,
  },
  guess: {
    position: "absolute",
    left: "50%",
    top: "50%",
    transform: "translate(-50%, -50%)",
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase400,
    letterSpacing: "0.2em",
    textTransform: "uppercase",
    color: tokens.colorBrandForeground2,
    minHeight: "1.4em",
    whiteSpace: "nowrap",
  },
  found: {
    listStyleType: "none",
    margin: 0,
    padding: 0,
    minWidth: "8em",
    fontFamily: tokens.fontFamilyMonospace,
    fontSize: tokens.fontSizeBase200,
    letterSpacing: "0.12em",
    textTransform: "uppercase",
    color: tokens.colorNeutralForeground3,
    display: "flex",
    flexDirection: "column",
    rowGap: tokens.spacingVerticalXS,
  },
});

/** Which letters of the ring the guess has already taken, by position. */
function usedPositions(letters: string, guess: string): Set<number> {
  const used = new Set<number>();
  for (const ch of guess) {
    for (let i = 0; i < letters.length; i++) {
      if (!used.has(i) && letters[i] === ch) {
        used.add(i);
        break;
      }
    }
  }
  return used;
}

export function WordRing() {
  const styles = useStyles();
  // The fresh ring is dealt once per mount and used only when nothing is
  // saved; a saved ring wins.
  const [fresh] = useState<WordsState>(() => ({ ...nextRing(), found: [] }));
  const { value: state, setValue: setState } = useLocalPersistedState<WordsState>(
    WORDS_KEY,
    fresh,
    isWordsState,
  );
  const [guess, setGuess] = useState("");
  const grant = useSkinGrant();

  const used = usedPositions(state.letters, guess);
  const all = wordsFrom(state.ring);

  const deal = () => {
    setState({ ...nextRing(state.ring), found: [] });
    setGuess("");
  };

  const spent = () => {
    // The reward, where it costs nothing: a worn, moving tank turns to its
    // next scene. A still one, or no skin, gets nothing -- and nothing is
    // ever unlocked.
    if (grant && grant.skinId === "tank" && isAnimated(grant)) {
      const ix = TANK_SCENES.findIndex((s) => s.src === grant.src);
      const next = TANK_SCENES[(ix + 1) % TANK_SCENES.length];
      writeSkinGrant({ ...grant, src: next.src, caption: next.caption });
    }
    deal();
  };

  const keep = () => {
    const word = guess;
    setGuess("");
    if (!isWord(word) || !canMake(word, state.ring) || state.found.includes(word)) return;
    const found = [...state.found, word];
    if (found.length >= all.length) {
      spent();
      return;
    }
    setState({ ...state, found });
  };

  const add = (ch: string) => {
    if (used.size >= state.letters.length) return;
    if (!canMake(guess + ch, state.letters)) return;
    setGuess(guess + ch);
  };

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.key === "Enter") {
      e.preventDefault();
      keep();
    } else if (e.key === "Backspace") {
      e.preventDefault();
      setGuess(guess.slice(0, -1));
    } else if (e.key === "Escape") {
      setGuess("");
    } else if (/^[a-z]$/i.test(e.key)) {
      e.preventDefault();
      add(e.key.toLowerCase());
    }
  };

  const n = state.letters.length;
  return (
    <PageCard
      scrollable
      headerLeft={<Subtitle2>Words</Subtitle2>}
      headerRight={
        <Button size="small" appearance="subtle" onClick={deal}>
          New ring
        </Button>
      }
      footerRight={<Caption1>type a word · enter keeps it · escape lets it go</Caption1>}
    >
      <div
        className={styles.table}
        role="group"
        aria-label="Word ring"
        tabIndex={0}
        onKeyDown={onKeyDown}
      >
        <div className={styles.ring}>
          {state.letters.split("").map((ch, i) => {
            const angle = (i / n) * Math.PI * 2 - Math.PI / 2;
            const left = 50 + 42 * Math.cos(angle);
            const top = 50 + 42 * Math.sin(angle);
            return (
              <button
                key={i}
                type="button"
                className={mergeClasses(styles.letter, used.has(i) && styles.letterUsed)}
                style={{ left: `${left}%`, top: `${top}%` }}
                aria-label={`letter ${ch}`}
                onClick={() => add(ch)}
              >
                {ch}
              </button>
            );
          })}
          {/* A status, not a bare live div: a label is prohibited on a div with
              no role (axe's aria-prohibited-attr), and status is the live
              region (polite) that may carry one. */}
          <div className={styles.guess} role="status" aria-label="your word">
            {guess}
          </div>
        </div>
        <ul className={styles.found} aria-label="words kept">
          {state.found.map((w) => (
            <li key={w}>{w}</li>
          ))}
        </ul>
      </div>
    </PageCard>
  );
}
