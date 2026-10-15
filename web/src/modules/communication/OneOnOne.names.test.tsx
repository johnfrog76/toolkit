import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { OneOnOne } from "./OneOnOne";

// Axe's button-name (critical): the Meetings card's filter is a Fluent
// Dropdown whose only text is its value ("All"), on /communication and on
// /organize, which hosts the card when organize is on. It carries an
// aria-label, a contract held here. The data hooks are stand-ins.

jest.mock("./api.communication", () => ({
  useGetManagerQuery: () => ({
    data: [],
    isLoading: false,
    isFetching: false,
    isError: false,
    refetch: jest.fn(),
  }),
  useCreateManagerSessionMutation: () => [jest.fn(), { isLoading: false }],
}));
jest.mock("./CloseMeeting", () => ({ CloseMeetingButton: () => null }));

describe("the Meetings card's filter", () => {
  it("is named Sessions", () => {
    render(
      <MemoryRouter>
        <OneOnOne />
      </MemoryRouter>,
    );
    expect(screen.getByRole("combobox", { name: "Sessions" })).toBeTruthy();
  });
});
