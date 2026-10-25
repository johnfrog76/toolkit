import { useEffect, useRef } from "react";
import type { CSSProperties } from "react";
import { COPY, fileUrl } from "./copy";
import type { LandingCopy } from "./copy";
import { PEOPLE } from "./people";
import { Wordmark } from "../shared/Wordmark";
import { Window, WindowStyles } from "./Window";
import { Code } from "./Code";
import { Butler } from "./Butler";
import { Faces } from "./Faces";
import { accentFor, accentWash } from "../shared/accent";

// The landing page, in the family's shape (the juggling and bowling engines,
// Connected Deck). A banner first: the wordmark, the offering, three bullets,
// the call to action, and the many faces at right with one line under them.
// Then the three ways of working under an eyebrow, each with one of the cast
// in their window, sides alternating. Then quick start with Nimbus beside the
// shell, then the footer. The words are the page's own (copy.ts).

/** The product's name: the wordmark's accessible name and the page's heading. */
export const PRODUCT_NAME = "ToolKit";

/**
 * The page's accent, from the product's one place (shared/accent.ts), as the
 * custom properties landing.css draws with. The page is dark, so it wears the
 * dark mode's steps: wine behind the wordmark, the key on the call to action,
 * the pale rose for the dots and the links.
 */
const DARK = accentFor("dark");
export const LANDING_ACCENT = {
  "--lp-accent": DARK.dot,
  "--lp-dot": DARK.dot,
  "--lp-blob": DARK.face,
  "--lp-cta": DARK.button,
  "--lp-cta-hover": DARK.hover,
  "--lp-glow": accentWash(0.1),
} as CSSProperties;

/** The visible address of the repository: the URL without its scheme. */
function shown(url: string): string {
  return url.replace(/^https?:\/\//, "");
}

export function Landing({
  copy = COPY,
  onPlay,
  playLabel,
  focusCta = false,
}: {
  copy?: LandingCopy;
  onPlay?: () => void;
  playLabel?: string;
  /** Back from the player: focus returns to the call to action. */
  focusCta?: boolean;
}) {
  const cta = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (focusCta) cta.current?.focus();
  }, [focusCta]);
  return (
    <div className="lp" style={LANDING_ACCENT}>
      <WindowStyles />
      {/* The banner. */}
      <header className="lp-banner">
        <div className="lp-banner-words">
          <h1 className="lp-title">
            <Wordmark
              size="clamp(170px, 24vw, 230px)"
              ink="var(--lp-text)"
              blob="var(--lp-blob)"
              title={PRODUCT_NAME}
            />
          </h1>
          <p className="lp-offer">{copy.offering}</p>
          <ul className="lp-bullets">
            {copy.bullets.map((b) => (
              <li key={b}>{b}</li>
            ))}
          </ul>
          {onPlay && (
            <div className="lp-cta">
              <button ref={cta} type="button" className="lp-cta-button" onClick={onPlay}>
                {playLabel} <span aria-hidden="true">→</span>
              </button>
            </div>
          )}
        </div>
        <div className="lp-banner-figure">
          <Faces line={copy.facesLine} />
        </div>
      </header>

      <main>
        {/* The three ways of working, each with one of the cast. */}
        <section className="lp-ways" aria-labelledby="lp-ways">
          <h2 id="lp-ways" className="lp-kicker">
            {copy.eyebrow}
          </h2>
          {copy.ways.map((way, i) => {
            const who = PEOPLE.find((p) => p.way === way.id);
            return (
              <article
                key={way.id}
                id={`way-${way.id}`}
                className={`lp-way ${i % 2 ? "lp-way--left" : "lp-way--right"}`}
              >
                <div className="lp-way-copy">
                  <h3>{way.heading}</h3>
                  <p>{way.text}</p>
                </div>
                {who && <Window person={who} />}
              </article>
            );
          })}
        </section>

        {/* Quick start. */}
        <section className="lp-quick" aria-labelledby="lp-quick">
          <h2 id="lp-quick">{copy.quickStartHeading}</h2>
          <div className="lp-quick-row">
            <pre className="lp-code" tabIndex={0} aria-labelledby="lp-quick">
              <Code lines={copy.quickStart} />
            </pre>
            <div className="lp-quick-figure">
              <Butler />
            </div>
          </div>
        </section>
      </main>

      {/* The footer. */}
      <footer className="lp-footer">
        <p className="lp-repo">
          <a href={copy.repository}>{shown(copy.repository)}</a>
        </p>
        <nav aria-label="Documentation">
          <ul className="lp-docs">
            {copy.documents.map((doc) => (
              <li key={doc.path}>
                <a href={fileUrl(copy.repository, doc.path)}>{doc.label}</a>
              </li>
            ))}
          </ul>
        </nav>
        <p className="lp-disclosure">{copy.narration}</p>
      </footer>
    </div>
  );
}
