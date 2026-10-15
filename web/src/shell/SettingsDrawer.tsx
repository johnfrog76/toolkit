import { useEffect, useState, type ReactNode } from "react";
import {
  Button,
  DrawerBody,
  DrawerHeader,
  DrawerHeaderTitle,
  OverlayDrawer,
  makeStyles,
  tokens,
  useRestoreFocusSource,
} from "@fluentui/react-components";
import { DismissRegular } from "@fluentui/react-icons";
import type { ToolkitTheme } from "./themeList";
import { SettingsFooterContext } from "./settings";
import { HowDoI } from "./HowDoI";

// SettingsDrawer -- the Toolkit's one settings surface, opened by the avatar in
// the nav bar.
//
// The model is the wasteland's drawer (src/SettingsDrawer.tsx),
// taken as written wherever the reasoning carries: one OverlayDrawer on the
// right at every width, a scrim click or Escape closes it, body scroll is
// locked while it is open, and the surface is the PAGE's background rather than
// Fluent's lighter default panel.
//
// Deliberately NOT a settings framework. It is a frame: a title, a close
// button and a scrolling body. Each section that moves in keeps owning its own
// storage -- the face preference its localStorage, configuration its PUT
// through the CLI -- and this is only where they surface.

// The wasteland's `small` (320px) holds a switch and a sentence. This drawer is
// going to hold a label, a source badge and a control on one row, so it is
// wider -- but never wider than the viewport, which is what makes the same
// component read as a drawer on a tablet and as a blade on a desktop.
const DRAWER_WIDTH = "min(460px, 100vw)";

const useStyles = makeStyles({
  surface: {
    width: DRAWER_WIDTH,
    borderLeft: `1px solid ${tokens.colorNeutralStroke2}`,
  },
  body: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalXXL,
    paddingBottom: tokens.spacingVerticalXXL,
  },
  // The foot of the drawer: pinned, outside the scrolling body. It is an
  // OUTLET -- a section that batches edits portals its Save / Discard and its
  // feedback in here (shell/settings.ts) -- and it takes no room at all while
  // nothing is in it, so a drawer of instant settings has no empty bar.
  footer: {
    display: "flex",
    flexDirection: "column",
    gap: tokens.spacingVerticalS,
    padding: `${tokens.spacingVerticalM} ${tokens.spacingHorizontalXXL}`,
    borderTop: `1px solid ${tokens.colorNeutralStroke2}`,
    ":empty": {
      display: "none",
    },
  },
});

interface SettingsDrawerProps {
  open: boolean;
  onClose: () => void;
  theme: ToolkitTheme;
  /** Where to arrive. Absent: the top. */
  anchor?: string;
  /** Changes identity on every request, so the same place can be asked for twice. */
  anchorRequest?: object;
  children?: ReactNode;
}

// Marks where the drawer arrived, for a moment: a wash of the accent that
// fades. Global, because the element belongs to a module's section.
const ARRIVED_CLASS = "settings-arrived";
const ARRIVED_CSS = `
[data-settings-anchor] { scroll-margin-top: 12px; border-radius: 6px; }
.${ARRIVED_CLASS} { animation: settings-arrived 1.6s ease-out; }
@keyframes settings-arrived {
  0%, 35% { box-shadow: 0 0 0 2px var(--colorBrandStroke1); background-color: var(--colorBrandBackground2); }
  100% { box-shadow: 0 0 0 2px transparent; background-color: transparent; }
}
@media (prefers-reduced-motion: reduce) { .${ARRIVED_CLASS} { animation-duration: 0.01s; } }`;

export function SettingsDrawer({
  open,
  onClose,
  theme,
  anchor,
  anchorRequest,
  children,
}: SettingsDrawerProps) {
  const styles = useStyles();
  // The other half of App.tsx's useRestoreFocusTarget: on close, focus goes
  // back to the avatar that opened this.
  const restoreFocusSource = useRestoreFocusSource();
  // State, not a ref: sections render their portal only once the node exists,
  // and a ref would not re-render them when it does.
  const [footerNode, setFooterNode] = useState<HTMLDivElement | null>(null);

  // Lock body scroll while the drawer is open. A Drawer is `position: fixed`,
  // sized against the viewport; the body's own scrollbar gutter narrows the
  // content box behind it and leaves a scrollbar-width sliver with nothing
  // painted in it at the drawer's edge. Removing the scrollbar removes the gap.
  // Restores whatever value was there rather than assuming "visible" -- this
  // should not assume it is the only thing that ever touches it.
  useEffect(() => {
    if (!open) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previous;
    };
  }, [open]);

  // Arriving. A section's rows come from a query, so the place may not exist
  // for a moment after the drawer does: look for it, briefly, then give up
  // quietly at the top -- an anchor nobody marks is not an error.
  useEffect(() => {
    if (!open || !anchor) return;
    let tries = 0;
    const timer = window.setInterval(() => {
      const target = document.querySelector<HTMLElement>(`[data-settings-anchor~="${anchor}"]`);
      if (!target && ++tries < 40) return;
      window.clearInterval(timer);
      if (!target) return;
      target.scrollIntoView({ block: "start", behavior: "auto" });
      target.classList.add(ARRIVED_CLASS);
      window.setTimeout(() => target.classList.remove(ARRIVED_CLASS), 1600);
      const focusable = target.matches("input,button,[tabindex]")
        ? target
        : target.querySelector<HTMLElement>("input,button,[role=combobox],[role=switch]");
      focusable?.focus({ preventScroll: true });
    }, 75);
    return () => window.clearInterval(timer);
  }, [open, anchor, anchorRequest]);

  return (
    <OverlayDrawer
      {...restoreFocusSource}
      open={open}
      position="end"
      className={styles.surface}
      // The page is a translucent gradient over a flat base (App.tsx paints
      // both onto <body>). The drawer takes the same two layers so it reads as
      // the same room sliding open, not a panel pasted over it.
      style={{
        backgroundColor: theme.page.color,
        backgroundImage: theme.page.image,
      }}
      // A settings panel never traps you: the scrim and Escape both close it.
      onOpenChange={(_e, { open: next }) => {
        if (!next) onClose();
      }}
    >
      <DrawerHeader>
        <DrawerHeaderTitle
          action={
            <Button
              appearance="subtle"
              aria-label="Close settings"
              icon={<DismissRegular />}
              onClick={onClose}
            />
          }
        >
          Settings
        </DrawerHeaderTitle>
      </DrawerHeader>
      <style>{ARRIVED_CSS}</style>
      <SettingsFooterContext.Provider value={footerNode}>
        <DrawerBody className={styles.body}>
          {/* The questions first (settings by workflow, D-W6); folded on a deep link (D-W11). */}
          <HowDoI anchor={anchor} />
          {children}
        </DrawerBody>
      </SettingsFooterContext.Provider>
      <div ref={setFooterNode} className={styles.footer} />
    </OverlayDrawer>
  );
}
