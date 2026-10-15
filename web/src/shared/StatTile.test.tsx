import { render, screen } from "@testing-library/react";
import { FluentProvider, Tooltip, webLightTheme } from "@fluentui/react-components";
import { StatTile, StatTiles } from "./StatTile";

// One costume for a count. The tile is the number beside its
// caption, boxed; the colour is the only thing a card may vary, and only when
// the number is a verdict.
describe("StatTile", () => {
  it("renders the number beside its caption, inside the tiles row", () => {
    const { container } = render(
      <StatTiles>
        <StatTile count={81} label="Items closed" />
        <StatTile count="3/5" label="active days" />
      </StatTiles>,
    );
    const row = container.querySelector("[data-stat-tiles]");
    expect(row).not.toBeNull();
    const tiles = row!.querySelectorAll("[data-stat-tile]");
    expect(tiles).toHaveLength(2);
    expect(tiles[0].textContent).toBe("81Items closed");
    expect(tiles[1].textContent).toBe("3/5active days");
  });

  it("colours the number only when the card says it is a verdict", () => {
    render(
      <StatTiles>
        <StatTile count={12} label="Passed" color="rgb(1, 2, 3)" />
        <StatTile count={4} label="Day streak" />
      </StatTiles>,
    );
    expect((screen.getByText("12") as HTMLElement).style.color).toBe("rgb(1, 2, 3)");
    expect((screen.getByText("4") as HTMLElement).style.color).toBe("");
  });

  it("can be wrapped in a Tooltip -- it forwards the ref and the trigger props", () => {
    render(
      <FluentProvider theme={webLightTheme}>
        <StatTiles>
          <Tooltip content="Commits in the last 3 days" relationship="description">
            <StatTile count={7} label="velocity" />
          </Tooltip>
        </StatTiles>
      </FluentProvider>,
    );
    const tile = screen.getByText("velocity").closest("[data-stat-tile]") as HTMLElement;
    expect(tile.getAttribute("aria-describedby")).toBeTruthy();
  });
});
