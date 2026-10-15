import { act, renderHook } from "@testing-library/react";
import type { ReactNode } from "react";
import { Provider } from "react-redux";
import { store as appStore } from "./store";
import { api } from "./api";
import { filtersActions, initialFilters, SPACE_SCOPED_PERSISTED_KEYS } from "./filtersSlice";
import { useDesignFilters, useDocsFilters } from "../modules/ado/docFilters";
import { useSharedPersistedValue } from "../shared/usePersistedState";

// A Space switch opens with the drawer clear. The reset is the slice's own
// (extraReducers on switchMode.matchFulfilled); the per-browser Docs and Design
// filters are cleared by a listener on the same action.

const SPACES_FILTER_KEY = "studio.spaces.filter"; // FoyerCard's -- not about one Space

/** What RTK Query dispatches when the switch-mode mutation succeeds. */
function switchFulfilled(mode: string) {
  return {
    type: "api/executeMutation/fulfilled",
    payload: {},
    meta: {
      requestId: "r1",
      requestStatus: "fulfilled",
      arg: { type: "mutation", endpointName: "switchMode", originalArgs: { mode } },
    },
  };
}

const setAll = () => {
  appStore.dispatch(filtersActions.setFilterValue("bug"));
  appStore.dispatch(filtersActions.setActiveRepo("web"));
  appStore.dispatch(filtersActions.setStateFilter("Active"));
  appStore.dispatch(filtersActions.setTypeFilter("Bug"));
  appStore.dispatch(filtersActions.setLinkFilter("Linked"));
  appStore.dispatch(filtersActions.setActiveSkillTag("react"));
};

describe("filters slice", () => {
  beforeEach(() => {
    window.localStorage.clear();
    appStore.dispatch(switchFulfilled("reset"));
  });

  it("matches the switch action", () => {
    expect(api.endpoints.switchMode.matchFulfilled(switchFulfilled("x"))).toBe(true);
  });

  it("opens on the defaults", () => {
    expect(appStore.getState().filters).toEqual(initialFilters);
    expect(initialFilters).toEqual({
      filterValue: "",
      activeRepo: null,
      stateFilter: "All",
      typeFilter: "All",
      linkFilter: "All",
      activeSkillTag: null,
    });
  });

  it("holds each of the six values", () => {
    setAll();
    expect(appStore.getState().filters).toEqual({
      filterValue: "bug",
      activeRepo: "web",
      stateFilter: "Active",
      typeFilter: "Bug",
      linkFilter: "Linked",
      activeSkillTag: "react",
    });
  });

  it("a successful switch puts every value back to its default", () => {
    setAll();
    appStore.dispatch(switchFulfilled("space-b"));
    expect(appStore.getState().filters).toEqual(initialFilters);
  });

  it("an unrelated action leaves the values alone", () => {
    setAll();
    appStore.dispatch({ type: "something/else" });
    appStore.dispatch({
      ...switchFulfilled("x"),
      type: "api/executeMutation/rejected",
      meta: { ...switchFulfilled("x").meta, requestStatus: "rejected" },
    });
    expect(appStore.getState().filters.filterValue).toBe("bug");
    expect(appStore.getState().filters.activeRepo).toBe("web");
  });

  it("a value set in Space A is not seen in Space B", () => {
    const wrapper = ({ children }: { children: ReactNode }) => (
      <Provider store={appStore}>{children}</Provider>
    );
    const { result } = renderHook(() => ({ s: appStore.getState().filters }), { wrapper });
    act(() => void appStore.dispatch(filtersActions.setActiveRepo("repo-of-A")));
    expect(appStore.getState().filters.activeRepo).toBe("repo-of-A");
    act(() => void appStore.dispatch(switchFulfilled("space-b")));
    expect(appStore.getState().filters.activeRepo).toBeNull();
    expect(result.current).toBeDefined();
  });
});

describe("persisted filters on a switch", () => {
  beforeEach(() => window.localStorage.clear());

  it("clears Docs and Design, and leaves the Spaces card filter", () => {
    const wrapper = ({ children }: { children: ReactNode }) => (
      <Provider store={appStore}>{children}</Provider>
    );
    const { result } = renderHook(
      () => ({
        design: useDesignFilters(),
        docs: useDocsFilters(),
        spaces: useSharedPersistedValue(SPACES_FILTER_KEY, "all"),
      }),
      { wrapper },
    );
    act(() => {
      result.current.design.setText("note");
      result.current.design.setKind("spec");
      result.current.docs.setText("readme");
      result.current.docs.setFolder("docs");
      result.current.spaces.setValue("products");
    });
    expect(result.current.design.text).toBe("note");
    expect(result.current.docs.folder).toBe("docs");

    act(() => void appStore.dispatch(switchFulfilled("space-b")));

    expect(result.current.design.text).toBe("");
    expect(result.current.design.kind).toBe("all");
    expect(result.current.docs.text).toBe("");
    expect(result.current.docs.folder).toBe("all");
    for (const key of SPACE_SCOPED_PERSISTED_KEYS)
      expect(window.localStorage.getItem(key)).toBeNull();
    expect(result.current.spaces.value).toBe("products");
    expect(window.localStorage.getItem(SPACES_FILTER_KEY)).toBe("products");
  });
});
