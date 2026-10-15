import type { ReactNode } from "react";
import { FluentProvider } from "@fluentui/react-components";
import { ViewportProvider } from "./viewport";
import { darkTheme } from "../../shell/theme";

/** A deck is its own room: dark, whatever the Toolkit's theme is around it.
 *  The route is chromeless (no nav bar), so this is the whole screen. Shared
 *  by both resolvers -- DeckHost's (a listed deck) and GeneratedDeckHost's (a
 *  deck built from data) -- so the two rooms cannot drift.
 *
 *  With no shell around it there is no shell's <main> either, so the room is
 *  its own (axe's region): the stage, its controls and the notes window
 *  are the page's main content, and a screen reader's landmark list has it. */
export function DeckRoom({ children }: { children: ReactNode }) {
  return (
    <FluentProvider theme={darkTheme} style={{ colorScheme: "dark", minHeight: "100vh" }}>
      <ViewportProvider>
        <main>{children}</main>
      </ViewportProvider>
    </FluentProvider>
  );
}
