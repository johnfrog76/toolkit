import { render, screen, waitFor, act } from "@testing-library/react";
import { PageHeading } from "./PageHeading";

describe("PageHeading", () => {
  it("supplies the one h1 when the page draws none", async () => {
    render(
      <main id="main">
        <PageHeading name="Board" mainId="main" />
      </main>,
    );
    expect(await screen.findByRole("heading", { level: 1, name: "Board" })).toBeTruthy();
  });

  it("steps aside once the page has its own h1, and returns when it goes", async () => {
    render(
      <main id="main">
        <PageHeading name="Board" mainId="main" />
      </main>,
    );
    await screen.findByRole("heading", { level: 1, name: "Board" });
    const own = document.createElement("h1");
    own.textContent = "Issue 4";
    act(() => {
      document.getElementById("main")!.appendChild(own);
    });
    await waitFor(() => expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1));
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("Issue 4");
    act(() => {
      own.remove();
    });
    await screen.findByRole("heading", { level: 1, name: "Board" });
  });
});
