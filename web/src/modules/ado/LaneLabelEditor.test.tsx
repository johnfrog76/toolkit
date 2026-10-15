import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { FluentProvider, webLightTheme } from "@fluentui/react-components";
import { LaneLabelEditor } from "./LaneLabelEditor";
import type { CommandResponse } from "./api.ado";

// The pencil (the owner, annotating the Demo board): click turns the
// label into an input, Enter writes through the one config mutation and Esc
// or a blur cancel without writing anything.
function success(): CommandResponse {
  return {
    command: "Config",
    status: "success",
    exit_code: 0,
    output: "",
    error: null,
    duration: 0,
  };
}
let nextResult: CommandResponse = success();
const writeConfig = jest.fn((_payload: { set: Record<string, unknown>; unset: string[] }) => ({
  unwrap: () => Promise.resolve({ result: nextResult, config: {} }),
}));
jest.mock("./api.ado", () => ({
  useWriteConfigMutation: () => [writeConfig, { isLoading: false }],
}));

beforeEach(() => {
  writeConfig.mockClear();
  nextResult = success();
});

// The box-affecting styles the house rule names: "an
// in-place editor occupies the EXACT box of the text it replaces -- same
// height, baseline and width, same typography tokens, padding that nets to
// the same box, no extra margin in either state." Measured, not eyeballed.
function boxOf(el: Element) {
  const cs = getComputedStyle(el);
  return { margin: cs.margin, height: cs.height, boxSizing: cs.boxSizing };
}
// Typography reads from the element's OWN inline style (an authored value,
// same for both states since both wear the identical `TITLE_STYLE` object) --
// not `getComputedStyle`, which jsdom cannot resolve a `var(...)` font-size
// through (it validates a length before accepting one; `fontFamily`,
// `lineHeight` and `fontWeight` are untyped strings and pass straight
// through, but a real browser resolves all four the same way regardless).
function typeOf(el: Element) {
  const style = (el as HTMLElement).style;
  return {
    fontFamily: style.fontFamily,
    fontSize: style.fontSize,
    lineHeight: style.lineHeight,
    fontWeight: style.fontWeight,
  };
}

describe("LaneLabelEditor", () => {
  it("with no config key, it is only the label -- no pencil to click", () => {
    render(<LaneLabelEditor label="Active" configKey={null} />);
    // getByText throws if the label is missing; not throwing is the check.
    screen.getByText("Active");
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("the pencil is always there, before the title", () => {
    const { container } = render(
      <LaneLabelEditor label="Active" configKey="spaces.demo.laneNames.active" />,
    );
    const pencil = screen.getByRole("button", { name: /rename the active lane/i });
    const title = screen.getByText("Active");
    expect(pencil.compareDocumentPosition(title) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(
      container.querySelector("svg")?.getAttribute("font-size") ??
        container.querySelector("svg")?.getAttribute("fontSize"),
    ).toBeTruthy();
  });

  // Part 1 and 2: the resting heading and the editor occupy the exact
  // same box, so nothing moves when the pencil is clicked or the edit ends.
  it("the resting heading and the editing input share one box and one typography", () => {
    // The tokens are CSS custom properties -- resolving them to real, comparable
    // values (rather than an unresolved `var(...)`) needs the theme that defines
    // them, the same as a real page provides.
    const { container } = render(
      <FluentProvider theme={webLightTheme}>
        <LaneLabelEditor label="Active" configKey="spaces.demo.laneNames.active" />
      </FluentProvider>,
    );
    const heading = screen.getByText("Active");
    const restingBox = boxOf(heading);
    const restingType = typeOf(heading);
    // No margin in the resting state -- the bug was a `Subtitle2 as="h2"`
    // carrying the browser's own default heading margin.
    expect(restingBox.margin).toBe("0px");

    fireEvent.click(screen.getByRole("button", { name: /rename the active lane/i }));
    const input = screen.getByRole("textbox");
    const inputRoot = container.querySelector(".fui-Input") ?? input.parentElement!;
    const editingBox = boxOf(inputRoot);
    const editingType = typeOf(input);

    expect(editingBox).toEqual(restingBox);
    expect(editingType).toEqual(restingType);
  });

  it("click, type, Enter -- writes the lane's config key with the new text and returns to the label", async () => {
    render(<LaneLabelEditor label="Active" configKey="spaces.demo.laneNames.active" />);
    fireEvent.click(screen.getByRole("button", { name: /rename the active lane/i }));
    const input = screen.getByRole("textbox");
    fireEvent.change(input, { target: { value: "To do" } });
    fireEvent.keyDown(input, { key: "Enter" });
    expect(writeConfig).toHaveBeenCalledTimes(1);
    expect(writeConfig.mock.calls[0][0]).toEqual({
      set: { "spaces.demo.laneNames.active": "To do" },
      unset: [],
    });
    // Back to the label once the write succeeds, not left in edit mode.
    await waitFor(() => screen.getByText("Active"));
  });

  it("Escape cancels without writing anything", () => {
    render(<LaneLabelEditor label="Active" configKey="spaces.demo.laneNames.active" />);
    fireEvent.click(screen.getByRole("button", { name: /rename the active lane/i }));
    fireEvent.change(screen.getByRole("textbox"), { target: { value: "Whatever" } });
    fireEvent.keyDown(screen.getByRole("textbox"), { key: "Escape" });
    expect(writeConfig).not.toHaveBeenCalled();
    screen.getByText("Active");
  });

  it("a blank value is an UNSET -- restores the space's default word", async () => {
    render(<LaneLabelEditor label="To do" configKey="spaces.demo.laneNames.active" />);
    fireEvent.click(screen.getByRole("button", { name: /rename the to do lane/i }));
    fireEvent.change(screen.getByRole("textbox"), { target: { value: "   " } });
    fireEvent.keyDown(screen.getByRole("textbox"), { key: "Enter" });
    expect(writeConfig.mock.calls[0][0]).toEqual({
      set: {},
      unset: ["spaces.demo.laneNames.active"],
    });
    await waitFor(() => screen.getByText("To do"));
  });

  // Part 3: a refusal used to be silent -- editing exited on Enter
  // regardless, before the write had even reached the agent, which reads
  // exactly like "the rename did not persist" whenever the write then
  // failed. It now follows the board's own rule for a card move: no
  // optimistic exit, and a refusal leaves it exactly where it was, named.
  it("a refused write stays in edit mode and says why, rather than silently reverting", async () => {
    nextResult = {
      command: "Config",
      status: "error",
      exit_code: 2,
      output: null,
      error: "'spaces.demo' is the hub's, and no hub is configured.",
      duration: 0,
    };
    render(<LaneLabelEditor label="Active" configKey="spaces.demo.laneNames.active" />);
    fireEvent.click(screen.getByRole("button", { name: /rename the active lane/i }));
    fireEvent.change(screen.getByRole("textbox"), { target: { value: "To do" } });
    fireEvent.keyDown(screen.getByRole("textbox"), { key: "Enter" });
    await waitFor(() => screen.getByText(/no hub is configured/i));
    // Still editing -- the draft is not thrown away and the input is still there.
    expect((screen.getByRole("textbox") as HTMLInputElement).value).toBe("To do");
  });
});
