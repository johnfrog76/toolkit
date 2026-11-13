import { act, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { ReferenceCard } from "./ReferenceCard";
import type { ReferenceDoc } from "./api.organize";

// The Reference panel: one item per document, its title the row and its Valid
// dates and Source the meta; Open goes to the reading room; the search asks the
// agent (after typing rests) and a hit says the line that matched. Read only --
// the panel has no create, no archive, nothing that writes.

const navigate = jest.fn();
jest.mock("react-router", () => ({
  ...jest.requireActual("react-router"),
  useNavigate: () => navigate,
}));

const asked: string[] = [];
let items: ReferenceDoc[] = [];

jest.mock("./api.organize", () => ({
  useGetReferenceQuery: (q: string) => {
    asked.push(q);
    return {
      data: { count: items.length, items, query: q },
      isLoading: false,
      isError: false,
      isFetching: false,
      refetch: jest.fn(),
    };
  },
}));

function doc(name: string, extra: Partial<ReferenceDoc> = {}): ReferenceDoc {
  return {
    name,
    title: "2027 Observed Days Off",
    source: "Office announcement",
    valid: "2027-01-01 to 2027-12-31",
    added: "2026-11-11",
    original: "",
    line: "",
    excerpt: "Date Holiday 2027-01-01 New Year's Day",
    ...extra,
  };
}

function draw() {
  return render(
    <MemoryRouter>
      <ReferenceCard />
    </MemoryRouter>,
  );
}

beforeEach(() => {
  jest.useFakeTimers();
  navigate.mockClear();
  asked.length = 0;
  items = [doc("days-off-2027.md")];
});
afterEach(() => jest.useRealTimers());

describe("the Reference panel", () => {
  it("draws a document's title, its Valid dates and its Source", () => {
    draw();
    expect(screen.getByText("2027 Observed Days Off")).not.toBeNull();
    expect(screen.getByText("Valid: 2027-01-01 to 2027-12-31")).not.toBeNull();
    expect(screen.getByText("Office announcement")).not.toBeNull();
  });

  it("shows the start of the document's content, for the card to clamp to two lines", () => {
    draw();
    expect(screen.getByText("Date Holiday 2027-01-01 New Year's Day")).not.toBeNull();
  });

  it("says so when a document has no valid dates", () => {
    items = [doc("bare.md", { valid: "", source: "" })];
    draw();
    expect(screen.getByText("No valid dates")).not.toBeNull();
  });

  it("opens a document in its reading room, by file name", () => {
    draw();
    fireEvent.click(screen.getByRole("button", { name: /open/i }));
    expect(navigate).toHaveBeenCalledWith("/organize/reference/days-off-2027.md");
  });

  it("asks the agent for a search only once typing has rested, and shows the matching line", () => {
    draw();
    expect(asked[asked.length - 1]).toBe("");
    items = [doc("days-off-2027.md", { line: "| 2027-05-31 | Memorial Day |" })];
    fireEvent.change(screen.getByRole("searchbox"), { target: { value: "memorial" } });
    expect(asked[asked.length - 1]).toBe("");
    act(() => {
      jest.advanceTimersByTime(300);
    });
    expect(asked[asked.length - 1]).toBe("memorial");
    expect(screen.getByText("| 2027-05-31 | Memorial Day |")).not.toBeNull();
  });

  it("offers nothing that writes: no create, no archive", () => {
    draw();
    expect(screen.queryByRole("button", { name: /new|create|archive/i })).toBeNull();
  });
});
