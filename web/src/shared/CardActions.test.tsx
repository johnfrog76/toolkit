import { fireEvent, render, screen } from "@testing-library/react";
import { CardActions, ROW, defineRowMoves } from "./CardActions";
import { CheckmarkCircleRegular } from "@fluentui/react-icons";

const TEST_MOVES = defineRowMoves("test", {
  close: { word: "Close issue", icon: CheckmarkCircleRegular, differentMove: "a test row" },
});

// The row's one action grammar: ONE exposed action, every other action
// in the `...` menu -- even when there is only one -- with the external link
// last. A single secondary used to be drawn as a second flat button, so the
// same row read two ways depending on a count.
describe("CardActions", () => {
  it("puts a lone secondary action in the menu, not beside the exposed one", async () => {
    const archive = jest.fn();
    render(
      <CardActions
        primaryAction={ROW.open.action({ detail: "the goal", onClick: () => {} })}
        secondaryActions={[ROW.archive.action({ onClick: archive })]}
        menuLabel="Actions for Learn Rust"
      />,
    );
    expect(screen.getByRole("button", { name: "Open the goal" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Archive" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Actions for Learn Rust" }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Archive" }));
    expect(archive).toHaveBeenCalledTimes(1);
  });

  it("draws no menu when a row has nothing but its one action", () => {
    render(
      <CardActions primaryAction={ROW.open.action({ detail: "the review", onClick: () => {} })} />,
    );
    expect(screen.getAllByRole("button")).toHaveLength(1);
  });

  it("draws the external link last, behind a divider, whatever order it was given in", async () => {
    render(
      <CardActions
        primaryAction={ROW.open.action({ detail: "the issue", onClick: () => {} })}
        secondaryActions={[
          ROW.external.action({ detail: "GitHub", href: "https://github.com/x/y/issues/1" }),
          TEST_MOVES.close.action({ onClick: () => {} }),
        ]}
        menuLabel="Actions for #1"
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Actions for #1" }));
    const items = (await screen.findAllByRole("menuitem")).map((m) => m.textContent);
    expect(items).toEqual(["Close issue", "Open on GitHub"]);
    expect(document.querySelectorAll(".fui-MenuDivider")).toHaveLength(1);
  });

  it("carries the move's tooltip on a menu item and the flat button", async () => {
    render(
      <CardActions
        primaryAction={ROW.open.action({ detail: "the note", onClick: () => {} })}
        secondaryActions={[ROW.archive.action({ detail: "as shipped", onClick: () => {} })]}
        menuLabel="Actions for x"
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Actions for x" }));
    const item = await screen.findByRole("menuitem", { name: "Archive as shipped" });
    expect(item.getAttribute("title")).toBe(ROW.archive.tooltip());
    expect(ROW.open.tooltip("the note")).toBe("Open the note here, in ToolKit");
  });
});
