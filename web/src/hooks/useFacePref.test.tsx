/**
 * A browser that refuses storage (a private window with site data
 * blocked, a policy, an iframe) THROWS on localStorage access, and the Face
 * store read it unguarded at MODULE SCOPE -- ToolKitLogo puts that module in
 * the shell, so the whole web UI was blank. Refused storage is the default
 * face for the session and nothing else.
 *
 * The module-scope read is the part a test has to reach, so each case makes
 * storage throw FIRST and only then requires the modules, in a fresh registry
 * (jest.isolateModules): a static import would have evaluated the store
 * against a working localStorage before the test body ran.
 */
import * as React from "react";
import * as jsxRuntime from "react/jsx-runtime";
import { act, render, renderHook, screen } from "@testing-library/react";
import type * as FacePrefModule from "./useFacePref";
import type * as LogoModule from "../shared/ToolKitLogo";
import { DEFAULT_FACE_ID, FACES } from "../shared/faces";

// jsdom has no matchMedia; the theme store (in the logo's import graph) asks it
// once for a browser that never chose.
(globalThis as unknown as { matchMedia: unknown }).matchMedia = (query: string) => ({
  matches: false,
  media: query,
  addEventListener: () => {},
  removeEventListener: () => {},
});

function loadFresh(): {
  useFacePref: typeof FacePrefModule.useFacePref;
  ToolKitLogo: typeof LogoModule.ToolKitLogo;
} {
  let out!: ReturnType<typeof loadFresh>;
  jest.isolateModules(() => {
    // A fresh registry would bring a second React, and a hook from one copy
    // cannot run under the other's renderer: hand it this file's.
    jest.doMock("react", () => React);
    jest.doMock("react/jsx-runtime", () => jsxRuntime);
    out = {
      useFacePref: jest.requireActual<typeof FacePrefModule>("./useFacePref").useFacePref,
      ToolKitLogo: jest.requireActual<typeof LogoModule>("../shared/ToolKitLogo").ToolKitLogo,
    };
  });
  return out;
}

afterEach(() => {
  jest.restoreAllMocks();
  window.localStorage.clear();
});

it("loads with the default face when localStorage.getItem throws at import", () => {
  const getItem = jest.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
    throw new DOMException("The operation is insecure.", "SecurityError");
  });

  const { useFacePref, ToolKitLogo } = loadFresh();
  // The module-scope read ran, against the throwing storage.
  expect(getItem).toHaveBeenCalled();

  const { result } = renderHook(() => useFacePref());
  expect(result.current.faceId).toBe(DEFAULT_FACE_ID);

  render(<ToolKitLogo />);
  expect(screen.getByRole("img", { name: "ToolKit" })).toBeTruthy();
});

it("holds a chosen face for the session when localStorage.setItem throws", () => {
  jest.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
    throw new DOMException("The quota has been exceeded.", "QuotaExceededError");
  });
  const other = FACES.find((f) => f.id !== DEFAULT_FACE_ID)!.id;

  const { useFacePref } = loadFresh();
  const { result } = renderHook(() => useFacePref());
  expect(result.current.faceId).toBe(DEFAULT_FACE_ID);

  expect(() => act(() => result.current.setFaceId(other))).not.toThrow();
  expect(result.current.faceId).toBe(other);
  // Nothing was kept: the choice is the session's, and a reload forgets it.
  expect(window.localStorage.getItem("toolkit-face")).toBeNull();
});
