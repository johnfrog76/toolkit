import { render, screen, fireEvent, act } from "@testing-library/react";
import { FilePath } from "./FilePath";

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

  it("shows the whole absolute path and copies it on click, saying so for two seconds", async () => {
    const path = "/hub/demo/current/Spike-K7M2-wallet-ticket.prompt.md";
    render(<FilePath path={path} />);
    expect(screen.getByText(path)).toBeTruthy();
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Copy the file path" }));
    });
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(path);
    expect(screen.getByText("Copied")).toBeTruthy();
    act(() => {
      jest.advanceTimersByTime(2100);
    });
    expect(screen.queryByText("Copied")).toBeNull();
  });
});
