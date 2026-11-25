import { fireEvent, screen } from "@testing-library/react";

/** The address a File line holds: what its tooltip says on keyboard focus, which is what a click copies. */
export async function fileLineValue(): Promise<string> {
  const line = screen.getByTestId("file-path");
  const button = line.querySelector("button");
  if (!button) throw new Error("the File line has no copy button");
  fireEvent.focus(button);
  const tip = await screen.findByRole("tooltip");
  return tip.textContent ?? "";
}
