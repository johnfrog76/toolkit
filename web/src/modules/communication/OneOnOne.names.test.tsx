import { render, screen, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { OneOnOne } from "./OneOnOne";

// Axe's button-name (critical): a filter a screen reader cannot name is an
// unnamed control. The Meetings panel splits its list with a row of chips, on
// /communication and on /organize, which hosts the panel when organize is on;
// the row is a named group, a contract held here. The data hooks are stand-ins.

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
jest.mock("./CloseMeeting", () => ({ CloseMeetingDialog: () => null }));

describe("the Meetings panel's filter", () => {
  it("is a group named Filter meetings, one chip a filter", () => {
    render(
      <MemoryRouter>
        <OneOnOne />
      </MemoryRouter>,
    );
    const group = screen.getByRole("group", { name: "Filter meetings" });
    expect(within(group).getAllByRole("radio")).toHaveLength(4);
  });
});
