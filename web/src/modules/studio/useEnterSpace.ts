import { useState } from "react";
import { useNavigate } from "react-router";
import { useSwitchModeMutation } from "../../shell/api";

// The one switch into a Space from the Studio (D-S2): the foyer's row and a
// design note's Space chip both take it. It is the avatar menu's switch -- the
// same cache key, so the header says "switching" whichever door was taken --
// and it lands where a GitHub Space's Home lands: its first tab, which owns
// `/`. Already in that Space, it only navigates. No confirmation: the foyer
// never had one.
export function useEnterSpace(slug: string, here: boolean) {
  const navigate = useNavigate();
  const [switchMode, { isLoading: switching }] = useSwitchModeMutation({
    fixedCacheKey: "org-switch",
  });
  const [failed, setFailed] = useState(false);

  const enter = () => {
    setFailed(false);
    if (here) {
      navigate("/");
      return;
    }
    switchMode({ mode: slug })
      .unwrap()
      .then(() => navigate("/"))
      .catch(() => setFailed(true));
  };

  return { enter, switching, failed };
}
