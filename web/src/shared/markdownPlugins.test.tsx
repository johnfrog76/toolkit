/**
 * The REAL renderer: react-markdown with the shared plugin list, no
 * mock. The registry tests mock every module so a sibling's tree never loads
 * react-markdown; this file is the one place that loads it on purpose, which
 * is why jest.config.mjs lets ts-jest transform the unified/remark/rehype ESM
 * packages (transformIgnorePatterns).
 */
import { render } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import ReactMarkdown from "react-markdown";
import { markdownPlugins } from "./markdownPlugins";
import { MarkdownViewer } from "./MarkdownViewer";
import { prepareMarkdown } from "./prepareMarkdown";

function html(md: string): HTMLElement {
  const { container } = render(
    <ReactMarkdown {...markdownPlugins}>{prepareMarkdown(md).body}</ReactMarkdown>,
  );
  return container;
}

describe("markdown plugins: simple HTML reads as it does on GitHub", () => {
  it("renders the issue's centred paragraph as elements, not text", () => {
    const c = html('<p align="center"><em>Your Spaces. Your work. Your Studio.</em></p>');
    const p = c.querySelector("p");
    expect(p?.getAttribute("align")).toBe("center");
    expect(p?.querySelector("em")?.textContent).toBe("Your Spaces. Your work. Your Studio.");
    expect(c.textContent).not.toContain("<p");
  });

  it("keeps an img with its width and alt", () => {
    const img = html('<img src="docs/logo.png" width="200" alt="Logo">').querySelector("img");
    expect(img?.getAttribute("src")).toBe("docs/logo.png");
    expect(img?.getAttribute("width")).toBe("200");
    expect(img?.getAttribute("alt")).toBe("Logo");
  });

  it("keeps details and summary", () => {
    const c = html("<details><summary>More</summary>\n\nhidden *text*\n\n</details>");
    expect(c.querySelector("details > summary")?.textContent).toBe("More");
    expect(c.querySelector("details em")?.textContent).toBe("text");
  });

  it("keeps br", () => {
    expect(html("one<br>two").querySelector("br")).not.toBeNull();
  });

  it("keeps a safe link", () => {
    expect(
      html('<a href="https://example.com">x</a>').querySelector("a")?.getAttribute("href"),
    ).toBe("https://example.com");
  });

  it("still renders markdown and gfm tables", () => {
    const c = html("# T\n\n| a | b |\n|---|---|\n| 1 | 2 |\n");
    expect(c.querySelector("h1")?.textContent).toBe("T");
    expect(c.querySelector("table td")?.textContent).toBe("1");
  });
});

describe("markdown plugins: nothing that executes survives", () => {
  it("drops a script element", () => {
    const c = html("before <script>alert(1)</script> after");
    expect(c.querySelector("script")).toBeNull();
    expect(c.innerHTML).not.toContain("alert(1)</script>");
  });

  it("drops style and iframe", () => {
    const c = html('<style>p{display:none}</style><iframe src="https://example.com"></iframe>');
    expect(c.querySelector("style")).toBeNull();
    expect(c.querySelector("iframe")).toBeNull();
  });

  it("drops an onclick handler and keeps the element", () => {
    const c = html('<p onclick="alert(1)" onmouseover="x()">hi</p>');
    const p = c.querySelector("p");
    expect(p?.textContent).toBe("hi");
    expect(p?.getAttributeNames().filter((n) => n.startsWith("on"))).toEqual([]);
  });

  it("drops a javascript: href", () => {
    const a = html('<a href="javascript:alert(1)">x</a>').querySelector("a");
    expect(a?.getAttribute("href") ?? "").not.toMatch(/javascript/i);
  });

  it("drops a javascript: markdown link and an img onerror", () => {
    const c = html('[x](javascript:alert(1))\n\n<img src="a.png" onerror="alert(1)">');
    expect(c.querySelector("a")?.getAttribute("href") ?? "").not.toMatch(/javascript/i);
    expect(c.querySelector("img")?.hasAttribute("onerror")).toBe(false);
  });
});

describe("markdown plugins: comments and code", () => {
  it("does not show an HTML comment", () => {
    const c = html("a\n\n<!-- template instruction -->\n\nb");
    expect(c.textContent).not.toContain("template instruction");
    expect(c.textContent).not.toContain("<!--");
  });

  it("shows tag-like text inside a fenced block and inline code as code", () => {
    const c = html('```html\n<p align="center">x</p>\n```\n\nuse `<script>` here');
    expect(c.querySelector("pre code")?.textContent).toContain('<p align="center">x</p>');
    expect(c.querySelector("p[align]")).toBeNull();
    expect(c.querySelector("script")).toBeNull();
    expect(c.textContent).toContain("<script>");
  });
});

