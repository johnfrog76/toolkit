import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { RitualPage } from "./RitualPage";

// The Team Agile tab's Standup | Triage | Milestones strip: each tab an address,
// the page under it the one that address names. The pages are stand-ins here --
// StandupPage.test.tsx, TriagePage.test.tsx and MilestonesPage.test.tsx are about them.
jest.mock("./StandupPage", () => ({ StandupPage: () => <p>the standup page</p> }));
jest.mock("./TriagePage", () => ({ TriagePage: () => <p>the triage page</p> }));
jest.mock("./MilestonesPage", () => ({ MilestonesPage: () => <p>the milestones page</p> }));

function at(path: string) {
  render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/solitaire-agile" element={<RitualPage ceremony="standup" />} />
        <Route path="/solitaire-agile/triage" element={<RitualPage ceremony="triage" />} />
        <Route path="/solitaire-agile/milestones" element={<RitualPage ceremony="milestones" />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe("the Standup | Triage | Milestones strip", () => {
  it("names the three pages, in order, and selects the one you are on", () => {
    at("/solitaire-agile");
    expect(screen.getAllByRole("tab")).toEqual(
      ["Standup", "Triage", "Milestones"].map((name) => screen.getByRole("tab", { name })),
    );
    expect(screen.getByRole("tab", { name: "Triage" }).getAttribute("aria-selected")).toBe("false");
    expect(screen.getByRole("tab", { name: "Standup" }).getAttribute("aria-selected")).toBe("true");
    expect(screen.getByText("the standup page")).toBeTruthy();
  });

  it("each tab is an address: Triage goes to /solitaire-agile/triage, and back", () => {
    at("/solitaire-agile");
    fireEvent.click(screen.getByRole("tab", { name: "Triage" }));
    expect(screen.getByText("the triage page")).toBeTruthy();
    fireEvent.click(screen.getByRole("tab", { name: "Standup" }));
    expect(screen.getByText("the standup page")).toBeTruthy();
  });

  it("Milestones is the third address, after Standup and Triage", () => {
    at("/solitaire-agile/milestones");
    expect(screen.getByRole("tab", { name: "Milestones" }).getAttribute("aria-selected")).toBe(
      "true",
    );
    expect(screen.getByText("the milestones page")).toBeTruthy();
    fireEvent.click(screen.getByRole("tab", { name: "Triage" }));
    expect(screen.getByText("the triage page")).toBeTruthy();
    fireEvent.click(screen.getByRole("tab", { name: "Milestones" }));
    expect(screen.getByText("the milestones page")).toBeTruthy();
  });
});
