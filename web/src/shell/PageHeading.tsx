import { useEffect, useState } from "react";
import { makeStyles } from "@fluentui/react-components";

const useStyles = makeStyles({
  // Read by a screen reader, drawn nowhere: the nav already says where you are.
  hidden: {
    position: "absolute",
    width: "1px",
    height: "1px",
    margin: "-1px",
    padding: 0,
    overflow: "hidden",
    clipPath: "inset(50%)",
    whiteSpace: "nowrap",
    border: 0,
  },
});

/**
 * The page's one level-one heading when the page draws none of its own.
 *
 * Most pages name themselves with a visible title that is already an h1 (a card
 * or a document page); the tab pages and a page still loading or empty do not,
 * and a page with no h1 is a gap in heading navigation. The shell knows the
 * page's name (its nav entry), so it supplies a visually hidden h1 -- and only
 * while `main` holds no other h1, so a page never ends up with two and nothing
 * new is drawn.
 */
export function PageHeading({ name, mainId }: { name: string; mainId: string }) {
  const styles = useStyles();
  const [needed, setNeeded] = useState(false);

  useEffect(() => {
    const main = document.getElementById(mainId);
    if (!main) return undefined;
    const check = () =>
      // Our own h1 is marked, so it does not count as the page's.
      setNeeded(main.querySelector("h1:not([data-shell-heading])") === null);
    check();
    const observer = new MutationObserver(check);
    observer.observe(main, { childList: true, subtree: true });
    return () => observer.disconnect();
  }, [mainId]);

  return needed ? (
    <h1 data-shell-heading="" className={styles.hidden}>
      {name}
    </h1>
  ) : null;
}
