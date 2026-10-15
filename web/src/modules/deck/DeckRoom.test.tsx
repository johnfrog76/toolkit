import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { webDarkTheme } from "@fluentui/react-components";
import { DeckRoom } from "./DeckRoom";
import { DeckPlayer } from "./engine/DeckPlayer";
import { darkTheme } from "../../shell/theme";

// The app's worn theme, which the deck must ignore. Anything that does
// read the hook gets whatever this id names.
let mockThemeId = "seaglass";
jest.mock("../../hooks/useWornTheme", () => ({
  useWornTheme: () => {
    const active = jest.requireActual("../../shell/themeList").themeById(mockThemeId);
    return { theme: active.mode, active, worn: null, chosen: active, setThemeId: () => {} };
  },
}));

beforeAll(() => {
  (globalThis as unknown as { BroadcastChannel: unknown }).BroadcastChannel = class {
    postMessage() {}
    close() {}
    addEventListener() {}
    removeEventListener() {}
    onmessage = null;
  };
});

/** The value a FluentProvider wrote for one token on its own class. */
function tokenOn(el: Element, name: string): string | undefined {
  const cls = Array.from(el.classList).find((c) => /^fui-FluentProvider.+/.test(c)) ?? "";
  const css = Array.from(document.styleSheets)
    .flatMap((sheet) => Array.from(sheet.cssRules))
    .map((rule) => rule.cssText)
    .find((t) => t.includes(`.${cls} `) && t.includes(`--${name}:`));
  return css?.match(new RegExp(`--${name}: ([^;]+);`))?.[1];
}

// Axe's region: a deck's routes are chromeless, so the shell's <main>
// is not around them, and the stage sat outside every landmark. The room is
// its own main -- for a listed deck, its notes window and a deck built from
// data (Team Agile's standup stage), which all come through DeckRoom.

describe("DeckRoom", () => {
  it("holds what it is given in a main landmark", () => {
    render(
      <DeckRoom>
        <p>the stage</p>
      </DeckRoom>,
    );
    expect(screen.getByRole("main").textContent).toBe("the stage");
  });
});

describe("the deck room keeps the default dark theme", () => {
  function played() {
    return render(
      <MemoryRouter>
        <DeckRoom>
          <DeckPlayer
            deckId="d"
            slides={[
              { id: "s1", copy: <p>copy one</p> },
              { id: "s2", copy: null },
            ]}
            mode="audience"
          />
        </DeckRoom>
      </MemoryRouter>,
    );
  }

  it.each(["seaglass", "sunny", "aurora"])(
    "the room and the player are dark whatever the app wears (%s)",
    (id) => {
      mockThemeId = id;
      const { container } = played();
      const room = container.querySelector(".fui-FluentProvider") as HTMLElement;
      const stage = screen.getByText("copy one").closest(".fui-FluentProvider") as HTMLElement;
      expect(tokenOn(room, "colorNeutralBackground1")).toBe(darkTheme.colorNeutralBackground1);
      expect(room.style.colorScheme).toBe("dark");
      expect(tokenOn(stage, "colorNeutralBackground1")).toBe(webDarkTheme.colorNeutralBackground1);
    },
  );
});
