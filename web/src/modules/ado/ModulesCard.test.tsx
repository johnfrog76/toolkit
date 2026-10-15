/**
 * The Modules card names every add-on whether or not it is on -- a machine
 * has to be able to say what it is not doing -- with three states, and the
 * Change link that opens Settings at the flag.
 */
jest.mock("../../shell/registry", () => ({
  modules: [
    { id: "ado", routes: [] },
    { id: "growth", feature: "growth", routes: [] },
    { id: "lounge", feature: "lounge", routes: [] },
    { id: "deck", feature: "deck", routes: [] },
  ],
}));
const openSettings = jest.fn();
jest.mock("../../shell/cards", () => ({ useOpenSettings: () => openSettings }));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ data: { features: { growth: true, lounge: false } }, isLoading: false }),
}));

import { render, screen, fireEvent } from "@testing-library/react";
import { ModulesCard, surfaceState } from "./ModulesCard";

describe("the Modules card", () => {
  it("names every add-on, on, off or not configured, and never the core", () => {
    render(<ModulesCard />);
    expect(screen.getByText("Modules")).toBeTruthy();
    const rows = ["Growth module", "Lounge module", "Deck module"].map((l) =>
      screen.getByText(l).closest("div")!,
    );
    expect(rows.map((r) => r.textContent)).toEqual([
      "✓Growth moduleonChange",
      "·Lounge moduleoffChange",
      "·Deck modulenot configuredChange",
    ]);
    expect(screen.queryByText("Ado module")).toBeNull();
  });

  it("Change opens Settings at the module's flag", () => {
    render(<ModulesCard />);
    fireEvent.click(screen.getByRole("button", { name: "Change Deck module in Settings" }));
    expect(openSettings).toHaveBeenCalledWith("features.deck");
  });

  it("off and not configured are different answers", () => {
    expect(surfaceState({ features: { x: false } } as never, "x")).toBe("off");
    expect(surfaceState({ features: {} } as never, "x")).toBe("not configured");
    expect(surfaceState(undefined, "x")).toBe("not configured");
    expect(surfaceState({ features: { x: true } } as never, "x")).toBe("on");
  });
});
