import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { RitualPage } from "./RitualPage";

// The Team Agile tab's Standup | Triage | Releases | Org strip: each tab an
// address, the page under it the one that address names. The pages are
// stand-ins here -- StandupPage.test.tsx, TriagePage.test.tsx,
// MilestonesPage.test.tsx and OrgPage.test.tsx are about them.
jest.mock("./StandupPage", () => ({ StandupPage: () => <p>the standup page</p> }));
jest.mock("./TriagePage", () => ({ TriagePage: () => <p>the triage page</p> }));
jest.mock("./MilestonesPage", () => ({ MilestonesPage: () => <p>the milestones page</p> }));
jest.mock("./OrgPage", () => ({ OrgPage: () => <p>the org page</p> }));

function at(path: string) {
  render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/solitaire-agile" element={<RitualPage ceremony="standup" />} />
        <Route path="/solitaire-agile/triage" element={<RitualPage ceremony="triage" />} />
        <Route path="/solitaire-agile/releases" element={<RitualPage ceremony="releases" />} />
        <Route path="/solitaire-agile/org" element={<RitualPage ceremony="org" />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe("the Standup | Triage | Releases | Org strip", () => {
  it("names the four pages, in order, and selects the one you are on", () => {
    at("/solitaire-agile");
    expect(screen.getAllByRole("tab")).toEqual(
      ["Standup", "Triage", "Releases", "Org"].map((name) => screen.getByRole("tab", { name })),
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

  it("Releases is the third address, after Standup and Triage", () => {
    at("/solitaire-agile/releases");
    expect(screen.getByRole("tab", { name: "Releases" }).getAttribute("aria-selected")).toBe(
      "true",
    );
    expect(screen.getByText("the milestones page")).toBeTruthy();
    fireEvent.click(screen.getByRole("tab", { name: "Triage" }));
    expect(screen.getByText("the triage page")).toBeTruthy();
    fireEvent.click(screen.getByRole("tab", { name: "Releases" }));
    expect(screen.getByText("the milestones page")).toBeTruthy();
  });

  it("Org is the fourth address, its page a chunk fetched when the tab is opened", async () => {
    at("/solitaire-agile/org");
    expect(screen.getByRole("tab", { name: "Org" }).getAttribute("aria-selected")).toBe("true");
    expect(await screen.findByText("the org page")).toBeTruthy();
    fireEvent.click(screen.getByRole("tab", { name: "Releases" }));
    expect(screen.getByText("the milestones page")).toBeTruthy();
    fireEvent.click(screen.getByRole("tab", { name: "Org" }));
    expect(await screen.findByText("the org page")).toBeTruthy();
  });
});