describe("MarkdownViewer: raw HTML reaches the existing handlers", () => {
  const base = { path: "README.md", assetFor: (p: string) => `/asset/${p}`, roomFor: () => null };

  it("sends a raw <img> through resolveImage and keeps its width", () => {
    const { container } = render(
      <MarkdownViewer
        content={'<img src="docs/logo.png" width="200" alt="L">'}
        links={base as never}
      />,
    );
    const img = container.querySelector("img");
    expect(img?.getAttribute("src")).toBe("/asset/docs/logo.png");
    expect(img?.getAttribute("width")).toBe("200");
  });

  it("sends a raw <a> through the link handling (external opens in a new tab)", () => {
    const { container } = render(
      <MarkdownViewer content={'<a href="https://example.com">x</a>'} />,
    );
    expect(container.querySelector("a")?.getAttribute("target")).toBe("_blank");
  });

  it("centres a raw aligned paragraph", () => {
    const { container } = render(<MarkdownViewer content={'<p align="center">hi</p>'} />);
    expect(container.querySelector("p")?.getAttribute("align")).toBe("center");
  });
});

// Axe's label (critical): GFM's task-list checkbox is a bare
// <input type="checkbox" disabled>; the viewer names it by the item's words,
// tight list or loose, and a nested item names only itself.
describe("MarkdownViewer: a task-list checkbox is named by its item", () => {
  it("names each checkbox in a tight list, nested items by their own words", () => {
    const { getByRole } = render(
      <MarkdownViewer content={"- [x] Write the fix\n- [ ] Ship it\n  - [ ] Tell the team\n"} />,
    );
    expect((getByRole("checkbox", { name: "Write the fix" }) as HTMLInputElement).checked).toBe(
      true,
    );
    expect(getByRole("checkbox", { name: "Ship it" })).toBeTruthy();
    expect(getByRole("checkbox", { name: "Tell the team" })).toBeTruthy();
  });

  it("names the checkbox of a loose list, which sits inside a paragraph", () => {
    const { getByRole } = render(
      <MarkdownViewer content={"- [ ] First **step**\n\n- [x] Second\n"} />,
    );
    expect(getByRole("checkbox", { name: "First step" })).toBeTruthy();
    expect(getByRole("checkbox", { name: "Second" })).toBeTruthy();
  });
});

// A repository's document whose issues are known links its `#N` mentions to
// that issue's room; inside code, an existing link, or with no issues known,
// `#N` stays the text it was written as.
describe("MarkdownViewer: a #N mention in a repository's document", () => {
  const issues = "https://github.com/o/r/issues";
  const withIssues = {
    path: "README.md",
    assetFor: (p: string) => `/asset/${p}`,
    roomFor: () => null,
    outside: () => "",
    issues: { url: issues, room: (n: string) => `/issue/${n}?repo=r` },
  };
  const draw = (content: string, links: object | null = withIssues) =>
    render(
      <MemoryRouter>
        <MarkdownViewer content={content} links={(links ?? undefined) as never} />
      </MemoryRouter>,
    ).container;

  it("opens the issue's room from prose, emphasis and a list", () => {
    const c = draw("Fixed in #93, see *also #7*.\n\n- (#12) one\n");
    const hrefs = [...c.querySelectorAll("a")].map((a) => [a.textContent, a.getAttribute("href")]);
    expect(hrefs).toEqual([
      ["#93", "/issue/93?repo=r"],
      ["#7", "/issue/7?repo=r"],
      ["#12", "/issue/12?repo=r"],
    ]);
    expect(c.textContent).toContain("Fixed in #93, see also #7.");
  });

  it("leaves a code span and a code block as text", () => {
    const c = draw("Run `gh issue view #93`.\n\n```\nsee #12\n```\n");
    expect(c.querySelectorAll("a")).toHaveLength(0);
    expect(c.querySelector("code")?.textContent).toBe("gh issue view #93");
    expect(c.querySelector("pre")?.textContent).toContain("see #12");
  });

  it("leaves a link's own text and a word-joined # alone", () => {
    const c = draw("[the #5 thread](https://example.com/x) and a#6 and C#7 and #8a\n");
    const links = [...c.querySelectorAll("a")];
    expect(links).toHaveLength(1);
    expect(links[0].textContent).toBe("the #5 thread");
  });

  it("is text with no issues known for the repository", () => {
    const { issues: _omit, ...noTracker } = withIssues;
    expect(draw("Fixed in #93.", noTracker).querySelectorAll("a")).toHaveLength(0);
    expect(draw("Fixed in #93.", null).querySelectorAll("a")).toHaveLength(0);
  });

  it("opens the room for the issue's github.com address written out, too", () => {
    const c = draw(
      `See [the issue](${issues}/93) and [another repo's](https://github.com/x/y/issues/1).`,
    );
    const hrefs = [...c.querySelectorAll("a")].map((a) => a.getAttribute("href"));
    expect(hrefs).toEqual(["/issue/93?repo=r", "https://github.com/x/y/issues/1"]);
  });
});
