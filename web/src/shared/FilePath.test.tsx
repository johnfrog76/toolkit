import { render, screen, fireEvent, act } from "@testing-library/react";
import { FilePath } from "./FilePath";
import { FILE_LINE } from "../shell/fileLine";

describe("FilePath", () => {
  beforeEach(() => {
    jest.useFakeTimers();
    Object.assign(navigator, { clipboard: { writeText: jest.fn().mockResolvedValue(undefined) } });
  });
  afterEach(() => jest.useRealTimers());

  it("renders nothing when the agent sent no path -- an older agent, not an error", () => {
    const { container } = render(<FilePath path={undefined} />);
    expect(container.innerHTML).toBe("");
  });

  it("shows a fixed label, never the address, and copies the whole path on click, saying so for two seconds", async () => {
    const path = "/hub/demo/current/Spike-K7M2-wallet-ticket.prompt.md";
    render(<FilePath path={path} />);
    expect(screen.getByRole("button", { name: FILE_LINE.copyPath }).textContent).toBe(
      FILE_LINE.copyPath,
    );
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: FILE_LINE.copyPath }));
    });
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(path);
    expect(screen.getByText(FILE_LINE.copied)).toBeTruthy();
    act(() => {
      jest.advanceTimersByTime(2100);
    });
    expect(screen.queryByText(FILE_LINE.copied)).toBeNull();
  });

  it("labels a URL as a link, and the label is the same however long the address is", async () => {
    const short = "https://example.test/a";
    const long = `https://example.test/${"a-very-long-segment/".repeat(20)}`;
    const { rerender } = render(<FilePath path={short} />);
    const first = screen.getByRole("button", { name: FILE_LINE.copyLink }).textContent;
    rerender(<FilePath path={long} />);
    expect(screen.getByRole("button", { name: FILE_LINE.copyLink }).textContent).toBe(first);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: FILE_LINE.copyLink }));
    });
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(long);
  });

  it("holds the address as the tooltip, on hover and on keyboard focus", async () => {
    jest.useRealTimers();
    const path = "/hub/demo/card.md";
    render(<FilePath path={path} />);
    const button = screen.getByRole("button", { name: FILE_LINE.copyPath });
    fireEvent.focus(button);
    expect((await screen.findByRole("tooltip")).textContent).toBe(path);
  });
});
