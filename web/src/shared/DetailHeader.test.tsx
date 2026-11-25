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

  it("File line, case one: an absolute path, copied as it is", () => {
    draw({ title: "T", path: "/Users/x/hub/card.md", url: "https://example.test/c" });
    expect(screen.getByText("/Users/x/hub/card.md")).toBeTruthy();
    expect(screen.queryByText("https://example.test/c")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Copy the file path" }));
    expect(copyText).toHaveBeenCalledWith("/Users/x/hub/card.md");
  });

  it("File line, case two: no path, so the URL, named by what", () => {
    draw({ title: "T", url: "https://example.test/c", what: "document link" });
    expect(screen.getByText("https://example.test/c")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Copy the document link" }));
    expect(copyText).toHaveBeenCalledWith("https://example.test/c");
  });

  it("File line, case three: no address at all, no line", () => {
    draw({ title: "T", meta: <span>m</span> });
    expect(screen.queryByTestId("file-path")).toBeNull();
    expect(screen.queryByRole("button", { name: /^Copy the/ })).toBeNull();
  });

  it("an empty meta slot draws no meta line", () => {
    const { container } = draw({ title: "T" });
    expect(container.querySelectorAll("h1 + div")).toHaveLength(0);
  });
});
