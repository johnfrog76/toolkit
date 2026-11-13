import { render, screen } from "@testing-library/react";
import { PanelFrame } from "./PanelFrame";

// The footer's centre slot (the pager) keeps its own width on one line, and the
// left sentence is the one that gives way.
describe("PanelFrame's footer with a centre slot", () => {
  it("keeps the centre from shrinking or wrapping, and lets the left text wrap", () => {
    render(
      <PanelFrame footerLeft={<span>a long left sentence</span>} footerCenter={<span>1 / 3</span>}>
        body
      </PanelFrame>,
    );
    const middle = screen.getByText("1 / 3").parentElement as HTMLElement;
    const left = screen.getByText("a long left sentence").parentElement as HTMLElement;
    expect(getComputedStyle(middle).flexShrink).toBe("0");
    expect(getComputedStyle(middle).whiteSpace).toBe("nowrap");
    expect(parseFloat(getComputedStyle(left).minWidth)).toBe(0);
  });

  it("leaves the footer as it was when there is no centre", () => {
    render(<PanelFrame footerLeft={<span>only left</span>}>body</PanelFrame>);
    const left = screen.getByText("only left").parentElement as HTMLElement;
    expect(parseFloat(getComputedStyle(left).minWidth)).not.toBe(0);
  });
});

// The foot holds the bottom: the frame is a column and its body grows, so a
// panel with one line of content still has its foot at its bottom edge.
describe("PanelFrame's foot, under short content", () => {
  it("the body takes the room between the header and the foot", () => {
    const { container } = render(
      <PanelFrame headerLeft={<span>Title</span>} footerLeft={<span>the foot</span>}>
        <p>one line</p>
        <p>and another</p>
      </PanelFrame>,
    );
    const frame = container.firstElementChild as HTMLElement;
    const body = screen.getByText("one line").parentElement as HTMLElement;
    const foot = screen.getByText("the foot").parentElement!.parentElement as HTMLElement;
    expect(getComputedStyle(frame).display).toBe("flex");
    expect(getComputedStyle(frame).flexDirection).toBe("column");
    // The body is the frame's child, grows, and the foot follows it, last.
    expect(body.parentElement).toBe(frame);
    expect(getComputedStyle(body).flexGrow).toBe("1");
    expect(body.nextElementSibling).toBe(foot);
    expect(frame.lastElementChild).toBe(foot);
    // No divider is drawn above the foot: only the header's.
    expect(frame.querySelectorAll("hr, [role='separator']").length).toBeLessThanOrEqual(1);
    // The body's own children keep the frame's gap.
    expect(getComputedStyle(body).flexDirection).toBe("column");
    expect(getComputedStyle(body).rowGap).not.toBe("");
  });

  it("a scrollable frame keeps its grid, whose body row takes the room", () => {
    const { container } = render(
      <PanelFrame scrollable footerLeft={<span>the foot</span>}>
        <p>one line</p>
      </PanelFrame>,
    );
    const frame = container.firstElementChild as HTMLElement;
    expect(getComputedStyle(frame).display).toBe("grid");
    expect(getComputedStyle(frame).gridTemplateRows).toBe("auto auto 1fr auto");
  });
});

// The body is a named slot like the others; children are the default slot and
// fill it. One or the other, never both.
describe("PanelFrame's body slot", () => {
  it("the named slot and the default slot draw the same frame", () => {
    const named = render(<PanelFrame headerLeft={<span>Title</span>} body={<p>the body</p>} />);
    const viaBody = named.container.innerHTML;
    named.unmount();
    const { container } = render(
      <PanelFrame headerLeft={<span>Title</span>}>
        <p>the body</p>
      </PanelFrame>,
    );
    expect(container.innerHTML).toBe(viaBody);
    expect(screen.getByText("the body").parentElement?.hasAttribute("data-panel-frame-body")).toBe(
      true,
    );
  });

  it("both at once is refused: by the types, and when drawn", () => {
    const quiet = jest.spyOn(console, "error").mockImplementation(() => undefined);
    const both = () =>
      render(
        // @ts-expect-error -- body or children, never both
        <PanelFrame body={<p>one</p>}>
          <p>two</p>
        </PanelFrame>,
      );
    expect(both).toThrow(/pass `body` or children, never both/);
    quiet.mockRestore();
  });
});
