import { fireEvent, render, screen } from "@testing-library/react";
import { ArchiveRegular, ArrowRightRegular, OpenRegular } from "@fluentui/react-icons";
import { CardActions } from "./CardActions";

// The row's one action grammar: ONE exposed action, every other action
// in the `...` menu -- even when there is only one -- with the external link
// last. A single secondary used to be drawn as a second flat button, so the
// same row read two ways depending on a count.
describe("CardActions", () => {
  it("puts a lone secondary action in the menu, not beside the exposed one", async () => {
    const retire = jest.fn();
    render(
      <CardActions
        primaryAction={{ icon: <ArrowRightRegular />, label: "View goal", onClick: () => {} }}
        secondaryActions={[{ icon: <ArchiveRegular />, label: "Retire", onClick: retire }]}
        menuLabel="Actions for Learn Rust"
      />,
    );
    expect(screen.getByRole("button", { name: "View goal" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Retire" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Actions for Learn Rust" }));
    fireEvent.click(await screen.findByRole("menuitem", { name: "Retire" }));
    expect(retire).toHaveBeenCalledTimes(1);
  });

  it("draws no menu when a row has nothing but its one action", () => {
    render(
      <CardActions
        primaryAction={{ icon: <ArrowRightRegular />, label: "Open review", onClick: () => {} }}
      />,
    );
    expect(screen.getAllByRole("button")).toHaveLength(1);
  });

  it("keeps the order it is given -- the external link last", async () => {
    render(
      <CardActions
        primaryAction={{ icon: <ArrowRightRegular />, label: "Open the issue", onClick: () => {} }}
        secondaryActions={[
          { icon: <ArchiveRegular />, label: "Close issue", onClick: () => {} },
          {
            icon: <OpenRegular />,
            label: "Open on GitHub",
            href: "https://github.com/x/y/issues/1",
            dividerBefore: true,
          },
        ]}
        menuLabel="Actions for #1"
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Actions for #1" }));
    const items = (await screen.findAllByRole("menuitem")).map((m) => m.textContent);
    expect(items).toEqual(["Close issue", "Open on GitHub"]);
  });
});
