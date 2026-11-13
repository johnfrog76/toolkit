import { useState } from "react";
import { useNavigate } from "react-router";
import { useSwitchModeMutation } from "../../shell/api";

// The one switch into a Space from the Studio (D-S2): the foyer's row and a
// design note's Space chip both take it. It is the avatar menu's switch -- the
// same cache key, so the header says "switching" whichever door was taken --
// and it lands where a GitHub Space's Home lands: its first tab, which owns
// `/`. Already in that Space, it only navigates. No confirmation: the foyer
// never had one.
// One hook for a whole panel: its items are data, so the panel holds the
// switch and each item names the Space it enters.
export function useEnterSpace(activeSpace: string) {
  const navigate = useNavigate();
  const [switchMode, { isLoading: switching }] = useSwitchModeMutation({
    fixedCacheKey: "org-switch",
  });
  /** The Space the last switch could not reach, or null. */
  const [failed, setFailed] = useState<string | null>(null);

  const enter = (slug: string) => {
    setFailed(null);
    if (slug === activeSpace) {
      navigate("/");
      return;
    }
    switchMode({ mode: slug })
      .unwrap()
      .then(() => navigate("/"))
      .catch(() => setFailed(slug));
  };

  return { enter, switching, failed };
}
