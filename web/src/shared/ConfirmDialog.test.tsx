import { fireEvent, render, screen } from "@testing-library/react";
import { ConfirmDialog } from "./ConfirmDialog";

// The one confirm: every act worth a second thought asks the same way --
// "Are you sure?", the act named, Cancel and Submit -- and a caller whose verb
// can refuse shows the refusal in place and holds the buttons while it runs.
describe("ConfirmDialog", () => {
  it("asks the house question, names the act, and runs nothing until Submit", () => {
    const onConfirm = jest.fn();
    const onCancel = jest.fn();
    render(
      <ConfirmDialog
        open
        what="Archive card Wallet ticket."
        onConfirm={onConfirm}
        onCancel={onCancel}
      />,
    );
    expect(screen.getByText("Are you sure?")).toBeTruthy();
    expect(screen.getByText("Archive card Wallet ticket.")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(onCancel).toHaveBeenCalledTimes(1);
    expect(onConfirm).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Submit" }));
    expect(onConfirm).toHaveBeenCalledTimes(1);
  });

  it("holds both buttons while the act runs", () => {
    const onConfirm = jest.fn();
    render(<ConfirmDialog open busy what="Retire it." onConfirm={onConfirm} onCancel={() => {}} />);
    const cancel = screen.getByRole("button", { name: "Cancel" }) as HTMLButtonElement;
    expect(cancel.disabled).toBe(true);
    expect(screen.queryByRole("button", { name: "Submit" })).toBeNull();
    expect(screen.getByLabelText("Working...")).toBeTruthy();
  });

  it("shows a stated refusal in place, as an alert, and stays open", () => {
    render(
      <ConfirmDialog
        open
        what="Close this meeting."
        message="A closed record for that date is already in archive/."
        onConfirm={() => {}}
        onCancel={() => {}}
      />,
    );
    expect(screen.getByRole("alert").textContent).toBe(
      "A closed record for that date is already in archive/.",
    );
    expect(screen.getByRole("button", { name: "Submit" })).toBeTruthy();
  });

  it("says nothing extra when there is no refusal", () => {
    render(<ConfirmDialog open what="Retire it." onConfirm={() => {}} onCancel={() => {}} />);
    expect(screen.queryByRole("alert")).toBeNull();
  });
});
