import { render } from "@testing-library/react";
import { TrackerBadge, trackerChip } from "./TrackerBadge";

// A card badges its tracker -- (gh), (ado), or nothing. The tracker itself
// is the agent's answer (the tracker rule over the card's own link, pinned in
// Tests/test_card_model.py); this is the chip that answer becomes, as a table.
describe("the tracker badge", () => {
  it.each<[string | undefined | null, string | null]>([
    ["github", "gh"],
    ["ado", "ado"],
    // A custom card needs no badge: unlabeled IS its label.
    ["none", null],
    // An older agent that does not serve the field, or a word we do not know.
    [undefined, null],
    [null, null],
    ["gitlab", null],
  ])("%s wears %s", (tracker, chip) => {
    expect(trackerChip(tracker)).toBe(chip);
    const { container } = render(<TrackerBadge tracker={tracker} />);
    const badge = container.querySelector("[data-tracker-badge]");
    expect(badge?.textContent ?? null).toBe(chip);
  });
});
