import { render } from "@testing-library/react";
import ReactMarkdown from "react-markdown";
import { markdownPlugins } from "./markdownPlugins";
import { pointsAtAgent } from "./noAgentImages";

describe("where a picture in a document may point", () => {
  it.each([
    ["/api/health"],
    ["/api"],
    ["api/health"],
    ["./api/health"],
    ["../../api/health"],
    ["/x/../api/health"],
    ["\\api\\health"],
    ["/%61pi/health"],
    ["  /api/health"],
    ["http://localhost:4100/api/health"],
    ["http://LOCALHOST:4100/"],
    ["http://127.0.0.1:4100/api/health"],
    ["http://127.1:4100/"],
    ["http://2130706433/"],
    ["http://[::1]:4100/"],
    ["http://0.0.0.0:4100/"],
    ["http://anything.localhost/"],
    ["//localhost:4100/api/health"],
  ])("never %s", (url) => {
    expect(pointsAtAgent(url)).toBe(true);
  });

  it.each([
    ["https://example.test/a.png"],
    ["https://example.test/api/a.png"],
    ["https://github.com/o/r/assets/1/a.png"],
    ["docs/images/board.png"],
    ["docs/api/diagram.png"],
    ["/apiary/a.png"],
    ["data:image/png;base64,AAAA"],
    ["#frag"],
  ])("still %s", (url) => {
    expect(pointsAtAgent(url)).toBe(false);
  });
});

function drawn(markdown: string) {
  const { container } = render(<ReactMarkdown {...markdownPlugins}>{markdown}</ReactMarkdown>);
  return container;
}

describe("the pipeline every document goes through", () => {
  it("drops a markdown image aimed at the API, keeps its words", () => {
    const img = drawn("![status](/api/health)").querySelector("img");
    expect(img?.getAttribute("src")).toBeNull();
    expect(img?.getAttribute("alt")).toBe("status");
  });

  it("drops raw HTML aimed at the API or this machine", () => {
    const html = drawn('<img src="http://localhost:4100/api/health" alt="a">').querySelector("img");
    expect(html?.getAttribute("src")).toBeNull();
  });

  it("drops a picture's source aimed at the API, whole", () => {
    const source = drawn(
      '<picture><source srcset="/api/health 1x, https://example.test/a.png 2x"><img src="https://example.test/a.png" alt="a"></picture>',
    );
    expect(source.querySelector("source")?.getAttribute("srcset")).toBeNull();
    expect(source.querySelector("img")?.getAttribute("src")).toBe("https://example.test/a.png");
  });

  it("leaves an ordinary picture alone", () => {
    const img = drawn("![a](https://example.test/a.png)").querySelector("img");
    expect(img?.getAttribute("src")).toBe("https://example.test/a.png");
  });
});
