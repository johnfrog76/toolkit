import { render, screen } from "@testing-library/react";
import { PageCard } from "./PageCard";

// The footer's centre slot (the pager) keeps its own width on one line, and the
// left sentence is the one that gives way.
describe("PageCard's footer with a centre slot", () => {
  it("keeps the centre from shrinking or wrapping, and lets the left text wrap", () => {
    render(
      <PageCard footerLeft={<span>a long left sentence</span>} footerCenter={<span>1 / 3</span>}>
        body
      </PageCard>,
    );
    const middle = screen.getByText("1 / 3").parentElement as HTMLElement;
    const left = screen.getByText("a long left sentence").parentElement as HTMLElement;
    expect(getComputedStyle(middle).flexShrink).toBe("0");
    expect(getComputedStyle(middle).whiteSpace).toBe("nowrap");
    expect(parseFloat(getComputedStyle(left).minWidth)).toBe(0);
  });

  it("leaves the footer as it was when there is no centre", () => {
    render(<PageCard footerLeft={<span>only left</span>}>body</PageCard>);
    const left = screen.getByText("only left").parentElement as HTMLElement;
    expect(parseFloat(getComputedStyle(left).minWidth)).not.toBe(0);
  });
});
