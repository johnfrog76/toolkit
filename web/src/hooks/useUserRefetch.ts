import { useState } from "react";

/**
 * A refresh the person ASKED for, told apart from the query's own background
 * fetches: the Refresh button spins for the first and not the second.
 *
 * `asked` goes up on the click and comes down when `isFetching` next turns
 * false. The turn is noticed while rendering, against the value the last
 * render saw -- React's "adjusting state when a prop changes" -- rather than in
 * an effect, which would paint one frame of a spinner for a fetch that had
 * already finished and render twice to take it away.
 */
export function useUserRefetch(isFetching: boolean, refetch: () => unknown): [boolean, () => void] {
  const [asked, setAsked] = useState(false);
  const [seen, setSeen] = useState(isFetching);
  if (seen !== isFetching) {
    setSeen(isFetching);
    if (!isFetching) setAsked(false);
  }
  const ask = () => {
    setAsked(true);
    refetch();
  };
  return [asked, ask];
}
