/**
 * A link to a setting lands on its row when the drawer opens -- including when
 * the row's list arrives long after the drawer does (the first read of a
 * session goes through the command line and takes many seconds). What decides
 * is the row being drawn, not a timer.
 */
import { act, cleanup, render } from "@testing-library/react";
import { FluentProvider } from "@fluentui/react-components";
import { useEffect, useState } from "react";
import { SettingsDrawer } from "./SettingsDrawer";
import { fluentThemeFor } from "./theme";
import { FIRST_LIGHT, themeById } from "./themeList";
import type { ToolkitTheme } from "./themeList";

jest.mock("./HowDoI", () => ({ HowDoI: () => null }));

const theme = themeById(FIRST_LIGHT) as ToolkitTheme;

/** A section whose row exists only after `lateMs`, like a list still being read. */
function LateRow({ lateMs }: { lateMs: number }) {
  const [drawn, setDrawn] = useState(false);
  useEffect(() => {
    const t = window.setTimeout(() => setDrawn(true), lateMs);
    return () => window.clearTimeout(t);
  }, [lateMs]);
  return drawn ? (
    <div data-settings-anchor="email">
      <input aria-label="Email" />
    </div>
  ) : (
    <p>Reading the settings files...</p>
  );
}

function open(lateMs: number, anchor = "email") {
  return render(
    <FluentProvider theme={fluentThemeFor(theme)}>
      <SettingsDrawer
        open
        onClose={() => undefined}
        theme={theme}
        anchor={anchor}
        anchorRequest={{}}
      >
        <LateRow lateMs={lateMs} />
      </SettingsDrawer>
    </FluentProvider>,
  );
}

describe("a settings link arrives", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    Element.prototype.scrollIntoView = jest.fn();
  });
  afterEach(() => {
    cleanup();
    jest.useRealTimers();
  });

  it("when the row is drawn at once", async () => {
    open(0);
    await act(async () => {
      jest.advanceTimersByTime(500);
    });
    expect(document.activeElement?.getAttribute("aria-label")).toBe("Email");
  });

  it("when the list arrives long after the old three seconds had run out", async () => {
    open(20_000);
    await act(async () => {
      jest.advanceTimersByTime(10_000);
    });
    expect(document.activeElement?.getAttribute("aria-label")).not.toBe("Email");
    await act(async () => {
      jest.advanceTimersByTime(11_000);
    });
    expect(document.activeElement?.getAttribute("aria-label")).toBe("Email");
    expect(Element.prototype.scrollIntoView).toHaveBeenCalledTimes(1);
  });

  it("an anchor nobody marks leaves the drawer at the top, quietly", async () => {
    open(0, "nowhere");
    await act(async () => {
      jest.advanceTimersByTime(30_000);
    });
    expect(Element.prototype.scrollIntoView).not.toHaveBeenCalled();
  });
});
