import { render } from "@testing-library/react";
import { VisibilityBadge, isPublicVisibility, visibilityLabel } from "./visibility";

// The one copy of a repository's visibility as a person reads it: gh's
// words for the New Space picker, the agent's for a Space. One row per input.
describe("a repository's visibility, as a person reads it", () => {
  it.each<[string | undefined, string, boolean]>([
    ["PUBLIC", "Public", true],
    ["public", "Public", true],
    ["PRIVATE", "Private", false],
    ["private", "Private", false],
    ["INTERNAL", "Internal", false],
    ["unknown", "Visibility unknown", false],
    ["", "", false],
    [undefined, "", false],
  ])("%p", (raw, label, pub) => {
    expect(visibilityLabel(raw)).toBe(label);
    expect(isPublicVisibility(raw)).toBe(pub);
  });

  it("the pill draws the word, and nothing when there is none", () => {
    const { container, rerender } = render(<VisibilityBadge visibility="public" />);
    expect(container.textContent).toBe("Public");
    rerender(<VisibilityBadge visibility="" />);
    expect(container.textContent).toBe("");
  });
});
