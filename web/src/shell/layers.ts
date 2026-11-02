// The app's stacking layers, named once: a z-index typed at its use is a number nobody
// can compare with the next one (AGENTS.md, "One place for magic strings").

/** Fluent UI's own portal layer: every dialog, popover and menu is drawn in a portal
 *  whose FluentProvider sits at this z-index. Fluent sets it, not us -- it is named
 *  here so the layers above it can say so. */
export const FLUENT_PORTAL_LAYER = 1000000;

/** The confetti's layer (shared/Confetti.tsx): just above Fluent's portals, so a burst
 *  falls OVER an open dialog and its backdrop rather than dimmed under them. It never
 *  takes a click -- the canvas has pointer-events off. */
export const CONFETTI_LAYER = FLUENT_PORTAL_LAYER + 1;
