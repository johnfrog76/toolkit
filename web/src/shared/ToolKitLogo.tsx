import { tokens } from "@fluentui/react-theme";
import { useWornTheme } from "../hooks/useWornTheme";
import { useFacePref } from "../hooks/useFacePref";
import { Wordmark } from "./Wordmark";

// The app's logo: the wordmark (Wordmark.tsx, the same mark the landing page
// draws) in the worn theme's blob colour, wearing the face the person chose.
// The WORN theme, not merely the chosen one: a granted skin owns the logo's
// blob too (D-L13, "it owns color of kit logo ... everything").

/** The mark's width in the header; its height follows. */
const HEADER_SIZE = 96;

export function ToolKitLogo({}) {
  const { theme, active } = useWornTheme();
  const { faceId } = useFacePref();
  return (
    <Wordmark
      size={HEADER_SIZE}
      ink={tokens.colorNeutralForeground1}
      blob={active.logo}
      face={faceId}
      theme={theme}
      className="tk-logo"
    />
  );
}
