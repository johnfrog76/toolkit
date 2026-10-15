/**
 * shell/lazy.tsx: a lazy part draws its fallback first and the real component
 * once the chunk arrives, props intact; a null fallback draws nothing while
 * waiting (the header bell's case).
 */
import { render, screen } from "@testing-library/react";
import { lazyPart } from "./lazy";

function Greeting({ name }: { name: string }) {
  return <p>hello {name}</p>;
}

describe("lazyPart", () => {
  it("shows the house fallback, then the picked export with its props", async () => {
    const Part = lazyPart(
      () => Promise.resolve({ Greeting }),
      (m) => m.Greeting,
    );
    render(<Part name="someone" />);
    expect(document.querySelector('[role="progressbar"]')).not.toBeNull();
    expect(await screen.findByText("hello someone")).toBeTruthy();
    expect(document.querySelector('[role="progressbar"]')).toBeNull();
  });

  it("draws nothing while waiting when the fallback is null", async () => {
    const Part = lazyPart(
      () => Promise.resolve({ Greeting }),
      (m) => m.Greeting,
      null,
    );
    const { container } = render(<Part name="quiet" />);
    expect(container.textContent).toBe("");
    expect(await screen.findByText("hello quiet")).toBeTruthy();
  });
});
