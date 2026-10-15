/**
 * In a browser that refuses storage (a private window with site data
 * blocked, a policy, an iframe) a theme choice did nothing -- setThemeId wrote,
 * caught the throw, and notify() re-read storage, found nothing and answered
 * the default. The rule the other persisted choices keep: refused storage holds
 * the choice for the session and loses it on reload.
 *
 * The store reads at module scope, so it is required AFTER storage is made to
 * throw, in a fresh registry (jest.isolateModules) -- the shape a private
 * window loads it in.
 */
import * as React from "react";
import { act, renderHook } from "@testing-library/react";
import type * as ThemeModule from "./useCurrentTheme";
import { FIRST_DARK, FIRST_LIGHT } from "../shell/themeList";

// jsdom has no matchMedia; the store asks it for a browser that never chose.
// `matches: false` -- a light system -- so the default is FIRST_LIGHT.
(globalThis as unknown as { matchMedia: unknown }).matchMedia = (query: string) => ({
  matches: false,
  media: query,
  addEventListener: () => {},
  removeEventListener: () => {},
});

function loadFresh(): typeof ThemeModule.useCurrentTheme {
  let hook!: typeof ThemeModule.useCurrentTheme;
  jest.isolateModules(() => {
    // One React for the hook and the renderer.
    jest.doMock("react", () => React);
    hook = jest.requireActual<typeof ThemeModule>("./useCurrentTheme").useCurrentTheme;
  });
  return hook;
}

afterEach(() => {
  jest.restoreAllMocks();
  window.localStorage.clear();
});

describe("useCurrentTheme with storage that throws", () => {
  it("holds a chosen theme for the session when every storage call throws", () => {
    const refuse = () => {
      throw new DOMException("The operation is insecure.", "SecurityError");
    };
    jest.spyOn(Storage.prototype, "getItem").mockImplementation(refuse);
    jest.spyOn(Storage.prototype, "setItem").mockImplementation(refuse);

    const useCurrentTheme = loadFresh();
    const { result } = renderHook(() => useCurrentTheme());
    expect(result.current.active.id).toBe(FIRST_LIGHT);

    expect(() => act(() => result.current.setThemeId(FIRST_DARK))).not.toThrow();
    expect(result.current.active.id).toBe(FIRST_DARK);
    expect(result.current.theme).toBe("dark");
  });

  it("forgets the session's choice on reload: a fresh load answers the default", () => {
    jest.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new DOMException("The quota has been exceeded.", "QuotaExceededError");
    });

    const firstHook = loadFresh();
    const first = renderHook(() => firstHook());
    act(() => first.result.current.setThemeId(FIRST_DARK));
    expect(first.result.current.active.id).toBe(FIRST_DARK);
    first.unmount();

    const againHook = loadFresh();
    const again = renderHook(() => againHook());
    expect(again.result.current.active.id).toBe(FIRST_LIGHT);
  });
});

describe("useCurrentTheme with storage that keeps", () => {
  it("persists a choice, so a fresh load answers it", () => {
    const firstHook = loadFresh();
    const first = renderHook(() => firstHook());
    act(() => first.result.current.setThemeId(FIRST_DARK));
    expect(window.localStorage.getItem("toolkit-theme")).toBe(FIRST_DARK);
    first.unmount();

    const againHook = loadFresh();
    const again = renderHook(() => againHook());
    expect(again.result.current.active.id).toBe(FIRST_DARK);
  });
});
