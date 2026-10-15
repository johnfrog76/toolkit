/**
 * The Space anchor: the pill at the left of the nav IS Home. Its
 * face is the Space's display name where one is declared, the slug where not,
 * and "Home" with no Space at all; its tooltip carries name, slug and address.
 */
import { fireEvent, render, screen } from "@testing-library/react";
import { FluentProvider, webLightTheme } from "@fluentui/react-components";
import { SpaceAnchor, spaceFace } from "./SpaceAnchor";
import type { NavEntry } from "./registry";
import type { SpaceInfo } from "./api";

const home: NavEntry = { label: "Home", to: "/", match: (p) => p === "/" || p === "/board" };

const spaces: SpaceInfo[] = [
  { slug: "azure-demo", name: "Azure demo", status: "local" },
  {
    slug: "toolkit",
    name: "toolkit",
    status: "active",
    org: "https://github.com/johnfrog76/toolkit",
  },
  { slug: "globex", name: "Globex", status: "active", org: "https://dev.azure.com/globex" },
];

function draw(activeSpace: string, path = "/") {
  const onNavigate = jest.fn();
  render(
    <FluentProvider theme={webLightTheme}>
      <SpaceAnchor
        entry={home}
        here={home.match(path)}
        config={activeSpace ? { activeSpace, spaces } : undefined}
        onNavigate={onNavigate}
      />
    </FluentProvider>,
  );
  return { link: screen.getByRole("link"), onNavigate };
}

describe("the Space anchor", () => {
  it("shows the display name for a Space that declares one", () => {
    const { link } = draw("azure-demo");
    expect(link.textContent).toContain("Azure demo");
    expect(link.textContent).not.toContain("azure-demo");
  });

  it("shows the slug for a Space whose name is its slug, or that is not in the list", () => {
    expect(draw("toolkit").link.textContent).toContain("toolkit");
  });

  it("falls back to the slug when the Space is not declared at all", () => {
    expect(spaceFace({ activeSpace: "ghost", spaces }, "Home")).toEqual({
      text: "ghost",
      tooltip: "ghost",
      isSpace: true,
    });
  });

  it("with no active Space, reads Home -- never an empty pill", () => {
    const { link } = draw("");
    expect(link.textContent).toBe("Home");
    expect(spaceFace(undefined, "Home").text).toBe("Home");
    expect(spaceFace({ activeSpace: "", spaces }, "Home").text).toBe("Home");
  });

  it("is named Home to a screen reader as well as by its icon", () => {
    expect(draw("azure-demo").link.textContent).toMatch(/^Home: Azure demo$/);
  });

  it("clicking it navigates Home, in place", () => {
    const { link, onNavigate } = draw("azure-demo", "/system");
    fireEvent.click(link);
    expect(onNavigate).toHaveBeenCalledWith("/");
    expect(link.getAttribute("href")).toBe("/");
  });

  it("a modified click is left to the browser (a new tab)", () => {
    const { link, onNavigate } = draw("azure-demo", "/system");
    fireEvent.click(link, { metaKey: true });
    expect(onNavigate).not.toHaveBeenCalled();
  });

  it("is the active entry on Home's routes, and not elsewhere", () => {
    expect(draw("azure-demo", "/board").link.getAttribute("aria-current")).toBe("page");
  });

  it("is not current away from Home", () => {
    expect(draw("azure-demo", "/system").link.getAttribute("aria-current")).toBeNull();
  });

  it("its tooltip carries name, slug and address, in that order", () => {
    expect(spaceFace({ activeSpace: "globex", spaces }, "Home").tooltip).toBe(
      "Globex · globex · https://dev.azure.com/globex",
    );
    expect(spaceFace({ activeSpace: "azure-demo", spaces }, "Home").tooltip).toBe(
      "Azure demo · azure-demo",
    );
    // A name that IS the slug is said once.
    expect(spaceFace({ activeSpace: "toolkit", spaces }, "Home").tooltip).toBe(
      "toolkit · https://github.com/johnfrog76/toolkit",
    );
  });

  it("the tooltip is drawn on hover", async () => {
    const { link } = draw("globex");
    fireEvent.mouseEnter(link);
    expect(await screen.findByText("Globex · globex · https://dev.azure.com/globex")).toBeTruthy();
  });
});
