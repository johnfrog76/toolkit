import { createHash } from "node:crypto";
import { renderToStaticMarkup } from "react-dom/server";
import { FACE_IDS, RefinedBust, RefinedPortrait } from "./refinedFaces";

// The refined cast, shared by the landing page and the Team Agile org chart.
//
// The landing page's three portraits were drawn before the faces moved here,
// and the move must not change a byte of them: each hash below is the markup
// the landing page's own copy of this file rendered, so a change to a shared
// part that reaches those three fails here, by name.

const LANDING_MARKUP: Record<string, string> = {
  minimalist: "c29c0f2ed316552e24c2eae6e6cbdaf9bf42ce168100f9076a68db2fa184f864",
  pm: "f0dad8b91689aa1a47384d0575a67bcbd9173193eb01611fae28adc2e3446af8",
  "dev-hero": "a7250d2e3da486fa85e36d69589c3f77831151e796eca7a917076e2b2d90b7dd",
};

const sha = (s: string) => createHash("sha256").update(s).digest("hex");

describe("the refined faces", () => {
  it.each(Object.keys(LANDING_MARKUP))(
    "the landing page's %s renders exactly as it did before the faces were shared",
    (face) => {
      const markup = renderToStaticMarkup(
        <RefinedPortrait face={face as (typeof FACE_IDS)[number]} className="lp-card-portrait" />,
      );
      expect(sha(markup)).toBe(LANDING_MARKUP[face]);
    },
  );

  it.each(FACE_IDS)("%s draws as a bust and as a portrait, hidden from a screen reader", (face) => {
    const bust = renderToStaticMarkup(<RefinedBust face={face} width={96} />);
    expect(bust).toContain(`data-refined="${face}"`);
    expect(bust).toContain('aria-hidden="true"');
    expect(bust).toContain('viewBox="0 -10 120 124"');
    // The figure under its own shadow, which the bust's own defs declare.
    const shadow = /filter="url\(#([^)]+)\)"/.exec(bust)?.[1];
    expect(shadow).toBeTruthy();
    expect(bust).toContain(`id="${shadow}"`);
    expect(renderToStaticMarkup(<RefinedPortrait face={face} />)).toContain(
      `data-refined="${face}"`,
    );
  });

  it("every face is drawn differently", () => {
    const strip = (s: string) => s.replace(/id="[^"]*"|url\(#[^)]*\)/g, "");
    const drawn = FACE_IDS.map((face) =>
      strip(renderToStaticMarkup(<RefinedBust face={face} width={96} />).replace(face, "")),
    );
    expect(new Set(drawn).size).toBe(FACE_IDS.length);
  });
});
