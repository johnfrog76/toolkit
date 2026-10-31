import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { StrictMode } from "react";
import type { Milestone } from "../ado/api.ado";
import type { MilestonesResponse } from "./api.solitaireAgile";
import { AWARD_SEEN_KEY, awardKey } from "./award";
import { resetCelebrateMemory } from "./celebrate";
import { ConfettiLayer } from "./ConfettiLayer";
import { resetConfetti } from "./useConfetti";
import { MilestonesPage } from "./MilestonesPage";

// The award opens ONCE per reached milestone per browser, however the page is left
// (button, Escape, navigation), revisited, or fed (the env and the ritual payload
// arriving in either order, the Space's slug changing between renders).

const bursts: unknown[] = [];
jest.mock("react-confetti", () => ({
  __esModule: true,
  default: (props: unknown) => {
    bursts.push(props);
    return null;
  },
}));

let response: { data?: MilestonesResponse; isLoading: boolean; error?: unknown } = {
  isLoading: false,
};
let envSpace: string | undefined = "widgets";
jest.mock("./api.solitaireAgile", () => ({
  useGetRitualMilestonesQuery: () => response,
}));
jest.mock("../../shell/api", () => ({
  useGetEnvQuery: () => ({ isLoading: false, data: { config: { activeSpace: envSpace } } }),
}));

const ms = (number: number, title: string, repo = "o/widgets"): Milestone => ({
  title,
  number,
  repo,
  url: `https://github.com/${repo}/milestone/${number}`,
  state: "open",
  open: 0,
  closed: 3,
  due: "",
  closed_at: "",
  created_at: "2026-10-01",
  updated_at: "2026-10-20",
  reached: true,
});
const ok = (milestones: Milestone[], space = "widgets"): MilestonesResponse => ({
  ceremony: "milestones",
  space,
  tracker: { ok: true, reason: "" },
  milestones,
});
const A = ms(1, "M1");
const B = ms(2, "M2");
const C = { ...ms(3, "M3"), updated_at: "2026-10-25" };
const D = ms(4, "M4");

/** The tab as the app draws it: the page, and the module's one confetti mount at the
 *  root (ConfettiLayer, the registry's `overlays`), beside it rather than inside. */
const Page = () => (
  <>
    <MilestonesPage />
    <ConfettiLayer />
  </>
);

beforeEach(() => {
  resetConfetti();
  bursts.length = 0;
  localStorage.clear();
  resetCelebrateMemory();
  envSpace = "widgets";
  response = { isLoading: false, data: ok([A, B]) };
  window.matchMedia = ((q: string) => ({
    matches: false,
    media: q,
    addEventListener: () => undefined,
    removeEventListener: () => undefined,
  })) as unknown as typeof window.matchMedia;
});

const dialog = () => screen.findByRole("dialog", { hidden: true });
const none = async () => {
  await act(async () => {
    await new Promise((r) => setTimeout(r, 0));
  });
  expect(screen.queryByRole("dialog", { hidden: true })).toBeNull();
};
async function closeByButton() {
  const d = await dialog();
  const bs = await within(d).findAllByRole("button", { name: "Close", hidden: true });
  fireEvent.click(bs.find((b) => b.textContent === "Close")!);
}
async function closeByEscape() {
  const d = await dialog();
  fireEvent.keyDown(d, { key: "Escape", code: "Escape" });
}
const settle = () =>
  waitFor(() => expect(screen.queryByRole("dialog", { hidden: true })).toBeNull());

const dialogs = () => screen.queryAllByRole("dialog", { hidden: true });

describe.each([
  ["the button", closeByButton],
  ["Escape", closeByEscape],
])("closed by %s", (_name, close) => {
  it("opens once for a backlog, and a revisit with the same storage opens nothing", async () => {
    response = { isLoading: false, data: ok([A, B, C, D]) };
    const { unmount } = render(<Page />);
    // One dialog naming all four, oldest reached first, one burst.
    const d = await dialog();
    await within(d).findByText("Congratulations: M1, M2, M4 and M3 reached!");
    expect(within(d).getAllByTestId("award-line")).toHaveLength(4);
    expect(bursts).toHaveLength(1);
    await close();
    await settle();
    await none();
    unmount();
    render(<Page />);
    await none();
  });
});

it("data landing in stages (no slug, then the slug, a payload, a refetch) opens ONE dialog", async () => {
  envSpace = undefined;
  response = { isLoading: true };
  const { rerender } = render(<Page />);
  expect(dialogs()).toHaveLength(0);
  envSpace = "widgets";
  rerender(<Page />);
  response = { isLoading: false, data: ok([A, B, C, D]) };
  rerender(<Page />);
  await dialog();
  // A refetch: new list and row objects, the dialog still open.
  response = { isLoading: false, data: ok([A, B, C, D].map((m) => ({ ...m }))) };
  rerender(<Page />);
  rerender(<Page />);
  expect(dialogs()).toHaveLength(1);
  // The mark is in place the moment the dialog is up, before any close.
  expect(JSON.parse(localStorage.getItem(AWARD_SEEN_KEY) ?? "[]")).toHaveLength(4);
  await closeByEscape();
  await settle();
  // A refetch after the close, and after a new milestone is reached: nothing opens.
  response = { isLoading: false, data: ok([A, B, C, D, ms(5, "M5")]) };
  rerender(<Page />);
  await none();
});

it("a milestone reached while you watch is awarded on the next visit, once", async () => {
  response = { isLoading: false, data: ok([{ ...A, reached: false }]) };
  const { unmount } = render(<Page />);
  await none();
  unmount();
  response = { isLoading: false, data: ok([A]) };
  const second = render(<Page />);
  await dialog();
  await closeByButton();
  await settle();
  second.unmount();
  render(<Page />);
  await none();
});

it("an existing title-keyed mark still counts as awarded, and a rename is not a new award", async () => {
  localStorage.setItem(AWARD_SEEN_KEY, JSON.stringify(["widgets:M1", "widgets:M2"]));
  response = { isLoading: false, data: ok([A, B]) };
  render(<Page />);
  await none();
});

it("the key is the repository and number, so a rename changes nothing", async () => {
  const { unmount } = render(<Page />);
  await dialog();
  await closeByButton();
  await settle();
  unmount();
  expect(localStorage.getItem(AWARD_SEEN_KEY)).toContain(awardKey("widgets", A));
  response = {
    isLoading: false,
    data: ok([{ ...A, title: "M1 renamed" }, B]),
  };
  const again = render(<Page />);
  await none();
  again.unmount();
});

it("the env slug and the agent's slug differing does not re-open on a revisit", async () => {
  envSpace = undefined;
  const { unmount } = render(<Page />);
  await dialog();
  await closeByButton();
  await settle();
  unmount();
  envSpace = "widgets";
  render(<Page />);
  await none();
});

it("StrictMode changes nothing", async () => {
  const { unmount } = render(
    <StrictMode>
      <Page />
    </StrictMode>,
  );
  await dialog();
  await closeByEscape();
  await settle();
  unmount();
  render(
    <StrictMode>
      <Page />
    </StrictMode>,
  );
  await none();
});
