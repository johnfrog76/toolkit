import { act, renderHook } from "@testing-library/react";
import { usePagination } from "./usePagination";

// Paging and filtering aren't mutually exclusive — you can page through a
// filtered set same as an unfiltered one. What IS enforced (in DeckCollection's
// toggle/clear, not here) is a coupling: changing the filter resets the page,
// because a page number that was valid against the old item list can point
// past the end of the new, smaller one. usePagination's job in that contract
// is narrower — CLAMP whatever page it's handed to the current item count —
// and that's what these pin, independent of where the items came from.

describe("usePagination", () => {
  const items = Array.from({ length: 25 }, (_, i) => i);

  it("clamps a page that's out of range for the current item count", () => {
    // Simulates the moment a filter shrinks the list: caller is still holding
    // page=2 (valid for 25 items at pageSize 10) but items has just dropped to 5.
    const { result } = renderHook(() =>
      usePagination(items.slice(0, 5), 10, {
        page: 2,
        onPageChange: () => {},
      }),
    );
    expect(result.current.page).toBe(0);
    expect(result.current.totalPages).toBe(1);
    expect(result.current.pageItems).toEqual([0, 1, 2, 3, 4]);
  });

  it("pages independently of the filtered set's size — not mutually exclusive", () => {
    const filtered = items.slice(0, 12); // e.g. a tag filter narrowing 25 -> 12
    let page = 0;
    const { result, rerender } = renderHook(
      ({ page: p }) =>
        usePagination(filtered, 5, { page: p, onPageChange: (next) => (page = next) }),
      { initialProps: { page } },
    );

    expect(result.current.totalPages).toBe(3);
    act(() => result.current.setPage(1));
    expect(page).toBe(1);

    rerender({ page });
    expect(result.current.pageItems).toEqual([5, 6, 7, 8, 9]);
  });

  it("in controlled mode, the caller's onPageChange is the only writer — no local page state leaks through", () => {
    const onPageChange = jest.fn();
    const { result } = renderHook(() => usePagination(items, 10, { page: 1, onPageChange }));

    act(() => result.current.setPage(2));

    expect(onPageChange).toHaveBeenCalledWith(2);
  });
});
