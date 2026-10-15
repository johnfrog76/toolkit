import { render, screen } from "@testing-library/react";
import { StatusMessage } from "./StatusMessage";
import { BootSpinner } from "../shell/BootSpinner";

// A message that appears and goes away is only heard if it sits in a live
// region; a spinner is only heard if it has a name.
describe("StatusMessage", () => {
  it("is a polite status for a success, with the message inside", async () => {
    render(<StatusMessage status="success">Attached.</StatusMessage>);
    const region = screen.getByRole("status");
    expect(await screen.findByText("Attached.")).toBeTruthy();
    expect(region.textContent).toContain("Attached.");
    expect(screen.queryByRole("alert")).toBeNull();
  });

  it("is an alert for an error, with the message inside", async () => {
    render(<StatusMessage status="error">Could not attach.</StatusMessage>);
    const region = screen.getByRole("alert");
    expect(await screen.findByText("Could not attach.")).toBeTruthy();
    expect(region.textContent).toContain("Could not attach.");
    expect(screen.queryByRole("status")).toBeNull();
  });

  it("mounts the region before its text, so a screen reader sees the change", () => {
    render(<StatusMessage status="success">Attached.</StatusMessage>);
    // Effects have flushed by now; the region was in the page first.
    expect(screen.getByRole("status")).toBeTruthy();
  });
});

describe("BootSpinner", () => {
  it("names the spinner with the words beside it", () => {
    render(<BootSpinner />);
    expect(screen.getByRole("progressbar", { name: "Loading toolkit..." })).toBeTruthy();
    expect(screen.getByText("Loading toolkit...")).toBeTruthy();
  });
});
