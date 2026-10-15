// The three link kinds, DRAWN: a room is an in-app link, an anchor
// scrolls this page and goes nowhere, and out is a new tab -- with the hover
// sentence when it is a repo file the room does not read.
import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { DocLink } from "./DocLink";
import type { DocLinkBase } from "./docLinks";

const base: DocLinkBase = {
  path: "README.md",
  roomFor: (p) => (p.startsWith("docs/") ? `/docs/${p}` : null),
  assetFor: (p) => `/api/docs/asset/${p}`,
  outside: (p) => `https://github.com/o/r/blob/main/${p}`,
};

function Where() {
  const loc = useLocation();
  return <div data-testid="where">{loc.pathname + loc.hash}</div>;
}

function mount(href: string, onAnchor = jest.fn()) {
  render(
    <MemoryRouter initialEntries={["/docs"]}>
      <Routes>
        <Route
          path="*"
          element={
            <>
              <DocLink href={href} base={base} onAnchor={onAnchor}>
                the link
              </DocLink>
              <Where />
            </>
          }
        />
      </Routes>
    </MemoryRouter>,
  );
  return onAnchor;
}

describe("DocLink", () => {
  it("a room link navigates in the app, its anchor kept, and opens no tab", () => {
    mount("docs/CLI.md#the-workflow");
    const a = screen.getByText("the link");
    expect(a.getAttribute("target")).toBeNull();
    fireEvent.click(a);
    expect(screen.getByTestId("where").textContent).toBe("/docs/docs/CLI.md#the-workflow");
  });

  it("an anchor scrolls this page and does not navigate", () => {
    const onAnchor = mount("#known-gaps");
    fireEvent.click(screen.getByText("the link"));
    expect(onAnchor).toHaveBeenCalledWith("known-gaps");
    expect(screen.getByTestId("where").textContent).toBe("/docs");
  });

  it("an external link leaves in a new tab", () => {
    mount("https://example.com/");
    const a = screen.getByText("the link");
    expect(a.getAttribute("href")).toBe("https://example.com/");
    expect(a.getAttribute("target")).toBe("_blank");
    expect(a.getAttribute("rel")).toBe("noopener noreferrer");
  });

  it("a repo file outside the room opens on github.com and says so on hover", () => {
    mount("AGENTS.md");
    const a = screen.getByText("the link");
    expect(a.getAttribute("href")).toBe("https://github.com/o/r/blob/main/AGENTS.md");
    expect(a.getAttribute("target")).toBe("_blank");
    expect(a.getAttribute("title")).toMatch(/AGENTS\.md on GitHub, in a new tab/);
  });
});
