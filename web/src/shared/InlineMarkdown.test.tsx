/**
 * The REAL renderer (react-markdown and its remark plugins, no mock), as
 * markdownPlugins.test.tsx renders it: one line of markdown drawn inline.
 */
import { render } from "@testing-library/react";
import { InlineMarkdown } from "./InlineMarkdown";

const draw = (md: string, issuesUrl?: string) =>
  render(
    <ul>
      <li>
        <InlineMarkdown issuesUrl={issuesUrl}>{md}</InlineMarkdown>
      </li>
    </ul>,
  ).container.querySelector("li")!;

describe("an inline line of markdown", () => {
  it("draws a code span, bold and emphasis, and the backticks are gone", () => {
    const li = draw("Run `tkTest -Consts` to **see** _it_.");
    expect(li.querySelector("code")?.textContent).toBe("tkTest -Consts");
    expect(li.querySelector("strong")?.textContent).toBe("see");
    expect(li.querySelector("em")?.textContent).toBe("it");
    expect(li.textContent).toBe("Run tkTest -Consts to see it.");
  });

  it("draws a link that opens in a new tab", () => {
    const a = draw("Read [the guide](https://example.invalid/guide).").querySelector("a");
    expect(a?.getAttribute("href")).toBe("https://example.invalid/guide");
    expect(a?.getAttribute("target")).toBe("_blank");
    expect(a?.getAttribute("rel")).toBe("noopener noreferrer");
  });

  it("never draws a block: no paragraph, heading, list or code block", () => {
    const li = draw("# Not a heading");
    expect(li.querySelector("p, h1, h2, h3, ul, ol, pre, blockquote")).toBeNull();
    expect(li.textContent).toBe("Not a heading");
    expect(draw("- not a list").querySelector("ul, li")).toBeNull();
  });

  it("does not draw raw HTML", () => {
    const li = draw('A <b onclick="x()">bold</b> claim <script>alert(1)</script>');
    expect(li.querySelector("b, script")).toBeNull();
    expect(li.innerHTML).not.toContain("onclick");
  });

  it("links a #N to the repository's issue when it is told where they are", () => {
    const a = draw(
      "Fixes the export (#12).",
      "https://github.com/acme/widgets/issues",
    ).querySelector("a");
    expect(a?.getAttribute("href")).toBe("https://github.com/acme/widgets/issues/12");
    expect(draw("Fixes the export (#12).").querySelector("a")).toBeNull();
  });
});
