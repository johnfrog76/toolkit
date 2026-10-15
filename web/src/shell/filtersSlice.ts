import { createListenerMiddleware, createSlice } from "@reduxjs/toolkit";
import type { PayloadAction } from "@reduxjs/toolkit";
import { api } from "./api";
import { clearPersisted } from "../shared/usePersistedState";
import {
  DESIGN_TEXT_KEY,
  DESIGN_KIND_KEY,
  DOCS_TEXT_KEY,
  DOCS_FOLDER_KEY,
} from "../modules/ado/docFilters";

// The filter drawer's six values. They were useState calls in App.tsx, so
// nothing cleared them when the Space changed and a repo chosen in one Space
// silently narrowed the next. They live in the store now, and the slice resets
// itself when the Space switch succeeds -- no component has to remember to.
export interface FiltersState {
  filterValue: string;
  activeRepo: string | null;
  stateFilter: string;
  typeFilter: string;
  linkFilter: string;
  activeSkillTag: string | null;
}

export const initialFilters: FiltersState = {
  filterValue: "",
  activeRepo: null,
  stateFilter: "All",
  typeFilter: "All",
  linkFilter: "All",
  activeSkillTag: null,
};

const filtersSlice = createSlice({
  name: "filters",
  initialState: initialFilters,
  reducers: {
    setFilterValue: (s, a: PayloadAction<string>) => void (s.filterValue = a.payload),
    setActiveRepo: (s, a: PayloadAction<string | null>) => void (s.activeRepo = a.payload),
    setStateFilter: (s, a: PayloadAction<string>) => void (s.stateFilter = a.payload),
    setTypeFilter: (s, a: PayloadAction<string>) => void (s.typeFilter = a.payload),
    setLinkFilter: (s, a: PayloadAction<string>) => void (s.linkFilter = a.payload),
    setActiveSkillTag: (s, a: PayloadAction<string | null>) => void (s.activeSkillTag = a.payload),
  },
  extraReducers: (builder) => {
    builder.addMatcher(api.endpoints.switchMode.matchFulfilled, () => initialFilters);
  },
});

export const filtersActions = filtersSlice.actions;
export const filtersReducer = filtersSlice.reducer;

/** The Docs and Design filters are per browser (localStorage), so a reducer
 *  cannot reach them: this listener clears them on the same successful switch.
 *  The Spaces card's and Reminders' filters are not about one Space and stay. */
export const SPACE_SCOPED_PERSISTED_KEYS = [
  DESIGN_TEXT_KEY,
  DESIGN_KIND_KEY,
  DOCS_TEXT_KEY,
  DOCS_FOLDER_KEY,
];

export const filtersListener = createListenerMiddleware();
filtersListener.startListening({
  matcher: api.endpoints.switchMode.matchFulfilled,
  effect: () => clearPersisted(SPACE_SCOPED_PERSISTED_KEYS),
});
