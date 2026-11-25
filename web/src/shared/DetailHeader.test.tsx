import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { DetailHeader } from "./DetailHeader";
import type { DetailHeaderProps } from "./DetailHeader";

jest.mock("./copyText", () => ({ copyText: jest.fn().mockResolvedValue(undefined) }));
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { copyText } = require("./copyText") as { copyText: jest.Mock };

function draw(props: DetailHeaderProps) {
  return render(
    <MemoryRouter>
      <DetailHeader {...props} />
    </MemoryRouter>,
  );
}

describe("DetailHeader", () => {
  beforeEach(() => copyText.mockClear());

  it("draws the title as the page's one h1, after the back button", () => {
    draw({ title: "A record" });
    expect(screen.getAllByRole("heading", { level: 1 })).toHaveLength(1);
    expect(screen.getByRole("heading", { level: 1, name: "A record" })).toBeTruthy();
    const back = screen.getByTitle("Back");
    const h1 = screen.getByRole("heading", { level: 1 });
    expect(back.compareDocumentPosition(h1) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it("with no title only the back button is drawn", () => {
    draw({ path: "/hub/x.md", refresh: { onClick: jest.fn() } });
    expect(screen.getByTitle("Back")).toBeTruthy();
    expect(screen.queryByRole("heading", { level: 1 })).toBeNull();
    expect(screen.queryByTestId("file-path")).toBeNull();
  });

  it("orders the parts: title, meta, extra, then the File line", () => {
    draw({
      title: "T",
      meta: <span>the-meta</span>,
      extra: <span>the-extra</span>,
      path: "/hub/x.md",
    });
    const order = [
      screen.getByRole("heading", { level: 1 }),
      screen.getByText("the-meta"),
      screen.getByText("the-extra"),
      screen.getByTestId("file-path"),
    ];
    for (let i = 0; i < order.length - 1; i++) {
      expect(
        order[i].compareDocumentPosition(order[i + 1]) & Node.DOCUMENT_POSITION_FOLLOWING,
      ).toBeTruthy();
    }
  });

  it("puts a description directly under the title, above the meta, and none when absent", () => {
    draw({ title: "T", description: "About it", meta: <span>the-meta</span>, path: "/hub/x.md" });
    const order = [
      screen.getByRole("heading", { level: 1 }),
      screen.getByText("About it"),
      screen.getByText("the-meta"),
      screen.getByTestId("file-path"),
    ];
    for (let i = 0; i < order.length - 1; i++) {
      expect(
        order[i].compareDocumentPosition(order[i + 1]) & Node.DOCUMENT_POSITION_FOLLOWING,
      ).toBeTruthy();
    }
  });

  it("keeps the whole description reachable as its title, for the phone width's clamp", () => {
    draw({ title: "T", description: "A long sentence about it", path: "/hub/x.md" });
    expect(screen.getByTestId("detail-description").getAttribute("title")).toBe(
      "A long sentence about it",
    );
  });

  it("draws no description line when none is given", () => {
    draw({ title: "T", path: "/hub/x.md" });
    expect(screen.queryByTestId("detail-description")).toBeNull();
  });

  it("orders the controls: actions, refresh, then the external link last", () => {
    draw({
      title: "T",
      actions: <button>act</button>,
      refresh: { onClick: jest.fn() },
      external: <a href="https://example.test/x">out</a>,
    });
    const order = [screen.getByText("act"), screen.getByTitle("Refresh"), screen.getByText("out")];
    for (let i = 0; i < order.length - 1; i++) {
      expect(
        order[i].compareDocumentPosition(order[i + 1]) & Node.DOCUMENT_POSITION_FOLLOWING,
      ).toBeTruthy();
    }
  });

  it("File line, case one: an absolute path, the label in view and the path in the tooltip", async () => {
    draw({ title: "T", path: "/hub/org/card.md", url: "https://example.test/c" });
    const button = screen.getByRole("button", { name: "Copy the file path" });
    expect(button.textContent).toBe("Copy the file path");
    fireEvent.focus(button);
    expect(await screen.findByRole("tooltip")).toHaveProperty("textContent", "/hub/org/card.md");
    fireEvent.click(button);
    expect(copyText).toHaveBeenCalledWith("/hub/org/card.md");
  });

  it("File line, case two: no path, so the URL, labelled as a link", async () => {
    draw({ title: "T", url: "https://example.test/c" });
    const button = screen.getByRole("button", { name: "Copy the file link" });
    fireEvent.focus(button);
    expect(await screen.findByRole("tooltip")).toHaveProperty(
      "textContent",
      "https://example.test/c",
    );
    fireEvent.click(button);
    expect(copyText).toHaveBeenCalledWith("https://example.test/c");
  });

  it("File line, case three: no address at all, no line", () => {
    draw({ title: "T", meta: <span>m</span> });
    expect(screen.queryByTestId("file-path")).toBeNull();
    expect(screen.queryByRole("button", { name: /^Copy the/ })).toBeNull();
  });

  it("an empty meta slot draws no meta element; a given one does", () => {
    draw({ title: "T" });
    expect(screen.queryByTestId("detail-meta")).toBeNull();
  });

  it("a meta slot draws its element", () => {
    draw({ title: "T", meta: <span>m</span> });
    expect(screen.getByTestId("detail-meta").textContent).toBe("m");
  });

  it("empty slots take no space: no meta wrapper, no extra, no controls wrapper", () => {
    const { container } = draw({
      title: "T",
      meta: false,
      extra: null,
      actions: undefined,
    });
    expect(screen.queryByTestId("detail-meta")).toBeNull();
    // the title block holds the h1 and nothing else
    expect(screen.getByRole("heading", { level: 1 }).parentElement?.children).toHaveLength(1);
    // the row holds the left side alone
    expect(screen.getByTestId("detail-header").children).toHaveLength(1);
    expect(container.querySelectorAll("[data-testid=file-path]")).toHaveLength(0);
  });

  it("the File line's tooltip is the button's description", async () => {
    draw({ title: "T", path: "/hub/org/card.md" });
    const button = screen.getByRole("button", { name: "Copy the file path" });
    fireEvent.focus(button);
    const tip = await screen.findByRole("tooltip");
    expect(button.getAttribute("aria-describedby")).toBe(tip.id);
  });
});
