import { useEffect, useRef } from "react";
import { useDispatch } from "react-redux";
import type { ToolkitModule } from "./registry";
import type { AppDispatch } from "./store";

/**
 * Starts each active module's `prefetch` once, after the app has loaded
 * (`ready`: /env has answered). A module that is off is not in `active`, so
 * it asks for nothing; one that switches on later is started then, and none
 * is started twice. Not awaited -- startup never waits on it.
 */
export function usePrefetchModules(active: ToolkitModule[], ready: boolean): void {
  const dispatch = useDispatch<AppDispatch>();
  const started = useRef(new Set<string>());
  useEffect(() => {
    if (!ready) return;
    for (const m of active) {
      if (!m.prefetch || started.current.has(m.id)) continue;
      started.current.add(m.id);
      m.prefetch(dispatch);
    }
  }, [active, ready, dispatch]);
}
