import { configureStore } from "@reduxjs/toolkit";
import { api } from "./api";
import { filtersReducer, filtersListener } from "./filtersSlice";

export const store = configureStore({
  reducer: {
    [api.reducerPath]: api.reducer,
    filters: filtersReducer,
  },
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware().concat(api.middleware, filtersListener.middleware),
});

export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;
