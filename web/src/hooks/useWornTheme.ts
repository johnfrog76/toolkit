// The theme the product is WEARING -- the one hook every shell surface reads
// (App, the logo, the avatar menu), so a granted skin can own the palette
// completely (D-L13, the owner: "it owns its theme --
// it owns color of kit logo, components, everything locked").
//
// No grant: the person's chosen theme, exactly as useCurrentTheme answers.
// Grant worn: the skin's own SKIN_THEMES record, full stop -- and `worn`
// says so, which is how the ThemePicker knows to LOCK (you cannot switch
// themes out from under a skin; the room is where it comes off). The chosen
// theme keeps living underneath, untouched, and returns with removal.
//
// Imports stay vite-node-safe like useCurrentTheme's (plain data + guarded
// storage), so a deck bake that drags the shell in still runs.
import { useCurrentTheme } from "./useCurrentTheme";
import { useSkinGrant } from "../shared/skinGrant";
import type { SkinGrant } from "../shared/skinGrant";
import { SKIN_THEMES } from "../shell/themeList";
import type { ToolkitTheme } from "../shell/themeList";

export function useWornTheme(): {
  /** The mode actually on screen -- the skin's while worn. */
  theme: "dark" | "light";
  /** The theme record actually on screen -- the skin's while worn. */
  active: ToolkitTheme;
  /** The grant being worn, or null. Truth for the picker's lock. */
  worn: SkinGrant | null;
  /** The person's UNDERLYING choice -- what returns when the skin comes off. */
  chosen: ToolkitTheme;
  setThemeId: (id: string) => void;
} {
  const current = useCurrentTheme();
  const worn = useSkinGrant();
  const active = worn ? SKIN_THEMES[worn.skinId] : current.active;
  return {
    theme: active.mode,
    active,
    worn,
    chosen: current.active,
    setThemeId: current.setThemeId,
  };
}
