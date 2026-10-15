/**
 * A module part that is fetched when it is first drawn, not when the app
 * loads.
 *
 * "Off means absent" ends in "no bytes": a module whose flag is off must ship
 * nothing to the browser. The registry has to read every module's DESCRIPTOR
 * -- id, flag, route paths, nav entry -- to decide what mounts, so a
 * descriptor is small and static and imports no component. Every page, card
 * and header item a module contributes comes through here instead: a dynamic
 * `import()` that Vite splits into its own chunk, and a Suspense boundary
 * around it, so the shell never has to grow one. The deck module drew this
 * shape first (its engine and voices were the weight that made it real).
 *
 * `pick` names the export, because the house exports its components by name
 * and React.lazy wants a default. The boundary is per part rather than around
 * the router outlet or the home grid: a card that is still loading shows its
 * own spinner in its own place, and the cards around it draw at once.
 */
import { Suspense, lazy } from "react";
import type { ComponentType, ReactElement } from "react";
import { Spinner } from "@fluentui/react-components";

/** The house's "still loading" for a module part: small, quiet, in place, and
 *  SAYING so -- every loading state in the product reads "Loading ...", and the
 *  smoke test waits for that word to clear before it reads a page. */
export const lazyFallback: ReactElement = <Spinner size="tiny" label="Loading..." />;

export function lazyPart<M, P extends object>(
  load: () => Promise<M>,
  pick: (m: M) => ComponentType<P>,
  fallback: ReactElement | null = lazyFallback,
): ComponentType<P> {
  // React.lazy types its result over PropsWithRef; the part's props are P.
  const Inner = lazy(() =>
    load().then((m) => ({ default: pick(m) })),
  ) as unknown as ComponentType<P>;
  function LazyPart(props: P) {
    return (
      <Suspense fallback={fallback}>
        <Inner {...props} />
      </Suspense>
    );
  }
  return LazyPart;
}
