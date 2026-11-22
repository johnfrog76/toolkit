/**
 * What a module asks for ahead of need: once the app has loaded, once per
 * module, never for a module that is off, never before /env has answered.
 */
import { renderHook } from "@testing-library/react";
import { Provider } from "react-redux";
import type { ReactNode } from "react";
import { store } from "./store";
import { usePrefetchModules } from "./prefetchModules";
import type { ToolkitModule } from "./registry";

function mod(id: ToolkitModule["id"], prefetch?: ToolkitModule["prefetch"]): ToolkitModule {
  return { id, routes: [], prefetch };
}

const wrapper = ({ children }: { children: ReactNode }) => (
  <Provider store={store}>{children}</Provider>
);

describe("usePrefetchModules", () => {
  it("dispatches a module's prefetch once after startup, however often it re-renders", () => {
    const ado = jest.fn();
    const active = [mod("ado", ado), mod("growth")];
    const { rerender } = renderHook(({ ready }) => usePrefetchModules(active, ready), {
      wrapper,
      initialProps: { ready: true },
    });
    rerender({ ready: true });
    rerender({ ready: true });
    expect(ado).toHaveBeenCalledTimes(1);
    expect(ado).toHaveBeenCalledWith(store.dispatch);
  });

  it("waits for the app to have loaded", () => {
    const ado = jest.fn();
    const active = [mod("ado", ado)];
    const { rerender } = renderHook(({ ready }) => usePrefetchModules(active, ready), {
      wrapper,
      initialProps: { ready: false },
    });
    expect(ado).not.toHaveBeenCalled();
    rerender({ ready: true });
    expect(ado).toHaveBeenCalledTimes(1);
  });

  it("asks nothing of a module that is not active, and starts one that becomes active later", () => {
    const ado = jest.fn();
    const growth = jest.fn();
    const { rerender } = renderHook(({ active }) => usePrefetchModules(active, true), {
      wrapper,
      initialProps: { active: [mod("ado", ado)] },
    });
    expect(growth).not.toHaveBeenCalled();
    rerender({ active: [mod("ado", ado), mod("growth", growth)] });
    expect(ado).toHaveBeenCalledTimes(1);
    expect(growth).toHaveBeenCalledTimes(1);
  });
});
