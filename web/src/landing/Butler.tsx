import { Nimbus } from "../modules/deck/decks/the-toolkit";

// Nimbus, the Azure Butler, from the commercial's second window, standing
// beside the call to action: the family's mascot slot. Drawn by the deck's
// own function; the chrome gradient and the blur his drawing names are
// declared here, and his keyframes live in landing.css.

export const BUTLER_NAME = "Nimbus, the Azure Butler";

export function Butler() {
  return (
    <svg className="lp-butler" viewBox="-72 -112 144 224" role="img" aria-label={BUTLER_NAME}>
      <defs>
        <linearGradient id="tc-chrome" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stopColor="#5c7280" />
          <stop offset="45%" stopColor="#b9ccd6" />
          <stop offset="60%" stopColor="#8ba2ae" />
          <stop offset="100%" stopColor="#3f525c" />
        </linearGradient>
        <filter id="tc-blur" x="-60%" y="-60%" width="220%" height="220%">
          <feGaussianBlur stdDeviation="18" />
        </filter>
      </defs>
      <Nimbus x={0} y={0} eye={0.45} acting gloves="folded" />
    </svg>
  );
}
