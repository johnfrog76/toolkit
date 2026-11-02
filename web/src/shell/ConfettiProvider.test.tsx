import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { useConfetti } from "../hooks/useConfetti";
import { ConfettiProvider } from "./ConfettiProvider";

// The app's one confetti mount (shell/ConfettiProvider.tsx): a throw draws one burst at
// the root, a throw while it rains is absorbed into it, the next throw after it ends is
// a fresh burst, reduced motion throws nothing, and with no provider the hook is a
// no-op.

const bursts: unknown[] = [];
jest.mock("react-confetti", () => ({
  __esModule: true,
  default: (props: { onConfettiComplete?: () => void }) => {
    bursts.push(props);
    return (
      <button type="button" data-testid="confetti" onClick={() => props.onConfettiComplete?.()}>
        burst
      </button>
    );
  },
}));

let reduced = false;
beforeEach(() => {
  bursts.length = 0;
  reduced = false;
  window.matchMedia = ((q: string) => ({
    matches: reduced && q.includes("prefers-reduced-motion"),
    media: q,
    addEventListener: () => {},
    removeEventListener: () => {},
  })) as unknown as typeof window.matchMedia;
});

function Thrower() {
  const throwConfetti = useConfetti();
  return (
    <button type="button" onClick={throwConfetti}>
      throw
    </button>
  );
}

const burstEnds = () => fireEvent.click(screen.getByTestId("confetti"));

it("a throw draws one burst; a second throw while it rains is absorbed", async () => {
  render(
    <ConfettiProvider>
      <Thrower />
    </ConfettiProvider>,
  );
  expect(screen.queryByTestId("confetti")).toBeNull();
  fireEvent.click(screen.getByText("throw"));
  await waitFor(() => expect(screen.getAllByTestId("confetti")).toHaveLength(1));
  fireEvent.click(screen.getByText("throw"));
  expect(screen.getAllByTestId("confetti")).toHaveLength(1);
  expect(bursts).toHaveLength(1);
  burstEnds();
  await waitFor(() => expect(screen.queryByTestId("confetti")).toBeNull());
});

it("the next throw after a burst ends is a fresh burst", async () => {
  render(
    <ConfettiProvider>
      <Thrower />
    </ConfettiProvider>,
  );
  fireEvent.click(screen.getByText("throw"));
  await waitFor(() => expect(screen.getByTestId("confetti")).toBeTruthy());
  burstEnds();
  await waitFor(() => expect(screen.queryByTestId("confetti")).toBeNull());
  fireEvent.click(screen.getByText("throw"));
  await waitFor(() => expect(screen.getByTestId("confetti")).toBeTruthy());
  expect(bursts).toHaveLength(2);
});

it("under prefers-reduced-motion a throw draws nothing", async () => {
  reduced = true;
  render(
    <ConfettiProvider>
      <Thrower />
    </ConfettiProvider>,
  );
  fireEvent.click(screen.getByText("throw"));
  await act(async () => {});
  expect(screen.queryByTestId("confetti")).toBeNull();
  expect(bursts).toHaveLength(0);
});

it("with no provider the hook is a no-op", async () => {
  render(<Thrower />);
  fireEvent.click(screen.getByText("throw"));
  await act(async () => {});
  expect(screen.queryByTestId("confetti")).toBeNull();
});
